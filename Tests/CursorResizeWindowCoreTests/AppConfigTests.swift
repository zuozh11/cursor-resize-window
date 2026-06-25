import XCTest
@testable import CursorResizeWindowCore

final class AppConfigTests: XCTestCase {
    func testDefaultsToControlModifier() throws {
        let config = try AppConfig.load(
            arguments: ["cursor-resize-window"],
            environment: ["HOME": "/tmp/nonexistent"],
            fileReader: { _ in "" }
        )

        XCTAssertEqual(config.modifier, .ctrl)
        XCTAssertEqual(config.minimumWidth, 160)
        XCTAssertEqual(config.minimumHeight, 120)
    }

    func testCommandLineOverridesConfigFile() throws {
        let config = try AppConfig.load(
            arguments: ["cursor-resize-window", "--config", "/tmp/config", "--modifier", "cmd", "--min-size", "200x140"],
            environment: ["HOME": "/tmp/nonexistent"],
            fileReader: { _ in "modifier = alt\nmin_width = 180\nmin_height = 130\n" }
        )

        XCTAssertEqual(config.modifier, .cmd)
        XCTAssertEqual(config.minimumWidth, 200)
        XCTAssertEqual(config.minimumHeight, 140)
    }

    func testRejectsInvalidModifier() {
        XCTAssertThrowsError(
            try AppConfig.load(
                arguments: ["cursor-resize-window", "--modifier", "capslock"],
                environment: ["HOME": "/tmp/nonexistent"],
                fileReader: { _ in "" }
            )
        )
    }
}
