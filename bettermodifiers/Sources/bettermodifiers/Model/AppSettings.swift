import Foundation

/// When enabled for a trigger, holding the trigger turns the next key into `modifiers + key`.
/// Per-rule mappings for that trigger are bypassed while this is on, except for
/// keys listed in `exceptions`, which follow `exceptionBehavior` instead.
struct ModifierModeConfig: Codable, Hashable {
    var isEnabled: Bool
    var modifiers: ModifierMask
    var exceptions: [UInt16]
    var exceptionBehavior: ExceptionBehavior

    enum ExceptionBehavior: String, Codable, CaseIterable {
        /// Excepted keys go through the trigger's per-key rules.
        case useRules
        /// Excepted keys type as if the trigger weren't held.
        case typeNormally
    }

    init(
        isEnabled: Bool,
        modifiers: ModifierMask,
        exceptions: [UInt16] = [],
        exceptionBehavior: ExceptionBehavior = .useRules
    ) {
        self.isEnabled = isEnabled
        self.modifiers = modifiers
        self.exceptions = exceptions
        self.exceptionBehavior = exceptionBehavior
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, modifiers, exceptions, exceptionBehavior
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        self.modifiers = try c.decode(ModifierMask.self, forKey: .modifiers)
        self.exceptions = try c.decodeIfPresent([UInt16].self, forKey: .exceptions) ?? []
        self.exceptionBehavior = try c.decodeIfPresent(ExceptionBehavior.self, forKey: .exceptionBehavior) ?? .useRules
    }
}

/// Blocks a single Escape in the listed apps; two quick taps send one Escape.
/// Guards against accidentally stopping a running agent (e.g. the Claude app).
struct EscapeGuardConfig: Codable, Hashable {
    var isEnabled: Bool
    var bundleIDs: [String]
    var windowMillis: Int

    static let `default` = EscapeGuardConfig(
        isEnabled: true,
        bundleIDs: ["com.anthropic.claudefordesktop"],
        windowMillis: 300
    )
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
    /// Keyed by `Trigger.id` (a stable string). Using `String` keys keeps the JSON
    /// encoding as a plain object - `{"tab": {...}, "custom:UUID": {...}}` -
    /// even though `Trigger` now has an associated-value `.custom` case which
    /// would otherwise encode as an array of pairs.
    var modifierMode: [String: ModifierModeConfig]
    var appearance: AppearanceMode
    /// When true, the menu-bar status item is removed. The user can still launch the app
    /// from the Dock / Spotlight to bring back the window (which also brings the icon
    /// back if they re-enable it from Appearance settings).
    var hideMenuBarIcon: Bool
    /// User-defined modifier-only triggers. Empty by default; the user adds entries
    /// from the Rules page.
    var customTriggers: [CustomTrigger]
    /// `Trigger.id` strings whose system-shortcut collision warning the user has
    /// dismissed. Stored on `AppSettings` (rather than `CustomTrigger` directly)
    /// so built-in triggers can also be silenced if needed in the future.
    var dismissedWarnings: [String]
    /// `Trigger.id` strings whose rules are paused as a group from the card's
    /// "⋯" menu. Each rule keeps its own on/off state, so Resume restores it.
    var pausedTriggers: [String]
    var escapeGuard: EscapeGuardConfig

    init(
        modifierMode: [String: ModifierModeConfig] = Self.defaultModifierMode,
        appearance: AppearanceMode = .system,
        hideMenuBarIcon: Bool = false,
        customTriggers: [CustomTrigger] = [],
        dismissedWarnings: [String] = [],
        pausedTriggers: [String] = [],
        escapeGuard: EscapeGuardConfig = .default
    ) {
        self.modifierMode = modifierMode
        self.appearance = appearance
        self.hideMenuBarIcon = hideMenuBarIcon
        self.customTriggers = customTriggers
        self.dismissedWarnings = dismissedWarnings
        self.pausedTriggers = pausedTriggers
        self.escapeGuard = escapeGuard
    }

    static let defaultModifierMode: [String: ModifierModeConfig] = [
        Trigger.tab.id:        ModifierModeConfig(isEnabled: false, modifiers: [.command, .option, .control, .shift]),
        Trigger.capsLock.id:   ModifierModeConfig(isEnabled: false, modifiers: [.command, .option, .control, .shift]),
        Trigger.shiftSpace.id: ModifierModeConfig(isEnabled: false, modifiers: [.command, .option, .control])
    ]

    static let `default` = AppSettings()

    /// Tolerant decoding so adding new fields to `AppSettings` in future releases
    /// doesn't wipe a user's existing settings.json. Missing fields fall back to
    /// the corresponding `init(...)` default.
    private enum CodingKeys: String, CodingKey {
        case modifierMode, appearance, hideMenuBarIcon, customTriggers, dismissedWarnings, pausedTriggers, escapeGuard
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.modifierMode      = try c.decodeIfPresent([String: ModifierModeConfig].self, forKey: .modifierMode) ?? Self.defaultModifierMode
        self.appearance        = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        self.hideMenuBarIcon   = try c.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon) ?? false
        self.customTriggers    = try c.decodeIfPresent([CustomTrigger].self, forKey: .customTriggers) ?? []
        self.dismissedWarnings = try c.decodeIfPresent([String].self, forKey: .dismissedWarnings) ?? []
        self.pausedTriggers    = try c.decodeIfPresent([String].self, forKey: .pausedTriggers) ?? []
        self.escapeGuard       = try c.decodeIfPresent(EscapeGuardConfig.self, forKey: .escapeGuard) ?? .default
    }
}
