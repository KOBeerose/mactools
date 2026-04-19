import SwiftUI

struct RulesView: View {
    @ObservedObject var store: RulesStore
    @ObservedObject var settings: SettingsStore

    /// When set, the matching row will auto-start input-key recording on appear.
    @State private var newlyAddedRuleId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Rules",
                subtitle: "Tap any chip to change it: pick modifiers directly, or click an input/output key to record."
            )

            // GeometryReader gives us the visible detail-pane width so we can
            // pin each card to AT LEAST that width via `.frame(minWidth:)`.
            // Inside `ScrollView([.vertical, .horizontal])`, that means:
            //   - Wide window: card width == visible width (cards "stretch"
            //     left-to-right like General/Appearance), and the row's
            //     leading/trailing `Spacer`s center the chip cluster.
            //   - Narrow window: card grows beyond the visible width to fit
            //     the row's intrinsic chip-cluster width, and the outer scroll
            //     lets the user reach the right-most controls.
            GeometryReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 20) {
                        ForEach(Trigger.allCases) { trigger in
                            triggerCard(trigger: trigger)
                                .frame(minWidth: proxy.size.width - 48,
                                       alignment: .leading)
                        }
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

        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: trigger == .tab ? "arrow.right.to.line" : "capslock")
                        .foregroundStyle(.secondary)
                    Text(trigger.displayName)
                        .font(.headline)
                    Text("\(group.count) rule\(group.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if mode.isEnabled {
                    modeBanner(trigger: trigger)
                }

                if group.isEmpty {
                    Text("No \(trigger.displayName) rules yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 22)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { index, rule in
                            InlineRuleRow(
                                store: store,
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
                    Label("Add rule for \(trigger.displayName)", systemImage: "plus.circle.fill")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .disabled(mode.isEnabled)
                .help(mode.isEnabled
                      ? "Disable Modifier Mode for \(trigger.displayName) to add rules."
                      : "Add a new \(trigger.displayName) rule")
            }
        }
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
        // Output key starts as the "unset" sentinel so the chip reads "Key" instead of
        // a misleading literal (previously the input key was reused and showed "0").
        // Auto-recording rolls in immediately; if the user cancels with Esc it stays
        // visibly empty, which is the correct affordance.
        let new = Rule(
            trigger: trigger,
            inputKey: key,
            outputModifiers: [],
            outputKey: KeyCodes.unset,
            isEnabled: true
        )
        store.add(new)
        newlyAddedRuleId = new.id
    }
}
