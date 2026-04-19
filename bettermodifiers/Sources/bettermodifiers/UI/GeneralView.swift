import SwiftUI

struct GeneralView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "General",
                subtitle: "Toggle the engine, manage launch behavior, and verify Accessibility access."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    engineSection
                    permissionsSection
                    troubleshootingSection
                    capsLockNote
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("General")
    }

    private var engineSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("Engine")
                Divider()
                trailingToggleRow(
                    label: "Enable BetterModifiers",
                    isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { viewModel.setEnabled($0) }
                    )
                )

                trailingToggleRow(
                    label: "Launch at Login",
                    isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: { viewModel.setLaunchAtLogin($0) }
                    ),
                    enabled: viewModel.canChangeLaunchAtLogin
                )

                Text(viewModel.launchAtLoginNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Pin the switch to the trailing edge of the card, matching the previous grouped
    /// Form layout. See AppearanceView.trailingToggleRow for the rationale.
    private func trailingToggleRow(label: String, isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(!enabled)
        }
    }

    private var permissionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Permissions")
                Divider()

                HStack(alignment: .top) {
                    Image(systemName: viewModel.hasAccessibility ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.hasAccessibility ? Color.green : Color.orange)
                        .font(.title3)
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Last triggered")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(viewModel.lastFiredText)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                        Spacer()
                        if let at = viewModel.lastFiredAt {
                            Text(at.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var troubleshootingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Troubleshooting")
                Divider()
                troubleshootingItem(
                    symbol: "keyboard.badge.ellipsis",
                    title: "Other key remappers can block BetterModifiers",
                    body: "Apps that grab keyboard input at the kernel level — Karabiner-Elements is the most common one — consume key events before any other app can see them. If \"Last triggered\" never updates, quit Karabiner-Elements completely (its background daemons keep running after you close the UI; use its Uninstaller from the Karabiner preferences pane, or stop the org.pqrs.* launch daemons). The same applies to Hammerspoon, Keyboard Maestro macros that grab keys, and similar tools."
                )

                troubleshootingItem(
                    symbol: "lock.shield",
                    title: "Re-add BetterModifiers to Accessibility after a rebuild",
                    body: "macOS pins each Accessibility grant to the exact binary signature. Every fresh build silently invalidates the previous grant and the event tap is created but receives zero events. Open System Settings → Privacy & Security → Accessibility, remove BetterModifiers with the minus button, then add it back from \(Self.installPath) and click Restart Engine."
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capsLockNote: some View {
        GroupBox {
            Text("Caps Lock is remapped to F18 at the HID level while BetterModifiers is running. Toggling Caps Lock without pressing another key still works as expected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private static let installPath: String = {
        Bundle.main.bundlePath.isEmpty ? "~/Applications/BetterModifiers.app" : Bundle.main.bundlePath
    }()

    @ViewBuilder
    private func troubleshootingItem(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
