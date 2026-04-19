import AppKit
import SwiftUI

/// Lightweight key recorder: captures a single non-modifier key press while in recording mode.
/// Modifiers are intentionally ignored (the editor uses ModifierTogglesView for explicit selection).
struct KeyRecorderView: View {
    @Binding var keyCode: UInt16?
    var placeholder: String = "Click to record"

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 6) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 140, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isRecording ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private var content: some View {
        if isRecording {
            Text("Press a key…")
                .foregroundStyle(.secondary)
                .italic()
        } else if let keyCode {
            KeyChip(label: KeyCodes.label(for: keyCode), emphasized: true)
        } else {
            Text(placeholder).foregroundStyle(.secondary)
        }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event: event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(event: NSEvent) {
        let code = UInt16(event.keyCode)
        guard !KeyCodes.isModifier(code) else { return }
        keyCode = code
        stopRecording()
    }
}
