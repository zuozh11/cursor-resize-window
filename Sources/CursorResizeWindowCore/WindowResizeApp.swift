@preconcurrency import ApplicationServices
@preconcurrency import AppKit
@preconcurrency import CoreGraphics
import Darwin
import Foundation
import os

public enum RuntimeError: Error, CustomStringConvertible {
    case accessibilityPermissionRequired
    case alreadyRunning
    case eventTapUnavailable

    public var description: String {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required. Re-run after approving this app in System Settings > Privacy & Security > Accessibility."
        case .alreadyRunning:
            "another cursor-resize-window instance is already running. Stop it before starting a new instance."
        case .eventTapUnavailable:
            "unable to create the global event tap. Check Accessibility and Input Monitoring permissions."
        }
    }
}

public final class WindowResizeApp: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private static let instanceLockPath = "/tmp/cursor-resize-window-\(getuid()).lock"

    private var eventTap: CFMachPort?
    private var instanceLockFileDescriptor: Int32 = -1
    private let frameApplier = AXFrameApplier()
    private var dragState: DragState?
    private var consumedMouseDown: CGEvent?
    private var dragDetected = false
    private var nativeDragState: NativeDragState?
    private var dragFeedbackOverlay: DragFeedbackOverlay?
    private var shadowCursorController: ShadowCursorController?

    public override init() {
        super.init()
    }

    deinit {
        if instanceLockFileDescriptor >= 0 {
            close(instanceLockFileDescriptor)
        }
    }

    @MainActor
    public func run() throws {
        try acquireInstanceLock()

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.delegate = self

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
        let dragFeedbackOverlay = DragFeedbackOverlay()
        self.dragFeedbackOverlay = dragFeedbackOverlay
        shadowCursorController = ShadowCursorController(overlay: dragFeedbackOverlay)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("cursor-resize-window: running with ctrl")
        application.run()
    }

    private func acquireInstanceLock() throws {
        let fileDescriptor = open(Self.instanceLockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw RuntimeError.alreadyRunning
        }
        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            throw RuntimeError.alreadyRunning
        }
        instanceLockFileDescriptor = fileDescriptor
    }

    @MainActor
    public func applicationWillTerminate(_ notification: Notification) {
        cancelDrag()
    }

    fileprivate func handle(_ type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if type == .leftMouseDragged,
           event.getIntegerValueField(.eventSourceUserData) == syntheticArmedDragMarker
        {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelDrag()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            cancelShadowCursor()
            guard hasOnlyControlKey(event.flags), beginDrag(at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            dragDetected = false
            consumedMouseDown = event.copy()
            if let nativeDragState {
                nativeDragState.pendingActivationPID = activateApplicationIfNeeded(
                    for: nativeDragState.window
                )
            }
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
            if let nativeDragState, nativeDragState.deferMouseUp(event) {
                return nil
            }
            if nativeDragState != nil {
                let rewrittenEvent = finishNativeResize(with: event)
                finishDrag(keepingShadowCursor: isShadowCursorActive)
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

        let target = ResizeTarget.from(point: point, frame: frame)
        let nativeMapping = NativeDragMapping(pointer: point, frame: frame, target: target)
        if let displayBounds = nativeMapping.clickableDisplay(in: activeDisplayBounds()) {
            nativeDragState = NativeDragState(
                window: window,
                mapping: nativeMapping,
                displayBounds: displayBounds,
                screenBounds: activeScreenBounds(),
                frame: frame,
                target: target
            )
            beginDragFeedback(at: nativeMapping.anchor, windowFrame: frame, target: target)
        } else if let resizeDirection = target.resizeDirection {
            dragState = DragState(
                window: window,
                downLocation: point,
                frame: frame,
                direction: resizeDirection
            )
            frameApplier.beginDrag(for: window, initialFrame: frame)
        } else {
            return false
        }
        return true
    }

    private func activeDisplayBounds() -> [CGRect] {
        activeScreenBounds(visibleOnly: true)
    }

    private func activeScreenBounds() -> [CGRect] {
        activeScreenBounds(visibleOnly: false)
    }

    private func activeScreenBounds(visibleOnly: Bool) -> [CGRect] {
        MainActor.assumeIsolated {
            let screens = NSScreen.screens
            guard let primaryScreen = screens.first else {
                return []
            }

            let flipReference = primaryScreen.frame.maxY
            return screens.map { screen in
                let frame = visibleOnly ? screen.visibleFrame : screen.frame
                return CGRect(
                    x: frame.minX,
                    y: flipReference - frame.maxY,
                    width: frame.width,
                    height: frame.height
                )
            }
        }
    }

    private func applyAccessibilityResize(to point: CGPoint) {
        guard let dragState else {
            return
        }

        let dx = point.x - dragState.downLocation.x
        let dy = point.y - dragState.downLocation.y
        guard dx != 0 || dy != 0 else {
            return
        }

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

        let inputLocation = event.location
        event.flags.remove(.maskControl)
        if nativeDragState.needsPointerWarp {
            nativeDragState.needsPointerWarp = false
            waitForApplicationActivation(pid: nativeDragState.pendingActivationPID)
            let usesShadowCursor = beginShadowCursor(
                at: nativeDragState.visiblePointer(for: nativeDragState.mapping.anchor)
            )
            if nativeDragState.isMove || usesShadowCursor {
                if !nativeDragState.warpPointerToAnchor() {
                    cancelShadowCursor()
                }
            }
            nativeDragState.beginArmingDrag(
                with: event,
                at: nativeDragState.translateFirstDrag(inputLocation)
            )
            prepareNativeMouseDown(event, at: nativeDragState.mapping.anchor)
            scheduleArmedNativeDrag(for: nativeDragState)
            return Unmanaged.passUnretained(event)
        }
        if nativeDragState.updateArmingDrag(with: event) {
            return nil
        }
        event.location = nativeDragState.translate(event.location)
        let previewFrame = nativeDragState.updatePreviewFrame(for: event.location)
        if isShadowCursorActive {
            updateShadowCursor(at: nativeDragState.visiblePointer(for: event.location))
        }
        updateDragFeedback(at: event.location, windowFrame: previewFrame)
        return Unmanaged.passUnretained(event)
    }

    private func scheduleArmedNativeDrag(for nativeDragState: NativeDragState) {
        let stateIdentifier = ObjectIdentifier(nativeDragState)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) { [weak self] in
            guard let currentState = self?.nativeDragState,
                  ObjectIdentifier(currentState) == stateIdentifier
            else {
                return
            }
            currentState.reinforcePointerWarp()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
            self?.flushArmedNativeDrag(stateIdentifier: stateIdentifier)
        }
    }

    private func flushArmedNativeDrag(stateIdentifier: ObjectIdentifier) {
        guard let nativeDragState,
              ObjectIdentifier(nativeDragState) == stateIdentifier,
              let events = nativeDragState.finishArmingDrag()
        else {
            return
        }

        events.drag.setIntegerValueField(
            .eventSourceUserData,
            value: syntheticArmedDragMarker
        )
        events.drag.post(tap: .cghidEventTap)
        events.mouseUp?.post(tap: .cghidEventTap)
    }

    private func finishNativeResize(with event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nativeDragState else {
            return Unmanaged.passUnretained(event)
        }

        event.flags.remove(.maskControl)
        event.location = nativeDragState.translate(event.location)
        if isShadowCursorActive {
            let visiblePointer = nativeDragState.visiblePointer(for: event.location)
            updateShadowCursor(at: visiblePointer)
            finishShadowCursor(afterMouseUpAt: visiblePointer)
        }
        return Unmanaged.passUnretained(event)
    }

    private func finishDrag(keepingShadowCursor: Bool = false) {
        if dragState != nil {
            frameApplier.endDrag()
        }
        dragState = nil
        nativeDragState = nil
        consumedMouseDown = nil
        dragDetected = false
        hideDragFeedback(keepingShadowCursor: keepingShadowCursor)
    }

    private func cancelDrag() {
        cancelShadowCursor()
        finishDrag()
    }

    private func updateDragFeedback(at point: CGPoint, windowFrame: CGRect) {
        guard let dragFeedbackOverlay else {
            return
        }

        DispatchQueue.main.async {
            dragFeedbackOverlay.update(at: point, windowFrame: windowFrame)
        }
    }

    private func hideDragFeedback(keepingShadowCursor: Bool = false) {
        guard let dragFeedbackOverlay else {
            return
        }

        DispatchQueue.main.async {
            dragFeedbackOverlay.hide(keepingShadowCursor: keepingShadowCursor)
        }
    }

    private var isShadowCursorActive: Bool {
        guard let shadowCursorController else {
            return false
        }
        return MainActor.assumeIsolated {
            shadowCursorController.isActive
        }
    }

    private func beginShadowCursor(at point: CGPoint) -> Bool {
        guard let shadowCursorController else {
            return false
        }
        return MainActor.assumeIsolated {
            shadowCursorController.begin(at: point)
        }
    }

    private func updateShadowCursor(at point: CGPoint) {
        guard let shadowCursorController else {
            return
        }
        MainActor.assumeIsolated {
            shadowCursorController.update(at: point)
        }
    }

    private func finishShadowCursor(afterMouseUpAt point: CGPoint) {
        guard let shadowCursorController else {
            return
        }
        MainActor.assumeIsolated {
            shadowCursorController.finishAfterMouseUp(at: point)
        }
    }

    private func cancelShadowCursor() {
        guard let shadowCursorController else {
            return
        }
        MainActor.assumeIsolated {
            shadowCursorController.cancel()
        }
    }

    private func beginDragFeedback(at point: CGPoint, windowFrame: CGRect, target: ResizeTarget) {
        guard let dragFeedbackOverlay else {
            return
        }

        DispatchQueue.main.async {
            dragFeedbackOverlay.begin(at: point, windowFrame: windowFrame, target: target)
        }
    }

    private func activateApplicationIfNeeded(for window: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else {
            return nil
        }

        return MainActor.assumeIsolated {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                return nil
            }
            _ = NSRunningApplication(processIdentifier: pid)?.activate()
            return pid
        }
    }

    private func waitForApplicationActivation(pid: pid_t?) {
        guard let pid else {
            return
        }
        for _ in 0..<10 {
            let isActive = MainActor.assumeIsolated {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            }
            if isActive {
                return
            }
            usleep(5_000)
        }
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
    let window: AXUIElement
    let mapping: NativeDragMapping
    private let displayBounds: CGRect
    private let screenBounds: [CGRect]
    private let target: ResizeTarget
    private var synthesizedPointer: CGPoint
    private var previewFrame: CGRect
    private var usesWarpedPointer = false
    private var usesWarpedEventCoordinates = false
    private let armingBuffer = NativeDragArmingBuffer()
    var pendingActivationPID: pid_t?
    var needsPointerWarp = true

    var isMove: Bool {
        target == .move
    }

    init(
        window: AXUIElement,
        mapping: NativeDragMapping,
        displayBounds: CGRect,
        screenBounds: [CGRect],
        frame: CGRect,
        target: ResizeTarget
    ) {
        self.window = window
        self.mapping = mapping
        self.displayBounds = displayBounds
        self.screenBounds = screenBounds
        synthesizedPointer = mapping.anchor
        previewFrame = frame
        self.target = target
    }

    func translate(_ point: CGPoint) -> CGPoint {
        if usesWarpedPointer {
            if !usesWarpedEventCoordinates,
               !mapping.isInWarpedCoordinateSpace(point)
            {
                if target == .move {
                    return mapping.translate(point, constrainedToAny: screenBounds)
                }
                return mapping.translate(point, constrainedTo: displayBounds)
            }
            usesWarpedEventCoordinates = true
            if target == .move {
                return mapping.constrain(point, toAny: screenBounds)
            }
            return mapping.constrainWarpedPointer(point, to: displayBounds)
        }
        if target == .move {
            return mapping.translate(point, constrainedToAny: screenBounds)
        }
        return mapping.translate(point, constrainedTo: displayBounds)
    }

    func beginArmingDrag(with event: CGEvent, at point: CGPoint) {
        armingBuffer.begin(with: event, at: point)
    }

    func updateArmingDrag(with event: CGEvent) -> Bool {
        armingBuffer.update(with: event, at: translate(event.location))
    }

    func deferMouseUp(_ event: CGEvent) -> Bool {
        armingBuffer.deferMouseUp(event)
    }

    func finishArmingDrag() -> (drag: CGEvent, mouseUp: CGEvent?)? {
        armingBuffer.finish()
    }

    func translateFirstDrag(_ point: CGPoint) -> CGPoint {
        if target == .move {
            return mapping.translate(point, constrainedToAny: screenBounds)
        }
        return mapping.translate(point, constrainedTo: displayBounds)
    }

    func warpPointerToAnchor() -> Bool {
        _ = setLocalEventsSuppressionInterval(0)
        usesWarpedPointer = CGWarpMouseCursorPosition(mapping.anchor) == .success
        if usesWarpedPointer {
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        }
        return usesWarpedPointer
    }

    func reinforcePointerWarp() {
        guard usesWarpedPointer else {
            return
        }
        _ = setLocalEventsSuppressionInterval(0)
        if CGWarpMouseCursorPosition(mapping.anchor) == .success {
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        }
    }

    func visiblePointer(for synthesizedPointer: CGPoint) -> CGPoint {
        mapping.visiblePointer(for: synthesizedPointer)
    }

    func updatePreviewFrame(for nextSynthesizedPointer: CGPoint) -> CGRect {
        let dx = nextSynthesizedPointer.x - synthesizedPointer.x
        let dy = nextSynthesizedPointer.y - synthesizedPointer.y

        if target == .move {
            previewFrame = previewFrame.offsetBy(dx: dx, dy: dy)
        } else if let direction = target.resizeDirection {
            previewFrame = ResizeModel.resize(
                frame: previewFrame,
                direction: direction,
                dx: dx,
                dy: dy
            )
        }

        synthesizedPointer = nextSynthesizedPointer
        return previewFrame
    }
}

final class NativeDragArmingBuffer {
    private var pendingDrag: CGEvent?
    private var pendingMouseUp: CGEvent?

    func begin(with event: CGEvent, at point: CGPoint) {
        guard let pendingDrag = event.copy() else {
            return
        }
        pendingDrag.flags.remove(.maskControl)
        pendingDrag.type = .leftMouseDragged
        pendingDrag.location = point
        self.pendingDrag = pendingDrag
    }

    func update(with event: CGEvent, at point: CGPoint) -> Bool {
        guard pendingDrag != nil,
              let pendingDrag = event.copy()
        else {
            return false
        }
        pendingDrag.flags.remove(.maskControl)
        pendingDrag.type = .leftMouseDragged
        pendingDrag.location = point
        self.pendingDrag = pendingDrag
        return true
    }

    func deferMouseUp(_ event: CGEvent) -> Bool {
        guard let pendingDrag,
              let pendingMouseUp = event.copy()
        else {
            return false
        }
        pendingMouseUp.flags.remove(.maskControl)
        pendingMouseUp.type = .leftMouseUp
        pendingMouseUp.location = pendingDrag.location
        self.pendingMouseUp = pendingMouseUp
        return true
    }

    func finish() -> (drag: CGEvent, mouseUp: CGEvent?)? {
        guard let pendingDrag else {
            return nil
        }
        let events = (pendingDrag, pendingMouseUp)
        self.pendingDrag = nil
        pendingMouseUp = nil
        return events
    }
}

@MainActor
private final class ShadowCursorController {
    private struct Session {
        let id: UInt64
        let image: NSImage
        let hotSpot: CGPoint
        var visiblePoint: CGPoint
    }

    private let overlay: DragFeedbackOverlay
    private let backgroundCursorAccess = BackgroundCursorAccess()
    private var session: Session?
    private var nextSessionID: UInt64 = 0
    private var ownsCursorHide = false

    var isActive: Bool {
        session != nil && ownsCursorHide
    }

    init(overlay: DragFeedbackOverlay) {
        self.overlay = overlay
    }

    func begin(at point: CGPoint) -> Bool {
        cancel()
        guard let backgroundCursorAccess,
              backgroundCursorAccess.enable()
        else {
            return false
        }

        guard let cursor = NSCursor.currentSystem else {
            backgroundCursorAccess.disable()
            return false
        }
        guard CGDisplayHideCursor(CGMainDisplayID()) == .success else {
            backgroundCursorAccess.disable()
            return false
        }
        ownsCursorHide = true
        nextSessionID &+= 1
        session = Session(
            id: nextSessionID,
            image: cursor.image,
            hotSpot: cursor.hotSpot,
            visiblePoint: point
        )
        overlay.showShadowCursor(at: point, image: cursor.image, hotSpot: cursor.hotSpot)
        return true
    }

    func update(at point: CGPoint) {
        guard var session else {
            return
        }
        session.visiblePoint = point
        self.session = session
        overlay.showShadowCursor(at: point, image: session.image, hotSpot: session.hotSpot)
    }

    func finishAfterMouseUp(at point: CGPoint) {
        update(at: point)
        guard let session else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.restore(sessionID: session.id)
        }
    }

    func cancel() {
        restore(sessionID: nil)
    }

    private func restore(sessionID: UInt64?) {
        guard let session,
              sessionID == nil || session.id == sessionID
        else {
            return
        }

        _ = setLocalEventsSuppressionInterval(0)
        _ = CGWarpMouseCursorPosition(session.visiblePoint)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        if ownsCursorHide {
            _ = CGDisplayShowCursor(CGMainDisplayID())
            ownsCursorHide = false
        }
        self.session = nil
        overlay.hideShadowCursor()
    }
}

