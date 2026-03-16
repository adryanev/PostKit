import SwiftUI

/// Preferences view for viewing and customizing keyboard shortcuts.
struct KeyboardShortcutView: View {
    @AppStorage("vimModeEnabled") private var vimModeEnabled = false
    @AppStorage("commandPaletteShortcut") private var commandPaletteKey = "k"

    private let shortcuts: [(String, String, String)] = [
        ("⌘K", "Command Palette", "Open the command palette for quick navigation"),
        ("⌘⏎", "Send Request", "Execute the current request"),
        ("⌘.", "Cancel Request", "Cancel the in-progress request"),
        ("⌘D", "Duplicate Request", "Duplicate the selected request"),
        ("⌘S", "Save Request", "Save the current request"),
        ("⌘N", "New Request", "Create a new request"),
        ("⇧⌘N", "New Collection", "Create a new collection"),
        ("/", "Focus Search", "Focus the search field"),
        ("Esc", "Close/Back", "Close dialog or go back")
    ]

    private let vimShortcuts: [(String, String, String)] = [
        ("J", "Move Down", "Navigate down in lists"),
        ("K", "Move Up", "Navigate up in lists"),
        ("↵", "Select", "Select the focused item"),
        ("/", "Search", "Focus the search field"),
        ("Esc", "Back", "Go back or close")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)

                // General shortcuts
                VStack(alignment: .leading, spacing: 12) {
                    Text("General Shortcuts")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    shortcutTable(shortcuts)
                }

                // Vim mode settings
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Vim Mode")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Toggle("Enable Vim-style navigation", isOn: $vimModeEnabled)
                    }
                    .padding(.vertical, 4)

                    if vimModeEnabled {
                        shortcutTable(vimShortcuts)
                    }

                    vimModeDescription
                }
            }
            .padding(20)
        }
    }

    private func shortcutTable(_ items: [(String, String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.0)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )

                    Text(item.1)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(item.2)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private var vimModeDescription: some View {
        Text("Vim mode enables J/K navigation in lists and the command palette. When enabled, arrow keys will also continue to work.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

#Preview {
    KeyboardShortcutView()
        .frame(width: 600, height: 500)
}
