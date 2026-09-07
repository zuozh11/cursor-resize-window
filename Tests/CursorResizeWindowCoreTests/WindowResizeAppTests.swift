import ApplicationServices
import CoreGraphics
import XCTest
@testable import CursorResizeWindowCore

final class WindowResizeAppTests: XCTestCase {
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
    func testPreviewWaitsForRealWindowMovementBeforeFollowingPointer() {
        let initial = CGRect(x: 100, y: 100, width: 600, height: 400)
        let mapping = NativeDragMapping(pointer: CGPoint(x: 400, y: 300), frame: initial, target: .move)
        let state = NativeDragState(
            window: AXUIElementCreateSystemWide(), windowID: 1, mapping: mapping,
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            screenBounds: [], frame: initial, target: .move
        )
        state.beginPreviewMovement(at: CGPoint(x: 410, y: 110))
        XCTAssertEqual(state.updatePreviewFrame(for: CGPoint(x: 430, y: 120)), initial)
        state.observeInitialWindowFrame(initial)
        XCTAssertEqual(state.updatePreviewFrame(for: CGPoint(x: 460, y: 135)), initial)
        XCTAssertTrue(state.awaitingWindowMovement)

        let actual = initial.offsetBy(dx: 5, dy: 4)
        state.observeInitialWindowFrame(actual)
        XCTAssertFalse(state.awaitingWindowMovement)
        XCTAssertEqual(
            state.updatePreviewFrame(for: CGPoint(x: 470, y: 140)),
            actual.offsetBy(dx: 10, dy: 5)
        )
        state.observeInitialWindowFrame(initial)
        XCTAssertEqual(
            state.updatePreviewFrame(for: CGPoint(x: 480, y: 145)),
            actual.offsetBy(dx: 20, dy: 10)
        )
    }
}
