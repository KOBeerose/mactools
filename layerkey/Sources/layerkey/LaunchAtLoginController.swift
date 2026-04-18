import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    enum SyncError: LocalizedError {
        case appNotInstalled

        var errorDescription: String? {
            switch self {
            case .appNotInstalled:
                return "Install and launch LayerKey from its app bundle before enabling launch at login."
            }
        }
    }

    enum State {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    private let fileManager: FileManager
    private let service = SMAppService.mainApp

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private static let legacyLaunchAgentLabel = "dev.tahaelghabi.LayerKey.launchagent"

    var isEnabled: Bool {
        state == .enabled
    }

    var state: State {
        guard isRunningFromInstalledAppBundle else {
            return .unavailable
        }

        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    var noteText: String {
        switch state {
        case .enabled:
            return "LayerKey will launch automatically after login."
        case .disabled:
            return "LayerKey will not launch automatically."
        case .requiresApproval:
            return "Login item approval is required in System Settings."
        case .unavailable:
            return "Install and launch LayerKey from its app bundle before enabling launch at login."
        }
    }

    func cleanupLegacyLaunchAgent() throws {
        let launchAgentURL = legacyLaunchAgentURL
        guard fileManager.fileExists(atPath: launchAgentURL.path) else {
            return
        }

        try fileManager.removeItem(at: launchAgentURL)
    }

    func setEnabled(_ isEnabled: Bool) throws {
        guard isRunningFromInstalledAppBundle else {
            if isEnabled {
                throw SyncError.appNotInstalled
            }
            return
        }

        try cleanupLegacyLaunchAgent()

        if isEnabled {
            if service.status == .enabled {
                try? service.unregister()
            }

            try service.register()
        } else {
            try service.unregister()
        }
    }

    private var isRunningFromInstalledAppBundle: Bool {
        Bundle.main.bundleURL.path.hasSuffix(".app")
    }

    private var legacyLaunchAgentURL: URL {
        let libraryURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return libraryURL
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.legacyLaunchAgentLabel).plist")
    }
}
