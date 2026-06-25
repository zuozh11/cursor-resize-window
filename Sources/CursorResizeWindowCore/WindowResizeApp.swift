@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation

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
    private var eventTap: CFMachPort?
    private let frameApplier = AXFrameApplier()
    private var dragState: DragState?
    private var pendingDragPoint: CGPoint?
    private var resizeScheduled = false
    private var consumedMouseDown: CGEvent?
    private var dragDetected = false

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
            guard dragState != nil else {
                return Unmanaged.passUnretained(event)
            }
            dragDetected = true
            queueResize(to: event.location)
            return nil
        case .leftMouseUp:
            guard dragState != nil else {
                return Unmanaged.passUnretained(event)
            }
            if !dragDetected, let consumedMouseDown {
                consumedMouseDown.tapPostEvent(proxy)
                event.tapPostEvent(proxy)
            } else {
                applyResize(to: event.location)
                frameApplier.flush()
            }
            frameApplier.endDrag()
            dragState = nil
            pendingDragPoint = nil
            resizeScheduled = false
            consumedMouseDown = nil
            dragDetected = false
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

        dragState = DragState(
            window: window,
            downLocation: point,
            frame: frame,
            direction: ResizeDirection.from(point: point, frame: frame)
        )
        frameApplier.beginDrag(for: window)
        return true
    }

    private func queueResize(to point: CGPoint) {
        pendingDragPoint = point

        guard !resizeScheduled else {
            return
        }

        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingResize()
        }
    }

    private func flushPendingResize() {
        resizeScheduled = false

        guard let point = pendingDragPoint else {
            return
        }
        pendingDragPoint = nil
        applyResize(to: point)

        if let latestPoint = pendingDragPoint {
            pendingDragPoint = nil
            queueResize(to: latestPoint)
        }
    }

    private func applyResize(to point: CGPoint) {
        guard let dragState else {
            return
        }

        let dx = point.x - dragState.downLocation.x
        let dy = point.y - dragState.downLocation.y
        let frame = ResizeModel.resize(frame: dragState.frame, direction: dragState.direction, dx: dx, dy: dy)

        frameApplier.enqueue(window: dragState.window, frame: frame, previousFrame: dragState.frame)
        self.dragState = DragState(
            window: dragState.window,
            downLocation: point,
            frame: frame,
            direction: dragState.direction
        )
    }

    private func windowElement(at point: CGPoint) -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        guard AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &element) == .success,
              let element
        else {
            return nil
        }

        return enclosingWindow(for: element)
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

private struct DragState {
    let window: AXUIElement
    let downLocation: CGPoint
    let frame: CGRect
    let direction: ResizeDirection
}

private struct FrameUpdate: @unchecked Sendable {
    let window: AXUIElement
    let frame: CGRect
    let previousFrame: CGRect
}

private final class AXFrameApplier: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cursor-resize-window.ax-frame-applier", qos: .userInteractive)
    private let lock = NSLock()
    private var pendingUpdate: FrameUpdate?
    private var applying = false
    private var enhancedUISession: EnhancedUISession?

    func beginDrag(for window: AXUIElement) {
        guard let application = applicationElement(for: window) else {
            enhancedUISession = nil
            return
        }

        let attribute = "AXEnhancedUserInterface" as CFString
        let shouldRestore = boolAttribute(application, attribute)
        enhancedUISession = EnhancedUISession(application: application, shouldRestore: shouldRestore)

        if shouldRestore {
            AXUIElementSetAttributeValue(application, attribute, kCFBooleanFalse)
        }
    }

    func endDrag() {
        guard let session = enhancedUISession else {
            return
        }
        enhancedUISession = nil

        if session.shouldRestore {
            AXUIElementSetAttributeValue(
                session.application,
                "AXEnhancedUserInterface" as CFString,
                kCFBooleanTrue
            )
        }
    }

    func enqueue(window: AXUIElement, frame: CGRect, previousFrame: CGRect) {
        lock.lock()
        pendingUpdate = FrameUpdate(window: window, frame: frame, previousFrame: previousFrame)
        let shouldStart = !applying
        if shouldStart {
            applying = true
        }
        lock.unlock()

        if shouldStart {
            queue.async { [weak self] in
                self?.drain()
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    private func drain() {
        while true {
            lock.lock()
            guard let update = pendingUpdate else {
                applying = false
                lock.unlock()
                return
            }
            pendingUpdate = nil
            lock.unlock()

            apply(update)
        }
    }

    private func apply(_ update: FrameUpdate) {
        set(frame: update.frame, previousFrame: update.previousFrame, for: update.window)
    }

    private func set(frame: CGRect, previousFrame: CGRect, for element: AXUIElement) {
        var size = frame.size

        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            return
        }

        if frame.origin != previousFrame.origin {
            var position = frame.origin
            if let positionValue = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
            }
        }

        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
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
