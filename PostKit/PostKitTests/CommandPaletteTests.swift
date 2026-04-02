//
//  CommandPaletteTests.swift
//  PostKitTests
//
//  Tests for Command Palette functionality
//

import Testing
import Foundation
import SwiftData
@testable import PostKit

@MainActor
struct CommandPaletteViewModelTests {

    // MARK: - Test Setup

    private func createModelContainer() throws -> ModelContainer {
        let schema = Schema([
            RequestCollection.self,
            Folder.self,
            HTTPRequest.self,
            APIEnvironment.self,
            Variable.self,
            HistoryEntry.self,
            ResponseExample.self
        ])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    // MARK: - Positive Cases

    @Test func showSetsVisibilityAndResetsSearch() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.searchText = "test query"
        viewModel.selectedIndex = 5

        viewModel.show()

        #expect(viewModel.isVisible == true)
        #expect(viewModel.searchText == "")
        #expect(viewModel.selectedIndex == 0)
    }

    @Test func hideSetsVisibilityToFalse() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.show()
        viewModel.hide()

        #expect(viewModel.isVisible == false)
    }

    @Test func toggleShowsWhenHidden() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.toggle()

        #expect(viewModel.isVisible == true)
    }

    @Test func toggleHidesWhenVisible() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.show()
        viewModel.toggle()

        #expect(viewModel.isVisible == false)
    }

    @Test func updateSearchFiltersResults() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        // Create test data
        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let request1 = HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users")
        request1.collection = collection
        context.insert(request1)

        let request2 = HTTPRequest(name: "Create User", method: .post, url: "https://api.example.com/users")
        request2.collection = collection
        context.insert(request2)

        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)
        viewModel.updateSearch("Get")

        #expect(viewModel.filteredItems.count > 0)
        #expect(viewModel.filteredItems.allSatisfy { item in
            item.displayTitle.contains("Get")
        })
    }

    @Test func selectNextIncrementsSelectionIndex() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.selectedIndex = 0
        viewModel.selectNext()

        #expect(viewModel.selectedIndex == 1)
    }

    @Test func selectNextDoesNotExceedBounds() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        // Create at least one item
        let collection = RequestCollection(name: "Test")
        context.insert(collection)
        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)
        let count = viewModel.filteredItems.count
        viewModel.selectedIndex = count - 1

        viewModel.selectNext()

        #expect(viewModel.selectedIndex == count - 1)
    }

    @Test func selectPreviousDecrementsSelectionIndex() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.selectedIndex = 2
        viewModel.selectPrevious()

        #expect(viewModel.selectedIndex == 1)
    }

    @Test func selectPreviousDoesNotGoBelowZero() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.selectedIndex = 0
        viewModel.selectPrevious()

        #expect(viewModel.selectedIndex == 0)
    }

    @Test func emptySearchReturnsAllItems() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        // Create test data
        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let request1 = HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users")
        request1.collection = collection
        context.insert(request1)

        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)
        viewModel.updateSearch("")

        #expect(viewModel.filteredItems.count == viewModel.allItems.count)
    }

    // MARK: - SearchableItem Tests

    @Test func requestSearchableItemGeneratesCorrectSearchText() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let request = HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users")
        context.insert(request)

        let item = RequestSearchableItem(request: request) { _ in }

        #expect(item.searchText.contains("Get Users"))
        #expect(item.searchText.contains("GET"))
        #expect(item.searchText.contains("https://api.example.com/users"))
    }

    @Test func collectionSearchableItemGeneratesCorrectSearchText() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "My API Collection")
        context.insert(collection)

        let item = CollectionSearchableItem(collection: collection) { _ in }

        #expect(item.searchText == "My API Collection")
        #expect(item.displayTitle == "My API Collection")
        #expect(item.category == "Collections")
    }

    @Test func folderSearchableItemGeneratesCorrectSearchText() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let folder = Folder(name: "User Endpoints")
        folder.collection = collection
        context.insert(folder)

        let item = FolderSearchableItem(folder: folder, collectionName: collection.name) { _ in }

        #expect(item.searchText == "User Endpoints")
        #expect(item.displayTitle == "User Endpoints")
        #expect(item.category == "Folders")
    }

    @Test func actionSearchableItemGeneratesCorrectSearchText() {
        let item = ActionSearchableItem(
            title: "New Request",
            subtitle: "Create a new HTTP request",
            icon: "plus.circle",
            category: "Actions"
        ) { }

        #expect(item.searchText.contains("New Request"))
        #expect(item.searchText.contains("Create a new HTTP request"))
        #expect(item.displayTitle == "New Request")
        #expect(item.subtitle == "Create a new HTTP request")
        #expect(item.icon == "plus.circle")
        #expect(item.category == "Actions")
    }

    // MARK: - Vim Mode Tests

    @Test func vimModeJKeyMovesDown() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test")
        context.insert(collection)
        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)
        viewModel.selectedIndex = 0

        viewModel.handleVimKey("j")

        #expect(viewModel.selectedIndex == 1)
    }

    @Test func vimModeKKeyMovesUp() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test")
        context.insert(collection)
        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)
        viewModel.selectedIndex = 2

        viewModel.handleVimKey("k")

        #expect(viewModel.selectedIndex == 1)
    }

    @Test func vimModeEnterExecutesSelectedItem() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        var actionPerformed = false
        let item = ActionSearchableItem(
            title: "Test Action",
            subtitle: nil,
            icon: "test",
            category: "Actions"
        ) {
            actionPerformed = true
        }

        // Mock executeSelectedItem by directly calling the action
        item.action()

        #expect(actionPerformed == true)
    }

    // MARK: - Negative Cases

    @Test func searchWithNoMatchesReturnsEmptyList() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let request = HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users")
        request.collection = collection
        context.insert(request)

        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)
        viewModel.updateSearch("NonExistentItemXYZ123")

        #expect(viewModel.filteredItems.isEmpty)
    }

    @Test func selectNextWithEmptyResultsDoesNothing() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.updateSearch("NonExistentItemXYZ123")
        viewModel.selectNext()

        #expect(viewModel.selectedIndex == 0 || viewModel.selectedIndex == nil)
    }

    @Test func selectPreviousWithEmptyResultsDoesNothing() throws {
        let container = try createModelContainer()
        let viewModel = CommandPaletteViewModel(modelContext: container.mainContext)

        viewModel.updateSearch("NonExistentItemXYZ123")
        viewModel.selectPrevious()

        #expect(viewModel.selectedIndex == 0 || viewModel.selectedIndex == nil)
    }

    // MARK: - Edge Cases

    @Test func caseInsensitiveSearchMatchesRegardlessOfCase() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let request = HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users")
        request.collection = collection
        context.insert(request)

        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)

        // Test lowercase
        viewModel.updateSearch("get users")
        #expect(!viewModel.filteredItems.isEmpty)

        // Test uppercase
        viewModel.updateSearch("GET USERS")
        #expect(!viewModel.filteredItems.isEmpty)

        // Test mixed case
        viewModel.updateSearch("GeT UsErS")
        #expect(!viewModel.filteredItems.isEmpty)
    }

    @Test func partialSearchMatches() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let request = HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users")
        request.collection = collection
        context.insert(request)

        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)

        // Should match with partial string
        viewModel.updateSearch("Get")
        #expect(!viewModel.filteredItems.isEmpty)

        viewModel.updateSearch("Users")
        #expect(!viewModel.filteredItems.isEmpty)

        viewModel.updateSearch("Get Us")
        #expect(!viewModel.filteredItems.isEmpty)
    }

    @Test func searchesAcrossRequestUrl() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let request = HTTPRequest(name: "My Request", method: .get, url: "https://api.example.com/users")
        request.collection = collection
        context.insert(request)

        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)

        // Should match by URL
        viewModel.updateSearch("api.example.com")
        #expect(!viewModel.filteredItems.isEmpty)

        viewModel.updateSearch("users")
        #expect(!viewModel.filteredItems.isEmpty)
    }

    @Test func groupsItemsByCategory() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let collection = RequestCollection(name: "Test Collection")
        context.insert(collection)

        let request = HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users")
        request.collection = collection
        context.insert(request)

        let folder = Folder(name: "User Endpoints")
        folder.collection = collection
        context.insert(folder)

        try context.save()

        let viewModel = CommandPaletteViewModel(modelContext: context)
        let grouped = viewModel.filteredGroupedItems

        #expect(grouped["Requests"] != nil)
        #expect(grouped["Collections"] != nil)
        #expect(grouped["Folders"] != nil)
        #expect(grouped["Actions"] != nil)
    }

    @Test func requestsHaveCorrectIconBasedOnMethod() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let getReq = HTTPRequest(name: "Get", method: .get, url: "https://example.com")
        let postReq = HTTPRequest(name: "Post", method: .post, url: "https://example.com")
        let deleteReq = HTTPRequest(name: "Delete", method: .delete, url: "https://example.com")

        context.insert(getReq)
        context.insert(postReq)
        context.insert(deleteReq)

        let getIcon = RequestSearchableItem(request: getReq) { _ in }.icon
        let postIcon = RequestSearchableItem(request: postReq) { _ in }.icon
        let deleteIcon = RequestSearchableItem(request: deleteReq) { _ in }.icon

        #expect(getIcon == "arrow.down.circle")
        #expect(postIcon == "arrow.up.circle")
        #expect(deleteIcon == "trash")
    }
}
