import SwiftUI

struct ModifierTogglesView: View {
    @Binding var modifiers: ModifierMask
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            toggle(.control, "⌃", "Control")
            toggle(.option,  "⌥", "Option")
            toggle(.shift,   "⇧", "Shift")
            toggle(.command, "⌘", "Command")
        }
        .opacity(isEnabled ? 1 : 0.5)
        .allowsHitTesting(isEnabled)
    }

    private func toggle(_ modifier: ModifierMask, _ symbol: String, _ name: String) -> some View {
        let isOn = modifiers.contains(modifier)
        return Button {
            if isOn { modifiers.remove(modifier) } else { modifiers.insert(modifier) }
        } label: {
            VStack(spacing: 1) {
                Text(symbol).font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(name).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isOn ? Color.white.opacity(0.9) : .secondary)
            }
            .frame(width: 56, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isOn ? 1 : 0.5)
            )
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help("\(name) (\(symbol))")
    }
}
