import SwiftUI

/// Top of the General page: answers "is it working, and if not, why?" with
/// the fix one click away.
struct EngineHealthStrip: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showFix = false

    var body: some View {
        let content = Content(health: viewModel.health)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: content.symbol)
                    .font(.title2)
                    .foregroundStyle(content.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.callout.weight(.semibold))
                    Text(content.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                actionButton
            }

            if !content.fixSteps.isEmpty {
                DisclosureGroup("How to fix", isExpanded: $showFix) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(content.fixSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(step)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.callout)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.leading, 4)
                }
                .font(.callout)
                .padding(.leading, 38)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(content.tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(content.tint.opacity(0.25), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.health {
        case .running, .tapFailed, .tapNotReceiving:
            Button("Restart Engine") { viewModel.restartEngine() }
                .controlSize(.small)
        case .disabled:
            Button("Turn On") { viewModel.setEnabled(true) }
                .controlSize(.small)
        case .missingPermission:
            Button("Open Settings") { viewModel.openAccessibilitySettings() }
                .controlSize(.small)
        case .secureInput(let holder, let blocked):
            if blocked, let holder, let name = holder.appName {
                Button("Show \(name)") { holder.activate() }
                    .controlSize(.small)
            }
        }
    }

    private struct Content {
        let symbol: String
        let tint: Color
        let title: String
        let detail: String
        var fixSteps: [String] = []

        init(health: EngineHealth) {
            switch health {
            case .running:
                symbol = "checkmark.circle.fill"
                tint = .green
                title = "Running"
                detail = "Watching for your triggers. Hold one and press a mapped key to see it below."
            case .disabled:
                symbol = "pause.circle.fill"
                tint = .secondary
                title = "BetterModifiers is off"
                detail = "Keys pass through untouched until you turn it back on."
            case .missingPermission:
                symbol = "exclamationmark.triangle.fill"
                tint = .orange
                title = "Accessibility access needed"
                detail = "BetterModifiers can't see keystrokes until it's allowed in Privacy & Security → Accessibility."
                fixSteps = [
                    "Click Open Settings and turn BetterModifiers on in the Accessibility list.",
                    "If it's already on, remove it with the minus button and add it back. Every rebuild changes the app's signature.",
                ]
            case .tapFailed:
                symbol = "xmark.octagon.fill"
                tint = .red
                title = "Couldn't start the keyboard engine"
                detail = "macOS refused to create the event tap."
                fixSteps = [
                    "Click Restart Engine.",
                    "If it keeps failing, re-add BetterModifiers in Privacy & Security → Accessibility.",
                ]
            case .tapNotReceiving:
                symbol = "exclamationmark.triangle.fill"
                tint = .orange
                title = "Not receiving keystrokes"
                detail = "Usually a stale Accessibility grant after a rebuild."
                fixSteps = [
                    "Open Privacy & Security → Accessibility.",
                    "Remove BetterModifiers with the minus button, add it back, then click Restart Engine.",
                ]
            case .secureInput(let holder, let blocked):
                symbol = "lock.fill"
                if !blocked {
                    tint = .blue
                    title = "Paused in a password field"
                    detail = "macOS hides keystrokes from other apps while a secure field is focused. BetterModifiers resumes when you leave it."
                } else {
                    let who = holder.map { h in h.appName.map { "\($0) (PID \(h.pid))" } ?? "PID \(h.pid)" }
                    let app = holder?.appName ?? "the app holding it"
                    tint = .orange
                    title = "Keyboard input blocked by Secure Input"
                    detail = "Held by \(who ?? "another app"). No key remapper can see keystrokes until it's released."
                    fixSteps = [
                        "Switch to \(app) and finish or cancel any password prompt (sudo, ssh, a login dialog).",
                        "In Terminal or iTerm, turn off Secure Keyboard Entry in the app menu.",
                        "Still stuck? Quit \(app) with ⌘Q. Closing its windows isn't enough; the app keeps running.",
                    ]
                }
            }
        }
    }
}