private final class BackgroundCursorAccess {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (
        Int32,
        Int32,
        CFString,
        CFTypeRef
    ) -> CGError

    private let connection: Int32
    private let setConnectionProperty: SetConnectionProperty
    private var isEnabled = false

    init?() {
        guard
            let defaultConnectionSymbol = dlsym(
                UnsafeMutableRawPointer(bitPattern: -2),
                "_CGSDefaultConnection"
            ),
            let setConnectionPropertySymbol = dlsym(
                UnsafeMutableRawPointer(bitPattern: -2),
                "CGSSetConnectionProperty"
            )
        else {
            return nil
        }

        let defaultConnection = unsafeBitCast(defaultConnectionSymbol, to: DefaultConnection.self)
        setConnectionProperty = unsafeBitCast(
            setConnectionPropertySymbol,
            to: SetConnectionProperty.self
        )
        connection = defaultConnection()
    }

    func enable() -> Bool {
        if isEnabled {
            return true
        }
        let result = setConnectionProperty(
            connection,
            connection,
            "SetsCursorInBackground" as CFString,
            kCFBooleanTrue
        )
        isEnabled = result == .success
        return isEnabled
    }

    func disable() {
        guard isEnabled else {
            return
        }
        _ = setConnectionProperty(
            connection,
            connection,
            "SetsCursorInBackground" as CFString,
            kCFBooleanFalse
        )
        isEnabled = false
    }
}

private final class DragState: @unchecked Sendable {
    let window: AXUIElement
    var downLocation: CGPoint
    var frame: CGRect
    let direction: ResizeDirection

    init(
        window: AXUIElement,
        downLocation: CGPoint,
        frame: CGRect,
        direction: ResizeDirection
    ) {
        self.window = window
        self.downLocation = downLocation
        self.frame = frame
        self.direction = direction
    }
}

@_silgen_name("CGSetLocalEventsSuppressionInterval")
private func setLocalEventsSuppressionInterval(_ seconds: CFTimeInterval) -> CGError


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

private let syntheticArmedDragMarker: Int64 = 0x4352_5744

func prepareNativeMouseDown(
    _ event: CGEvent,
    at point: CGPoint
) {
    event.type = .leftMouseDown
    event.location = point
    event.setIntegerValueField(.mouseEventDeltaX, value: 0)
    event.setIntegerValueField(.mouseEventDeltaY, value: 0)
    event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.setDoubleValueField(.mouseEventPressure, value: 1)
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
