import AppKit
import SwiftUI

/// A single rule rendered as an inline-editable row inside `RulesView`.
///
/// Tapping the input/output key chip puts that chip into "Press a key…" mode and the
/// next non-modifier key press commits the change directly via `RulesStore.update`.
/// Modifier chips toggle the output mask in place. There is no editor sheet anymore.
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

    private enum RecordingTarget {
        case input, output
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

            HStack(spacing: 8) {
                KeyChip(label: rule.trigger.displayName, emphasized: true)
                Text("+").foregroundStyle(.secondary)

                keyChipButton(
                    isRecording: recording == .input,
                    keyCode: rule.inputKey,
                    onTap: { startRecording(.input) }
                )

                Text("→").foregroundStyle(.secondary)

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

                keyChipButton(
                    isRecording: recording == .output,
                    keyCode: rule.outputKey,
                    onTap: { startRecording(.output) }
                )
            }
            .opacity(rule.isEnabled ? 1.0 : 0.55)

            Spacer(minLength: 0)

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
        .padding(.horizontal, 28)
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
                onAutoRecordConsumed()
                startRecording(.input)
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
        // Escape cancels recording without saving.
        if code == 53 { stopRecording(); return }
        guard !KeyCodes.isModifier(code) else { return }
        var copy = rule
        switch target {
        case .input:  copy.inputKey = code
        case .output: copy.outputKey = code
        }
        store.update(copy)
        stopRecording()
    }
}

/// Small modifier picker tailored for inline rule rows. Mirrors `ModifierTogglesView` but
/// is more compact (no captions) so multiple rows stay readable at standard window widths.
struct CompactModifierTogglesView: View {
    @Binding var modifiers: ModifierMask

    var body: some View {
        HStack(spacing: 4) {
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
            Text(symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isOn ? 1 : 0.5)
                )
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help("\(name) (\(symbol))")
    }
}
