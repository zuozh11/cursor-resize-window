import CursorResizeWindowCore
import Foundation

do {
    try WindowResizeApp().run()
} catch {
    fputs("cursor-resize-window: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
