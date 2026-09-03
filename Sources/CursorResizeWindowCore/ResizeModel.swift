import CoreGraphics

struct ResizeDirection: OptionSet, Equatable {
    let rawValue: UInt8

    static let left = ResizeDirection(rawValue: 1 << 0)
    static let top = ResizeDirection(rawValue: 1 << 1)
    static let right = ResizeDirection(rawValue: 1 << 2)
    static let bottom = ResizeDirection(rawValue: 1 << 3)

}

enum ResizeTarget: CaseIterable, Equatable {
    static let middleBandMin: CGFloat = 3.0 / 8.0
    static let middleBandMax: CGFloat = 5.0 / 8.0

    case move
    case left
    case right
    case top
    case bottom
    case leftTop
    case rightTop
    case leftBottom
    case rightBottom

    static func from(point: CGPoint, frame: CGRect) -> ResizeTarget {
        let u = (point.x - frame.minX) / frame.width
        let v = (point.y - frame.minY) / frame.height
        let isInMiddleColumn = middleBandMin...middleBandMax ~= u
        let isInMiddleRow = middleBandMin...middleBandMax ~= v

        if isInMiddleRow && !isInMiddleColumn {
            return u < 0.5 ? .left : .right
        }
        if isInMiddleColumn && !isInMiddleRow {
            return v < 0.5 ? .top : .bottom
        }
        if !isInMiddleColumn && !isInMiddleRow {
            switch (u < 0.5, v < 0.5) {
            case (true, true):
                return .leftTop
            case (false, true):
                return .rightTop
            case (true, false):
                return .leftBottom
            case (false, false):
                return .rightBottom
            }
        }

        return .move
    }

    var resizeDirection: ResizeDirection? {
        switch self {
        case .move:
            return nil
        case .left:
            return .left
        case .right:
            return .right
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .leftTop:
            return [.left, .top]
        case .rightTop:
            return [.right, .top]
        case .leftBottom:
            return [.left, .bottom]
        case .rightBottom:
            return [.right, .bottom]
        }
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

struct NativeDragMapping: Equatable {
    private static let edgeInset: CGFloat = 2
    private static let cornerInset: CGFloat = 5
    private static let titleBarInset: CGFloat = 3

    let anchor: CGPoint
    private let target: ResizeTarget
    private let pointer: CGPoint
    private let offset: CGPoint

    init(pointer: CGPoint, frame: CGRect, target: ResizeTarget) {
        self.target = target
        self.pointer = pointer
        switch target {
        case .move:
            anchor = CGPoint(x: pointer.x, y: frame.minY + Self.titleBarInset)
        case .left:
            anchor = CGPoint(x: frame.minX + Self.edgeInset, y: pointer.y)
        case .right:
            anchor = CGPoint(x: frame.maxX - Self.edgeInset, y: pointer.y)
        case .top:
            anchor = CGPoint(x: pointer.x, y: frame.minY + Self.edgeInset)
        case .bottom:
            anchor = CGPoint(x: pointer.x, y: frame.maxY - Self.edgeInset)
        case .leftTop:
            anchor = CGPoint(
                x: frame.minX + Self.cornerInset,
                y: frame.minY + Self.cornerInset
            )
        case .rightTop:
            anchor = CGPoint(
                x: frame.maxX - Self.cornerInset,
                y: frame.minY + Self.cornerInset
            )
        case .leftBottom:
            anchor = CGPoint(
                x: frame.minX + Self.cornerInset,
                y: frame.maxY - Self.cornerInset
            )
        case .rightBottom:
            anchor = CGPoint(
                x: frame.maxX - Self.cornerInset,
                y: frame.maxY - Self.cornerInset
            )
        }
        offset = CGPoint(x: anchor.x - pointer.x, y: anchor.y - pointer.y)
    }

    func translate(_ point: CGPoint) -> CGPoint {
        switch target {
        case .move, .leftTop, .rightTop, .leftBottom, .rightBottom:
            return CGPoint(x: point.x + offset.x, y: point.y + offset.y)
        case .left, .right:
            return CGPoint(x: point.x + offset.x, y: anchor.y)
        case .top, .bottom:
            return CGPoint(x: anchor.x, y: point.y + offset.y)
        }
    }

    func isClickable(in bounds: [CGRect]) -> Bool {
        bounds.contains { $0.contains(pointer) && $0.contains(anchor) }
    }
}
