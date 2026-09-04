import AppKit

@MainActor
final class DragFeedbackOverlay {
    private static let dotSize: CGFloat = 12

    private let dotPanel: NSPanel
    private let cursorPanel: NSPanel
    private let dotView: NSView
    private let cursorImageView: NSImageView
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

        dotView = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.dotSize,
                height: Self.dotSize
            )
        )
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = Self.dotSize / 2
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.borderColor = NSColor.white.cgColor
        dotView.layer?.borderWidth = 2
        dotPanel.contentView = dotView

        cursorPanel = Self.makePanel(frame: .zero)
        cursorImageView = NSImageView(frame: .zero)
        cursorPanel.contentView = cursorImageView

        regionPanel = Self.makePanel(frame: .zero)
        regionView = ResizeRegionPreviewView(frame: .zero)
        regionPanel.contentView = regionView
    }

    func begin(at point: CGPoint, windowFrame: CGRect, target: ResizeTarget) {
        showPointer(at: point)
        regionView.target = target
        updateRegionFrame(windowFrame)
        regionPanel.orderFrontRegardless()
    }

    func update(at point: CGPoint, windowFrame: CGRect) {
        showPointer(at: point)
        updateRegionFrame(windowFrame)
    }

    func showPointer(at point: CGPoint) {
        guard let appKitPoint = appKitPoint(from: point) else {
            hideDot()
            return
        }

        dotPanel.setFrame(
            NSRect(
                x: point.x - Self.dotSize / 2,
                y: appKitPoint.y - Self.dotSize / 2,
                width: Self.dotSize,
                height: Self.dotSize
            ),
            display: false
        )

        if !dotPanel.isVisible {
            dotPanel.orderFrontRegardless()
        }
    }

    func showShadowCursor(at point: CGPoint, image: NSImage, hotSpot: CGPoint) {
        guard let appKitPoint = appKitPoint(from: point) else {
            hideShadowCursor()
            return
        }

        cursorImageView.image = image
        cursorImageView.imageScaling = .scaleNone
        cursorImageView.frame = NSRect(origin: .zero, size: image.size)
        cursorPanel.setFrame(
            NSRect(
                x: point.x - hotSpot.x,
                y: appKitPoint.y - image.size.height + hotSpot.y,
                width: image.size.width,
                height: image.size.height
            ),
            display: false
        )

        if !cursorPanel.isVisible {
            cursorPanel.orderFrontRegardless()
        }
    }

    func hide(keepingShadowCursor: Bool = false) {
        if regionPanel.isVisible {
            regionPanel.orderOut(nil)
        }
        if dotPanel.isVisible {
            dotPanel.orderOut(nil)
        }
        if !keepingShadowCursor {
            hideShadowCursor()
        }
    }

    func hideShadowCursor() {
        if cursorPanel.isVisible {
            cursorPanel.orderOut(nil)
        }
    }

    private func hideDot() {
        if dotPanel.isVisible {
            dotPanel.orderOut(nil)
        }
    }

    func updateRegionFrame(_ windowFrame: CGRect) {
        guard let regionFrame = appKitFrame(from: windowFrame) else {
            return
        }

        regionPanel.setFrame(regionFrame, display: true)
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

    private func appKitPoint(from point: CGPoint) -> CGPoint? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        return CGPoint(x: point.x, y: primaryScreen.frame.maxY - point.y)
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

        let leftWidth = bounds.width * ResizeTarget.middleBandMin
        let middleWidth = bounds.width * (ResizeTarget.middleBandMax - ResizeTarget.middleBandMin)
        let bottomHeight = bounds.height * ResizeTarget.middleBandMin
        let middleHeight = bounds.height * (ResizeTarget.middleBandMax - ResizeTarget.middleBandMin)
        let middleColumn = NSRect(
            x: leftWidth,
            y: 0,
            width: middleWidth,
            height: bounds.height
        )
        let middleRow = NSRect(
            x: 0,
            y: bottomHeight,
            width: bounds.width,
            height: middleHeight
        )

        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        middleColumn.fill()
        middleRow.fill()

        NSColor.systemRed.withAlphaComponent(0.28).setFill()
        targetRect(
            leftWidth: leftWidth,
            middleWidth: middleWidth,
            bottomHeight: bottomHeight,
            middleHeight: middleHeight
        ).fill()

        let grid = NSBezierPath()
        grid.lineWidth = 1
        grid.move(to: NSPoint(x: leftWidth, y: 0))
        grid.line(to: NSPoint(x: leftWidth, y: bounds.height))
        grid.move(to: NSPoint(x: leftWidth + middleWidth, y: 0))
        grid.line(to: NSPoint(x: leftWidth + middleWidth, y: bounds.height))
        grid.move(to: NSPoint(x: 0, y: bottomHeight))
        grid.line(to: NSPoint(x: bounds.width, y: bottomHeight))
        grid.move(to: NSPoint(x: 0, y: bottomHeight + middleHeight))
        grid.line(to: NSPoint(x: bounds.width, y: bottomHeight + middleHeight))
        NSColor.white.withAlphaComponent(0.72).setStroke()
        grid.stroke()

        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        border.stroke()
    }

    private func targetRect(
        leftWidth: CGFloat,
        middleWidth: CGFloat,
        bottomHeight: CGFloat,
        middleHeight: CGFloat
    ) -> NSRect {
        let rightOrigin = leftWidth + middleWidth
        let topOrigin = bottomHeight + middleHeight
        let rightWidth = bounds.width - rightOrigin
        let topHeight = bounds.height - topOrigin

        switch target {
        case .leftTop:
            return NSRect(x: 0, y: topOrigin, width: leftWidth, height: topHeight)
        case .top:
            return NSRect(x: leftWidth, y: topOrigin, width: middleWidth, height: topHeight)
        case .rightTop:
            return NSRect(x: rightOrigin, y: topOrigin, width: rightWidth, height: topHeight)
        case .left:
            return NSRect(x: 0, y: bottomHeight, width: leftWidth, height: middleHeight)
        case .move:
            return NSRect(x: leftWidth, y: bottomHeight, width: middleWidth, height: middleHeight)
        case .right:
            return NSRect(x: rightOrigin, y: bottomHeight, width: rightWidth, height: middleHeight)
        case .leftBottom:
            return NSRect(x: 0, y: 0, width: leftWidth, height: bottomHeight)
        case .bottom:
            return NSRect(x: leftWidth, y: 0, width: middleWidth, height: bottomHeight)
        case .rightBottom:
            return NSRect(x: rightOrigin, y: 0, width: rightWidth, height: bottomHeight)
        }
    }
}
