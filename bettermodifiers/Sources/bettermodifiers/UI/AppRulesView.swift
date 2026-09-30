import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Per-app key behavior: one card per app, one row per key.
struct AppRulesView: View {
    @ObservedObject var settings: SettingsStore

    /// Rule whose key chip should start recording as soon as its row appears.
    @State private var autoRecordId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "App Rules",
                subtitle: "Change what a key does in one app. Rules apply to the plain key, so ⇧ ⌃ ⌥ ⌘ combos still work normally."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    doubleTapSection
                    ForEach(apps, id: \.bundleID) { app in
                        appCard(bundleID: app.bundleID, name: app.name)
                    }
                    addAppMenu
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("App Rules")
    }

    /// Apps in the order their first rule was added.
    private var apps: [(bundleID: String, name: String)] {
        var seen = Set<String>()
        return settings.settings.appRules.compactMap { rule in
            seen.insert(rule.bundleID).inserted ? (rule.bundleID, rule.appName) : nil
        }
    }

    private var doubleTapSection: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Double-tap speed")
                    Text("How quickly the second tap must follow for “Require double-tap” keys.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.settings.doubleTapMillis },
                    set: { settings.settings.doubleTapMillis = $0 }
                )) {
                    Text("Fast (250 ms)").tag(250)
                    Text("Normal (300 ms)").tag(300)
                    Text("Relaxed (400 ms)").tag(400)
                    Text("Slow (500 ms)").tag(500)
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(12)
        }
    }

    private func appCard(bundleID: String, name: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AppIcon(bundleID: bundleID)
                    Text(name).font(.headline)
                    Spacer()
                    Menu {
                        Button("Remove App", role: .destructive) {
                            settings.removeAppRules(bundleID: bundleID)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Divider()
                ForEach(settings.settings.appRules.filter { $0.bundleID == bundleID }) { rule in
                    AppRuleRow(settings: settings, rule: rule, autoRecord: autoRecordId == rule.id) {
                        autoRecordId = nil
                    }
                }
                Button {
                    autoRecordId = settings.addAppRule(bundleID: bundleID, appName: name).id
                } label: {
                    Label("Add Key", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addAppMenu: some View {
        Menu {
            let existing = Set(apps.map(\.bundleID))
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app -> (String, String)? in
                    guard let id = app.bundleIdentifier, !existing.contains(id) else { return nil }
                    return (id, app.localizedName ?? id)
                }
                .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
            Section("Running Apps") {
                ForEach(running, id: \.0) { id, name in
                    Button(name) { addApp(bundleID: id, name: name) }
                }
            }
            Divider()
            Button("Choose from Applications…", action: chooseApp)
        } label: {
            Label("Add App", systemImage: "plus.app")
        }
        .fixedSize()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        addApp(bundleID: id, name: name)
    }

    private func addApp(bundleID: String, name: String) {
        autoRecordId = settings.addAppRule(bundleID: bundleID, appName: name).id
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 24, height: 24)
    }

    private var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// One key in an app card: enable switch, key chip, behavior, and (for Remap) the output.
private struct AppRuleRow: View {
    @ObservedObject var settings: SettingsStore
    let rule: AppRule
    let autoRecord: Bool
    let onAutoRecordConsumed: () -> Void

    @State private var recording: Target?
    @State private var monitor: Any?

    private enum Target { case input, output }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: binding(\.isEnabled))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)

            keyChip(.input, keyCode: rule.keyCode)

            Picker("", selection: binding(\.behavior)) {
                ForEach(AppRule.Behavior.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            if rule.behavior == .remap {
                CompactModifierTogglesView(modifiers: binding(\.outputModifiers))
                keyChip(.output, keyCode: rule.outputKey)
            }

            Spacer(minLength: 0)

            Button {
                stopRecording()
                settings.removeAppRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove key")
        }
        .opacity(rule.isEnabled ? 1 : 0.55)
        .onAppear {
            if autoRecord {
                onAutoRecordConsumed()
                startRecording(.input)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppRule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { value in
                guard var copy = currentRule() else { return }
                copy[keyPath: keyPath] = value
                settings.updateAppRule(copy)
            }
        )
    }

    private func currentRule() -> AppRule? {
        settings.settings.appRules.first { $0.id == rule.id }
    }

    private func keyChip(_ target: Target, keyCode: UInt16) -> some View {
        Button {
            recording == target ? stopRecording() : startRecording(target)
        } label: {
            if recording == target {
                KeyChip(label: "Press a key…", emphasized: true)
            } else if keyCode == KeyCodes.unset {
                KeyChip(label: "Set key", style: .placeholder)
            } else {
                KeyChip(label: KeyCodes.label(for: keyCode))
            }
        }
        .buttonStyle(.plain)
        .help(recording == target ? "Click again to cancel" : "Click to record a key")
    }

    /// Unlike rule rows, Escape is recordable here (it's the main use case),
    /// so recording is cancelled by clicking the chip again.
    private func startRecording(_ target: Target) {
        stopRecording()
        recording = target
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let code = UInt16(event.keyCode)
            guard !KeyCodes.isModifier(code), var copy = currentRule() else { return nil }
            switch target {
            case .input:  copy.keyCode = code
            case .output: copy.outputKey = code
            }
            settings.updateAppRule(copy)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
