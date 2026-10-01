import Foundation

/// An app whose floating overlay (a launcher, a dictation pill) takes keys while
/// another app stays frontmost. While it's on screen, App Rules step aside so a
/// key like Escape reaches the overlay on the first press. Personal branch.
struct OverlayApp: Codable, Hashable, Identifiable {
    enum Windows: String, Codable, CaseIterable, Identifiable {
        /// Any floating window of the app counts.
        case anyFloating
        /// Only the app's first-created floating window counts. For apps with
        /// several overlays where only one takes keys (DualWhisper's dictation
        /// pill, not its read-aloud controls).
        case firstFloating

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .anyFloating:   return "Any floating window"
            case .firstFloating: return "Only its first floating window"
            }
        }
    }

    var id: UUID
    var isEnabled: Bool
    var bundleID: String
    var appName: String
    var windows: Windows

    init(id: UUID = UUID(), isEnabled: Bool = true, bundleID: String, appName: String, windows: Windows = .anyFloating) {
        self.id = id
        self.isEnabled = isEnabled
        self.bundleID = bundleID
        self.appName = appName
        self.windows = windows
    }

    static let defaults: [OverlayApp] = [
        OverlayApp(bundleID: "dev.kobetools.betterpalette", appName: "BetterPalette"),
        OverlayApp(bundleID: "com.dualwhisper.app", appName: "DualWhisper", windows: .firstFloating),
    ]
}
