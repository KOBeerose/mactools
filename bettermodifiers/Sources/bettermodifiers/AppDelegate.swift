import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let sidebarVisibility = SidebarVisibility()
    let permissions = PermissionsController()
    let capsLockController = CapsLockController()
    let launchAtLoginController = LaunchAtLoginController()
    lazy var rulesStore = RulesStore()
    lazy var settingsStore = SettingsStore()
    lazy var engine = EventTapController(
        rules: rulesStore,
        settings: settingsStore,
        permissions: permissions,
        capsLockController: capsLockController
    )
    lazy var updateController = UpdateController()
    lazy var viewModel = AppViewModel(
        engine: engine,
        permissions: permissions,
        launchAtLogin: launchAtLoginController
    )
    private var menuBar: MenuBarController!

    /// Captured by the SwiftUI App scene so AppKit code (menu bar, dock click
    /// reopen) can request the main window be opened/focused. The Scene-managed
    /// window is the only way `.toolbar(removing: .sidebarToggle)` actually
    /// removes the auto-injected trailing sidebar toggle on macOS 14+.
    static var openMainWindowAction: (() -> Void)?

    private var pollTimer: Timer?
    private var lastAccessibilityState = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigrator.runOnce()

        rulesStore.onChange = { [weak self] in
            self?.engine.refresh()
        }

        settingsStore.onChange = { [weak self] in
            guard let self else { return }
            self.applyAppearance()
            self.menuBar?.setHidden(self.settingsStore.settings.hideMenuBarIcon)
            self.engine.refresh()
        }

        applyAppearance()

        engine.onStatusChange = { [weak self] _ in
            DispatchQueue.main.async { self?.viewModel.refresh(); self?.menuBar.refresh() }
        }
        engine.onRuleFired = { [weak self] trigger, inputKey, modifiers, outputKey in
            DispatchQueue.main.async {
                self?.viewModel.noteRuleFired(
                    trigger: trigger,
                    inputKey: inputKey,
                    modifiers: modifiers,
                    outputKey: outputKey
                )
            }
        }

        viewModel.onShowError = { [weak self] message in
            self?.presentError(message)
        }

        menuBar = MenuBarController(viewModel: viewModel) { [weak self] in
            self?.openMainWindow()
        }
        menuBar.setHidden(settingsStore.settings.hideMenuBarIcon)

        lastAccessibilityState = permissions.hasAccessibilityPermission
        if !lastAccessibilityState {
            // Trigger the system Accessibility prompt so the user is led straight to the
            // right pane in System Settings on first launch.
            permissions.requestAccessibilityPermission()
        }
        engine.refresh()
        startPermissionPolling()

        // Re-apply Caps -> F18 mapping after sleep/wake, because IOKit forgets per-device
        // user key maps across wake on some keyboards (Keychron Q-series and other QMK
        // boards re-enumerate as new HID services on wake).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        capsLockController.syncRemap(enabled: true)
        engine.refresh()
    }

    @objc func restartEngine() {
        engine.refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
    }

    private func applyAppearance() {
        switch settingsStore.settings.appearance {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        engine.stop()
    }

    private func startPermissionPolling() {
        pollTimer = Timer.scheduledTimer(
            timeInterval: 2,
            target: self,
            selector: #selector(pollPermissions),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func pollPermissions() {
        let current = permissions.hasAccessibilityPermission
        if current != lastAccessibilityState {
            lastAccessibilityState = current
            engine.refresh()
        }
        viewModel.refresh()
        menuBar.refresh()
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.openMainWindowAction?()
    }

    private static func findSplitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        for sub in view.subviews {
            if let found = findSplitView(in: sub) { return found }
        }
        return nil
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "BetterModifiers"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // After the Scene-managed window closes, demote back to a menu-bar-only
        // app so we leave Cmd-Tab and the Dock again.
        DispatchQueue.main.async {
            if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) == false {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
