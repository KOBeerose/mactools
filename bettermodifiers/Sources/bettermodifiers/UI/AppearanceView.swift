import SwiftUI

struct AppearanceView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Appearance",
                subtitle: "Choose how BetterModifiers looks."
            )

            Form {
                Section("Theme") {
                    Picker("Appearance", selection: Binding(
                        get: { settings.settings.appearance },
                        set: { settings.settings.appearance = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Appearance")
    }
}
