import Foundation
import XCTest
@testable import CursorResizeWindowCore

final class TitleBarDragSettingsTests: XCTestCase {
    func testLoadsPerApplicationOffsetsIntoNativeDragMapping() throws {
        let domain = "com.zuozhi.cursor-resize-window.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set([
            "com.google.Chrome": 2.0,
            "com.jetbrains.intellij": 6.0,
            "zero-offset-app": 0.0
        ], forKey: TitleBarDragSettings.offsetsKey)

        let settings = TitleBarDragSettings(defaults: defaults)
        let frame = CGRect(x: 100, y: 200, width: 600, height: 400)
        let pointer = CGPoint(x: 350, y: 400)
        let cases: [(String?, CGFloat)] = [
            ("com.google.Chrome", 2),
            ("com.jetbrains.intellij", 6),
            ("zero-offset-app", 0),
            ("com.apple.Safari", 6),
            (nil, 6)
        ]

        for (bundleIdentifier, expectedOffset) in cases {
            let mapping = NativeDragMapping(
                pointer: pointer,
                frame: frame,
                target: .move,
                titleBarYOffset: settings.yOffset(for: bundleIdentifier)
            )
            XCTAssertEqual(mapping.anchor, CGPoint(x: 350, y: 200 + expectedOffset))
            let translated = mapping.translate(CGPoint(x: 380, y: 420))
            XCTAssertEqual(translated, CGPoint(x: 380, y: 220 + expectedOffset))
            XCTAssertEqual(mapping.visiblePointer(for: translated), CGPoint(x: 380, y: 420))
        }

        defaults.removeObject(forKey: TitleBarDragSettings.offsetsKey)
        let resetSettings = TitleBarDragSettings(defaults: defaults)
        XCTAssertEqual(resetSettings.yOffset(for: "com.google.Chrome"), 6)
    }

    func testTitleBarOffsetDoesNotChangeResizeAnchorsOrTranslation() {
        let frame = CGRect(x: 100, y: 200, width: 600, height: 400)
        let pointer = CGPoint(x: 350, y: 400)

        for target in ResizeTarget.allCases where target != .move {
            let defaultMapping = NativeDragMapping(pointer: pointer, frame: frame, target: target)
            let customMapping = NativeDragMapping(
                pointer: pointer,
                frame: frame,
                target: target,
                titleBarYOffset: 15
            )

            XCTAssertEqual(customMapping.anchor, defaultMapping.anchor)
            XCTAssertEqual(
                customMapping.translate(CGPoint(x: 380, y: 420)),
                defaultMapping.translate(CGPoint(x: 380, y: 420))
            )
        }
    }
}
