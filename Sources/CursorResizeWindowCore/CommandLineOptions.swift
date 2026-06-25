import Foundation

public enum CommandLineError: Error, CustomStringConvertible {
    case unknownArgument(String)

    public var description: String {
        switch self {
        case let .unknownArgument(value):
            "unknown argument: \(value)"
        }
    }
}

public struct CommandLineOptions: Equatable {
    public var showHelp: Bool

    public init(showHelp: Bool = false) {
        self.showHelp = showHelp
    }

    public static let helpText = """
    cursor-resize-window

    Resize the window under the pointer by holding ctrl and dragging with the left mouse button.

    Usage:
      cursor-resize-window
      cursor-resize-window --help
    """

    public static func parse(arguments: [String]) throws -> CommandLineOptions {
        var options = CommandLineOptions()

        for argument in arguments.dropFirst() {
            switch argument {
            case "--help", "-h":
                options.showHelp = true
            default:
                throw CommandLineError.unknownArgument(argument)
            }
        }

        return options
    }
}
