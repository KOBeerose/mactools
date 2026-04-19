import AppKit
import SwiftUI

@main
struct BetterModifiersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Window scene (not WindowGroup) gives us a single, identifiable window
        // we can re-open from the menu bar via OpenWindowAction. Crucially, a
        // Scene-managed window is the only configuration in which
        // `.toolbar(removing: .sidebarToggle)` actually removes the auto-injected
        // trailing toggle from NavigationSplitView's underlying split-view
        // controller. Hand-rolled `NSWindow` + `NSHostingController` does not
        // wire that hint through, which is why the duplicate kept appearing.
        Window("BetterModifiers", id: "main") {
            MainWindow(
                store: appDelegate.rulesStore,
                settings: appDelegate.settingsStore,
                viewModel: appDelegate.viewModel,
                updateController: appDelegate.updateController,
                sidebarVisibility: appDelegate.sidebarVisibility
            )
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                AppDelegate.openMainWindowAction = { openWindow(id: "main") }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 640)
        .commands {
            // Hide the default "New Window" command - we only ever want one
            // main window and reopen via the menu bar / dock click.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
