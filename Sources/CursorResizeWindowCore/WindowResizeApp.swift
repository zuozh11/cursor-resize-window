@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Darwin
import Foundation
import os

public enum RuntimeError: Error, CustomStringConvertible {
    case accessibilityPermissionRequired
    case eventTapUnavailable

    public var description: String {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required. Re-run after approving this app in System Settings > Privacy & Security > Accessibility."
        case .eventTapUnavailable:
            "unable to create the global event tap. Check Accessibility and Input Monitoring permissions."
        }
    }
}

public final class WindowResizeApp: @unchecked Sendable {
    private static let directionSampleDistance: CGFloat = 8

    private var eventTap: CFMachPort?
    private let frameApplier = AXFrameApplier()
    private var dragState: DragState?
    private var consumedMouseDown: CGEvent?
    private var dragDetected = false
    private var nativeDragState: NativeDragState?

    public init() {}

    public func run() throws {
        let promptOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(promptOptions) else {
            throw RuntimeError.accessibilityPermissionRequired
        }

        let eventMask = [
            CGEventType.leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .tapDisabledByTimeout,
            .tapDisabledByUserInput
        ].reduce(CGEventMask(0)) { mask, type in
            mask | (1 << CGEventMask(type.rawValue))
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventCallback,
            userInfo: userInfo
        ) else {
            throw RuntimeError.eventTapUnavailable
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("cursor-resize-window: running with ctrl")
        CFRunLoopRun()
    }

    fileprivate func handle(_ type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            guard hasOnlyControlKey(event.flags), beginDrag(at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            dragDetected = false
            consumedMouseDown = event.copy()
            return nil
        case .leftMouseDragged:
            guard dragState != nil || nativeDragState != nil else {
                return Unmanaged.passUnretained(event)
            }
            dragDetected = true
            if nativeDragState != nil {
                return applyNativeResize(to: event)
            }
            applyAccessibilityResize(to: event.location)
            return nil
        case .leftMouseUp:
            guard dragState != nil || nativeDragState != nil else {
                return Unmanaged.passUnretained(event)
            }
            if !dragDetected, let consumedMouseDown {
                consumedMouseDown.tapPostEvent(proxy)
                event.tapPostEvent(proxy)
                finishDrag()
                return nil
            }
            if nativeDragState != nil {
                let rewrittenEvent = finishNativeResize(with: event)
                finishDrag()
                return rewrittenEvent
            }
            applyAccessibilityResize(to: event.location)
            finishDrag()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func beginDrag(at point: CGPoint) -> Bool {
        guard
            let window = windowElement(at: point),
            let frame = frame(of: window)
        else {
            return false
        }

        let nativeMapping = NativeResizeMapping(pointer: point, frame: frame)
        if nativeMapping.isClickable(in: activeDisplayBounds()) {
            nativeDragState = NativeDragState(mapping: nativeMapping)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        } else {
            dragState = DragState(
                window: window,
                downLocation: point,
                directionSampleLocation: point,
                frame: frame,
                direction: ResizeDirection.from(point: point, frame: frame)
            )
            frameApplier.beginDrag(for: window, initialFrame: frame)
        }
        return true
    }

    private func activeDisplayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return []
        }

        return displays.prefix(Int(displayCount)).map(CGDisplayBounds)
    }

    private func applyAccessibilityResize(to point: CGPoint) {
        guard let dragState else {
            return
        }

        var dx = point.x - dragState.downLocation.x
        var dy = point.y - dragState.downLocation.y
        guard dx != 0 || dy != 0 else {
            return
        }

        let sampleDx = point.x - dragState.directionSampleLocation.x
        let sampleDy = point.y - dragState.directionSampleLocation.y
        if dragState.motion == nil {
            guard max(abs(sampleDx), abs(sampleDy)) >= Self.directionSampleDistance else {
                return
            }
        }

        if max(abs(sampleDx), abs(sampleDy)) >= Self.directionSampleDistance {
            dragState.motion = ResizeMotion.from(dx: sampleDx, dy: sampleDy)
            dragState.directionSampleLocation = point
        }

        guard let motion = dragState.motion else {
            return
        }
        (dx, dy) = motion.constrain(dx: dx, dy: dy)

        let frame = ResizeModel.resize(
            frame: dragState.frame,
            direction: dragState.direction,
            dx: dx,
            dy: dy
        )

        if frame != dragState.frame {
            frameApplier.enqueue(window: dragState.window, frame: frame)
        }

        dragState.downLocation = point
        dragState.frame = frame
    }

    private func applyNativeResize(to event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nativeDragState else {
            return Unmanaged.passUnretained(event)
        }

        event.flags.remove(.maskControl)
        if nativeDragState.needsMouseDown {
            nativeDragState.needsMouseDown = false
            event.type = .leftMouseDown
            event.location = nativeDragState.mapping.anchor
        } else {
            event.location = nativeDragState.mapping.translate(event.location)
        }
        return Unmanaged.passUnretained(event)
    }

    private func finishNativeResize(with event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nativeDragState else {
            return Unmanaged.passUnretained(event)
        }

        event.flags.remove(.maskControl)
        event.location = nativeDragState.mapping.translate(event.location)
        return Unmanaged.passUnretained(event)
    }

    private func finishDrag() {
        if dragState != nil {
            frameApplier.endDrag()
        }
        dragState = nil
        nativeDragState = nil
        consumedMouseDown = nil
        dragDetected = false
    }

    private func windowElement(at point: CGPoint) -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        if AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &element) == .success,
           let element,
           let window = enclosingWindow(for: element)
        {
            return window
        }

