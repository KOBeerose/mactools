import Foundation

enum Trigger: String, Codable, CaseIterable, Identifiable, Hashable {
    case tab
    case capsLock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab: return "Tab"
        case .capsLock: return "Caps Lock"
        }
    }
}
