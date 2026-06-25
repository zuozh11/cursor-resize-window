import XCTest
@testable import CursorResizeWindowCore

final class CommandLineOptionsTests: XCTestCase {
    func testParsesNoConfiguration() throws {
        let options = try CommandLineOptions.parse(arguments: ["cursor-resize-window"])

        XCTAssertFalse(options.showHelp)
    }

    func testParsesHelpOnly() throws {
        let options = try CommandLineOptions.parse(arguments: ["cursor-resize-window", "--help"])

        XCTAssertTrue(options.showHelp)
    }

    func testRejectsModifierArgument() {
        XCTAssertThrowsError(
            try CommandLineOptions.parse(arguments: ["cursor-resize-window", "--modifier", "cmd"])
        )
    }
}
