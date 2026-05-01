import Foundation

enum Trigger: String, Codable, CaseIterable, Identifiable, Hashable {
    case tab
    case capsLock
    /// Spacebar held together with Shift. Plain Space is never used as a layer trigger
    /// because typing relies on it; requiring Shift as a qualifier sidesteps the
    /// hold-vs-tap ambiguity that would otherwise eat real space characters.
    case shiftSpace

    var id: String { rawValue }

    /// Long, descriptive name used in headers, settings copy, and tooltips.
    var displayName: String {
        switch self {
        case .tab: return "Tab"
        case .capsLock: return "Caps Lock"
        case .shiftSpace: return "Shift + Space"
        }
    }

    /// Short form used inside `KeyChip`s so the label never overflows the cap shape
    /// when the window or sidebar is narrow. "Caps" reads cleanly next to the
    /// `capslock` SF Symbol.
    var chipLabel: String {
        switch self {
        case .tab: return "Tab"
        case .capsLock: return "Caps"
        case .shiftSpace: return "⇧Space"
        }
    }
}
