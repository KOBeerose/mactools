import Combine
import Foundation

/// Bridges the engine, permissions, and login-item controllers into observable state for SwiftUI views.
@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var hasAccessibility: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var canChangeLaunchAtLogin: Bool
    @Published private(set) var launchAtLoginNote: String
    @Published private(set) var statusText: String

    private let engine: EventTapController
    private let permissions: PermissionsController
    private let launchAtLogin: LaunchAtLoginController

    var onShowError: ((String) -> Void)?

    init(
        engine: EventTapController,
        permissions: PermissionsController,
        launchAtLogin: LaunchAtLoginController
    ) {
        self.engine = engine
        self.permissions = permissions
        self.launchAtLogin = launchAtLogin
        self.isEnabled = engine.isEnabled
        self.hasAccessibility = permissions.hasAccessibilityPermission
        self.launchAtLoginEnabled = launchAtLogin.isEnabled
        self.canChangeLaunchAtLogin = launchAtLogin.state != .unavailable
        self.launchAtLoginNote = launchAtLogin.noteText
        self.statusText = engine.status.displayText
    }

    func setEnabled(_ enabled: Bool) {
        engine.setEnabled(enabled)
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
        } catch {
            onShowError?(error.localizedDescription)
        }
        refresh()
    }

    func openAccessibilitySettings() {
        permissions.openAccessibilitySettings()
    }

    func requestAccessibilityPermission() {
        permissions.requestAccessibilityPermission()
        refresh()
    }

    func restartEngine() {
        engine.refresh()
        refresh()
    }

    func refresh() {
        isEnabled = engine.isEnabled
        hasAccessibility = permissions.hasAccessibilityPermission
        launchAtLoginEnabled = launchAtLogin.isEnabled
        canChangeLaunchAtLogin = launchAtLogin.state != .unavailable
        launchAtLoginNote = launchAtLogin.noteText
        statusText = engine.status.displayText
    }
}
