import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = .default {
        didSet {
            guard oldValue != settings else { return }
            scheduleSave()
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.tahaelghabi.BetterModifiers.SettingsStore", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSHomeDirectory())
            let folder = appSupport.appendingPathComponent("BetterModifiers", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.fileURL = folder.appendingPathComponent("settings.json")
        }
        load()
    }

    func modeConfig(for trigger: Trigger) -> ModifierModeConfig {
        settings.modifierMode[trigger.id] ?? ModifierModeConfig(isEnabled: false, modifiers: [])
    }

    func setModeEnabled(_ enabled: Bool, for trigger: Trigger) {
        var current = modeConfig(for: trigger)
        current.isEnabled = enabled
        settings.modifierMode[trigger.id] = current
    }

    func setModeModifiers(_ modifiers: ModifierMask, for trigger: Trigger) {
        var current = modeConfig(for: trigger)
        current.modifiers = modifiers
        settings.modifierMode[trigger.id] = current
    }

    func addModeException(_ keyCode: UInt16, for trigger: Trigger) {
        var current = modeConfig(for: trigger)
        guard !current.exceptions.contains(keyCode) else { return }
        current.exceptions.append(keyCode)
        settings.modifierMode[trigger.id] = current
    }

    func removeModeException(_ keyCode: UInt16, for trigger: Trigger) {
        var current = modeConfig(for: trigger)
        current.exceptions.removeAll { $0 == keyCode }
        settings.modifierMode[trigger.id] = current
    }

    func setExceptionBehavior(_ behavior: ModifierModeConfig.ExceptionBehavior, for trigger: Trigger) {
        var current = modeConfig(for: trigger)
        current.exceptionBehavior = behavior
        settings.modifierMode[trigger.id] = current
    }

    // MARK: Paused triggers

    func isPaused(_ trigger: Trigger) -> Bool {
        settings.pausedTriggers.contains(trigger.id)
    }

    func setPaused(_ paused: Bool, for trigger: Trigger) {
        guard paused != isPaused(trigger) else { return }
        if paused {
            settings.pausedTriggers.append(trigger.id)
        } else {
            settings.pausedTriggers.removeAll { $0 == trigger.id }
        }
    }

    // MARK: Custom triggers

    /// Adds a new modifier-combo trigger with sensible defaults. The user can
    /// then rename it and pick the exact modifier set from the Rules page.
    @discardableResult
    func addCustomTrigger() -> CustomTrigger {
        let index = settings.customTriggers.count + 1
        let new = CustomTrigger(
            name: "Custom \(index)",
            modifiers: [.control, .option]
        )
        settings.customTriggers.append(new)
        return new
    }

    func updateCustomTrigger(_ trigger: CustomTrigger) {
        guard let idx = settings.customTriggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        settings.customTriggers[idx] = trigger
    }

    func removeCustomTrigger(id: UUID) {
        settings.customTriggers.removeAll { $0.id == id }
        let triggerId = Trigger.custom(id).id
        // Drop any modifier-mode entry tied to this custom trigger, too.
        settings.modifierMode[triggerId] = nil
        settings.dismissedWarnings.removeAll { $0 == triggerId }
        settings.pausedTriggers.removeAll { $0 == triggerId }
    }

    func customTrigger(id: UUID) -> CustomTrigger? {
        settings.customTriggers.first(where: { $0.id == id })
    }

    /// Human label for diagnostics, e.g. "Tab" or "Custom 1 (⇪␣)" for custom combos.
    func label(for trigger: Trigger) -> String {
        guard case .custom(let id) = trigger, let ct = customTrigger(id: id) else {
            return trigger.displayName
        }
        return "\(ct.resolvedName) (\(ct.symbolLabel))"
    }

    // MARK: Dismissed system-shortcut warnings

    func isWarningDismissed(for trigger: Trigger) -> Bool {
        settings.dismissedWarnings.contains(trigger.id)
    }

    func dismissWarning(for trigger: Trigger) {
        guard !settings.dismissedWarnings.contains(trigger.id) else { return }
        settings.dismissedWarnings.append(trigger.id)
    }

    func addAppRule(bundleID: String, appName: String) -> AppRule {
        let rule = AppRule(bundleID: bundleID, appName: appName)
        settings.appRules.append(rule)
        return rule
    }

    func updateAppRule(_ rule: AppRule) {
        guard let index = settings.appRules.firstIndex(where: { $0.id == rule.id }) else { return }
        settings.appRules[index] = rule
    }

    func removeAppRule(id: UUID) {
        settings.appRules.removeAll { $0.id == id }
    }

    func removeAppRules(bundleID: String) {
        settings.appRules.removeAll { $0.bundleID == bundleID }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            settings = .default
            return
        }
        settings = decoded
        // `didSet` doesn't fire from init, so write back here when decoding
        // migrated or filled in fields; otherwise the file keeps the old shape.
        if (try? Self.makeEncoder().encode(decoded)) != data {
            scheduleSave()
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()

        let url = fileURL
        guard let data = try? Self.makeEncoder().encode(settings) else { return }

        let block: @Sendable () -> Void = {
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                NSLog("[BetterModifiers] failed to save settings: \(error)")
            }
        }
        let item = DispatchWorkItem(block: block)
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }
}
