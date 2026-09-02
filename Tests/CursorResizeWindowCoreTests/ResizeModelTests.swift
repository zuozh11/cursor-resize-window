import CoreGraphics
import XCTest
@testable import CursorResizeWindowCore

final class ResizeModelTests: XCTestCase {
    func testSelectsYabaiStyleDirectionFromPointerQuadrant() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)

        XCTAssertEqual(ResizeDirection.from(point: CGPoint(x: 150, y: 250), frame: frame), [.left, .top])
        XCTAssertEqual(ResizeDirection.from(point: CGPoint(x: 450, y: 450), frame: frame), [.right, .bottom])
    }

    func testResizesLeftTopUsingIncrementalDelta() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        let resized = ResizeModel.resize(frame: frame, direction: [.left, .top], dx: 20, dy: 30)

        XCTAssertEqual(resized, CGRect(x: 120, y: 230, width: 380, height: 270))
    }

    func testResizesRightBottomUsingIncrementalDelta() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        let resized = ResizeModel.resize(frame: frame, direction: [.right, .bottom], dx: 20, dy: 30)

        XCTAssertEqual(resized, CGRect(x: 100, y: 200, width: 420, height: 330))
    }

    func testClampsSizeToOneLikeYabai() {
        let frame = CGRect(x: 100, y: 200, width: 20, height: 30)
        let resized = ResizeModel.resize(frame: frame, direction: [.right, .bottom], dx: -100, dy: -100)

        XCTAssertEqual(resized.size, CGSize(width: 1, height: 1))
    }

    func testMapsNativeResizeToNearestCorner() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)

        XCTAssertEqual(
            NativeResizeMapping(pointer: CGPoint(x: 150, y: 250), frame: frame).anchor,
            CGPoint(x: 105, y: 205)
        )
        XCTAssertEqual(
            NativeResizeMapping(pointer: CGPoint(x: 450, y: 450), frame: frame).anchor,
            CGPoint(x: 495, y: 495)
        )
    }

    func testTranslatesNativeResizeEventsByPointerToCornerOffset() {
        let mapping = NativeResizeMapping(
            pointer: CGPoint(x: 150, y: 250),
            frame: CGRect(x: 100, y: 200, width: 400, height: 300)
        )

        XCTAssertEqual(mapping.translate(CGPoint(x: 170, y: 280)), CGPoint(x: 125, y: 235))
    }

    func testUsesNativeResizeWhenPointerAndCornerAreOnSameDisplay() {
        let mapping = NativeResizeMapping(
            pointer: CGPoint(x: 150, y: 250),
            frame: CGRect(x: 100, y: 200, width: 400, height: 300)
        )

        XCTAssertTrue(mapping.isClickable(in: [CGRect(x: 0, y: 0, width: 1440, height: 900)]))
    }

    func testFallsBackWhenNativeResizeCornerIsOutsideClickableDisplayBounds() {
        let mapping = NativeResizeMapping(
            pointer: CGPoint(x: 500, y: 300),
            frame: CGRect(x: -200, y: 100, width: 1600, height: 600)
        )

        XCTAssertFalse(mapping.isClickable(in: [CGRect(x: 0, y: 0, width: 1000, height: 800)]))
    }

    func testFallsBackWhenNativeResizeCornerIsOnAnotherDisplay() {
        let mapping = NativeResizeMapping(
            pointer: CGPoint(x: 800, y: 300),
            frame: CGRect(x: -200, y: 100, width: 1600, height: 600)
        )
        let displays = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1000, height: 800)
        ]

        XCTAssertFalse(mapping.isClickable(in: displays))
    }
}
