import SwiftUI

struct AppearanceView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Appearance",
                subtitle: "Choose how BetterModifiers looks."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    themeSection
                    menuBarSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Appearance")
    }

    private var themeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme").font(.headline)
                Divider()
                HStack {
                    Text("Appearance")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.settings.appearance },
                        set: { settings.settings.appearance = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var menuBarSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Menu Bar").font(.headline)
                Divider()
                trailingToggleRow(
                    label: "Hide menu bar icon",
                    isOn: Binding(
                        get: { settings.settings.hideMenuBarIcon },
                        set: { settings.settings.hideMenuBarIcon = $0 }
                    )
                )
                Text("When hidden, re-open BetterModifiers from the Dock or Spotlight to access this window again. The engine keeps running either way.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `Toggle(...).toggleStyle(.switch)` places the switch immediately next to its
    /// label (no flex space), which makes the row look "control beside text" inside a
    /// full-width card. Wrapping label + Spacer + labelsHidden Toggle pins the switch
    /// to the trailing edge — same alignment the previous grouped Form gave us.
    private func trailingToggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}
