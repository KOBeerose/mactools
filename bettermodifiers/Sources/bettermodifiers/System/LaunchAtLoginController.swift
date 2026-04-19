import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    enum SyncError: LocalizedError {
        case appNotInstalled

        var errorDescription: String? {
            switch self {
            case .appNotInstalled:
                return "Install and launch BetterModifiers from its app bundle before enabling launch at login."
            }
        }
    }

    enum State {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    private let service = SMAppService.mainApp

    var isEnabled: Bool { state == .enabled }

    var state: State {
        guard isRunningFromInstalledAppBundle else { return .unavailable }

        switch service.status {
        case .enabled:         return .enabled
        case .notRegistered:   return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound:        return .unavailable
        @unknown default:      return .unavailable
        }
    }

    var noteText: String {
        switch state {
        case .enabled:         return "BetterModifiers will launch automatically after login."
        case .disabled:        return "BetterModifiers will not launch automatically."
        case .requiresApproval: return "Login item approval is required in System Settings."
        case .unavailable:     return "Run from ~/Applications to enable launch at login."
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        guard isRunningFromInstalledAppBundle else {
            if isEnabled { throw SyncError.appNotInstalled }
            return
        }

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
}
