import SwiftUI

struct AboutView: View {
    @ObservedObject var updateController: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "About",
                subtitle: "Use Tab and Caps Lock as full modifier keys."
            )

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .foregroundStyle(.tint)
                        Text("BetterModifiers")
                            .font(.title2).fontWeight(.semibold)
                        Text("Version \(Self.versionString)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                    GroupBox("Updates") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Check for updates automatically", isOn: $updateController.automaticChecksEnabled)
                                .toggleStyle(.switch)
                                .disabled(!updateController.isConfigured)

                            HStack {
                                Button("Check Now") {
                                    updateController.checkForUpdates()
                                }
                                .disabled(!updateController.isConfigured)
                                Spacer()
                                Text(updateController.lastCheckText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            if let status = updateController.statusMessage {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("About")
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "100"
        return "\(short) (\(build))"
    }
}
