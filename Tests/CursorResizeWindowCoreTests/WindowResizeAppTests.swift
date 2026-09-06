import ApplicationServices
import CoreGraphics
import XCTest
@testable import CursorResizeWindowCore

final class WindowResizeAppTests: XCTestCase {
    func testAccessibilityFallbackMovesUsingIncrementalDeltaWithoutResizing() {
        let state = DragState(
            window: AXUIElementCreateApplication(getpid()),
            downLocation: CGPoint(x: 500, y: 400),
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            target: .move
        )

        XCTAssertEqual(
            state.updateFrame(to: CGPoint(x: 540, y: 425)),
            CGRect(x: 140, y: 125, width: 800, height: 600)
        )
        XCTAssertEqual(
            state.updateFrame(to: CGPoint(x: 520, y: 415)),
            CGRect(x: 120, y: 115, width: 800, height: 600)
        )
    }

    func testAccessibilityFallbackStillResizesSelectedCorner() {
        let state = DragState(
            window: AXUIElementCreateApplication(getpid()),
            downLocation: CGPoint(x: 100, y: 100),
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            target: .leftTop
        )

        XCTAssertEqual(
            state.updateFrame(to: CGPoint(x: 120, y: 130)),
            CGRect(x: 120, y: 130, width: 780, height: 570)
        )
    }

    func testPreparesNativeMouseDownWithoutDraggedEventDelta() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let event = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: CGPoint(x: 500, y: 600),
                mouseButton: .left
            )
        )
        event.setIntegerValueField(.mouseEventDeltaX, value: -8)
        event.setIntegerValueField(.mouseEventDeltaY, value: 12)

        prepareNativeMouseDown(event, at: CGPoint(x: 300, y: 106))

        XCTAssertEqual(event.type, .leftMouseDown)
        XCTAssertEqual(event.location, CGPoint(x: 300, y: 106))
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaX), 0)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaY), 0)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 0)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 1)
        XCTAssertEqual(event.getDoubleValueField(.mouseEventPressure), 1)
    }

    func testArmingBufferFlushesLatestDragThenDeferredMouseUpOnce() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let firstDrag = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: CGPoint(x: 100, y: 100),
                mouseButton: .left
            )
        )
        firstDrag.flags = .maskControl
        let latestDrag = try XCTUnwrap(firstDrag.copy())
        let mouseUp = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: 130, y: 140),
                mouseButton: .left
            )
        )
        let buffer = NativeDragArmingBuffer()

        buffer.begin(with: firstDrag, at: CGPoint(x: 300, y: 40))
        XCTAssertTrue(buffer.update(with: latestDrag, at: CGPoint(x: 320, y: 60)))
        XCTAssertTrue(buffer.deferMouseUp(mouseUp))

        let events = try XCTUnwrap(buffer.finish())
        XCTAssertEqual(events.drag.type, .leftMouseDragged)
        XCTAssertEqual(events.drag.location, CGPoint(x: 320, y: 60))
        XCTAssertFalse(events.drag.flags.contains(.maskControl))
        XCTAssertEqual(events.mouseUp?.type, .leftMouseUp)
        XCTAssertEqual(events.mouseUp?.location, CGPoint(x: 320, y: 60))
        XCTAssertNil(buffer.finish())
    }

    func testArmingBufferIgnoresUpdatesBeforeItBegins() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let drag = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: CGPoint(x: 100, y: 100),
                mouseButton: .left
            )
        )
        let mouseUp = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: 100, y: 100),
                mouseButton: .left
            )
        )
        let buffer = NativeDragArmingBuffer()

        XCTAssertFalse(buffer.update(with: drag, at: CGPoint(x: 200, y: 200)))
        XCTAssertFalse(buffer.deferMouseUp(mouseUp))
        XCTAssertNil(buffer.finish())
    }
}
