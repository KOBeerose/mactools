import SwiftUI

struct RulesView: View {
    @ObservedObject var store: RulesStore
    @ObservedObject var settings: SettingsStore

    /// When set, the matching row will auto-start input-key recording on appear.
    @State private var newlyAddedRuleId: UUID?

    /// Pending destructive action awaiting user confirmation.
    @State private var pendingDelete: PendingDelete?

    private enum PendingDelete: Equatable {
        case clearRules(Trigger)
        case deleteCustom(UUID)
    }

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

            // Plain vertical ScrollView with cards stretched to fill available
            // width. We previously used a GeometryReader + horizontal ScrollView
            // to allow chip clusters to overflow on narrow windows; the side
            // effects were a permanently-visible horizontal scrollbar and a
            // very stuttery sidebar-toggle animation (each frame rebuilt the
            // whole layout against the changing proxy width).
            //
            // `LazyVStack` here is specifically about the sidebar-toggle
            // smoothness: with N built-in cards and M custom cards, each
            // containing many rule rows, the eager `VStack` re-laid out every
            // row on every animation frame. Lazy materialisation keeps the
            // animation frames cheap because rows below the fold don't get
            // re-laid out during the sidebar transition.
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(allTriggers) { trigger in
                        triggerCard(trigger: trigger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    addCustomTriggerButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
        }
        .navigationTitle("Rules")
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            actions: {
                Button(confirmationActionLabel, role: .destructive) {
                    performPendingDelete()
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            },
            message: {
                if let message = confirmationMessage {
                    Text(message)
                }
            }
        )
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var confirmationTitle: String {
        switch pendingDelete {
        case .clearRules(let t):
            let name = t.displayName(customs: settings.settings.customTriggers)
            let count = store.rules.filter { $0.trigger == t }.count
            return "Delete \(count) rule\(count == 1 ? "" : "s") for \(name)?"
        case .deleteCustom(let id):
            let name = settings.customTrigger(id: id)?.resolvedName ?? "this custom trigger"
            return "Delete \(name)?"
        case nil:
            return ""
        }
    }

    private var confirmationMessage: String? {
        switch pendingDelete {
        case .clearRules:
            return "This removes every rule under this trigger. The trigger itself stays."
        case .deleteCustom(let id):
            let count = store.rules.filter {
                if case .custom(let cid) = $0.trigger { return cid == id }
                return false
            }.count
            if count == 0 {
                return "The custom trigger has no rules; this just removes the trigger definition."
            }
            return "This also deletes the \(count) rule\(count == 1 ? "" : "s") tied to it."
        case nil:
            return nil
        }
    }

    private var confirmationActionLabel: String {
        switch pendingDelete {
        case .clearRules:    return "Delete rules"
        case .deleteCustom:  return "Delete trigger"
        case nil:            return "Delete"
        }
    }

    private func performPendingDelete() {
        switch pendingDelete {
        case .clearRules(let t):
            store.removeAll(for: t)
        case .deleteCustom(let id):
            settings.removeCustomTrigger(id: id)
        case nil:
            break
        }
        pendingDelete = nil
    }

    private func triggerCard(trigger: Trigger) -> some View {
        let group = store.rules.filter { $0.trigger == trigger }
        let mode = settings.modeConfig(for: trigger)
        let paused = settings.isPaused(trigger)
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
                    modeBanner(trigger: trigger, mode: mode)
                }

                if group.isEmpty {
                    emptyState(trigger: trigger, customId: customId)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { index, rule in
                            let dimmed = isDimmed(rule, mode: mode, paused: paused)
                            InlineRuleRow(
                                store: store,
                                settings: settings,
                                rule: rule,
                                autoRecordOnAppearForId: newlyAddedRuleId,
                                onAutoRecordConsumed: { newlyAddedRuleId = nil }
                            )
                            .opacity(dimmed ? 0.4 : 1)
                            .allowsHitTesting(!dimmed)

                            if index < group.count - 1 {
                                Divider().padding(.leading, 28)
                            }
                        }
                    }
                    Divider()

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
                    .disabled(!canAddRule(trigger: trigger, customId: customId))
                    .help(buttonHelpText(trigger: trigger, customId: customId))
                }
            }
        }
    }

    /// Rows are dimmed while the card is paused, or while Modifier Mode owns the
    /// key (every key except `useRules` exceptions).
    private func isDimmed(_ rule: Rule, mode: ModifierModeConfig, paused: Bool) -> Bool {
        if paused { return true }
        guard mode.isEnabled else { return false }
        return !(mode.exceptionBehavior == .useRules && mode.exceptions.contains(rule.inputKey))
    }

    private func canAddRule(trigger: Trigger, customId: UUID?) -> Bool {
        let mode = settings.modeConfig(for: trigger)
        let modeAllowsRules = !mode.isEnabled
            || (mode.exceptionBehavior == .useRules && !mode.exceptions.isEmpty)
        return modeAllowsRules && !settings.isPaused(trigger) && !customTriggerHasNoModifiers(customId)
    }

    private func builtInHeader(trigger: Trigger, ruleCount: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: trigger.symbolName)
                .foregroundStyle(.secondary)
            Text(trigger.displayName)
                .font(.headline)
            pausedControls(trigger: trigger)
            Spacer()
            headerSummary(trigger: trigger, ruleCount: ruleCount)
            cardMenu(trigger: trigger, ruleCount: ruleCount, customId: nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contextMenu { cardMenuItems(trigger: trigger, ruleCount: ruleCount, customId: nil) }
    }

    /// "Paused" badge plus a one-click Resume, shown only while paused.
    @ViewBuilder
    private func pausedControls(trigger: Trigger) -> some View {
        if settings.isPaused(trigger) {
            Text("Paused")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            Button {
                settings.setPaused(false, for: trigger)
            } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .controlSize(.small)
        }
    }

    /// Rule count, plus an orange issue count when rules are duplicated or incomplete.
    @ViewBuilder
    private func headerSummary(trigger: Trigger, ruleCount: Int) -> some View {
        let issues = store.issueCount(for: trigger)
        HStack(spacing: 4) {
            Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            if issues > 0 {
                Text("· \(issues) issue\(issues == 1 ? "" : "s")")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    /// The card's "⋯" menu. It replaces the header trash so bulk actions stay
    /// out of the way and don't look like the per-rule switches.
    private func cardMenu(trigger: Trigger, ruleCount: Int, customId: UUID?) -> some View {
        Menu {
            cardMenuItems(trigger: trigger, ruleCount: ruleCount, customId: customId)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pause, enable, disable or delete rules")
    }

    @ViewBuilder
    private func cardMenuItems(trigger: Trigger, ruleCount: Int, customId: UUID?) -> some View {
        if settings.isPaused(trigger) {
            Button("Resume Rules") { settings.setPaused(false, for: trigger) }
        } else {
            Button("Pause All Rules") { settings.setPaused(true, for: trigger) }
                .disabled(ruleCount == 0)
        }
        Button("Enable All Rules") { store.setEnabled(true, forAllIn: trigger) }
            .disabled(ruleCount == 0)
        Button("Disable All Rules") { store.setEnabled(false, forAllIn: trigger) }
            .disabled(ruleCount == 0)
        Divider()
        Button("Delete All Rules…", role: .destructive) { pendingDelete = .clearRules(trigger) }
            .disabled(ruleCount == 0)
        if let customId {
            Button("Delete Trigger…", role: .destructive) { pendingDelete = .deleteCustom(customId) }
        }
    }

    /// One line on what the trigger does, one obvious next step, and presets.
    private func emptyState(trigger: Trigger, customId: UUID?) -> some View {
        let canAdd = canAddRule(trigger: trigger, customId: customId)
        return VStack(alignment: .leading, spacing: 10) {
            Text(emptyExplanation(for: trigger))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Add First Rule") { addRule(for: trigger) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Menu("Start from Preset") {
                    ForEach(RulePreset.all) { preset in
                        Button(preset.name) { store.addPreset(preset.rules, for: trigger) }
                    }
                }
                .controlSize(.small)
                .fixedSize()
            }
            .disabled(!canAdd)
            .help(canAdd ? "" : buttonHelpText(trigger: trigger, customId: customId))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyExplanation(for trigger: Trigger) -> String {
        switch trigger {
        case .tab:
            return "Hold Tab and press a key to send a shortcut. A plain tap still types a tab."
        case .capsLock:
            return "Hold Caps Lock and press a key to send a shortcut. A plain tap still toggles Caps Lock."
        case .shiftSpace:
            return "Hold Shift + Space and press a key to send a shortcut. Normal typing isn't affected."
        case .custom:
            let combo = trigger.chipLabel(customs: settings.settings.customTriggers)
            return "Hold \(combo) and press a key to send a shortcut."
        }
    }

    private func customTriggerHeader(customId: UUID, ruleCount: Int) -> some View {
        let binding = customTriggerBinding(id: customId)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                AutoSizingTextField(placeholder: "Trigger name", text: binding.name,
                                    minWidth: 110, maxWidth: 260)
                CompactModifierTogglesView(modifiers: binding.modifiers)
                CapsToggleChip(isOn: binding.requiresCapsLock)
                TabToggleChip(isOn: binding.requiresTab)
                SpaceToggleChip(isOn: binding.requiresSpace)
                pausedControls(trigger: .custom(customId))
                Spacer(minLength: 8)
                headerSummary(trigger: .custom(customId), ruleCount: ruleCount)
                cardMenu(trigger: .custom(customId), ruleCount: ruleCount, customId: customId)
            }

            if settings.customTrigger(id: customId)?.isEmpty ?? true {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Pick at least one qualifier so the combo can fire. Try:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    qualifierPreset("⌃⌥", customId: customId, modifiers: [.control, .option])
                    qualifierPreset("⇪ + ⌥", customId: customId, modifiers: [.option], caps: true)
                    qualifierPreset("⇧⌃⌥", customId: customId, modifiers: [.shift, .control, .option])
                }
            }

            systemShortcutWarningRow(customId: customId)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    /// Inline collision-warning under a custom-combo header. Renders only when
    /// the combo matches a known macOS / app shortcut pattern AND the user has
    /// not dismissed it for this trigger. The dismiss button persists the user
    /// choice so the warning never re-appears for that trigger id.
    @ViewBuilder
    private func systemShortcutWarningRow(customId: UUID) -> some View {
        let trigger = Trigger.custom(customId)
        if let ct = settings.customTrigger(id: customId),
           let warning = ct.systemShortcutWarning,
           !settings.isWarningDismissed(for: trigger) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    settings.dismissWarning(for: trigger)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Don't show this warning again for this trigger")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )
        }
    }

    /// One-click qualifier for a custom trigger that has none yet.
    private func qualifierPreset(_ label: String, customId: UUID, modifiers: ModifierMask, caps: Bool = false) -> some View {
        Button(label) {
            guard var ct = settings.customTrigger(id: customId) else { return }
            ct.modifiers = modifiers
            ct.requiresCapsLock = caps
            settings.updateCustomTrigger(ct)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
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

    private func modeBanner(trigger: Trigger, mode: ModifierModeConfig) -> some View {
        let name = trigger.displayName(customs: settings.settings.customTriggers)
        let ruleExceptions = mode.exceptionBehavior == .useRules ? mode.exceptions : []
        let text = ruleExceptions.isEmpty
            ? "\(name) is currently in Modifier Mode. Rules below are paused. Disable Modifier Mode to re-enable them."
            : "\(name) is in Modifier Mode. Only rules for the excepted keys (\(ruleExceptions.map { KeyCodes.label(for: $0) }.joined(separator: ", "))) still fire."
        return HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            Text(text)
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
        return settings.customTrigger(id: customId)?.isEmpty ?? true
    }

    private func buttonHelpText(trigger: Trigger, customId: UUID?) -> String {
        if settings.isPaused(trigger) {
            return "Resume this card's rules to add more."
        }
        if settings.modeConfig(for: trigger).isEnabled {
            return "Disable Modifier Mode for \(trigger.displayName(customs: settings.settings.customTriggers)) to add rules, or add an exception that uses rules."
        }
        if customTriggerHasNoModifiers(customId) {
            return "Pick at least one modifier (or enable Caps Lock) for this combo before adding rules."
        }
        return "Add a new \(trigger.displayName(customs: settings.settings.customTriggers)) rule"
    }

    /// Bindings for the inline name + modifier-mask editing on a custom-trigger card.
    private struct CustomTriggerBinding {
        let name: Binding<String>
        let modifiers: Binding<ModifierMask>
        let requiresCapsLock: Binding<Bool>
        let requiresSpace: Binding<Bool>
        let requiresTab: Binding<Bool>
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
        let requiresCaps = Binding<Bool>(
            get: { settings.customTrigger(id: id)?.requiresCapsLock ?? false },
            set: { newValue in
                guard var ct = settings.customTrigger(id: id) else { return }
                ct.requiresCapsLock = newValue
                settings.updateCustomTrigger(ct)
            }
        )
        let requiresSpace = Binding<Bool>(
            get: { settings.customTrigger(id: id)?.requiresSpace ?? false },
            set: { newValue in
                guard var ct = settings.customTrigger(id: id) else { return }
                ct.requiresSpace = newValue
                settings.updateCustomTrigger(ct)
            }
        )
        let requiresTab = Binding<Bool>(
            get: { settings.customTrigger(id: id)?.requiresTab ?? false },
            set: { newValue in
                guard var ct = settings.customTrigger(id: id) else { return }
                ct.requiresTab = newValue
                settings.updateCustomTrigger(ct)
            }
        )
        return CustomTriggerBinding(
            name: name,
            modifiers: modifiers,
            requiresCapsLock: requiresCaps,
            requiresSpace: requiresSpace,
            requiresTab: requiresTab
        )
    }
}

/// Toggle pill matching `CompactModifierTogglesView`'s chip style, used to add
/// Caps Lock as an extra qualifier on a custom modifier-combo trigger.
struct CapsToggleChip: View {
    @Binding var isOn: Bool

    var body: some View {
        QualifierToggleChip(symbol: "⇪", caption: "Caps", isOn: $isOn,
                            help: "Require Caps Lock to be held for this combo")
    }
}

/// Same chip style as Caps, used to add the spacebar as an extra qualifier.
/// Space alone is intentionally not a valid trigger - the editor still requires
/// at least one modifier (or Caps Lock) on top, so plain typing is preserved
/// via the AHK-style "forward the space, retro-actively backspace it once a
/// qualifier joins" trick built into the engine.
struct SpaceToggleChip: View {
    @Binding var isOn: Bool

    var body: some View {
        QualifierToggleChip(symbol: "␣", caption: "Space", isOn: $isOn,
                            help: "Require the spacebar to be held for this combo")
    }
}

/// Same chip style, for adding Tab as an extra qualifier. Tab alone is the
/// built-in Tab trigger, so the editor requires at least one modifier
/// alongside `Tab` (`isEmpty` rejects `Tab` + nothing). Defining a `Tab + ⌘`
/// custom combo overrides the macOS app switcher; the warning row spells
/// that out before the user commits to it.
struct TabToggleChip: View {
    @Binding var isOn: Bool

    var body: some View {
        QualifierToggleChip(symbol: "⇥", caption: "Tab", isOn: $isOn,
                            help: "Require the Tab key to be held for this combo (intercepts Cmd+Tab if combined with ⌘)")
    }
}

private struct QualifierToggleChip: View {
    let symbol: String
    let caption: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 1) {
                Text(symbol)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isOn ? Color.white.opacity(0.9) : .secondary)
            }
            .frame(width: 50, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isOn ? 1 : 0.5)
            )
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
