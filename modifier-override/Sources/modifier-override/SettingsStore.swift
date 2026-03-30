import Foundation

final class SettingsStore {
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let outputModifier = "outputModifier"
        static let enabledTabTrigger = "enabledTabTrigger"
        static let enabledCapsLockTrigger = "enabledCapsLockTrigger"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    var outputModifier: OutputModifier {
        get {
            let rawValue = defaults.string(forKey: Keys.outputModifier) ?? OutputModifier.option.rawValue
            return OutputModifier(rawValue: rawValue) ?? .option
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.outputModifier)
        }
    }

    var enabledTriggers: [TriggerKey] {
        var triggers: [TriggerKey] = []
        if defaults.bool(forKey: Keys.enabledTabTrigger) {
            triggers.append(.tab)
        }
        if defaults.bool(forKey: Keys.enabledCapsLockTrigger) {
            triggers.append(.capsLock)
        }
        return triggers
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.outputModifier: OutputModifier.option.rawValue,
            Keys.enabledTabTrigger: true,
            Keys.enabledCapsLockTrigger: false
        ])
    }
}
