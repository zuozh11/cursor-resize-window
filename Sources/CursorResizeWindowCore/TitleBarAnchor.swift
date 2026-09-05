@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

// AX describes controls and background candidates, not native drag regions.
func findTitleBarAnchor(
    window: AXUIElement,
    frame: CGRect,
    pointer: CGPoint,
    display: CGRect,
    yOffset: CGFloat
) -> CGPoint? {
    let started = CFAbsoluteTimeGetCurrent()
    let y = frame.minY + yOffset
    let left = max(frame.minX + 16, display.minX)
    let right = min(frame.maxX - 16, display.maxX - 1)
    var inspected = 0
    var blocked: [(CGFloat, CGFloat)] = []
    var complete = true
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.02)

    func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
    }
    func rect(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute),
              let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }
    func hit(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success else {
            return nil
        }
        if let element {
            AXUIElementSetMessagingTimeout(element, 0.02)
        }
        return element
    }
    guard left < right, display.contains(CGPoint(x: left, y: y)) else {
        return nil
    }
    let original = CGPoint(x: min(max(pointer.x, left), right), y: y)
    if let element = hit(at: original), CFEqual(element, window) {
        return original
    }

    let containers: Set<String> = [kAXWindowRole, kAXGroupRole, kAXToolbarRole, kAXSplitGroupRole]
    func visit(_ element: AXUIElement, depth: Int) {
        guard complete else { return }
        guard depth < 16, inspected < 96, CFAbsoluteTimeGetCurrent() - started < 0.08 else {
            complete = false
            return
        }
        inspected += 1
        AXUIElementSetMessagingTimeout(element, 0.02)
        guard let role = value(element, kAXRoleAttribute) as? String else {
            complete = false
            return
        }
        let bounds = CFEqual(element, window) ? frame : rect(element)
        var actionsRef: CFArray?
        let actionResult = AXUIElementCopyActionNames(element, &actionsRef)
        guard actionResult == .success else {
            complete = false
            return
        }
        let actions = actionsRef as? [String] ?? []
        let structural = containers.contains(role) && actions.allSatisfy {
            $0 == kAXRaiseAction || $0 == kAXShowMenuAction
        }
        if !structural {
            guard let bounds else {
                complete = false
                return
            }
            if bounds.minY <= y && y <= bounds.maxY && bounds.width > 0 && bounds.height > 0 {
                blocked.append((bounds.minX - 2, bounds.maxX + 2))
            }
            return
        }
        // Transparent containers may have children outside their own bounds.
        guard let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else {
            complete = false
            return
        }
        for child in children { visit(child, depth: depth + 1) }
    }
    visit(window, depth: 0)
    guard complete else { return nil }

    var gaps: [(CGFloat, CGFloat)] = [(left, right)]
    for (start, end) in blocked {
        gaps = gaps.flatMap { lo, hi -> [(CGFloat, CGFloat)] in
            if end <= lo || start >= hi { return [(lo, hi)] }
            var remaining: [(CGFloat, CGFloat)] = []
            if start > lo { remaining.append((lo, min(start, hi))) }
            if end < hi { remaining.append((max(end, lo), hi)) }
            return remaining
        }
    }
    let candidates = gaps.filter { $0.1 - $0.0 >= 8 }.map { lo, hi in
        CGPoint(x: min(max(pointer.x, lo + 4), hi - 4), y: y)
    }.sorted { abs($0.x - pointer.x) < abs($1.x - pointer.x) }
    for candidate in candidates.prefix(12) {
        guard CFAbsoluteTimeGetCurrent() - started < 0.12 else { break }
        guard let element = hit(at: candidate),
              let role = value(element, kAXRoleAttribute) as? String
        else { continue }
        guard containers.contains(role) else { continue }
        let owner = CFEqual(element, window) ? window : value(element, kAXWindowAttribute)
        guard let owner, CFEqual(owner, window) else { continue }
        return candidate
    }
    return nil
}
