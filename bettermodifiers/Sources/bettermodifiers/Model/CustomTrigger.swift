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

    init(id: UUID = UUID(), name: String = "Custom", modifiers: ModifierMask = []) {
        self.id = id
        self.name = name
        self.modifiers = modifiers
    }

    /// Display name with a graceful fallback so an empty user-typed name still
    /// renders something legible.
    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Custom" : trimmed
    }
}
