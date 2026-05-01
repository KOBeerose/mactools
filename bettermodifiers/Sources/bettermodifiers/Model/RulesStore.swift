import Combine
import Foundation

/// Result of asking the store "what should I do with this first input key?"
/// Keeps the engine's hot path branch-free and predictable.
enum RuleLookup {
    /// A normal 1-key rule matches AND no 2-key rule shares this prefix.
    /// Caller fires immediately - no waiting.
    case singleKeyHit(Rule)
    /// At least one 2-key rule shares this prefix. Caller must wait for a
    /// second key (with a timeout). `fallback` is the 1-key rule to fire on
    /// timeout, if one exists.
    case ambiguous(fallback: Rule?)
    /// No rule (single or sequence) starts with this key.
    case miss
}

@MainActor
final class RulesStore: ObservableObject {
    @Published private(set) var rules: [Rule] = []

    var onChange: (() -> Void)?

    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.tahaelghabi.BetterModifiers.RulesStore", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private var singleKeyCache: [LookupKey: Rule] = [:]
    private var sequenceCache: [SequenceKey: Rule] = [:]
    private var sequencePrefixes: Set<LookupKey> = []

    private struct LookupKey: Hashable {
        let trigger: Trigger
        let inputKey: UInt16
    }

    private struct SequenceKey: Hashable {
        let trigger: Trigger
        let firstKey: UInt16
        let secondKey: UInt16
    }

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSHomeDirectory())
            let folder = appSupport.appendingPathComponent("BetterModifiers", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.fileURL = folder.appendingPathComponent("rules.json")
        }
        load()
    }

    /// Hot-path lookup. Tells the engine whether to fire now, wait for a second key,
    /// or pass the keystroke through.
    func lookup(trigger: Trigger, firstKey: UInt16) -> RuleLookup {
        let single = singleKeyCache[LookupKey(trigger: trigger, inputKey: firstKey)].flatMap(usableRule)
        let hasSequencePrefix = sequencePrefixes.contains(LookupKey(trigger: trigger, inputKey: firstKey))
        if hasSequencePrefix { return .ambiguous(fallback: single) }
        if let single { return .singleKeyHit(single) }
        return .miss
    }

    /// Second-key resolution after a `.ambiguous` lookup.
    func sequenceRule(trigger: Trigger, firstKey: UInt16, secondKey: UInt16) -> Rule? {
        let key = SequenceKey(trigger: trigger, firstKey: firstKey, secondKey: secondKey)
        return sequenceCache[key].flatMap(usableRule)
    }

    /// Legacy single-key lookup retained for tests / call sites that don't need sequence
    /// support. Returns nil if a 2-key rule shadows the prefix (callers must use `lookup`
    /// to get the full picture).
    func rule(for trigger: Trigger, inputKey: UInt16) -> Rule? {
        singleKeyCache[LookupKey(trigger: trigger, inputKey: inputKey)].flatMap(usableRule)
    }

    private func usableRule(_ rule: Rule) -> Rule? {
        guard rule.isEnabled, rule.outputKey != KeyCodes.unset else { return nil }
        return rule
    }

    func add(_ rule: Rule) {
        rules.append(rule)
        rebuildCacheAndPersist()
    }

    func update(_ rule: Rule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        rebuildCacheAndPersist()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        rebuildCacheAndPersist()
    }

    /// Duplicates the rule with `id`, inserting the copy directly after it.
    /// Returns the new rule's id so callers can scroll to / highlight it.
    @discardableResult
    func duplicate(id: UUID) -> UUID? {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = rules[index]
        copy.id = UUID()
        rules.insert(copy, at: index + 1)
        rebuildCacheAndPersist()
        return copy.id
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        rebuildCacheAndPersist()
    }

    /// Picks the first 0..9 digit not yet used as a single-key trigger.
    /// (Sequence rules don't reserve digits - their first key is allowed to coexist
    /// with a 1-key rule using the same digit.)
    static let digitKeyCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25] // 0..9
    func firstUnusedInputKey(for trigger: Trigger) -> UInt16 {
        let used = Set(rules
            .filter { $0.trigger == trigger && $0.inputKeys.count == 1 }
            .map(\.inputKey))
        return Self.digitKeyCodes.first(where: { !used.contains($0) }) ?? Self.digitKeyCodes[0]
    }

    /// Rules that share the exact same `(trigger, inputKeys)` as `candidate` but a different id.
    func conflicts(for candidate: Rule) -> [Rule] {
        rules.filter {
            $0.id != candidate.id
                && $0.trigger == candidate.trigger
                && $0.inputKeys == candidate.inputKeys
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            rules = Self.defaultRules
            rebuildCacheAndPersist()
            return
        }

        do {
            rules = try JSONDecoder().decode([Rule].self, from: data)
            rebuildCache()
        } catch {
            rules = Self.defaultRules
            rebuildCacheAndPersist()
        }
    }

    private func rebuildCacheAndPersist() {
        rebuildCache()
        scheduleSave()
        onChange?()
    }

    private func rebuildCache() {
        var single: [LookupKey: Rule] = [:]
        var sequence: [SequenceKey: Rule] = [:]
        var prefixes: Set<LookupKey> = []
        for rule in rules {
            switch rule.inputKeys.count {
            case 1:
                single[LookupKey(trigger: rule.trigger, inputKey: rule.inputKeys[0])] = rule
            case 2:
                sequence[SequenceKey(trigger: rule.trigger,
                                     firstKey: rule.inputKeys[0],
                                     secondKey: rule.inputKeys[1])] = rule
                prefixes.insert(LookupKey(trigger: rule.trigger, inputKey: rule.inputKeys[0]))
            default:
                break
            }
        }
        singleKeyCache = single
        sequenceCache = sequence
        sequencePrefixes = prefixes
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()

        // Encode synchronously on the main actor so the dispatched closure only deals with
        // Sendable values. Closures inherit @MainActor isolation from their enclosing
        // context, so capturing only Sendable values + an explicit @Sendable block keeps
        // Swift 6's runtime isolation check from tripping when the work runs off-main.
        let url = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return }

        let block: @Sendable () -> Void = {
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                NSLog("[BetterModifiers] failed to save rules: \(error)")
            }
        }
        let item = DispatchWorkItem(block: block)
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }

    /// Seed rules so a fresh install demonstrates Tab + 0..9 -> Option + 0..9.
    private static let defaultRules: [Rule] = {
        let digitKeyCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25] // 0..9
        return digitKeyCodes.map { code in
            Rule(
                trigger: .tab,
                inputKeys: [code],
                outputModifiers: [.option],
                outputKey: code
            )
        }
    }()
}
