import AppKit

@MainActor
final class SynthesizedPointerOverlay {
    private static let dotSize: CGFloat = 12

    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.dotSize,
                height: Self.dotSize
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let dot = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.dotSize,
                height: Self.dotSize
            )
        )
        dot.wantsLayer = true
        dot.layer?.cornerRadius = Self.dotSize / 2
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.borderColor = NSColor.white.cgColor
        dot.layer?.borderWidth = 2
        panel.contentView = dot
    }

    func show(at point: CGPoint) {
        guard let primaryScreen = NSScreen.screens.first else {
            hide()
            return
        }

        let appKitY = primaryScreen.frame.maxY - point.y
        panel.setFrame(
            NSRect(
                x: point.x - Self.dotSize / 2,
                y: appKitY - Self.dotSize / 2,
                width: Self.dotSize,
                height: Self.dotSize
            ),
            display: false
        )

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }
}
