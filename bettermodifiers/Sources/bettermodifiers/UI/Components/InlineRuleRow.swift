import AppKit
import SwiftUI

/// A single rule rendered as an inline-editable row inside `RulesView`.
///
/// Tapping the input/output key chip puts that chip into "Press a key…" mode and the
/// next non-modifier key press commits the change directly via `RulesStore.update`.
/// Modifier chips toggle the output mask in place. There is no editor sheet anymore.
///
/// A small `+` button after the first input key promotes the rule to a 2-key
/// sequence (e.g. `Tab + W + W -> ...`); the engine waits ~250 ms for the
/// second key when a sequence rule shares the prefix with a 1-key rule.
struct InlineRuleRow: View {
    @ObservedObject var store: RulesStore
    let rule: Rule
    /// When non-nil and matches `rule.id`, auto-start input recording on appear.
    var autoRecordOnAppearForId: UUID?
    /// Cleared after the auto-record has been consumed.
    var onAutoRecordConsumed: () -> Void = {}

    @State private var recording: RecordingTarget?
    @State private var monitor: Any?
    @State private var isHovering = false
    /// True while we're auto-recording a freshly added rule (input then output).
    @State private var autoChainActive = false

    private enum RecordingTarget: Equatable {
        case input(index: Int)
        case output
    }

    var body: some View {
        HStack(spacing: 14) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { store.setEnabled($0, for: rule.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(rule.isEnabled ? "Disable rule" : "Enable rule")

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                KeyChip(label: rule.trigger.chipLabel, symbol: rule.trigger.symbolName, emphasized: true)
                    .help(rule.trigger.displayName)
                    .layoutPriority(2)
                Text("+")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)

                keyChipButton(
                    isRecording: recording == .input(index: 0),
                    keyCode: rule.inputKeys.first ?? KeyCodes.unset,
                    onTap: { startRecording(.input(index: 0)) }
                )

                if rule.inputKeys.count >= 2 {
                    Text("+")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                    keyChipButton(
                        isRecording: recording == .input(index: 1),
                        keyCode: rule.inputKeys[1],
                        onTap: { startRecording(.input(index: 1)) }
                    )
                    Button {
                        removeSecondInputKey()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the second input key (revert to a 1-key rule)")
                } else {
                    Button {
                        addSecondInputKey()
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add a second input key for a double-tap-style sequence rule")
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                CompactModifierTogglesView(
                    modifiers: Binding(
                        get: { rule.outputModifiers },
                        set: { newMask in
                            var copy = rule
                            copy.outputModifiers = newMask
                            store.update(copy)
                        }
                    )
                )
                .padding(.trailing, 4)

                keyChipButton(
                    isRecording: recording == .output,
                    keyCode: rule.outputKey,
                    onTap: { startRecording(.output) }
                )
            }
            .opacity(rule.isEnabled ? 1.0 : 0.55)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            Spacer(minLength: 0)

            Button {
                stopRecording()
                _ = store.duplicate(id: rule.id)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Color.primary.opacity(isHovering ? 0.10 : 0.06))
                    )
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Duplicate rule")

            Button(role: .destructive) {
                stopRecording()
                store.remove(id: rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Color.red.opacity(isHovering ? 0.18 : 0.10))
                    )
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete rule")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onAppear {
            if autoRecordOnAppearForId == rule.id {
                autoChainActive = true
                onAutoRecordConsumed()
                startRecording(.input(index: 0))
            }
        }
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private func keyChipButton(isRecording: Bool, keyCode: UInt16, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            if isRecording {
                Text("Press a key…")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
            } else {
                KeyChip(label: KeyCodes.label(for: keyCode))
            }
        }
        .buttonStyle(.plain)
    }

    /// Reads the freshest copy of this row's rule from the store. Closures
    /// captured by `NSEvent.addLocalMonitorForEvents` (and by dispatch-after
    /// blocks) see a stale `self.rule`, so any code path that mutates and
    /// writes back must start from this value rather than the captured one.
    private func currentRule() -> Rule? {
        store.rules.first(where: { $0.id == rule.id })
    }

    private func addSecondInputKey() {
        guard var copy = currentRule() else { return }
        let placeholder = copy.inputKeys.first ?? KeyCodes.unset
        copy.inputKeys = [placeholder, KeyCodes.unset]
        store.update(copy)
        // Roll directly into recording the new (second) input key.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            startRecording(.input(index: 1))
        }
    }

    private func removeSecondInputKey() {
        stopRecording()
        guard var copy = currentRule(), let first = copy.inputKeys.first else { return }
        copy.inputKeys = [first]
        store.update(copy)
    }

    private func startRecording(_ target: RecordingTarget) {
        stopRecording()
        recording = target
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event: event, target: target)
            return nil
        }
    }

    private func stopRecording() {
        recording = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(event: NSEvent, target: RecordingTarget) {
        let code = UInt16(event.keyCode)
        // Escape cancels recording (and the auto chain) without saving further.
        if code == 53 {
            autoChainActive = false
            stopRecording()
            return
        }
        guard !KeyCodes.isModifier(code) else { return }
        // Always read the freshest rule from the store. The captured
        // `self.rule` may be stale: an auto-chained recording (e.g. input -> output)
        // installs a NEW local monitor whose closure captures `self` *before* the
        // first edit's re-render landed, so committing `var copy = rule` here would
        // overwrite the just-recorded input key with the original value.
        guard var copy = currentRule() else {
            stopRecording()
            return
        }
        switch target {
        case .input(let index):
            var keys = copy.inputKeys
            // Resize defensively in case the array is shorter than expected (older
            // persisted rules can be 1-element when this branch runs for index 1).
            while keys.count <= index { keys.append(KeyCodes.unset) }
            keys[index] = code
            copy.inputKeys = keys
        case .output:
            copy.outputKey = code
        }
        store.update(copy)
        stopRecording()

        // For freshly added rules: after the input is set, immediately roll into
        // recording the output so the user is never left with a placeholder output.
        if autoChainActive, case .input = target {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                startRecording(.output)
            }
        } else if autoChainActive, target == .output {
            autoChainActive = false
        }
    }
}

/// Modifier picker tailored for inline rule rows. Each chip is large enough to read at
/// a glance and has a caption underneath so the user does not need to memorise the symbols.
struct CompactModifierTogglesView: View {
    @Binding var modifiers: ModifierMask

    var body: some View {
        HStack(spacing: 10) {
            chip(.control, "⌃", "Control")
            chip(.option,  "⌥", "Option")
            chip(.shift,   "⇧", "Shift")
            chip(.command, "⌘", "Command")
        }
    }

    private func chip(_ modifier: ModifierMask, _ symbol: String, _ name: String) -> some View {
        let isOn = modifiers.contains(modifier)
        return Button {
            if isOn { modifiers.remove(modifier) } else { modifiers.insert(modifier) }
        } label: {
            VStack(spacing: 1) {
                Text(symbol)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(name)
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
        .help("\(name) (\(symbol))")
    }
}
