import Foundation

/// Starter rule sets offered by an empty trigger card's "Start from Preset" menu.
struct RulePreset: Identifiable {
    let id: String
    let name: String
    let rules: [(input: UInt16, modifiers: ModifierMask, output: UInt16)]

    @MainActor static let all: [RulePreset] = [
        RulePreset(
            id: "digits",
            name: "Digits → ⌥ + digit (0–9)",
            rules: RulesStore.digitKeyCodes.map { ($0, [.option], $0) }
        ),
        RulePreset(
            id: "vim-arrows",
            name: "Vim arrows (H J K L → ← ↓ ↑ →)",
            rules: [(4, [], 123), (38, [], 125), (40, [], 126), (37, [], 124)]
        ),
        RulePreset(
            id: "line-nav",
            name: "Line start / end (A, E → ⌘←, ⌘→)",
            rules: [(0, [.command], 123), (14, [.command], 124)]
        ),
    ]
}
