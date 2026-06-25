import CursorResizeWindowCore
import Foundation

do {
    let config = try AppConfig.load(arguments: CommandLine.arguments)

    if config.showHelp {
        print(AppConfig.helpText)
        exit(EXIT_SUCCESS)
    }

    try WindowResizeApp(config: config).run()
} catch {
    fputs("cursor-resize-window: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
