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
    static let throttleNanoseconds: UInt64 = 67_670_000

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
