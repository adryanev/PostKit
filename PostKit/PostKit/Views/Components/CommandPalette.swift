import SwiftUI

struct CommandPalette: View {
    @State private var viewModel: CommandPaletteViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var vimModeEnabled = false

    private let onDismiss: () -> Void

    init(viewModel: CommandPaletteViewModel, onDismiss: @escaping () -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.hide()
                    onDismiss()
                }

            // Command palette window
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))

                    TextField("Search requests, collections, actions...", text: $viewModel.searchText)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .onSubmit {
                            viewModel.executeSelectedItem()
                        }
                        .onChange(of: viewModel.searchText) { _, newValue in
                            viewModel.updateSearch(newValue)
                        }
                        .onKeyPress { keyPress in
                            handleKeyPress(keyPress)
                        }

                    if !viewModel.searchText.isEmpty {
                        Button(action: {
                            viewModel.searchText = ""
                            viewModel.updateSearch("")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }

                    // Vim mode indicator
                    if vimModeEnabled {
                        Text("VIM")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Results list
                if viewModel.filteredItems.isEmpty {
                    emptyStateView
                } else {
                    ScrollViewReader { proxy in
                        let flatItems = viewModel.filteredItems
                        List(selection: $viewModel.selectedIndex) {
                            ForEach(Array(viewModel.filteredGroupedItems.keys.sorted()), id: \.self) { category in
                                if let items = viewModel.filteredGroupedItems[category], !items.isEmpty {
                                    Section(header: categoryHeader(category)) {
                                        ForEach(Array(items.enumerated()), id: \.element) { _, item in
                                            let flatIndex = flatItems.firstIndex(where: { $0.displayTitle == item.displayTitle && $0.category == item.category }) ?? 0
                                            ItemRow(
                                                item: item,
                                                index: flatIndex,
                                                isSelected: viewModel.selectedIndex == flatIndex
                                            )
                                            .tag(flatIndex)
                                            .id(flatIndex)
                                            .onTapGesture {
                                                viewModel.selectedIndex = flatIndex
                                                viewModel.executeSelectedItem()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollDisabled(false)
                        .frame(maxHeight: 400)
                        .onChange(of: viewModel.selectedIndex) { _, newIndex in
                            guard let index = newIndex else { return }
                            proxy.scrollTo(index)
                        }
                    }
                }

                Divider()

                // Footer with keyboard shortcuts
                footerView
            }
            .frame(width: 560)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator, lineWidth: 1)
            )
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: viewModel.isVisible) { _, isVisible in
            if isVisible {
                isSearchFocused = true
            } else {
                onDismiss()
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No results found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(height: 200)
    }

    private func categoryHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private var footerView: some View {
        HStack(spacing: 20) {
            keyboardHint("↑↓", "or j/k to navigate")
            keyboardHint("↵", "to select")
            keyboardHint("Esc", "to close")

            Spacer()

            // Vim mode toggle
            Button(action: { vimModeEnabled.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: vimModeEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                    Text("Vim mode")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Vim-style navigation (j/k keys)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func keyboardHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                )

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Key Press Handling

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .escape:
            viewModel.hide()
            return .handled

        case .upArrow:
            if vimModeEnabled {
                // Vim mode: k moves up, arrow up moves up
                viewModel.selectPrevious()
                return .handled
            }
            return .ignored // Let List handle arrow navigation

        case .downArrow:
            if vimModeEnabled {
                viewModel.selectNext()
                return .handled
            }
            return .ignored

        case .return, .enter:
            viewModel.executeSelectedItem()
            return .handled

        case .tab:
            return .handled // Prevent tab from moving focus

        default:
            // Check for Vim-style key presses
            if vimModeEnabled, let char = keyPress.characters {
                let lowerChar = char.lowercased().first
                if ["j", "k"].contains(lowerChar) {
                    viewModel.handleVimKey(lowerChar!)
                    return .handled
                }
            }
            return .ignored
        }
    }
}

// MARK: - Item Row

struct ItemRow: View {
    let item: SearchableItem
    let index: Int
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? selectionColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        switch item.category {
        case "Requests":
            return .blue
        case "Collections":
            return .orange
        case "Folders":
            return .indigo
        case "Actions":
            return .green
        default:
            return .gray
        }
    }

    private var selectionColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.05)
    }
}

// MARK: - Preview

#Preview {
    CommandPalette(
        viewModel: CommandPaletteViewModel(modelContext: {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: HTTPRequest.self, configurations: [config])
            return container.mainContext
        }()),
        onDismiss: {}
    )
    .frame(width: 800, height: 600)
}
