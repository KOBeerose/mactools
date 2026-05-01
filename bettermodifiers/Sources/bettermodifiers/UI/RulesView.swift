import SwiftUI

struct RulesView: View {
    @ObservedObject var store: RulesStore
    @ObservedObject var settings: SettingsStore

    /// When set, the matching row will auto-start input-key recording on appear.
    @State private var newlyAddedRuleId: UUID?

    /// All triggers to render: the three built-ins plus any custom modifier-combo
    /// triggers the user has defined. Recomputed on every body invocation so
    /// adding/removing customs immediately reflects in the card list.
    private var allTriggers: [Trigger] {
        Trigger.builtIn + settings.settings.customTriggers.map { Trigger.custom($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Rules",
                subtitle: "Tap any chip to change it: pick modifiers directly, or click an input/output key to record. Add a custom modifier combo at the bottom to build your own trigger."
            )

            GeometryReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 20) {
                        ForEach(allTriggers) { trigger in
                            triggerCard(trigger: trigger)
                                .frame(minWidth: proxy.size.width - 48,
                                       alignment: .leading)
                        }

                        addCustomTriggerButton
                            .frame(minWidth: proxy.size.width - 48,
                                   alignment: .leading)
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle("Rules")
    }

    private func triggerCard(trigger: Trigger) -> some View {
        let group = store.rules.filter { $0.trigger == trigger }
        let mode = settings.modeConfig(for: trigger)
        let customId: UUID? = {
            if case .custom(let id) = trigger { return id }
            return nil
        }()

        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if let customId {
                    customTriggerHeader(customId: customId, ruleCount: group.count)
                } else {
                    builtInHeader(trigger: trigger, ruleCount: group.count)
                }

                Divider()

                if mode.isEnabled {
                    modeBanner(trigger: trigger)
                }

                if group.isEmpty {
                    Text("No \(trigger.displayName(customs: settings.settings.customTriggers)) rules yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 22)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { index, rule in
                            InlineRuleRow(
                                store: store,
                                settings: settings,
                                rule: rule,
                                autoRecordOnAppearForId: newlyAddedRuleId,
                                onAutoRecordConsumed: { newlyAddedRuleId = nil }
                            )
                            .opacity(mode.isEnabled ? 0.4 : 1)
                            .allowsHitTesting(!mode.isEnabled)

                            if index < group.count - 1 {
                                Divider().padding(.leading, 28)
                            }
                        }
                    }
                    Divider()
                }

                Button {
                    addRule(for: trigger)
                } label: {
                    Label("Add rule for \(trigger.displayName(customs: settings.settings.customTriggers))",
                          systemImage: "plus.circle.fill")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .disabled(mode.isEnabled || customTriggerHasNoModifiers(customId))
                .help(buttonHelpText(modeEnabled: mode.isEnabled, customId: customId, trigger: trigger))
            }
        }
    }

    private func builtInHeader(trigger: Trigger, ruleCount: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: trigger.symbolName)
                .foregroundStyle(.secondary)
            Text(trigger.displayName)
                .font(.headline)
            Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func customTriggerHeader(customId: UUID, ruleCount: Int) -> some View {
        let binding = customTriggerBinding(id: customId)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("Trigger name", text: binding.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    settings.removeCustomTrigger(id: customId)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.red.opacity(0.10)))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete this custom trigger and all its rules")
            }

            HStack(spacing: 10) {
                Text("Combo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)
                CompactModifierTogglesView(modifiers: binding.modifiers)
                Spacer()
            }

            if (settings.customTrigger(id: customId)?.modifiers.isEmpty ?? true) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Pick at least one modifier so the combo can fire.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var addCustomTriggerButton: some View {
        Button {
            settings.addCustomTrigger()
        } label: {
            Label("Add custom modifier combo", systemImage: "plus.rectangle.on.rectangle")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help("Define your own modifier-key combo (e.g. ⌃⌥) as a layer trigger")
    }

    private func modeBanner(trigger: Trigger) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            Text("\(trigger.displayName) is currently in Modifier Mode. Rules below are paused. Disable Modifier Mode to re-enable them.")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
    }

    private func addRule(for trigger: Trigger) {
        let key = store.firstUnusedInputKey(for: trigger)
        let new = Rule(
            trigger: trigger,
            inputKeys: [key],
            outputModifiers: [],
            outputKey: KeyCodes.unset,
            isEnabled: true
        )
        store.add(new)
        newlyAddedRuleId = new.id
    }

    private func customTriggerHasNoModifiers(_ customId: UUID?) -> Bool {
        guard let customId else { return false }
        return settings.customTrigger(id: customId)?.modifiers.isEmpty ?? true
    }

    private func buttonHelpText(modeEnabled: Bool, customId: UUID?, trigger: Trigger) -> String {
        if modeEnabled {
            return "Disable Modifier Mode for \(trigger.displayName) to add rules."
        }
        if customTriggerHasNoModifiers(customId) {
            return "Pick at least one modifier for this combo before adding rules."
        }
        return "Add a new \(trigger.displayName(customs: settings.settings.customTriggers)) rule"
    }

    /// Bindings for the inline name + modifier-mask editing on a custom-trigger card.
    private struct CustomTriggerBinding {
        let name: Binding<String>
        let modifiers: Binding<ModifierMask>
    }

    private func customTriggerBinding(id: UUID) -> CustomTriggerBinding {
        let name = Binding<String>(
            get: { settings.customTrigger(id: id)?.name ?? "" },
            set: { newValue in
                guard var ct = settings.customTrigger(id: id) else { return }
                ct.name = newValue
                settings.updateCustomTrigger(ct)
            }
        )
        let modifiers = Binding<ModifierMask>(
            get: { settings.customTrigger(id: id)?.modifiers ?? [] },
            set: { newValue in
                guard var ct = settings.customTrigger(id: id) else { return }
                ct.modifiers = newValue
                settings.updateCustomTrigger(ct)
            }
        )
        return CustomTriggerBinding(name: name, modifiers: modifiers)
    }
}
