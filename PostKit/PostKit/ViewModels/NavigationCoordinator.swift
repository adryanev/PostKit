import SwiftUI

@Observable
final class NavigationCoordinator {
    // MARK: - Pending State

    var pendingSelection: SidebarSelection?
    var pendingAction: CommandPaletteAction?

    // MARK: - Selection

    /// Requests navigation to the given sidebar item and activates the app.
    func selectItem(_ selection: SidebarSelection) {
        pendingSelection = selection
        NSApp.activate()
    }

    /// Requests execution of a command palette action.
    func performAction(_ action: CommandPaletteAction) {
        pendingAction = action
    }

    /// Consumes and returns the pending selection, resetting it to nil.
    func consumeSelection() -> SidebarSelection? {
        defer { pendingSelection = nil }
        return pendingSelection
    }

    /// Consumes and returns the pending action, resetting it to nil.
    func consumeAction() -> CommandPaletteAction? {
        defer { pendingAction = nil }
        return pendingAction
    }
}
