import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = SettingsStore()
    private let permissions = PermissionsController()
    private let capsLockController = CapsLockController()
    private lazy var eventTapController = EventTapController(
        settings: settings,
        permissions: permissions,
        capsLockController: capsLockController
    )

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var modifierMenuItem: NSMenuItem!
    private var accessibilityMenuItem: NSMenuItem!
    private var permissionNoteMenuItem: NSMenuItem!
    private var openAccessibilityMenuItem: NSMenuItem!
    private var pollTimer: Timer?
    private var lastAccessibilityPermissionState = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        eventTapController.onStatusChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshMenuState()
            }
        }

        lastAccessibilityPermissionState = permissions.hasAccessibilityPermission
        eventTapController.refresh()
        startPermissionPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        eventTapController.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button,
           let image = NSImage(
               systemSymbolName: "keyboard",
               accessibilityDescription: "LayerKey"
           ) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            statusItem.button?.title = "MO"
        }

        menu = NSMenu()
        menu.delegate = self

        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false

        enabledMenuItem = NSMenuItem(
            title: "",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabledMenuItem.target = self

        modifierMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        modifierMenuItem.isEnabled = false

        accessibilityMenuItem = NSMenuItem(
            title: "",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        accessibilityMenuItem.target = self

        permissionNoteMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionNoteMenuItem.isEnabled = false

        openAccessibilityMenuItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAccessibilityMenuItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit LayerKey",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        menu.addItem(statusMenuItem)
        menu.addItem(enabledMenuItem)
        menu.addItem(modifierMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(accessibilityMenuItem)
        menu.addItem(permissionNoteMenuItem)
        menu.addItem(openAccessibilityMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuState()
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
        let currentAccessibilityPermission = permissions.hasAccessibilityPermission
        if currentAccessibilityPermission != lastAccessibilityPermissionState {
            lastAccessibilityPermissionState = currentAccessibilityPermission
            eventTapController.refresh()
        }
        refreshMenuState()
    }

    private func refreshMenuState() {
        let accessibilityState = permissions.hasAccessibilityPermission ? "Granted" : "Missing"

        statusMenuItem.title = "Status: \(eventTapController.status.displayText)"
        enabledMenuItem.title = settings.isEnabled ? "Disable remapping" : "Enable remapping"
        enabledMenuItem.state = settings.isEnabled ? .on : .off
        let enabledTriggers = settings.enabledTriggers.map(\.displayName).joined(separator: ", ")
        modifierMenuItem.title = "Rules: \(enabledTriggers) + 0-9 -> \(settings.outputModifier.displayName) + 0-9"

        accessibilityMenuItem.title = "Accessibility: \(accessibilityState)"
        accessibilityMenuItem.isEnabled = !permissions.hasAccessibilityPermission

        permissionNoteMenuItem.title = "Input Monitoring: not required for this Tab MVP"
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        eventTapController.refresh()
        refreshMenuState()
    }

    @objc private func requestAccessibilityPermission() {
        permissions.requestAccessibilityPermission()
        let currentAccessibilityPermission = permissions.hasAccessibilityPermission
        if currentAccessibilityPermission != lastAccessibilityPermissionState {
            lastAccessibilityPermissionState = currentAccessibilityPermission
            eventTapController.refresh()
        }
        refreshMenuState()
    }

    @objc private func openAccessibilitySettings() {
        permissions.openAccessibilitySettings()
    }
}
