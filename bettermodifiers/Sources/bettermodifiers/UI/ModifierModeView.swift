import SwiftUI

struct ModifierModeView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Modifier Mode",
                subtitle: "Turn Tab or Caps Lock into a fixed modifier combo. While held, the next key is sent as the chosen modifiers + that key. When enabled, individual rules for that trigger are bypassed."
            )

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Trigger.allCases) { trigger in
                        card(for: trigger)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Modifier Mode")
    }

    private func card(for trigger: Trigger) -> some View {
        let config = settings.modeConfig(for: trigger)
        return GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trigger.displayName)
                            .font(.headline)
                        Text("Use \(trigger.displayName) as a fixed modifier combo")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.modeConfig(for: trigger).isEnabled },
                        set: { settings.setModeEnabled($0, for: trigger) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider()

                HStack(alignment: .center) {
                    Text("Modifiers")
                        .frame(width: 90, alignment: .leading)
                        .foregroundStyle(.secondary)
                    ModifierTogglesView(
                        modifiers: Binding(
                            get: { settings.modeConfig(for: trigger).modifiers },
                            set: { settings.setModeModifiers($0, for: trigger) }
                        ),
                        isEnabled: config.isEnabled
                    )
                    Spacer()
                }

                HStack(alignment: .center) {
                    Text("Preview")
                        .frame(width: 90, alignment: .leading)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        KeyChip(label: trigger.chipLabel, symbol: trigger.symbolName, emphasized: true)
                        Text("+")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)
                        KeyChip(label: "Key")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        KeyComboView(modifiers: config.modifiers, keyLabel: "Key")
                    }
                    .opacity(config.isEnabled ? 1 : 0.5)
                    Spacer()
                }
            }
            .padding(8)
        }
    }
}
