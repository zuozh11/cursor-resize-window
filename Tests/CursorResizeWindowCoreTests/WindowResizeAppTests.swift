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
}
