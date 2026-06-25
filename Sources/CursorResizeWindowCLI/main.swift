import CursorResizeWindowCore
import Foundation

do {
    let options = try CommandLineOptions.parse(arguments: CommandLine.arguments)

    if options.showHelp {
        print(CommandLineOptions.helpText)
        exit(EXIT_SUCCESS)
    }

    try WindowResizeApp().run()
} catch {
    fputs("cursor-resize-window: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
