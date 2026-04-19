import Foundation

enum Trigger: String, Codable, CaseIterable, Identifiable, Hashable {
    case tab
    case capsLock

    var id: String { rawValue }

    /// Long, descriptive name used in headers, settings copy, and tooltips.
    var displayName: String {
        switch self {
        case .tab: return "Tab"
        case .capsLock: return "Caps Lock"
        }
    }

    /// Short form used inside `KeyChip`s so the label never overflows the cap shape
    /// when the window or sidebar is narrow. "Caps" reads cleanly next to the
    /// `capslock` SF Symbol.
    var chipLabel: String {
        switch self {
        case .tab: return "Tab"
        case .capsLock: return "Caps"
        }
    }
}
