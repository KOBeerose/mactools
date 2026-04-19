import SwiftUI

struct GeneralView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "General",
                subtitle: "Toggle the engine, manage launch behavior, and verify Accessibility access."
            )

            Form {
                Section("Engine") {
                    Toggle("Enable BetterModifiers", isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { viewModel.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)

                    Toggle("Launch at Login", isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: { viewModel.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(!viewModel.canChangeLaunchAtLogin)
                    Text(viewModel.launchAtLoginNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Permissions") {
                    HStack {
                        Image(systemName: viewModel.hasAccessibility ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(viewModel.hasAccessibility ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility")
                            Text(viewModel.hasAccessibility
                                 ? "Granted. BetterModifiers can intercept keys."
                                 : "Required to intercept Tab and Caps Lock.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open System Settings") {
                            viewModel.openAccessibilitySettings()
                        }
                    }

                    HStack {
                        Text("Engine status: \(viewModel.statusText)")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        Button("Restart Engine") {
                            viewModel.restartEngine()
                        }
                    }
                }

                Section {
                    Text("Caps Lock is remapped to F18 at the HID level while BetterModifiers is running. Toggling Caps Lock without pressing another key still works as expected.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("General")
    }
}
