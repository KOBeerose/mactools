import AppKit
import SwiftUI

/// Chip list of Modifier Mode exception keys with an inline "Add Key" recorder.
struct ExceptionKeysEditor: View {
    let keys: [UInt16]
    let onAdd: (UInt16) -> Void
    let onRemove: (UInt16) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(keys, id: \.self) { key in
                HStack(spacing: 4) {
                    KeyChip(label: KeyCodes.label(for: key))
                    Button {
                        onRemove(key)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(KeyCodes.label(for: key)) from the exceptions")
                }
            }

            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                if isRecording {
                    Text("Press a key…")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Add Key", systemImage: "plus")
                }
            }
            .controlSize(.small)
            .help("Record a key that should skip Modifier Mode. Esc cancels.")
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let code = UInt16(event.keyCode)
            if code == 53 { // Esc
                stopRecording()
            } else if !KeyCodes.isModifier(code) {
                onAdd(code)
                stopRecording()
            }
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
}
