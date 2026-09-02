import CoreGraphics

struct ResizeDirection: OptionSet, Equatable {
    let rawValue: UInt8

    static let left = ResizeDirection(rawValue: 1 << 0)
    static let top = ResizeDirection(rawValue: 1 << 1)
    static let right = ResizeDirection(rawValue: 1 << 2)
    static let bottom = ResizeDirection(rawValue: 1 << 3)

    static func from(point: CGPoint, frame: CGRect) -> ResizeDirection {
        var direction: ResizeDirection = []
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)

        if point.x < midpoint.x {
            direction.insert(.left)
        }
        if point.y < midpoint.y {
            direction.insert(.top)
        }
        if point.x > midpoint.x {
            direction.insert(.right)
        }
        if point.y > midpoint.y {
            direction.insert(.bottom)
        }

        return direction
    }
}

enum ResizeModel {
    static func resize(frame: CGRect, direction: ResizeDirection, dx: CGFloat, dy: CGFloat) -> CGRect {
        let xModifier: CGFloat
        if direction.contains(.left) {
            xModifier = -1
        } else if direction.contains(.right) {
            xModifier = 1
        } else {
            xModifier = 0
        }

        let yModifier: CGFloat
        if direction.contains(.top) {
            yModifier = -1
        } else if direction.contains(.bottom) {
            yModifier = 1
        } else {
            yModifier = 0
        }

        let width = max(1, frame.width + dx * xModifier)
        let height = max(1, frame.height + dy * yModifier)
        let x = direction.contains(.left) ? frame.origin.x + frame.width - width : frame.origin.x
        let y = direction.contains(.top) ? frame.origin.y + frame.height - height : frame.origin.y

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct NativeResizeMapping: Equatable {
    private static let cornerInset: CGFloat = 5

    let anchor: CGPoint
    private let offset: CGPoint

    init(pointer: CGPoint, frame: CGRect) {
        anchor = CGPoint(
            x: pointer.x < frame.midX ? frame.minX + Self.cornerInset : frame.maxX - Self.cornerInset,
            y: pointer.y < frame.midY ? frame.minY + Self.cornerInset : frame.maxY - Self.cornerInset
        )
        offset = CGPoint(x: anchor.x - pointer.x, y: anchor.y - pointer.y)
    }

    func translate(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + offset.x, y: point.y + offset.y)
    }

    func isClickable(in bounds: [CGRect]) -> Bool {
        bounds.contains { $0.contains(anchor) }
    }
}

enum ResizeMotion {
    case horizontal
    case vertical
    case diagonal

    private static let axisSnapSlope: CGFloat = 0.5

    static func from(dx: CGFloat, dy: CGFloat) -> ResizeMotion {
        if abs(dy) <= abs(dx) * axisSnapSlope {
            return .horizontal
        }
        if abs(dx) <= abs(dy) * axisSnapSlope {
            return .vertical
        }
        return .diagonal
    }

    func constrain(dx: CGFloat, dy: CGFloat) -> (CGFloat, CGFloat) {
        switch self {
        case .horizontal:
            return (dx, 0)
        case .vertical:
            return (0, dy)
        case .diagonal:
            return (dx, dy)
        }
    }
}
