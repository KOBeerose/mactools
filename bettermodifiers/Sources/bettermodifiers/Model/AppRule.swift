import Foundation

/// Changes what a plain key (no modifiers held) does while one app is frontmost.
struct AppRule: Codable, Hashable, Identifiable {
    enum Behavior: String, Codable, CaseIterable, Identifiable {
        /// A single press is ignored; two quick presses send one.
        case doubleTap
        /// The key does nothing in this app.
        case block
        /// The key sends `outputModifiers + outputKey` instead.
        case remap

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .doubleTap: return "Require double-tap"
            case .block:     return "Block"
            case .remap:     return "Remap to"
            }
        }
    }

    var id: UUID
    var isEnabled: Bool
    var bundleID: String
    var appName: String
    var keyCode: UInt16
    var behavior: Behavior
    var outputKey: UInt16
    var outputModifiers: ModifierMask

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        bundleID: String,
        appName: String,
        keyCode: UInt16 = KeyCodes.unset,
        behavior: Behavior = .doubleTap,
        outputKey: UInt16 = KeyCodes.unset,
        outputModifiers: ModifierMask = []
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.bundleID = bundleID
        self.appName = appName
        self.keyCode = keyCode
        self.behavior = behavior
        self.outputKey = outputKey
        self.outputModifiers = outputModifiers
    }

    /// False while the rule is missing a key it needs, so the engine skips it.
    var isComplete: Bool {
        keyCode != KeyCodes.unset && (behavior != .remap || outputKey != KeyCodes.unset)
    }

    static let claudeBundleID = "com.anthropic.claudefordesktop"

    static let defaultRules: [AppRule] = [
        AppRule(bundleID: claudeBundleID, appName: "Claude", keyCode: KeyCodes.escape, behavior: .doubleTap)
    ]
}
