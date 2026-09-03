import CoreGraphics
import XCTest
@testable import CursorResizeWindowCore

final class ResizeModelTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 200, width: 300, height: 300)

    func testMapsOuterRegionsToCornerTargets() {
        XCTAssertEqual(target(x: 0.1, y: 0.1), .leftTop)
        XCTAssertEqual(target(x: 0.9, y: 0.1), .rightTop)
        XCTAssertEqual(target(x: 0.1, y: 0.9), .leftBottom)
        XCTAssertEqual(target(x: 0.9, y: 0.9), .rightBottom)
    }

    func testMapsCrossArmsToEdgeTargets() {
        XCTAssertEqual(target(x: 0.1, y: 0.5), .left)
        XCTAssertEqual(target(x: 0.9, y: 0.5), .right)
        XCTAssertEqual(target(x: 0.5, y: 0.1), .top)
        XCTAssertEqual(target(x: 0.5, y: 0.9), .bottom)
    }

    func testMapsCenterIntersectionToMove() {
        XCTAssertEqual(target(x: 0.4, y: 0.5), .move)
        XCTAssertEqual(target(x: 0.5, y: 0.4), .move)
        XCTAssertEqual(target(x: 0.4, y: 0.4), .move)
        XCTAssertEqual(target(x: 0.5, y: 0.5), .move)
    }

    func testIncludesThirdBoundariesInCross() {
        XCTAssertEqual(target(x: 1.0 / 3.0, y: 0.1), .top)
        XCTAssertEqual(target(x: 2.0 / 3.0, y: 0.1), .top)
        XCTAssertEqual(target(x: 0.1, y: 1.0 / 3.0), .left)
        XCTAssertEqual(target(x: 0.1, y: 2.0 / 3.0), .left)
        XCTAssertEqual(target(x: 1.0 / 3.0, y: 1.0 / 3.0), .move)
        XCTAssertEqual(target(x: 2.0 / 3.0, y: 2.0 / 3.0), .move)
    }

    func testIncludesExactThirdBoundaryForNegativeNonDivisibleFrame() {
        let frame = CGRect(x: -1000, y: 200, width: 50, height: 50)
        let point = CGPoint(x: frame.minX + frame.width / 3.0, y: frame.minY + 5)

        XCTAssertEqual(ResizeTarget.from(point: point, frame: frame), .top)
    }

    func testMapsResizeTargetsToDirections() {
        let expected: [ResizeTarget: ResizeDirection?] = [
            .move: nil,
            .left: .left,
            .right: .right,
            .top: .top,
            .bottom: .bottom,
            .leftTop: [.left, .top],
            .rightTop: [.right, .top],
            .leftBottom: [.left, .bottom],
            .rightBottom: [.right, .bottom]
        ]

        for target in ResizeTarget.allCases {
            XCTAssertEqual(target.resizeDirection, expected[target]!)
        }
    }

    func testMapsEveryTargetToNativeAnchor() {
        let pointer = CGPoint(x: 250, y: 350)
        let expected: [ResizeTarget: CGPoint] = [
            .move: CGPoint(x: 250, y: 203),
            .left: CGPoint(x: 102, y: 350),
            .right: CGPoint(x: 398, y: 350),
            .top: CGPoint(x: 250, y: 202),
            .bottom: CGPoint(x: 250, y: 498),
            .leftTop: CGPoint(x: 105, y: 205),
            .rightTop: CGPoint(x: 395, y: 205),
            .leftBottom: CGPoint(x: 105, y: 495),
            .rightBottom: CGPoint(x: 395, y: 495)
        ]

        for target in ResizeTarget.allCases {
            let mapping = NativeDragMapping(pointer: pointer, frame: frame, target: target)
            XCTAssertEqual(mapping.anchor, expected[target])
        }
    }

    func testResizesLeftTopUsingIncrementalDelta() {
        let resized = ResizeModel.resize(frame: frame, direction: [.left, .top], dx: 20, dy: 30)

        XCTAssertEqual(resized, CGRect(x: 120, y: 230, width: 280, height: 270))
    }

    func testResizesRightBottomUsingIncrementalDelta() {
        let resized = ResizeModel.resize(frame: frame, direction: [.right, .bottom], dx: 20, dy: 30)

        XCTAssertEqual(resized, CGRect(x: 100, y: 200, width: 320, height: 330))
    }

    func testResizesHorizontalEdgesWithoutChangingHeight() {
        let left = ResizeModel.resize(frame: frame, direction: .left, dx: 20, dy: 30)
        let right = ResizeModel.resize(frame: frame, direction: .right, dx: 20, dy: 30)

        XCTAssertEqual(left, CGRect(x: 120, y: 200, width: 280, height: 300))
        XCTAssertEqual(right, CGRect(x: 100, y: 200, width: 320, height: 300))
    }

    func testResizesVerticalEdgesWithoutChangingWidth() {
        let top = ResizeModel.resize(frame: frame, direction: .top, dx: 20, dy: 30)
        let bottom = ResizeModel.resize(frame: frame, direction: .bottom, dx: 20, dy: 30)

        XCTAssertEqual(top, CGRect(x: 100, y: 230, width: 300, height: 270))
        XCTAssertEqual(bottom, CGRect(x: 100, y: 200, width: 300, height: 330))
    }

    func testClampsSizeToOneLikeYabai() {
        let smallFrame = CGRect(x: 100, y: 200, width: 20, height: 30)
        let resized = ResizeModel.resize(frame: smallFrame, direction: [.right, .bottom], dx: -100, dy: -100)

        XCTAssertEqual(resized.size, CGSize(width: 1, height: 1))
    }

    func testTranslatesNativeMoveEventsOnBothAxes() {
        let mapping = NativeDragMapping(pointer: CGPoint(x: 250, y: 350), frame: frame, target: .move)

        XCTAssertEqual(mapping.translate(CGPoint(x: 270, y: 380)), CGPoint(x: 270, y: 233))
    }

    func testLocksUnrelatedAxisForNativeEdgeResizeEvents() {
        let left = NativeDragMapping(pointer: CGPoint(x: 150, y: 350), frame: frame, target: .left)
        let right = NativeDragMapping(pointer: CGPoint(x: 350, y: 350), frame: frame, target: .right)
        let top = NativeDragMapping(pointer: CGPoint(x: 250, y: 250), frame: frame, target: .top)
        let bottom = NativeDragMapping(pointer: CGPoint(x: 250, y: 450), frame: frame, target: .bottom)

        XCTAssertEqual(left.translate(CGPoint(x: 170, y: 380)), CGPoint(x: 122, y: 350))
        XCTAssertEqual(right.translate(CGPoint(x: 330, y: 380)), CGPoint(x: 378, y: 350))
        XCTAssertEqual(top.translate(CGPoint(x: 270, y: 280)), CGPoint(x: 250, y: 232))
        XCTAssertEqual(bottom.translate(CGPoint(x: 270, y: 420)), CGPoint(x: 250, y: 468))
    }

    func testTranslatesNativeCornerResizeEventsOnBothAxes() {
        let mapping = NativeDragMapping(pointer: CGPoint(x: 150, y: 250), frame: frame, target: .leftTop)

        XCTAssertEqual(mapping.translate(CGPoint(x: 170, y: 280)), CGPoint(x: 125, y: 235))
    }

    func testUsesNativeResizeWhenPointerAndAnchorAreOnSameDisplay() {
        let mapping = NativeDragMapping(pointer: CGPoint(x: 150, y: 350), frame: frame, target: .left)

        XCTAssertTrue(mapping.isClickable(in: [CGRect(x: 0, y: 0, width: 1440, height: 900)]))
    }

    func testFallsBackWhenNativeResizeAnchorIsOutsideClickableDisplayBounds() {
        let mapping = NativeDragMapping(
            pointer: CGPoint(x: 500, y: 300),
            frame: CGRect(x: -200, y: 100, width: 1600, height: 600),
            target: .right
        )

        XCTAssertFalse(mapping.isClickable(in: [CGRect(x: 0, y: 0, width: 1000, height: 800)]))
    }

    func testFallsBackWhenNativeResizeAnchorIsOnAnotherDisplay() {
        let mapping = NativeDragMapping(
            pointer: CGPoint(x: 800, y: 300),
            frame: CGRect(x: -200, y: 100, width: 1600, height: 600),
            target: .right
        )
        let displays = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1000, height: 800)
        ]

        XCTAssertFalse(mapping.isClickable(in: displays))
    }

    private func target(x: CGFloat, y: CGFloat) -> ResizeTarget {
        ResizeTarget.from(
            point: CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y),
            frame: frame
        )
    }
}
