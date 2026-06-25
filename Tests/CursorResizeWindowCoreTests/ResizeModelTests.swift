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
}
