import AppKit
import Combine
import SwiftUI

/// Source of truth for whether the sidebar is visible. Lives outside the SwiftUI
/// view tree so the AppKit toolbar item can flip it from a `@objc` action while the
/// SwiftUI `NavigationSplitView` keeps observing it as `@Published` state.
@MainActor
final class SidebarVisibility: ObservableObject {
    @Published var isVisible: Bool = true

    func toggle() {
        // Animate so NavigationSplitView slides the sidebar in/out instead of
        // snapping. The animation is driven by the @Published change being applied
        // inside a withAnimation transaction; SwiftUI then animates the
        // columnVisibility binding update.
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible.toggle()
        }
    }

    var columnVisibility: NavigationSplitViewVisibility {
        isVisible ? .all : .detailOnly
    }
}
