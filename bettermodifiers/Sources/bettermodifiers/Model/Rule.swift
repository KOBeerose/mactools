import Foundation

struct Rule: Identifiable, Codable, Hashable {
    var id: UUID
    var trigger: Trigger
    /// 1-element for a normal rule, 2-element for a "double-tap" sequence rule
    /// (e.g. Tab + W + W -> ...). The engine waits up to ~250 ms for a second
    /// key whenever a 2-key rule shares the first key, so single-key latency
    /// is preserved when no sequence rule exists for that prefix.
    var inputKeys: [UInt16]
    var outputModifiers: ModifierMask
    var outputKey: UInt16
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        trigger: Trigger,
        inputKeys: [UInt16],
        outputModifiers: ModifierMask,
        outputKey: UInt16,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.inputKeys = inputKeys
        self.outputModifiers = outputModifiers
        self.outputKey = outputKey
        self.isEnabled = isEnabled
    }

    /// Convenience for the many UI sites that only care about the first input key
    /// (chip rendering, default-digit picking, single-key conflict checks).
    var inputKey: UInt16 { inputKeys.first ?? KeyCodes.unset }

    var summary: String {
        let inLabel = inputKeys.map { KeyCodes.label(for: $0) }.joined(separator: " + ")
        let outLabel = KeyCodes.label(for: outputKey)
        let mods = outputModifiers.displaySymbols
        return "\(trigger.displayName) + \(inLabel)  →  \(mods)\(outLabel)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, trigger, inputKey, inputKeys, outputModifiers, outputKey, isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.trigger = try c.decode(Trigger.self, forKey: .trigger)
        if let keys = try c.decodeIfPresent([UInt16].self, forKey: .inputKeys), !keys.isEmpty {
            self.inputKeys = keys
        } else {
            // Migrate: older rules.json files only carry the singular `inputKey` field.
            let single = try c.decode(UInt16.self, forKey: .inputKey)
            self.inputKeys = [single]
        }
        self.outputModifiers = try c.decode(ModifierMask.self, forKey: .outputModifiers)
        self.outputKey = try c.decode(UInt16.self, forKey: .outputKey)
        self.isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(inputKeys, forKey: .inputKeys)
        try c.encode(outputModifiers, forKey: .outputModifiers)
        try c.encode(outputKey, forKey: .outputKey)
        try c.encode(isEnabled, forKey: .isEnabled)
    }
}
