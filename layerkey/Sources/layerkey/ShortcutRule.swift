import ApplicationServices

enum TriggerKey: String, CaseIterable {
    case tab
    case capsLock

    var displayName: String {
        switch self {
        case .tab:
            return "Tab"
        case .capsLock:
            return "Caps Lock"
        }
    }
}

enum OutputModifier: String, CaseIterable {
    case option
    case control
    case command
    case shift

    var displayName: String {
        rawValue.capitalized
    }

    var eventFlags: CGEventFlags {
        switch self {
        case .option:
            return .maskAlternate
        case .control:
            return .maskControl
        case .command:
            return .maskCommand
        case .shift:
            return .maskShift
        }
    }
}

struct ShortcutRule {
    let trigger: TriggerKey
    let outputModifier: OutputModifier
}

enum KeyCodeMap {
    static let tab: Int64 = 48
    static let capsLock: Int64 = 57
    static let f18: Int64 = 79

    static let digitKeyCodes: [Int64] = [
        18, 19, 20, 21, 23, 22, 26, 28, 25, 29
    ]

    static func isDigit(_ keyCode: Int64) -> Bool {
        digitKeyCodes.contains(keyCode)
    }
}
