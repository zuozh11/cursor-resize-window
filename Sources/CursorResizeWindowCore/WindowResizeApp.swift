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
    private let config: AppConfig
    private var eventTap: CFMachPort?
    private var dragState: DragState?

    public init(config: AppConfig) {
        self.config = config
    }

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
            tap: .cgSessionEventTap,
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

        print("cursor-resize-window: running with modifier=\(config.modifier.rawValue)")
        CFRunLoopRun()
    }

    fileprivate func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            guard event.flags.contains(config.modifier.eventFlag), beginDrag(at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            return nil
        case .leftMouseDragged:
            guard dragState != nil else {
                return Unmanaged.passUnretained(event)
            }
            updateDrag(to: event.location)
            return nil
        case .leftMouseUp:
            guard dragState != nil else {
                return Unmanaged.passUnretained(event)
            }
            dragState = nil
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

        let midpointX = frame.midX
        let midpointY = frame.midY
        dragState = DragState(
            window: window,
            startMouse: point,
            startFrame: frame,
            anchor: ResizeAnchor(resizeLeft: point.x < midpointX, resizeTop: point.y < midpointY)
        )
        return true
    }

    private func updateDrag(to point: CGPoint) {
        guard let dragState else {
            return
        }

        let dx = point.x - dragState.startMouse.x
        let dy = point.y - dragState.startMouse.y
        var frame = dragState.startFrame

        if dragState.anchor.resizeLeft {
            frame.origin.x = min(
                dragState.startFrame.maxX - CGFloat(config.minimumWidth),
                dragState.startFrame.origin.x + dx
            )
            frame.size.width = dragState.startFrame.maxX - frame.origin.x
        } else {
            frame.size.width = max(CGFloat(config.minimumWidth), dragState.startFrame.width + dx)
        }

        if dragState.anchor.resizeTop {
            frame.origin.y = min(
                dragState.startFrame.maxY - CGFloat(config.minimumHeight),
                dragState.startFrame.origin.y + dy
            )
            frame.size.height = dragState.startFrame.maxY - frame.origin.y
        } else {
            frame.size.height = max(CGFloat(config.minimumHeight), dragState.startFrame.height + dy)
        }

        set(frame: frame, for: dragState.window)
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
    let startMouse: CGPoint
    let startFrame: CGRect
    let anchor: ResizeAnchor
}

private struct ResizeAnchor {
    let resizeLeft: Bool
    let resizeTop: Bool
}

private func eventCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let app = Unmanaged<WindowResizeApp>.fromOpaque(refcon).takeUnretainedValue()
    return app.handle(type, event: event)
}
