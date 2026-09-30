import AppKit

/// Status item: any click opens the menu; the icon dims while off.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: AppViewModel
    private let onOpenWindow: () -> Void

    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    /// When true, the status item is removed from the menu bar entirely.
    private(set) var isHidden = false
    private var statusMenuItem: NSMenuItem!
    private var enabledSwitch: MenuSwitch!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var accessibilityMenuItem: NSMenuItem!

    init(viewModel: AppViewModel, onOpenWindow: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenWindow = onOpenWindow
        super.init()
        install()
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
        } else if statusItem == nil {
            installStatusItem()
            refresh()
        }
    }

    func refresh() {
        guard menu != nil else { return }
        updateIcon()
        statusMenuItem.title = statusLine
        enabledSwitch.isOn = viewModel.isEnabled
        launchAtLoginMenuItem.state = viewModel.launchAtLoginEnabled ? .on : .off
        launchAtLoginMenuItem.isEnabled = viewModel.canChangeLaunchAtLogin
        accessibilityMenuItem.title = viewModel.hasAccessibility
            ? "Accessibility: Granted"
            : "Grant Accessibility…"
        accessibilityMenuItem.isEnabled = !viewModel.hasAccessibility
    }

    private var statusLine: String {
        switch viewModel.health {
        case .running:           return "BetterModifiers is on"
        case .disabled:          return "BetterModifiers is off"
        case .missingPermission: return "Needs Accessibility permission"
        case .secureInput:       return "Paused in a password field"
        case .tapFailed, .tapNotReceiving:
            return "Not receiving keys. Try Restart Engine"
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = viewModel.isEnabled && !viewModel.health.isHealthy
            ? "exclamationmark.triangle"
            : "keyboard"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "BetterModifiers") {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            button.image = image
        }
        button.appearsDisabled = !viewModel.isEnabled
        button.toolTip = viewModel.isEnabled
            ? "BetterModifiers is on"
            : "BetterModifiers is off"
    }

    private func install() {
        menu = NSMenu()
        menu.delegate = self

        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false

        let openItem = makeItem(title: "Open BetterModifiers…", action: #selector(openWindow))
        launchAtLoginMenuItem = makeItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin))

        let troubleshooting = NSMenu()
        accessibilityMenuItem = makeItem(title: "", action: #selector(requestAccessibilityPermission))
        troubleshooting.addItem(accessibilityMenuItem)
        troubleshooting.addItem(makeItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings)))
        troubleshooting.addItem(makeItem(title: "Restart Engine", action: #selector(restartEngine)))
        let troubleshootingItem = NSMenuItem(title: "Troubleshooting", action: nil, keyEquivalent: "")
        troubleshootingItem.submenu = troubleshooting

        let quitItem = NSMenuItem(
            title: "Quit BetterModifiers",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        menu.addItem(statusMenuItem)
        menu.addItem(makeSwitchItem())
        menu.addItem(.separator())
        menu.addItem(openItem)
        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(.separator())
        menu.addItem(troubleshootingItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        installStatusItem()
        refresh()
    }

    /// "Enabled" label with a real switch, so the on/off state reads at a glance.
    private func makeSwitchItem() -> NSMenuItem {
        let label = NSTextField(labelWithString: "Enabled")
        label.font = .menuFont(ofSize: 0)
        enabledSwitch = MenuSwitch()
        enabledSwitch.target = self
        enabledSwitch.action = #selector(switchChanged)

        let row = NSStackView(views: [label, NSView(), enabledSwitch])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 3, left: 14, bottom: 3, right: 14)
        row.frame = NSRect(x: 0, y: 0, width: 240, height: 28)

        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        statusItem = item
        guard let button = item.button else { return }
        button.imagePosition = .imageOnly
        updateIcon()
    }

    private func makeItem(title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        viewModel.refresh()
        viewModel.refreshLaunchAtLogin()
        refresh()
    }

    @objc private func switchChanged() {
        viewModel.setEnabled(enabledSwitch.isOn)
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        viewModel.setLaunchAtLogin(!viewModel.launchAtLoginEnabled)
        refresh()
    }

    @objc private func requestAccessibilityPermission() {
        viewModel.requestAccessibilityPermission()
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        viewModel.openAccessibilitySettings()
    }

    @objc private func restartEngine() {
        viewModel.restartEngine()
        refresh()
    }

    @objc private func openWindow() {
        onOpenWindow()
    }
}
