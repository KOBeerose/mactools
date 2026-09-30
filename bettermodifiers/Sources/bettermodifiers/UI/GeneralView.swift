import SwiftUI

struct GeneralView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "General",
                subtitle: "Toggle the engine, manage launch behavior, and verify Accessibility access."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EngineHealthStrip(viewModel: viewModel)
                    engineSection
                    escapeGuardSection
                    lastTriggeredSection
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

    private var escapeGuardSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("Escape Guard")
                Divider()
                trailingToggleRow(
                    label: "Double-tap Escape in Claude",
                    isOn: Binding(
                        get: { settings.settings.escapeGuard.isEnabled },
                        set: { settings.settings.escapeGuard.isEnabled = $0 }
                    )
                )

                HStack {
                    Text("Double-tap speed")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.settings.escapeGuard.windowMillis },
                        set: { settings.settings.escapeGuard.windowMillis = $0 }
                    )) {
                        Text("Fast (250 ms)").tag(250)
                        Text("Normal (300 ms)").tag(300)
                        Text("Relaxed (400 ms)").tag(400)
                        Text("Slow (500 ms)").tag(500)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.settings.escapeGuard.isEnabled)
                }

                Text("A single Escape is ignored in the Claude app so it can't stop a running agent by accident. Tap Escape twice quickly to send it.")
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

            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lastTriggeredSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Last Triggered")
                Divider()
                if let latest = viewModel.recentFired.first {
                    FiredRecordRow(record: latest)
                    if viewModel.recentFired.count > 1 {
                        DisclosureGroup("Recent") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(viewModel.recentFired.dropFirst()) { record in
                                    FiredRecordRow(record: record)
                                        .opacity(0.75)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.callout)
                    }
                } else {
                    Text("Nothing yet. Hold a trigger and press a mapped key.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            Text("Caps Lock is remapped to F18 at the HID level while BetterModifiers is running. Toggling Caps Lock without pressing another key still works as expected. In password and other secure fields, that remap is paused automatically so Caps Lock and typing behave normally.")
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

/// One fired key in the same chip language as the Rules page, so you can match
/// it to the row that caused it.
private struct FiredRecordRow: View {
    let record: FiredRecord

    var body: some View {
        HStack(spacing: 8) {
            KeyChip(label: record.triggerChip, symbol: record.triggerSymbol, emphasized: true)
                .help(record.triggerName)
            ForEach(Array(record.inputKeys.enumerated()), id: \.offset) { _, key in
                Text("+").foregroundStyle(.tertiary)
                KeyChip(label: KeyCodes.label(for: key))
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            KeyComboView(modifiers: record.modifiers, keyLabel: KeyCodes.label(for: record.outputKey))
            Spacer(minLength: 8)
            Text(record.source == .rule ? "Rule" : "Modifier Mode")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
            Text(record.date.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
