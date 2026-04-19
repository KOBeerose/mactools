import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController`. The updater is **not** started eagerly so a
/// missing or placeholder `SUPublicEDKey` cannot block app launch with Sparkle's modal alert.
/// We start it lazily on first user-initiated action ("Check Now" or toggling auto-check on),
/// and we detect the placeholder key to surface a friendly inline status instead of Sparkle's
/// generic "Unable to Check For Updates" sheet.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    let updaterController: SPUStandardUpdaterController

    @Published private(set) var lastCheckText: String
    @Published private(set) var statusMessage: String?
    @Published var automaticChecksEnabled: Bool {
        didSet {
            guard oldValue != automaticChecksEnabled else { return }
            if automaticChecksEnabled {
                ensureStarted()
                if isConfigured {
                    updaterController.updater.automaticallyChecksForUpdates = true
                }
            } else if started {
                updaterController.updater.automaticallyChecksForUpdates = false
            }
        }
    }

    let isConfigured: Bool

    private var started = false
    private var observer: NSKeyValueObservation?

    override init() {
        self.isConfigured = Self.detectConfigured()

        // startingUpdater: false — never block launch. We start it only on demand.
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Mirror Sparkle's persisted preference, but never auto-start the updater here.
        self.automaticChecksEnabled = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? false

        if isConfigured {
            self.lastCheckText = "Never checked"
            self.statusMessage = nil
        } else {
            self.lastCheckText = "Updates not configured"
            self.statusMessage = "Updates are wired but the maintainer hasn't set SUPublicEDKey yet."
        }

        super.init()
    }

    func checkForUpdates() {
        guard isConfigured else {
            statusMessage = "Updates are not configured for this build."
            return
        }
        ensureStarted()
        updaterController.checkForUpdates(nil)
    }

    private func ensureStarted() {
        guard !started, isConfigured else { return }
        updaterController.startUpdater()
        started = true
        observeLastCheck()
        refreshLastCheckText()
    }

    private func observeLastCheck() {
        observer = updaterController.updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshLastCheckText() }
        }
    }

    private func refreshLastCheckText() {
        if let date = updaterController.updater.lastUpdateCheckDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            lastCheckText = "Last checked: \(formatter.string(from: date))"
        } else {
            lastCheckText = "Never checked"
        }
    }

    /// Returns true if Info.plist ships a real `SUPublicEDKey` (not the placeholder).
    private static func detectConfigured() -> Bool {
        let info = Bundle.main.infoDictionary
        let key = (info?["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return false }
        if key.hasPrefix("REPLACE_ME") { return false }
        return true
    }
}
