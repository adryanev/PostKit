import SwiftUI

/// Central registry for keyboard shortcuts across the application.
enum KeyboardShortcuts {
    // MARK: - Global Shortcuts
    static let commandPalette = KeyEquivalent("k")
    static let sendRequest = KeyEquivalent(.return)
    static let cancelRequest = KeyEquivalent(".")
    static let duplicateRequest = KeyEquivalent("d")
    static let saveRequest = KeyEquivalent("s")
    static let newRequest = KeyEquivalent("n")
    static let newCollection = KeyEquivalent("N")
    static let focusSearch = KeyEquivalent("/")
    static let close = KeyEquivalent(.escape)

    // MARK: - Vim-Style Navigation (optional mode)
    enum VimMode {
        static let down = KeyEquivalent("j")
        static let up = KeyEquivalent("k")
        static let select = KeyEquivalent(.return)
        static let back = KeyEquivalent(.escape)
        static let search = KeyEquivalent("/")
    }

    // MARK: - Helper Properties
    static var commandModifiers: EventModifiers { .command }
    static var shiftModifiers: EventModifiers { [.command, .shift] }
    static var noModifiers: EventModifiers { [] }
}
