import Foundation

struct TitleBarDragSettings {
    static let domain = "com.zuozhi.cursor-resize-window"
    static let offsetsKey = "TitleBarYOffsets"

    private let offsets: [String: Any]

    init(defaults: UserDefaults = UserDefaults(suiteName: TitleBarDragSettings.domain)!) {
        offsets = defaults.dictionary(forKey: Self.offsetsKey) ?? [:]
    }

    func yOffset(for bundleIdentifier: String?) -> CGFloat {
        guard let bundleIdentifier,
              let value = offsets[bundleIdentifier] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite
        else {
            return NativeDragMapping.defaultTitleBarYOffset
        }

        return min(max(CGFloat(value.doubleValue), 0), 15)
    }
}
