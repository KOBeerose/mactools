import AppKit
@preconcurrency import ApplicationServices
import Foundation

@MainActor
final class PermissionsController {
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        openSettings(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ])
    }

    private func openSettings(candidates: [String]) {
        for target in candidates {
            guard let url = URL(string: target) else { continue }
            if NSWorkspace.shared.open(url) {
                break
            }
        }
    }
}
