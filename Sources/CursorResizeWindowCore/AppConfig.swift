import ApplicationServices
import Foundation

public enum ConfigError: Error, CustomStringConvertible {
    case unknownArgument(String)
    case missingArgumentValue(String)
    case invalidModifier(String)
    case invalidMinimumSize(String)
    case unreadableConfig(String)

    public var description: String {
        switch self {
        case let .unknownArgument(value):
            "unknown argument: \(value)"
        case let .missingArgumentValue(value):
            "missing value for \(value)"
        case let .invalidModifier(value):
            "invalid modifier '\(value)'; use ctrl, cmd, alt, shift, or fn"
        case let .invalidMinimumSize(value):
            "invalid minimum size '\(value)'; use WIDTHxHEIGHT, for example 160x120"
        case let .unreadableConfig(path):
            "unable to read config file at \(path)"
        }
    }
}

public enum MouseModifier: String, CaseIterable {
    case ctrl
    case cmd
    case alt
    case shift
    case fn

    public var eventFlag: CGEventFlags {
        switch self {
        case .ctrl:
            .maskControl
        case .cmd:
            .maskCommand
        case .alt:
            .maskAlternate
        case .shift:
            .maskShift
        case .fn:
            .maskSecondaryFn
        }
    }

    static func parse(_ value: String) -> MouseModifier? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ctrl", "control":
            .ctrl
        case "cmd", "command", "super":
            .cmd
        case "alt", "option", "opt":
            .alt
        case "shift":
            .shift
        case "fn", "function":
            .fn
        default:
            nil
        }
    }
}

public struct AppConfig: Equatable {
    public var modifier: MouseModifier
    public var minimumWidth: Double
    public var minimumHeight: Double
    public var showHelp: Bool

    public init(
        modifier: MouseModifier = .ctrl,
        minimumWidth: Double = 160,
        minimumHeight: Double = 120,
        showHelp: Bool = false
    ) {
        self.modifier = modifier
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        self.showHelp = showHelp
    }

    public static let helpText = """
    cursor-resize-window

    Resize the window under the pointer by holding a modifier and dragging with the left mouse button.

    Usage:
      cursor-resize-window [--modifier ctrl|cmd|alt|shift|fn] [--min-size WIDTHxHEIGHT]
      cursor-resize-window --help

    Config:
      ~/.config/cursor-resize-window/config

    Example config:
      modifier = ctrl
      min_width = 160
      min_height = 120
    """

    public static func load(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileReader: (String) throws -> String = { try String(contentsOfFile: $0, encoding: .utf8) }
    ) throws -> AppConfig {
        var config = AppConfig()
        let configPath = defaultConfigPath(environment: environment)

        if FileManager.default.fileExists(atPath: configPath) {
            do {
                try config.applyConfigFile(try fileReader(configPath))
            } catch {
                throw ConfigError.unreadableConfig(configPath)
            }
        }

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                config.showHelp = true
            case "--modifier":
                index += 1
                guard index < arguments.count else {
                    throw ConfigError.missingArgumentValue(argument)
                }
                try config.setModifier(arguments[index])
            case "--min-size":
                index += 1
                guard index < arguments.count else {
                    throw ConfigError.missingArgumentValue(argument)
                }
                try config.setMinimumSize(arguments[index])
            case "--config":
                index += 1
                guard index < arguments.count else {
                    throw ConfigError.missingArgumentValue(argument)
                }
                do {
                    try config.applyConfigFile(try fileReader(arguments[index]))
                } catch {
                    throw ConfigError.unreadableConfig(arguments[index])
                }
            default:
                throw ConfigError.unknownArgument(argument)
            }
            index += 1
        }

        return config
    }

    static func defaultConfigPath(environment: [String: String]) -> String {
        if let explicitPath = environment["CURSOR_RESIZE_WINDOW_CONFIG"], !explicitPath.isEmpty {
            return explicitPath
        }

        let home = environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/.config/cursor-resize-window/config"
    }

    private mutating func applyConfigFile(_ contents: String) throws {
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }

            guard parts.count == 2 else {
                continue
            }

            switch parts[0] {
            case "modifier":
                try setModifier(parts[1])
            case "min_width":
                guard let value = Double(parts[1]), value > 0 else {
                    throw ConfigError.invalidMinimumSize(parts[1])
                }
                minimumWidth = value
            case "min_height":
                guard let value = Double(parts[1]), value > 0 else {
                    throw ConfigError.invalidMinimumSize(parts[1])
                }
                minimumHeight = value
            case "min_size":
                try setMinimumSize(parts[1])
            default:
                continue
            }
        }
    }

    private mutating func setModifier(_ value: String) throws {
        guard let parsed = MouseModifier.parse(value) else {
            throw ConfigError.invalidModifier(value)
        }
        modifier = parsed
    }

    private mutating func setMinimumSize(_ value: String) throws {
        let parts = value.lowercased().split(separator: "x", maxSplits: 1)
        guard
            parts.count == 2,
            let width = Double(parts[0]),
            let height = Double(parts[1]),
            width > 0,
            height > 0
        else {
            throw ConfigError.invalidMinimumSize(value)
        }

        minimumWidth = width
        minimumHeight = height
    }
}
