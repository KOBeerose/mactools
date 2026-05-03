import Foundation

/// User-defined modifier-only layer trigger. While the user holds *exactly* the
/// modifiers in `modifiers` (no more, no fewer), the next non-modifier key is
/// treated as a layer key: if a rule for `(Trigger.custom(id), keyCode)` exists,
/// its output is emitted and the original keystroke is swallowed.
///
/// Strict-equality matching means defining `⌃⌥` does not also fire when
/// `⌃⌥⌘` is held — that lets the user safely stack additional system
/// modifiers without their custom combo intercepting.
struct CustomTrigger: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var modifiers: ModifierMask
    /// When true, the trigger only fires while the (HID-remapped) Caps Lock
    /// key is also held. Lets the user build combos like `Caps + ⌥` that
    /// piggy-back on the existing Caps-as-F18 layer key without writing them
    /// as a built-in `.capsLock` rule.
    var requiresCapsLock: Bool
    /// When true, the trigger only fires while the spacebar is also held.
    /// Reuses the same AHK-style "forward space, retroactively backspace once
    /// a qualifier joins" machinery the built-in `Shift+Space` trigger uses,
    /// so plain typing keeps working. `Space` alone (no other qualifier) is
    /// not allowed - `isEmpty` returns true in that state and the editor
    /// surfaces a warning.
    var requiresSpace: Bool
    /// When true, the trigger only fires while the Tab key is also held AND
    /// the modifier mask matches exactly. Tab alone is the built-in Tab
    /// trigger, so a custom Tab combo MUST also include at least one
    /// modifier (or Caps Lock) - `isEmpty` returns true otherwise. Defining
    /// `Tab + ⌘` overrides the macOS app switcher; the warning row notes
    /// this so the user can decide whether to keep it.
    var requiresTab: Bool

    init(
        id: UUID = UUID(),
        name: String = "Custom",
        modifiers: ModifierMask = [],
        requiresCapsLock: Bool = false,
        requiresSpace: Bool = false,
        requiresTab: Bool = false
    ) {
        self.id = id
        self.name = name
        self.modifiers = modifiers
        self.requiresCapsLock = requiresCapsLock
        self.requiresSpace = requiresSpace
        self.requiresTab = requiresTab
    }

    /// True when the combo has nothing the engine can safely match on. Space
    /// or Tab alone count as empty - the engine reserves Tab/Space-with-no-
    /// modifiers for the built-in triggers, and Space-only would block normal
    /// typing entirely.
    var isEmpty: Bool {
        if !modifiers.isEmpty { return false }
        if requiresCapsLock { return false }
        return true
    }

    /// Display name with a graceful fallback so an empty user-typed name still
    /// renders something legible.
    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Custom" : trimmed
    }

    /// Returns a short warning string when this combo is likely to collide with
    /// commonly-used macOS / app shortcuts. Adding Caps or Space as a qualifier
    /// makes collisions vanishingly unlikely, so those combos return nil.
    /// Returned text is plain and concise so the editor can render it as a
    /// dismissible inline note rather than a modal alert.
    var systemShortcutWarning: String? {
        if requiresTab {
            switch modifiers {
            case [.command]:
                return "⌘⇥ overrides the macOS app switcher (Cmd+Tab). While this trigger exists, Cmd+Tab will not switch apps - remove the trigger or pick a different combo to restore it."
            case [.command, .shift]:
                return "⌘⇧⇥ overrides the reverse app switcher. Remove this trigger or change the combo to restore it."
            default:
                return nil
            }
        }
        if requiresCapsLock || requiresSpace { return nil }
        switch modifiers {
        case [.command]:
            return "⌘ alone collides with most app shortcuts (⌘C, ⌘V, ⌘S, …). Pick another modifier or add Caps Lock / Space."
        case [.command, .shift]:
            return "⌘⇧ collides with many app shortcuts (⌘⇧Z, ⌘⇧T, …). Consider adding ⌃ or ⌥, or rebinding the conflicting macOS shortcut."
        case [.command, .option]:
            return "⌥⌘ overlaps macOS shortcuts (⌥⌘M = minimize, etc.). Rebind the conflicting system shortcut or pick a different combo."
        case [.command, .control]:
            return "⌃⌘ overlaps Mission Control / Spaces shortcuts. Rebind the conflicting system shortcut or pick a different combo."
        case [.option]:
            return "⌥ alone produces special characters (⌥e = é, ⌥c = ç, …). Most letter inputs will type accents instead of firing a rule."
        case [.control]:
            return "⌃ alone collides with text-editing keys (⌃A = beginning of line, ⌃E = end, …). Consider adding ⌥ or ⌘."
        case [.shift]:
            return "⇧ alone is required for capitals and shifted symbols, so this combo will conflict with normal typing."
        default:
            return nil
        }
    }

    /// Compact symbol representation used in chip labels, e.g. `⇪⌃⌥` or `⇥⌘`.
    var symbolLabel: String {
        var s = ""
        if requiresCapsLock { s += "⇪" }
        if requiresTab      { s += "⇥" }
        if requiresSpace    { s += "␣" }
        s += modifiers.displaySymbols
        return s.isEmpty ? "Combo" : s
    }

    /// Codable migration: older settings.json files predate `requiresCapsLock`,
    /// `requiresSpace`, and `requiresTab`. All decode as `false` when missing.
    private enum CodingKeys: String, CodingKey {
        case id, name, modifiers, requiresCapsLock, requiresSpace, requiresTab
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.modifiers = try c.decode(ModifierMask.self, forKey: .modifiers)
        self.requiresCapsLock = try c.decodeIfPresent(Bool.self, forKey: .requiresCapsLock) ?? false
        self.requiresSpace = try c.decodeIfPresent(Bool.self, forKey: .requiresSpace) ?? false
        self.requiresTab = try c.decodeIfPresent(Bool.self, forKey: .requiresTab) ?? false
    }
}
