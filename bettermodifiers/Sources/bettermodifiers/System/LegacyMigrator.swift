import Foundation
import ServiceManagement

/// One-time cleanup of the previous LayerKey install when a user upgrades to Better Modifiers.
/// Best effort; all errors are swallowed so a partial cleanup can never block startup.
@MainActor
enum LegacyMigrator {
    private static let didRunKey = "BetterModifiers.legacyMigratorDidRun"

    static func runOnce(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: didRunKey) else { return }

        unregisterLegacyLoginItem()
        removeLegacyLaunchAgent(fileManager: fileManager)
        removeLegacyAppBundle(fileManager: fileManager)

        defaults.set(true, forKey: didRunKey)
    }

    private static func unregisterLegacyLoginItem() {
        // Best-effort: if SMAppService.mainApp on this binary somehow knew the LayerKey label
        // it would unregister it. We can't directly target a different bundle id from here,
        // but `SMAppService.mainApp.unregister()` is safe to call even when not registered.
        try? SMAppService.mainApp.unregister()
    }

    private static func removeLegacyLaunchAgent(fileManager: FileManager) {
        let url = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/dev.tahaelghabi.LayerKey.launchagent.plist")
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func removeLegacyAppBundle(fileManager: FileManager) {
        let candidates = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LayerKey.app"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ModifierOverride.app"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Better Modifiers.app")
        ]
        for url in candidates where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
