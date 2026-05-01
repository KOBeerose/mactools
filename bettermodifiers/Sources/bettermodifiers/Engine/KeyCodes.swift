import Foundation

enum KeyCodes {
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51 // backspace key (deletes left)
    static let capsLock: UInt16 = 57
    static let f18: UInt16 = 79
    /// Sentinel meaning "no key has been chosen yet". Rendered as "Key" in the UI.
    /// Picked at the top of the UInt16 range so it can never collide with a real keycode.
    static let unset: UInt16 = .max

    static let modifierKeyCodes: Set<UInt16> = [
        54, 55,             // right/left command
        56, 60,             // shift, right shift
        58, 61,             // option, right option
        59, 62,             // control, right control
        57,                 // caps lock
        63                  // fn
    ]

    static func isModifier(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    /// Human-readable label for a virtual key code. Best-effort; falls back to "Key <code>".
    /// Returns "Key" for the `unset` sentinel.
    static func label(for keyCode: UInt16) -> String {
        if keyCode == unset { return "Key" }
        if let known = knownLabels[keyCode] {
            return known
        }
        return "Key \(keyCode)"
    }

    private static let knownLabels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9",
        26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        45: "N", 46: "M",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        57: "Caps Lock", 76: "Enter",
        // Arrows
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // Function keys
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20"
    ]
}
