import SwiftUI

struct KeyChip: View {
    let label: String
    /// Optional SF Symbol shown to the left of `label` (e.g. for trigger chips).
    var symbol: String? = nil
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(label)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 32, minHeight: 24)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(emphasized ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(emphasized ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .foregroundStyle(emphasized ? Color.accentColor : Color.primary)
    }
}

extension Trigger {
    /// SF Symbol used to render this trigger as a compact icon-chip.
    var symbolName: String {
        switch self {
        case .tab: return "arrow.right.to.line"
        case .capsLock: return "capslock"
        case .shiftSpace: return "space"
        case .custom: return "command"
        }
    }

    /// Display name with custom-trigger lookup. Falls back to the static
    /// `displayName` for built-ins.
    func displayName(customs: [CustomTrigger]) -> String {
        if case .custom(let id) = self,
           let ct = customs.first(where: { $0.id == id }) {
            return ct.resolvedName
        }
        return displayName
    }

    /// Chip label with custom-trigger lookup. For `.custom` we render the
    /// modifier symbols (e.g. `⌃⌥`) so the user can see the combo at a glance.
    func chipLabel(customs: [CustomTrigger]) -> String {
        if case .custom(let id) = self,
           let ct = customs.first(where: { $0.id == id }) {
            let symbols = ct.modifiers.displaySymbols
            return symbols.isEmpty ? "Combo" : symbols
        }
        return chipLabel
    }
}

struct KeyComboView: View {
    let modifiers: ModifierMask
    let keyLabel: String

    var body: some View {
        HStack(spacing: 6) {
            if modifiers.contains(.control) { KeyChip(label: "⌃") }
            if modifiers.contains(.option)  { KeyChip(label: "⌥") }
            if modifiers.contains(.shift)   { KeyChip(label: "⇧") }
            if modifiers.contains(.command) { KeyChip(label: "⌘") }
            KeyChip(label: keyLabel, emphasized: true)
        }
    }
}
