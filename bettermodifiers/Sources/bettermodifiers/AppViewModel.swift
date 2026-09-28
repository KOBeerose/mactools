import Combine
import Foundation

/// One entry in General's "Last triggered" card.
struct FiredRecord: Identifiable {
    let id = UUID()
    let triggerName: String
    let triggerChip: String
    let triggerSymbol: String
    let inputKeys: [UInt16]
    let modifiers: ModifierMask
    let outputKey: UInt16
    let source: EventTapController.FireSource
    let date: Date
}

/// What the General page health strip shows. Ordered by what blocks the engine first.
enum EngineHealth: Equatable {
    case running
    case disabled
    case missingPermission
    case tapFailed
    case tapNotReceiving
    /// `blocked` turns true once secure input outlasts `secureInputGrace`: a password
    /// field is normal, a lock held for longer usually means an app is stuck with it.
    case secureInput(holder: SecureInputHolder?, blocked: Bool)

    var isHealthy: Bool {
        switch self {
        case .running: return true
        case .secureInput(_, let blocked): return !blocked
        default: return false
        }
    }
}

/// Bridges the engine, permissions, and login-item controllers into observable state for SwiftUI views.
@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var hasAccessibility: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var canChangeLaunchAtLogin: Bool
    @Published private(set) var launchAtLoginNote: String
    @Published private(set) var statusText: String
    @Published private(set) var recentFired: [FiredRecord] = []
    @Published private(set) var health: EngineHealth = .running

    static let recentFiredLimit = 5
    private static let secureInputGrace: TimeInterval = 5
    private var secureInputSince: Date?

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
        self.health = computeHealth()
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

    /// Called from `EventTapController.onRuleFired` so the General page can prove that the
    /// engine is alive in real time.
    func noteRuleFired(_ record: FiredRecord) {
        recentFired.insert(record, at: 0)
        if recentFired.count > Self.recentFiredLimit {
            recentFired.removeLast(recentFired.count - Self.recentFiredLimit)
        }
    }

    /// Runs every 2 s from the permission poll. Only assign changed values:
    /// @Published fires on every set, which would re-render the window each tick.
    func refresh() {
        update(\.isEnabled, engine.isEnabled)
        update(\.hasAccessibility, permissions.hasAccessibilityPermission)
        update(\.launchAtLoginEnabled, launchAtLogin.isEnabled)
        update(\.canChangeLaunchAtLogin, launchAtLogin.state != .unavailable)
        update(\.launchAtLoginNote, launchAtLogin.noteText)
        update(\.statusText, engine.status.displayText)
        update(\.health, computeHealth())
    }

    private func computeHealth() -> EngineHealth {
        guard engine.isEnabled else { return .disabled }
        guard permissions.hasAccessibilityPermission else { return .missingPermission }
        switch engine.status {
        case .failedToCreateTap: return .tapFailed
        case .tapNotReceiving: return .tapNotReceiving
        case .missingPermissions: return .missingPermission
        case .inactive: return .disabled
        case .running: break
        }
        guard engine.secureInputActive else {
            secureInputSince = nil
            return .running
        }
        let since = secureInputSince ?? Date()
        secureInputSince = since
        let blocked = Date().timeIntervalSince(since) >= Self.secureInputGrace
        return .secureInput(holder: SecureInputHolder.current(), blocked: blocked)
    }

    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppViewModel, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
