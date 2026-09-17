import AppKit
import XCTest
@testable import CursorResizeWindowCore

final class ShadowCursorAppearanceTests: XCTestCase {
    func testScalesImageAndHotSpotWithoutChangingSourceImage() {
        let image = NSImage(size: NSSize(width: 24, height: 32))
        let hotSpot = CGPoint(x: 3, y: 5)

        for scale: CGFloat in [1, 2.025, 4] {
            let appearance = ShadowCursorAppearance(image: image, hotSpot: hotSpot, scale: scale)

            XCTAssertEqual(appearance.image.size, NSSize(width: 24 * scale, height: 32 * scale))
            XCTAssertEqual(appearance.hotSpot, CGPoint(x: 3 * scale, y: 5 * scale))
            XCTAssertEqual(image.size, NSSize(width: 24, height: 32))
            XCTAssertFalse(appearance.image === image)
        }
    }

    func testInvalidScalesPreserveNormalSizeAndHotSpot() {
        let image = NSImage(size: NSSize(width: 24, height: 32))
        let hotSpot = CGPoint(x: 3, y: 5)

        for scale: CGFloat in [0, -1, 0.5, .nan, .infinity] {
            let appearance = ShadowCursorAppearance(image: image, hotSpot: hotSpot, scale: scale)

            XCTAssertEqual(appearance.image.size, image.size)
            XCTAssertEqual(appearance.hotSpot, hotSpot)
        }
    }
}
