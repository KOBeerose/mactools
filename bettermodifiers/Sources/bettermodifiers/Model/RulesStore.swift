import Combine
import Foundation

@MainActor
final class RulesStore: ObservableObject {
    @Published private(set) var rules: [Rule] = []

    var onChange: (() -> Void)?

    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.tahaelghabi.BetterModifiers.RulesStore", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private var lookupCache: [LookupKey: Rule] = [:]

    private struct LookupKey: Hashable {
        let trigger: Trigger
        let inputKey: UInt16
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

    /// O(1) lookup used by the event tap on the hot path.
    func rule(for trigger: Trigger, inputKey: UInt16) -> Rule? {
        let rule = lookupCache[LookupKey(trigger: trigger, inputKey: inputKey)]
        guard let rule, rule.isEnabled else { return nil }
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

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        rebuildCacheAndPersist()
    }

    /// Picks the first 0..9 digit not yet used by a rule with this trigger.
    /// Falls back to "0" if every digit is taken (the new rule will then conflict with
    /// the existing "0" rule, which is fine - the row UI surfaces conflicts).
    static let digitKeyCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25] // 0..9
    func firstUnusedInputKey(for trigger: Trigger) -> UInt16 {
        let used = Set(rules.filter { $0.trigger == trigger }.map(\.inputKey))
        return Self.digitKeyCodes.first(where: { !used.contains($0) }) ?? Self.digitKeyCodes[0]
    }

    /// Returns rules that share the same (trigger, inputKey) as `candidate` but a different id.
    func conflicts(for candidate: Rule) -> [Rule] {
        rules.filter {
            $0.id != candidate.id
                && $0.trigger == candidate.trigger
                && $0.inputKey == candidate.inputKey
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
        var cache: [LookupKey: Rule] = [:]
        for rule in rules {
            cache[LookupKey(trigger: rule.trigger, inputKey: rule.inputKey)] = rule
        }
        lookupCache = cache
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
                inputKey: code,
                outputModifiers: [.option],
                outputKey: code
            )
        }
    }()
}
