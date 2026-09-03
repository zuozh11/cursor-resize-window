import AppKit

@MainActor
final class DragFeedbackOverlay {
    private static let dotSize: CGFloat = 12

    private let dotPanel: NSPanel
    private let regionPanel: NSPanel
    private let regionView: ResizeRegionPreviewView

    init() {
        dotPanel = Self.makePanel(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.dotSize,
                height: Self.dotSize
            )
        )

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
        dotPanel.contentView = dot

        regionPanel = Self.makePanel(frame: .zero)
        regionView = ResizeRegionPreviewView(frame: .zero)
        regionPanel.contentView = regionView
    }

    func begin(at point: CGPoint, windowFrame: CGRect, target: ResizeTarget) {
        showPointer(at: point)

        guard let regionFrame = appKitFrame(from: windowFrame) else {
            return
        }

        regionView.target = target
        regionPanel.setFrame(regionFrame, display: true)
        regionPanel.orderFrontRegardless()
    }

    func showPointer(at point: CGPoint) {
        guard let primaryScreen = NSScreen.screens.first else {
            hide()
            return
        }

        let appKitY = primaryScreen.frame.maxY - point.y
        dotPanel.setFrame(
            NSRect(
                x: point.x - Self.dotSize / 2,
                y: appKitY - Self.dotSize / 2,
                width: Self.dotSize,
                height: Self.dotSize
            ),
            display: false
        )

        if !dotPanel.isVisible {
            dotPanel.orderFrontRegardless()
        }
    }

    func hideRegionPreview() {
        if regionPanel.isVisible {
            regionPanel.orderOut(nil)
        }
    }

    func hide() {
        hideRegionPreview()
        if dotPanel.isVisible {
            dotPanel.orderOut(nil)
        }
    }

    private func appKitFrame(from frame: CGRect) -> NSRect? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        return NSRect(
            x: frame.minX,
            y: primaryScreen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private static func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
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
        return panel
    }
}

private final class ResizeRegionPreviewView: NSView {
    var target: ResizeTarget = .move {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cellWidth = bounds.width / 3
        let cellHeight = bounds.height / 3
        let middleColumn = NSRect(
            x: cellWidth,
            y: 0,
            width: cellWidth,
            height: bounds.height
        )
        let middleRow = NSRect(
            x: 0,
            y: cellHeight,
            width: bounds.width,
            height: cellHeight
        )

        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        middleColumn.fill()
        middleRow.fill()

        NSColor.systemRed.withAlphaComponent(0.28).setFill()
        targetRect(cellWidth: cellWidth, cellHeight: cellHeight).fill()

        let grid = NSBezierPath()
        grid.lineWidth = 1
        grid.move(to: NSPoint(x: cellWidth, y: 0))
        grid.line(to: NSPoint(x: cellWidth, y: bounds.height))
        grid.move(to: NSPoint(x: cellWidth * 2, y: 0))
        grid.line(to: NSPoint(x: cellWidth * 2, y: bounds.height))
        grid.move(to: NSPoint(x: 0, y: cellHeight))
        grid.line(to: NSPoint(x: bounds.width, y: cellHeight))
        grid.move(to: NSPoint(x: 0, y: cellHeight * 2))
        grid.line(to: NSPoint(x: bounds.width, y: cellHeight * 2))
        NSColor.white.withAlphaComponent(0.72).setStroke()
        grid.stroke()

        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        border.stroke()
    }

    private func targetRect(cellWidth: CGFloat, cellHeight: CGFloat) -> NSRect {
        let column: CGFloat
        let row: CGFloat

        switch target {
        case .leftTop:
            (column, row) = (0, 2)
        case .top:
            (column, row) = (1, 2)
        case .rightTop:
            (column, row) = (2, 2)
        case .left:
            (column, row) = (0, 1)
        case .move:
            (column, row) = (1, 1)
        case .right:
            (column, row) = (2, 1)
        case .leftBottom:
            (column, row) = (0, 0)
        case .bottom:
            (column, row) = (1, 0)
        case .rightBottom:
            (column, row) = (2, 0)
        }

        return NSRect(
            x: column * cellWidth,
            y: row * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
    }
}
