import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionsController()
    private let capsLockController = CapsLockController()
    private let launchAtLoginController = LaunchAtLoginController()
    private lazy var rulesStore = RulesStore()
    private lazy var settingsStore = SettingsStore()
    private lazy var engine = EventTapController(
        rules: rulesStore,
        settings: settingsStore,
        permissions: permissions,
        capsLockController: capsLockController
    )
    private lazy var updateController = UpdateController()
    private lazy var viewModel = AppViewModel(
        engine: engine,
        permissions: permissions,
        launchAtLogin: launchAtLoginController
    )
    private var menuBar: MenuBarController!

    private var window: NSWindow?
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

        lastAccessibilityState = permissions.hasAccessibilityPermission
        if !lastAccessibilityState {
            // Trigger the system Accessibility prompt so the user is led straight to the
            // right pane in System Settings on first launch.
            permissions.requestAccessibilityPermission()
        }
        engine.refresh()
        startPermissionPolling()
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
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = MainWindow(
            store: rulesStore,
            settings: settingsStore,
            viewModel: viewModel,
            updateController: updateController
        )
        let hostingController = NSHostingController(rootView: root)
        hostingController.sizingOptions = [.minSize, .preferredContentSize]

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "BetterModifiers"
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .visible
        newWindow.toolbarStyle = .unified
        // Use the standard window background and let the SwiftUI content paint a single
        // unified material on top - this avoids the previous mismatch between sidebar
        // (translucent) and detail (warm grey) in light mode.
        newWindow.backgroundColor = NSColor.windowBackgroundColor
        newWindow.contentViewController = hostingController
        newWindow.setContentSize(NSSize(width: 980, height: 640))
        newWindow.minSize = NSSize(width: 820, height: 520)
        newWindow.collectionBehavior.insert(.fullScreenPrimary)
        if let zoomButton = newWindow.standardWindowButton(.zoomButton) {
            zoomButton.isEnabled = true
        }
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        window = newWindow

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
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
        // Drop the strong reference so SwiftUI views deallocate and we stay LSUIElement-light.
        if let closing = notification.object as? NSWindow, closing === window {
            window = nil
        }
    }
}
