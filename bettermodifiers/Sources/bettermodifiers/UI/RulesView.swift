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
            Spacer()
            ruleCountAndClearAll(trigger: trigger, ruleCount: ruleCount)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Right-aligned rule count + "delete all rules" button used on every
    /// trigger card. For built-in cards this is the only delete affordance
    /// (the trigger itself is non-deletable); for custom cards it sits next
    /// to the per-trigger trash so the user can clear the rules without
    /// destroying the trigger definition.
    @ViewBuilder
    private func ruleCountAndClearAll(trigger: Trigger, ruleCount: Int) -> some View {
        Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button(role: .destructive) {
            pendingDelete = .clearRules(trigger)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.red.opacity(ruleCount == 0 ? 0.04 : 0.10)))
                .foregroundStyle(ruleCount == 0 ? Color.red.opacity(0.4) : .red)
        }
        .buttonStyle(.plain)
        .disabled(ruleCount == 0)
        .help(ruleCount == 0 ? "No rules to delete" : "Delete all \(ruleCount) rule\(ruleCount == 1 ? "" : "s") under this trigger")
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
                Spacer(minLength: 8)
                Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    pendingDelete = .deleteCustom(customId)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.red.opacity(0.10)))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete this custom trigger and all its \(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
            }

            if settings.customTrigger(id: customId)?.isEmpty ?? true {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Pick at least one qualifier (modifier, Caps Lock, or Space + a modifier) so the combo can fire.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        return settings.customTrigger(id: customId)?.isEmpty ?? true
    }

    private func buttonHelpText(modeEnabled: Bool, customId: UUID?, trigger: Trigger) -> String {
        if modeEnabled {
            return "Disable Modifier Mode for \(trigger.displayName) to add rules."
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
