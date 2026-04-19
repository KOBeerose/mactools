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
    /// True while we're auto-recording a freshly added rule (input then output).
    @State private var autoChainActive = false

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

            HStack(spacing: 12) {
                KeyChip(label: rule.trigger.chipLabel, symbol: rule.trigger.symbolName, emphasized: true)
                    .help(rule.trigger.displayName)
                    .layoutPriority(2)
                Text("+")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)

                keyChipButton(
                    isRecording: recording == .input,
                    keyCode: rule.inputKey,
                    onTap: { startRecording(.input) }
                )

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
            // No `.fixedSize(horizontal: true)` here: the chip cluster is inside the
            // Rules ScrollView, which silently absorbs intrinsic-width requests. Forcing
            // a horizontal fixed size made the row report a width larger than the detail
            // pane, which in turn made NavigationSplitView fall back to overlaying the
            // sidebar on top of the detail content. The window minimum width in
            // MainWindow already guarantees there is room for every chip.
            .frame(maxWidth: .infinity, alignment: .center)
            .layoutPriority(1)

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
        // Escape cancels recording (and the auto chain) without saving further.
        if code == 53 {
            autoChainActive = false
            stopRecording()
            return
        }
        guard !KeyCodes.isModifier(code) else { return }
        var copy = rule
        switch target {
        case .input:  copy.inputKey = code
        case .output: copy.outputKey = code
        }
        store.update(copy)
        stopRecording()

        // For freshly added rules: after the input is set, immediately roll into
        // recording the output so the user is never left with a placeholder output.
        if autoChainActive, target == .input {
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
