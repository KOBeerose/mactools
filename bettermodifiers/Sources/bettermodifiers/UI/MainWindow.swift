import SwiftUI

struct MainWindow: View {
    @ObservedObject var store: RulesStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var updateController: UpdateController

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case modifierMode, rules, general, appearance, about
        var id: String { rawValue }

        var label: String {
            switch self {
            case .modifierMode: return "Modifier Mode"
            case .rules: return "Rules"
            case .general: return "General"
            case .appearance: return "Appearance"
            case .about: return "About"
            }
        }

        var systemImage: String {
            switch self {
            case .modifierMode: return "bolt.fill"
            case .rules: return "keyboard"
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selection: Section = .modifierMode

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            // Drop the translucent sidebar material so it blends into the main window
            // background instead of looking like a separate, brighter pane in light mode.
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            .hideSidebarToggleIfPossible()
        } detail: {
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Same single window-background colour everywhere. Forms inside the detail
                // views also opt out of their default scroll backgrounds (see below).
                .background(Color(nsColor: .windowBackgroundColor))
                .frame(minWidth: 600, minHeight: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder
    private func detail(for section: Section) -> some View {
        switch section {
        case .modifierMode: ModifierModeView(settings: settings)
        case .rules:        RulesView(store: store, settings: settings)
        case .general:      GeneralView(viewModel: viewModel)
        case .appearance:   AppearanceView(settings: settings)
        case .about:        AboutView(updateController: updateController)
        }
    }
}

private extension View {
    @ViewBuilder
    func hideSidebarToggleIfPossible() -> some View {
        if #available(macOS 14.4, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