        return windowFromWindowServer(at: point)
    }

    private func windowFromWindowServer(at point: CGPoint) -> AXUIElement? {
        guard let pid = windowOwnerPIDFromWindowServer(at: point) else {
            return nil
        }

        let application = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else {
            return nil
        }

        return windows.first { window in
            guard stringAttribute(window, kAXRoleAttribute) == kAXWindowRole as String,
                  let frame = frame(of: window)
            else {
                return false
            }

            return frame.contains(point)
        }
    }

    private func windowOwnerPIDFromWindowServer(at point: CGPoint) -> pid_t? {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowInfoList {
            guard windowLayer(windowInfo) == 0,
                  let bounds = windowBounds(windowInfo),
                  bounds.contains(point),
                  let pid = windowOwnerPID(windowInfo)
            else {
                continue
            }

            return pid
        }

        return nil
    }

    private func windowLayer(_ windowInfo: [String: Any]) -> Int? {
        windowInfo[kCGWindowLayer as String] as? Int
    }

    private func windowOwnerPID(_ windowInfo: [String: Any]) -> pid_t? {
        guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
            return nil
        }

        return ownerPID
    }

    private func windowBounds(_ windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] else {
            return nil
        }

        return CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary)
    }

    private func enclosingWindow(for element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element

        for _ in 0..<12 {
            guard let candidate = current else {
                return nil
            }

            if stringAttribute(candidate, kAXRoleAttribute) == kAXWindowRole as String {
                return candidate
            }

            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parent) == .success,
                  let parent
            else {
                return nil
            }
            current = (parent as! AXUIElement)
        }

        return nil
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let positionRef,
            let sizeRef
        else {
            return nil
        }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

}

private final class NativeDragState {
    let mapping: NativeResizeMapping
    var needsMouseDown = true

    init(mapping: NativeResizeMapping) {
        self.mapping = mapping
    }
}

private final class DragState: @unchecked Sendable {
    let window: AXUIElement
    var downLocation: CGPoint
    var directionSampleLocation: CGPoint
    var frame: CGRect
    let direction: ResizeDirection
    var motion: ResizeMotion?

    init(
        window: AXUIElement,
        downLocation: CGPoint,
        directionSampleLocation: CGPoint,
        frame: CGRect,
        direction: ResizeDirection
    ) {
        self.window = window
        self.downLocation = downLocation
        self.directionSampleLocation = directionSampleLocation
        self.frame = frame
        self.direction = direction
    }
}

private struct FrameUpdate: @unchecked Sendable {
    let window: AXUIElement
    let frame: CGRect
}

private struct FrameApplierState {
    var pendingUpdate: FrameUpdate?
    var applying = false
}

private final class AXFrameApplier: @unchecked Sendable {
    private static let frameIntervalNanoseconds: UInt64 = 8_333_333
    private static let frameIntervalAbsoluteTime = nanosecondsToAbsoluteTime(frameIntervalNanoseconds)
    private static let positionAttribute = kAXPositionAttribute as CFString
    private static let sizeAttribute = kAXSizeAttribute as CFString
    private static let enhancedUIAttribute = "AXEnhancedUserInterface" as CFString

