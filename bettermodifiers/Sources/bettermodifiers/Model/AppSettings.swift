import Foundation

/// When enabled for a trigger, holding the trigger turns the next key into `modifiers + key`.
/// Per-rule mappings for that trigger are bypassed while this is on.
struct ModifierModeConfig: Codable, Hashable {
    var isEnabled: Bool
    var modifiers: ModifierMask
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

struct AppSettings: Codable, Hashable {
    var modifierMode: [Trigger: ModifierModeConfig] = [
        .tab:        ModifierModeConfig(isEnabled: false, modifiers: [.command, .option, .control, .shift]),
        .capsLock:   ModifierModeConfig(isEnabled: false, modifiers: [.command, .option, .control, .shift]),
        .shiftSpace: ModifierModeConfig(isEnabled: false, modifiers: [.command, .option, .control])
    ]
    var appearance: AppearanceMode = .system
    /// When true, the menu-bar status item is removed. The user can still launch the app
    /// from the Dock / Spotlight to bring back the window (which also brings the icon
    /// back if they re-enable it from Appearance settings).
    var hideMenuBarIcon: Bool = false

    static let `default` = AppSettings()
}
