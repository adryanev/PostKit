import Foundation

/// Protocol for items that can be searched and selected via the command palette.
protocol SearchableItem {
    /// Combined text used for fuzzy search (includes title, subtitle, etc.)
    var searchText: String { get }

    /// Primary display title
    var displayTitle: String { get }

    /// Optional subtitle for additional context (e.g., collection name)
    var subtitle: String? { get }

    /// SF Symbol icon name
    var icon: String { get }

    /// Action to execute when this item is selected
    var action: () -> Void { get }

    /// Category for grouping (e.g., "Requests", "Collections", "Actions")
    var category: String { get }
}

// MARK: - Built-in Searchable Items

/// Represents a request that can be searched in the command palette.
struct RequestSearchableItem: SearchableItem {
    let request: HTTPRequest
    let onSelect: (HTTPRequest) -> Void

    var searchText: String {
        "\(request.name) \(request.method.rawValue) \(request.urlTemplate)"
    }

    var displayTitle: String { request.name }

    var subtitle: String? {
        let parts: [String] = [
            request.collection?.name,
            request.folder?.name,
            "\(request.method.rawValue) \(request.urlTemplate)"
        ].compactMap { $0 }
        return parts.joined(separator: " • ")
    }

    var icon: String {
        switch request.method {
        case .get: return "arrow.down.circle"
        case .post: return "arrow.up.circle"
        case .put: return "arrow.up.doc"
        case .patch: return "arrow.triangle.merge"
        case .delete: return "trash"
        case .head: return "eye"
        case .options: return "list.bullet"
        case .trace: return "scope"
        }
    }

    var action: () -> Void { { onSelect(request) } }
    var category: String { "Requests" }
}

/// Represents a collection that can be searched in the command palette.
struct CollectionSearchableItem: SearchableItem {
    let collection: RequestCollection
    let onSelect: (RequestCollection) -> Void

    var searchText: String { collection.name }

    var displayTitle: String { collection.name }

    var subtitle: String? {
        let requestCount = collection.requests.count
        return "\(requestCount) \(requestCount == 1 ? "request" : "requests")"
    }

    var icon: String { "folder" }
    var action: () -> Void { { onSelect(collection) } }
    var category: String { "Collections" }
}

/// Represents a generic action that can be searched in the command palette.
struct ActionSearchableItem: SearchableItem {
    let title: String
    let subtitle: String?
    let icon: String
    let category: String
    let action: () -> Void

    var searchText: String { "\(title) \(subtitle ?? "")" }
    var displayTitle: String { title }
}

/// Represents a folder that can be searched in the command palette.
struct FolderSearchableItem: SearchableItem {
    let folder: Folder
    let collectionName: String?
    let onSelect: (Folder) -> Void

    var searchText: String { folder.name }

    var displayTitle: String { folder.name }

    var subtitle: String? { collectionName }

    var icon: String { "folder.fill" }
    var action: () -> Void { { onSelect(folder) } }
    var category: String { "Folders" }
}
