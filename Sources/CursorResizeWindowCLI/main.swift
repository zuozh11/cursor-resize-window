import CursorResizeWindowCore
import Foundation

guard CommandLine.arguments.count == 1 else {
    fputs("usage: cursor-resize-window\n", stderr)
    exit(EXIT_FAILURE)
}

do {
    try WindowResizeApp().run()
} catch {
    fputs("cursor-resize-window: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
