import SwiftUI

struct ModifierModeView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var rules: RulesStore

    @State private var pendingDeleteCustomId: UUID?

    /// Built-in triggers plus user-defined custom modifier-combo triggers, so
    /// the user can toggle Modifier Mode on any of them.
    private var allTriggers: [Trigger] {
        Trigger.builtIn + settings.settings.customTriggers.map { Trigger.custom($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Modifier Mode",
                subtitle: "Turn a trigger into a fixed modifier combo. While held, the next key is sent as the chosen modifiers + that key. When enabled, individual rules for that trigger are bypassed."
            )

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(allTriggers) { trigger in
                        card(for: trigger)
                    }

                    addCustomTriggerButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
        }
        .navigationTitle("Modifier Mode")
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            actions: {
                Button("Delete trigger", role: .destructive) {
                    if let id = pendingDeleteCustomId {
                        settings.removeCustomTrigger(id: id)
                    }
                    pendingDeleteCustomId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteCustomId = nil
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
            get: { pendingDeleteCustomId != nil },
            set: { if !$0 { pendingDeleteCustomId = nil } }
        )
    }

    private var confirmationTitle: String {
        guard let id = pendingDeleteCustomId else { return "" }
        let name = settings.customTrigger(id: id)?.resolvedName ?? "this custom trigger"
        return "Delete \(name)?"
    }

    private var confirmationMessage: String? {
        guard let id = pendingDeleteCustomId else { return nil }
        let count = rules.rules.filter {
            if case .custom(let cid) = $0.trigger { return cid == id }
            return false
        }.count
        if count == 0 {
            return "The custom trigger has no rules; this just removes the trigger definition."
        }
        return "This also deletes the \(count) rule\(count == 1 ? "" : "s") tied to it."
    }

    private func card(for trigger: Trigger) -> some View {
        let config = settings.modeConfig(for: trigger)
        let title = trigger.displayName(customs: settings.settings.customTriggers)
        let chip = trigger.chipLabel(customs: settings.settings.customTriggers)
        let customId: UUID? = {
            if case .custom(let id) = trigger { return id }
            return nil
        }()
        return GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if let customId {
                    customQualifierHeader(customId: customId, title: title)
                    Divider()
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.headline)
                            Text("Use \(title) as a fixed modifier combo")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                HStack {
                    Text("Modifier Mode")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.modeConfig(for: trigger).isEnabled },
                        set: { settings.setModeEnabled($0, for: trigger) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider()

                HStack(alignment: .center) {
                    Text("Modifiers")
                        .frame(width: 90, alignment: .leading)
                        .foregroundStyle(.secondary)
                    ModifierTogglesView(
                        modifiers: Binding(
                            get: { settings.modeConfig(for: trigger).modifiers },
                            set: { settings.setModeModifiers($0, for: trigger) }
                        ),
                        isEnabled: config.isEnabled
                    )
                    Spacer()
                }

                HStack(alignment: .center) {
                    Text("Preview")
                        .frame(width: 90, alignment: .leading)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        KeyChip(label: chip, symbol: trigger.symbolName, emphasized: true)
                        Text("+")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)
                        KeyChip(label: "Key")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        KeyComboView(modifiers: config.modifiers, keyLabel: "Key")
                    }
                    .opacity(config.isEnabled ? 1 : 0.5)
                    Spacer()
                }
            }
            .padding(8)
        }
    }

    /// Inline header for a custom-trigger card. Mirrors the qualifier editing
    /// affordances on the Rules tab so the user can manage a custom trigger's
    /// identity (modifiers, Caps, Space) and name from either tab. The trash
    /// button deletes the trigger and any rules associated with it.
    @ViewBuilder
    private func customQualifierHeader(customId: UUID, title: String) -> some View {
        let binding = customTriggerBinding(id: customId)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                AutoSizingTextField(placeholder: "Trigger name", text: binding.name,
                                    minWidth: 110, maxWidth: 240)
                CompactModifierTogglesView(modifiers: binding.modifiers)
                CapsToggleChip(isOn: binding.requiresCapsLock)
                TabToggleChip(isOn: binding.requiresTab)
                SpaceToggleChip(isOn: binding.requiresSpace)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    pendingDeleteCustomId = customId
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.red.opacity(0.10)))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete \(title) and any rules tied to it")
            }

            if let ct = settings.customTrigger(id: customId),
               let warning = ct.systemShortcutWarning,
               !settings.isWarningDismissed(for: .custom(customId)) {
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
                        settings.dismissWarning(for: .custom(customId))
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

    /// Bindings for inline editing of a custom trigger from the Modifier Mode tab.
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
