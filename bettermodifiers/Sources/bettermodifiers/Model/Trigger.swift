import Foundation

/// A layer trigger. The first three cases are built-in (engineered with their own
/// state machines for tap-vs-hold, fallback chord posting, etc.). `.custom` is a
/// user-defined modifier-only combo (e.g. `⌃⌥`) that arms a layer for as long as
/// those exact modifiers are held — there is no tap-fallback because modifiers
/// don't have one. The associated UUID points at the matching `CustomTrigger`
/// stored in `AppSettings.customTriggers`.
enum Trigger: Hashable, Identifiable {
    case tab
    case capsLock
    case shiftSpace
    case custom(UUID)

    /// Stable string id used as a Codable representation, dictionary key
    /// (e.g. `AppSettings.modifierMode`), and SwiftUI `Identifiable` value.
    var id: String {
        switch self {
        case .tab: return "tab"
        case .capsLock: return "capsLock"
        case .shiftSpace: return "shiftSpace"
        case .custom(let uuid): return "custom:\(uuid.uuidString)"
        }
    }

    /// The built-in triggers, in canonical card-display order.
    static let builtIn: [Trigger] = [.tab, .capsLock, .shiftSpace]

    /// Long, descriptive name. For `.custom` callers should prefer
    /// `displayName(customs:)` so the user-supplied name surfaces.
    var displayName: String {
        switch self {
        case .tab: return "Tab"
        case .capsLock: return "Caps Lock"
        case .shiftSpace: return "Shift + Space"
        case .custom: return "Custom Trigger"
        }
    }

    /// Short form for compact `KeyChip`s.
    var chipLabel: String {
        switch self {
        case .tab: return "Tab"
        case .capsLock: return "Caps"
        case .shiftSpace: return "⇧Space"
        case .custom: return "Combo"
        }
    }
}

extension Trigger: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        switch raw {
        case "tab": self = .tab
        case "capsLock": self = .capsLock
        case "shiftSpace": self = .shiftSpace
        default:
            if raw.hasPrefix("custom:"),
               let uuid = UUID(uuidString: String(raw.dropFirst("custom:".count))) {
                self = .custom(uuid)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: c,
                    debugDescription: "Unknown trigger raw value: \(raw)"
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}
