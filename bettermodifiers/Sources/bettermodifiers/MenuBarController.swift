import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let viewModel: AppViewModel
    private let onOpenWindow: () -> Void

    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var openWindowMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var accessibilityMenuItem: NSMenuItem!
    private var openAccessibilityMenuItem: NSMenuItem!
    private var restartEngineMenuItem: NSMenuItem!

    init(viewModel: AppViewModel, onOpenWindow: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenWindow = onOpenWindow
        super.init()
        install()
    }

    func refresh() {
        guard menu != nil, statusItem != nil else { return }
        statusMenuItem.title = "Status: \(viewModel.statusText)"
        enabledMenuItem.title = viewModel.isEnabled ? "Disable BetterModifiers" : "Enable BetterModifiers"
        enabledMenuItem.state = viewModel.isEnabled ? .on : .off
        launchAtLoginMenuItem.state = viewModel.launchAtLoginEnabled ? .on : .off
        launchAtLoginMenuItem.isEnabled = viewModel.canChangeLaunchAtLogin
        accessibilityMenuItem.title = "Accessibility: \(viewModel.hasAccessibility ? "Granted" : "Missing")"
        accessibilityMenuItem.isEnabled = !viewModel.hasAccessibility
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button,
           let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "BetterModifiers") {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            item.button?.title = "BM"
        }

        menu = NSMenu()
        menu.delegate = self

        statusMenuItem = makeItem(title: "", action: nil)
        statusMenuItem.isEnabled = false

        enabledMenuItem = makeItem(title: "", action: #selector(toggleEnabled))
        openWindowMenuItem = makeItem(title: "Open BetterModifiers…", action: #selector(openWindow))

        launchAtLoginMenuItem = makeItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin))
        accessibilityMenuItem = makeItem(title: "Accessibility", action: #selector(requestAccessibilityPermission))
        openAccessibilityMenuItem = makeItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings))
        restartEngineMenuItem = makeItem(title: "Restart Engine", action: #selector(restartEngine))

        let quitItem = NSMenuItem(
            title: "Quit BetterModifiers",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        menu.addItem(statusMenuItem)
        menu.addItem(enabledMenuItem)
        menu.addItem(openWindowMenuItem)
        menu.addItem(.separator())
        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(accessibilityMenuItem)
        menu.addItem(openAccessibilityMenuItem)
        menu.addItem(restartEngineMenuItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        item.menu = menu
        refresh()
    }

    private func makeItem(title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        viewModel.refresh()
        refresh()
    }

    @objc private func toggleEnabled() {
        viewModel.setEnabled(!viewModel.isEnabled)
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