    private let queue = DispatchQueue(label: "cursor-resize-window.ax-frame-applier", qos: .userInteractive)
    private let state = OSAllocatedUnfairLock(initialState: FrameApplierState())
    private var enhancedUISession: EnhancedUISession?
    private var lastAppliedFrame: CGRect?
    private var lastFrameStartTime: UInt64 = 0

    func beginDrag(for window: AXUIElement, initialFrame: CGRect) {
        lastAppliedFrame = initialFrame
        lastFrameStartTime = 0

        guard let application = applicationElement(for: window) else {
            enhancedUISession = nil
            return
        }

        let shouldRestore = boolAttribute(application, Self.enhancedUIAttribute)
        enhancedUISession = EnhancedUISession(application: application, shouldRestore: shouldRestore)

        if shouldRestore {
            AXUIElementSetAttributeValue(application, Self.enhancedUIAttribute, kCFBooleanFalse)
        }
    }

    func endDrag() {
        guard let session = enhancedUISession else {
            return
        }
        enhancedUISession = nil

        queue.async {
            if session.shouldRestore {
                AXUIElementSetAttributeValue(
                    session.application,
                    Self.enhancedUIAttribute,
                    kCFBooleanTrue
                )
            }
        }
    }

    func enqueue(window: AXUIElement, frame: CGRect) {
        let shouldStart = state.withLock { state in
            state.pendingUpdate = FrameUpdate(window: window, frame: frame)

            if state.applying {
                return false
            }

            state.applying = true
            return true
        }

        if shouldStart {
            queue.async { [weak self] in
                self?.drain()
            }
        }
    }

    private func drain() {
        while true {
            guard let queuedUpdate = takePendingUpdateOrFinish() else {
                return
            }

            waitForNextFrame()
            let update = takeLatestUpdate(replacing: queuedUpdate)
            apply(update)
        }
    }

    private func takePendingUpdateOrFinish() -> FrameUpdate? {
        state.withLock { state in
            guard let update = state.pendingUpdate else {
                state.applying = false
                return nil
            }

            state.pendingUpdate = nil
            return update
        }
    }

    private func takeLatestUpdate(replacing queuedUpdate: FrameUpdate) -> FrameUpdate {
        state.withLock { state in
            guard let latestUpdate = state.pendingUpdate else {
                return queuedUpdate
            }

            state.pendingUpdate = nil
            return latestUpdate
        }
    }

    private func set(_ update: FrameUpdate) {
        let previousFrame = lastAppliedFrame
        let shouldSetPosition: Bool
        let shouldSetSize: Bool

        if let previousFrame {
            shouldSetPosition = previousFrame.origin != update.frame.origin
            shouldSetSize = previousFrame.size != update.frame.size
        } else {
            shouldSetPosition = true
            shouldSetSize = true
        }

        if shouldSetPosition {
            var position = update.frame.origin
            if let positionValue = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(update.window, Self.positionAttribute, positionValue)
            }
        }

        if shouldSetSize {
            var size = update.frame.size
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(update.window, Self.sizeAttribute, sizeValue)
            }
        }

        lastAppliedFrame = update.frame
    }

    private func apply(_ update: FrameUpdate) {
        lastFrameStartTime = mach_absolute_time()
        set(update)
    }

    private func waitForNextFrame() {
        guard lastFrameStartTime > 0 else {
            return
        }

        let now = mach_absolute_time()
        let nextFrameTime = lastFrameStartTime + Self.frameIntervalAbsoluteTime
        guard now < nextFrameTime else {
            return
        }

        mach_wait_until(nextFrameTime)
    }

    private static func nanosecondsToAbsoluteTime(_ nanoseconds: UInt64) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        let numerator = nanoseconds * UInt64(timebase.denom)
        let denominator = UInt64(timebase.numer)
        return max(1, (numerator + denominator - 1) / denominator)
    }

    private func applicationElement(for window: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else {
            return nil
        }

        return AXUIElementCreateApplication(pid)
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else {
            return false
        }

        return CFBooleanGetValue((value as! CFBoolean))
    }
}

private struct EnhancedUISession {
    let application: AXUIElement
    let shouldRestore: Bool
}

private func hasOnlyControlKey(_ flags: CGEventFlags) -> Bool {
    let keyMask: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn]
    return flags.intersection(keyMask) == .maskControl
}

private func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let app = Unmanaged<WindowResizeApp>.fromOpaque(refcon).takeUnretainedValue()
    return app.handle(type, event: event, proxy: proxy)
}
