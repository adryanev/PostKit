import Foundation
import Observation
import SwiftData
import SwiftUI
import FactoryKit

@Observable
final class CommandPaletteViewModel {
    // MARK: - UI State

    var isVisible = false
    var searchText = ""
    var selectedIndex: Int? = 0
    var groupedItems: [String: [SearchableItem]] = [:]
    var allItems: [SearchableItem] = []

    // MARK: - Dependencies

    private let modelContext: ModelContext
    @ObservationIgnored @MainActor @Injected(\.navigationCoordinator) private var coordinator

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadSearchableItems()
    }

    // MARK: - Public Methods

    /// Shows the command palette and resets search state.
    func show() {
        isVisible = true
        searchText = ""
        selectedIndex = 0
        loadSearchableItems()
        recomputeFilteredItems()
    }

    /// Hides the command palette.
    func hide() {
        isVisible = false
        searchText = ""
        selectedIndex = 0
    }

    /// Toggles the command palette visibility.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Updates the search text and filters results.
    func updateSearch(_ text: String) {
        searchText = text
        recomputeFilteredItems()
        selectedIndex = filteredItems.isEmpty ? nil : 0
    }

    /// Executes the action for the currently selected item.
    func executeSelectedItem() {
        guard let index = selectedIndex,
              let item = filteredItem(at: index) else { return }
        item.action()
        hide()
    }

    /// Selects the next item in the filtered list.
    func selectNext() {
        guard !filteredItems.isEmpty else { return }
        if selectedIndex == nil {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex! + 1, filteredItems.count - 1)
        }
    }

    /// Selects the previous item in the filtered list.
    func selectPrevious() {
        guard !filteredItems.isEmpty else { return }
        if selectedIndex == nil {
            selectedIndex = 0
        } else {
            selectedIndex = max(selectedIndex! - 1, 0)
        }
    }

    /// Handles Vim-style key presses.
    func handleVimKey(_ key: Character) {
        switch key {
        case "j", KeyboardShortcuts.VimMode.down.character:
            selectNext()
        case "k", KeyboardShortcuts.VimMode.up.character:
            selectPrevious()
        case KeyboardShortcuts.VimMode.select.character:
            executeSelectedItem()
        case KeyboardShortcuts.VimMode.back.character:
            hide()
        case KeyboardShortcuts.VimMode.search.character:
            // Focus search - this would need to be handled by the view
            break
        default:
            break
        }
    }

    // MARK: - Cached Filtered Results

    /// All items flattened and filtered by search text.
    var filteredItems: [SearchableItem] = []

    /// Groups filtered items by category.
    var filteredGroupedItems: [String: [SearchableItem]] = [:]

    /// Lookup from "category:displayTitle" to flat index for O(1) row lookups.
    private var flatIndexLookup: [String: Int] = [:]

    /// Returns the flat index for a given item using the pre-built lookup.
    func flatIndex(for item: SearchableItem) -> Int {
        flatIndexLookup["\(item.category):\(item.displayTitle)"] ?? 0
    }

    private func recomputeFilteredItems() {
        if searchText.isEmpty {
            filteredItems = allItems
        } else {
            let searchLower = searchText.lowercased()
            filteredItems = allItems.filter { $0.searchText.lowercased().contains(searchLower) }
        }
        recomputeGroupedItems()
        rebuildFlatIndexLookup()
    }

    private func recomputeGroupedItems() {
        var grouped: [String: [SearchableItem]] = [:]
        for item in filteredItems {
            grouped[item.category, default: []].append(item)
        }
        filteredGroupedItems = grouped
    }

    private func rebuildFlatIndexLookup() {
        flatIndexLookup = [:]
        for (index, item) in filteredItems.enumerated() {
            let key = "\(item.category):\(item.displayTitle)"
            flatIndexLookup[key] = index
        }
    }

    /// Returns the item at the given index in the filtered list.
    func filteredItem(at index: Int) -> SearchableItem? {
        guard index >= 0 && index < filteredItems.count else { return nil }
        return filteredItems[index]
    }

    // MARK: - Private Methods

    /// Loads all searchable items from the model context.
    private func loadSearchableItems() {
        var items: [SearchableItem] = []

        // Load requests
        let requestDescriptor = FetchDescriptor<HTTPRequest>(
            sortBy: [SortDescriptor(\.name)]
        )
        if let requests = try? modelContext.fetch(requestDescriptor) {
            items.append(contentsOf: requests.map { request in
                RequestSearchableItem(request: request) { [weak self] request in
                    self?.selectRequest(request)
                }
            })
        }

        // Load collections
        let collectionDescriptor = FetchDescriptor<RequestCollection>(
            sortBy: [SortDescriptor(\.name)]
        )
        if let collections = try? modelContext.fetch(collectionDescriptor) {
            items.append(contentsOf: collections.map { collection in
                CollectionSearchableItem(collection: collection) { [weak self] collection in
                    self?.selectCollection(collection)
                }
            })
        }

        // Load folders
        let folderDescriptor = FetchDescriptor<Folder>(
            sortBy: [SortDescriptor(\.name)]
        )
        if let folders = try? modelContext.fetch(folderDescriptor) {
            items.append(contentsOf: folders.map { folder in
                FolderSearchableItem(
                    folder: folder,
                    collectionName: folder.collection?.name
                ) { [weak self] folder in
                    self?.selectFolder(folder)
                }
            })
        }

        // Add actions
        items.append(contentsOf: buildActions())

        allItems = items
        groupedItems = Dictionary(grouping: items) { $0.category }
        recomputeFilteredItems()
    }

    /// Builds the list of global actions available in the command palette.
    private func buildActions() -> [SearchableItem] {
        return [
            ActionSearchableItem(
                title: "New Request",
                subtitle: "Create a new HTTP request",
                icon: "plus.circle",
                category: "Actions"
            ) { [weak self] in
                self?.createNewRequest()
            },
            ActionSearchableItem(
                title: "New Collection",
                subtitle: "Create a new collection",
                icon: "folder.badge.plus",
                category: "Actions"
            ) { [weak self] in
                self?.createNewCollection()
            },
            ActionSearchableItem(
                title: "Import cURL Command",
                subtitle: "Paste a cURL command to import",
                icon: "terminal",
                category: "Actions"
            ) { [weak self] in
                self?.importCurlCommand()
            },
            ActionSearchableItem(
                title: "Import OpenAPI Spec",
                subtitle: "Import an OpenAPI specification",
                icon: "doc.text",
                category: "Actions"
            ) { [weak self] in
                self?.importOpenAPISpec()
            },
            ActionSearchableItem(
                title: "Import Postman Collection",
                subtitle: "Import a Postman collection",
                icon: "square.stack.3d.up",
                category: "Actions"
            ) { [weak self] in
                self?.importPostmanCollection()
            }
        ]
    }

    // MARK: - Selection Actions

    @MainActor
    private func selectRequest(_ request: HTTPRequest) {
        coordinator.selectItem(.request(request))
    }

    @MainActor
    private func selectCollection(_ collection: RequestCollection) {
        coordinator.selectItem(.collection(collection))
    }

    @MainActor
    private func selectFolder(_ folder: Folder) {
        coordinator.selectItem(.folder(folder))
    }

    // MARK: - Action Handlers

    @MainActor
    private func createNewRequest() {
        coordinator.performAction(.newRequest)
    }

    @MainActor
    private func createNewCollection() {
        coordinator.performAction(.newCollection)
    }

    @MainActor
    private func importCurlCommand() {
        coordinator.performAction(.importCurl)
    }

    @MainActor
    private func importOpenAPISpec() {
        coordinator.performAction(.importOpenAPI)
    }

    @MainActor
    private func importPostmanCollection() {
        coordinator.performAction(.importPostman)
    }
}

// MARK: - Action Types

enum CommandPaletteAction: Equatable {
    case newRequest
    case newCollection
    case importCurl
    case importOpenAPI
    case importPostman
}

// MARK: - KeyEquivalent Helper

extension KeyEquivalent {
    var character: Character? {
        switch self {
        case .upArrow: return Character(UnicodeScalar(0xF700)!)
        case .downArrow: return Character(UnicodeScalar(0xF701)!)
        case .leftArrow: return Character(UnicodeScalar(0xF702)!)
        case .rightArrow: return Character(UnicodeScalar(0xF703)!)
        case .escape: return Character(UnicodeScalar(0x1B)!)
        case .return: return Character("\r")
        case .tab: return Character("\t")
        case .space: return Character(" ")
        default:
            return nil
        }
    }
}
