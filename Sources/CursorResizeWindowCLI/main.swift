import CursorResizeWindowCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let mode: WindowResizeMode
switch arguments {
case []:
    mode = .accessibility
case ["--native"]:
    mode = .native
default:
    fputs("usage: cursor-resize-window [--native]\n", stderr)
    exit(EXIT_FAILURE)
}

do {
    try WindowResizeApp(mode: mode).run()
} catch {
    fputs("cursor-resize-window: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
