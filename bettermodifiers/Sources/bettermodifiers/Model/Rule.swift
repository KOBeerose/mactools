import Foundation

struct Rule: Identifiable, Codable, Hashable {
    var id: UUID
    var trigger: Trigger
    var inputKey: UInt16
    var outputModifiers: ModifierMask
    var outputKey: UInt16
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        trigger: Trigger,
        inputKey: UInt16,
        outputModifiers: ModifierMask,
        outputKey: UInt16,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.inputKey = inputKey
        self.outputModifiers = outputModifiers
        self.outputKey = outputKey
        self.isEnabled = isEnabled
    }

    var summary: String {
        let inLabel = KeyCodes.label(for: inputKey)
        let outLabel = KeyCodes.label(for: outputKey)
        let mods = outputModifiers.displaySymbols
        return "\(trigger.displayName) + \(inLabel)  →  \(mods)\(outLabel)"
    }
}
