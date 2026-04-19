import SwiftUI

struct KeyChip: View {
    let label: String
    var emphasized: Bool = false

    var body: some View {
        Text(label)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
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

struct KeyComboView: View {
    let modifiers: ModifierMask
    let keyLabel: String

    var body: some View {
        HStack(spacing: 4) {
            if modifiers.contains(.control) { KeyChip(label: "⌃") }
            if modifiers.contains(.option)  { KeyChip(label: "⌥") }
            if modifiers.contains(.shift)   { KeyChip(label: "⇧") }
            if modifiers.contains(.command) { KeyChip(label: "⌘") }
            KeyChip(label: keyLabel, emphasized: true)
        }
    }
}
