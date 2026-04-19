import ApplicationServices
import Foundation

struct ModifierMask: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = ModifierMask(rawValue: 1 << 0)
    static let option  = ModifierMask(rawValue: 1 << 1)
    static let control = ModifierMask(rawValue: 1 << 2)
    static let shift   = ModifierMask(rawValue: 1 << 3)

    static let all: [ModifierMask] = [.command, .option, .control, .shift]

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option)  { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }

    var displaySymbols: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option)  { parts.append("⌥") }
        if contains(.shift)   { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventFlags: CGEventFlags) {
        var mask: ModifierMask = []
        if eventFlags.contains(.maskCommand)   { mask.insert(.command) }
        if eventFlags.contains(.maskAlternate) { mask.insert(.option) }
        if eventFlags.contains(.maskControl)   { mask.insert(.control) }
        if eventFlags.contains(.maskShift)     { mask.insert(.shift) }
        self = mask
    }
}
