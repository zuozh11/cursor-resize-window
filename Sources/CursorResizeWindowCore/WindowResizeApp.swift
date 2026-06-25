import ApplicationServices
import CoreGraphics
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

public final class WindowResizeApp {
    private var eventTap: CFMachPort?
    private var dragState: DragState?
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

        print("cursor-resize-window: running with modifier=ctrl")
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
            guard hasOnlyControlModifier(event.flags), beginDrag(at: event.location) else {
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
            updateDrag(to: event.location)
            return nil
        case .leftMouseUp:
            guard dragState != nil else {
                return Unmanaged.passUnretained(event)
            }
            if !dragDetected, let consumedMouseDown {
                consumedMouseDown.tapPostEvent(proxy)
                event.tapPostEvent(proxy)
            }
            dragState = nil
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
            direction: ResizeDirection.from(point: point, frame: frame),
            lastResizeTime: 0
        )
        return true
    }

    private func updateDrag(to point: CGPoint) {
        guard let dragState else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        guard now - dragState.lastResizeTime >= ResizeModel.throttleNanoseconds else {
            return
        }

        let dx = CGFloat(Int(point.x - dragState.downLocation.x))
        let dy = CGFloat(Int(point.y - dragState.downLocation.y))
        let frame = ResizeModel.resize(frame: dragState.frame, direction: dragState.direction, dx: dx, dy: dy)

        set(frame: frame, for: dragState.window)
        self.dragState = DragState(
            window: dragState.window,
            downLocation: point,
            frame: frame,
            direction: dragState.direction,
            lastResizeTime: now
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

    private func set(frame: CGRect, for element: AXUIElement) {
        var position = frame.origin
        var size = frame.size

        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return
        }

        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }
}

private struct DragState {
    let window: AXUIElement
    let downLocation: CGPoint
    let frame: CGRect
    let direction: ResizeDirection
    let lastResizeTime: UInt64
}

private func hasOnlyControlModifier(_ flags: CGEventFlags) -> Bool {
    let modifierMask: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn]
    return flags.intersection(modifierMask) == .maskControl
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
