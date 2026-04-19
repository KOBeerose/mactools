import SwiftUI

struct MainWindow: View {
    @ObservedObject var store: RulesStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var updateController: UpdateController
    @ObservedObject var sidebarVisibility: SidebarVisibility

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
        let columnBinding = Binding<NavigationSplitViewVisibility>(
            get: { sidebarVisibility.columnVisibility },
            set: { newValue in
                sidebarVisibility.isVisible = (newValue != .detailOnly)
            }
        )

        return NavigationSplitView(columnVisibility: columnBinding) {
            List(Section.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
            // NavigationSplitView injects an auto sidebar toggle into BOTH the
            // sidebar column's toolbar and the detail column's toolbar. Removing
            // it on only one column leaves the other duplicate visible.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .frame(minWidth: 660, minHeight: 480)
                .navigationTitle("BetterModifiers")
                // `.toolbar(removing: .sidebarToggle)` only takes effect when
                // applied to a view INSIDE a NavigationSplitView column - applying
                // it to the split view itself is silently ignored, which is why
                // the trailing toggle kept reappearing. Same for the custom
                // ToolbarItem: it has to be declared on a column view so SwiftUI
                // attaches it to that column's toolbar set.
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            sidebarVisibility.toggle()
                        } label: {
                            Image(systemName: "sidebar.leading")
                        }
                        .help("Toggle Sidebar")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 540)
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

