# SwiftData Best Practices for Production Apps (2025)

> Comprehensive guide for building a production HTTP client app with models: Collection, Folder, HTTPRequest, Environment, Variable, HistoryEntry

---

## Table of Contents

1. [Model Relationships (@Relationship)](#1-model-relationships-relationship)
2. [@Transient and Computed Properties](#2-transient-and-computed-properties)
3. [Performance with Large Datasets](#3-performance-with-large-datasets)
4. [Migration Strategies](#4-migration-strategies)
5. [ModelContainer Configuration](#5-modelcontainer-configuration)
6. [Querying Patterns and Predicates](#6-querying-patterns-and-predicates)
7. [iCloud Sync Considerations](#7-icloud-sync-considerations)
8. [Common Pitfalls and Anti-Patterns](#8-common-pitfalls-and-anti-patterns)

---

## 1. Model Relationships (@Relationship)

### Best Practices Summary

| Rule | Reason |
|------|--------|
| All relationships MUST be optional | SwiftData requirement for proper persistence |
| Always define inverse relationships | Prevents orphaned references and crashes |
| Use `.cascade` deliberately | Only when children should be deleted with parent |
| Default delete rule is `.nullify` | Can cause crashes with non-optional relationships |

### Delete Rules Reference

```swift
// Available delete rules
@Relationship(deleteRule: .cascade)   // Delete children when parent deleted
@Relationship(deleteRule: .nullify)   // Set relationship to nil (DEFAULT)
@Relationship(deleteRule: .deny)      // Prevent deletion if children exist
@Relationship(deleteRule: .noAction)  // Do nothing to related objects
```

### Recommended Model Structure for Your HTTP Client

```swift
import SwiftData
import Foundation

// MARK: - Collection (Root container)
@Model
final class Collection {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // One-to-many: Collection owns Folders
    @Relationship(deleteRule: .cascade, inverse: \Folder.collection)
    var folders: [Folder]?

    // One-to-many: Collection owns root-level requests
    @Relationship(deleteRule: .cascade, inverse: \HTTPRequest.collection)
    var requests: [HTTPRequest]?

    // One-to-many: Collection owns Environments
    @Relationship(deleteRule: .cascade, inverse: \Environment.collection)
    var environments: [Environment]?

    // Track active environment (optional, no cascade)
    @Relationship(deleteRule: .nullify)
    var activeEnvironment: Environment?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Folder (Organizes requests)
@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date

    // Parent collection (inverse)
    var collection: Collection?

    // Self-referential: Nested folders
    @Relationship(deleteRule: .cascade, inverse: \Folder.parentFolder)
    var subfolders: [Folder]?
    var parentFolder: Folder?

    // Folder owns requests
    @Relationship(deleteRule: .cascade, inverse: \HTTPRequest.folder)
    var requests: [HTTPRequest]?

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

// MARK: - HTTPRequest
@Model
final class HTTPRequest {
    @Attribute(.unique) var id: UUID
    var name: String
    var urlString: String
    var method: String  // GET, POST, PUT, DELETE, etc.
    var bodyData: Data?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    // Parent references (one will be set)
    var collection: Collection?
    var folder: Folder?

    // Request owns its headers and parameters as separate models
    // IMPORTANT: Don't use [String: String] for searchable data!
    @Relationship(deleteRule: .cascade, inverse: \RequestHeader.request)
    var headers: [RequestHeader]?

    @Relationship(deleteRule: .cascade, inverse: \QueryParameter.request)
    var queryParameters: [QueryParameter]?

    // History entries for this request
    @Relationship(deleteRule: .cascade, inverse: \HistoryEntry.request)
    var history: [HistoryEntry]?

    init(name: String, urlString: String, method: String = "GET") {
        self.id = UUID()
        self.name = name
        self.urlString = urlString
        self.method = method
        self.sortOrder = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Supporting Models for Headers/Params (NOT Dictionary!)
// SwiftData stores [String: String] as Codable blob - not searchable!

@Model
final class RequestHeader {
    var key: String
    var value: String
    var isEnabled: Bool
    var request: HTTPRequest?

    init(key: String, value: String, isEnabled: Bool = true) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}

@Model
final class QueryParameter {
    var key: String
    var value: String
    var isEnabled: Bool
    var request: HTTPRequest?

    init(key: String, value: String, isEnabled: Bool = true) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}

// MARK: - Environment
@Model
final class Environment {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    var collection: Collection?

    @Relationship(deleteRule: .cascade, inverse: \Variable.environment)
    var variables: [Variable]?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

// MARK: - Variable
@Model
final class Variable {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String
    var isSecret: Bool

    var environment: Environment?

    init(key: String, value: String, isSecret: Bool = false) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}

// MARK: - HistoryEntry
@Model
final class HistoryEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var requestURL: String
    var requestMethod: String
    var requestBody: Data?
    var responseStatusCode: Int
    var responseBody: Data?
    var responseHeaders: Data?  // JSON encoded for storage
    var durationMs: Double

    var request: HTTPRequest?

    init(
        requestURL: String,
        requestMethod: String,
        responseStatusCode: Int,
        durationMs: Double
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.requestURL = requestURL
        self.requestMethod = requestMethod
        self.responseStatusCode = responseStatusCode
        self.durationMs = durationMs
    }
}
```

### Key Relationship Patterns

```swift
// Pattern 1: Safe parent-child with cascade
@Model
final class Parent {
    @Relationship(deleteRule: .cascade, inverse: \Child.parent)
    var children: [Child]?
}

@Model
final class Child {
    var parent: Parent?  // MUST be optional
}

// Pattern 2: Self-referential (folders containing folders)
@Model
final class Folder {
    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder]?
    var parent: Folder?
}

// Pattern 3: Many-to-one without cascade (reference only)
@Model
final class HTTPRequest {
    @Relationship(deleteRule: .nullify)
    var activeEnvironment: Environment?
}
```

---

## 2. @Transient and Computed Properties

### Key Points

- **Computed properties are automatically transient** - no `@Transient` needed
- **@Transient stored properties** must have default values
- **Cannot use transient properties in predicates** - crashes at runtime
- **@Transient properties don't trigger view updates** alone

### Patterns for Your HTTP Client

```swift
@Model
final class HTTPRequest {
    var urlString: String
    var method: String
    var bodyData: Data?

    // GOOD: Computed property (automatically transient)
    var displayName: String {
        "\(method) \(URL(string: urlString)?.path ?? urlString)"
    }

    // GOOD: Computed property for derived data
    var bodyString: String? {
        guard let data = bodyData else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // GOOD: Transient runtime state with default value
    @Transient
    var isExecuting: Bool = false

    @Transient
    var lastError: Error? = nil

    // GOOD: Computed property for URL parsing
    var parsedURL: URL? {
        URL(string: urlString)
    }

    var host: String? {
        parsedURL?.host
    }

    init(urlString: String, method: String) {
        self.urlString = urlString
        self.method = method
    }
}

@Model
final class HistoryEntry {
    var responseBody: Data?
    var responseHeaders: Data?
    var durationMs: Double

    // Computed: Parse stored JSON headers
    var parsedHeaders: [String: String] {
        guard let data = responseHeaders,
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    // Computed: Format duration
    var formattedDuration: String {
        if durationMs < 1000 {
            return String(format: "%.0fms", durationMs)
        }
        return String(format: "%.2fs", durationMs / 1000)
    }

    // Computed: Response body as string
    var responseText: String? {
        guard let data = responseBody else { return nil }
        return String(data: data, encoding: .utf8)
    }

    init(durationMs: Double) {
        self.durationMs = durationMs
    }
}

// MARK: - Environment Variable Interpolation
@Model
final class Environment {
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \Variable.environment)
    var variables: [Variable]?

    // Computed: Create lookup dictionary
    var variableDictionary: [String: String] {
        (variables ?? []).reduce(into: [:]) { dict, variable in
            dict[variable.key] = variable.value
        }
    }

    // Computed: Interpolate variables in a string
    func interpolate(_ string: String) -> String {
        var result = string
        for variable in (variables ?? []) {
            result = result.replacingOccurrences(
                of: "{{\\(variable.key)}}",
                with: variable.value
            )
        }
        return result
    }

    init(name: String) {
        self.name = name
    }
}
```

### Warning: Performance with Computed Properties

```swift
// BAD: Expensive computed property over relationships
@Model
final class Collection {
    @Relationship(deleteRule: .cascade)
    var requests: [HTTPRequest]?

    // WARNING: This can cause hangs with large datasets!
    var totalRequests: Int {
        requests?.count ?? 0
    }

    // WARNING: Even worse - filtering over relationships
    var failedRequestsCount: Int {
        (requests ?? []).filter {
            ($0.history ?? []).contains { $0.responseStatusCode >= 400 }
        }.count
    }
}

// BETTER: Store denormalized counts, update when data changes
@Model
final class Collection {
    var cachedRequestCount: Int = 0

    func updateCounts() {
        cachedRequestCount = requests?.count ?? 0
    }
}
```

---

## 3. Performance with Large Datasets (500+ Requests)

### Critical Optimizations

#### 1. Use Fetch Limits and Paging

```swift
// GOOD: Paginated fetching
func fetchHistoryPage(
    for request: HTTPRequest,
    page: Int,
    pageSize: Int = 50,
    context: ModelContext
) throws -> [HistoryEntry] {
    var descriptor = FetchDescriptor<HistoryEntry>(
        predicate: #Predicate<HistoryEntry> { entry in
            entry.request?.id == request.id
        },
        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )
    descriptor.fetchLimit = pageSize
    descriptor.fetchOffset = page * pageSize

    return try context.fetch(descriptor)
}
```

#### 2. Use fetchCount() Instead of Fetching All

```swift
// BAD: Fetches all objects just to count
let allHistory = try context.fetch(FetchDescriptor<HistoryEntry>())
let count = allHistory.count

// GOOD: Uses efficient SQL COUNT
let descriptor = FetchDescriptor<HistoryEntry>(
    predicate: #Predicate { $0.request?.id == requestId }
)
let count = try context.fetchCount(descriptor)
```

#### 3. Optimize Predicate Order

```swift
// BAD: String comparison first (slow)
let descriptor = FetchDescriptor<HTTPRequest>(
    predicate: #Predicate { request in
        request.name.localizedStandardContains("api") &&
        request.method == "GET"
    }
)

// GOOD: Fast comparison first, eliminates data early
let descriptor = FetchDescriptor<HTTPRequest>(
    predicate: #Predicate { request in
        request.method == "GET" &&  // Integer/enum comparison first
        request.name.localizedStandardContains("api")  // String search last
    }
)
```

#### 4. Use Indexes for Frequently Queried Properties (iOS 18+)

```swift
@Model
final class HistoryEntry {
    // Index frequently filtered/sorted properties
    #Index<HistoryEntry>([\.timestamp])
    #Index<HistoryEntry>([\.responseStatusCode])

    var timestamp: Date
    var responseStatusCode: Int
    // ...
}

@Model
final class HTTPRequest {
    #Index<HTTPRequest>([\.method])
    #Index<HTTPRequest>([\.updatedAt])

    var method: String
    var updatedAt: Date
    // ...
}
```

#### 5. Prefetch Relationships When Needed

```swift
// When you know you'll access relationships
var descriptor = FetchDescriptor<HTTPRequest>()
descriptor.relationshipKeyPathsForPrefetching = [
    \HTTPRequest.headers,
    \HTTPRequest.queryParameters
]

let requests = try context.fetch(descriptor)
// Now accessing headers/queryParameters won't cause additional fetches
```

#### 6. Selective Property Fetching

```swift
// Fetch only needed properties for list views
var descriptor = FetchDescriptor<HTTPRequest>(
    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
)
descriptor.propertiesToFetch = [\.name, \.method, \.urlString, \.updatedAt]
descriptor.fetchLimit = 100

let requests = try context.fetch(descriptor)
```

#### 7. Background Processing with ModelActor

```swift
import SwiftData

@ModelActor
actor HistoryManager {
    // Heavy operations run off main thread

    func cleanupOldHistory(olderThan days: Int) throws -> Int {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        )!

        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.timestamp < cutoffDate }
        )

        let oldEntries = try modelContext.fetch(descriptor)
        let count = oldEntries.count

        for entry in oldEntries {
            modelContext.delete(entry)
        }

        try modelContext.save()
        return count
    }

    func exportHistory(for requestId: UUID) throws -> [HistoryExportDTO] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.request?.id == requestId },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        let entries = try modelContext.fetch(descriptor)

        // Map to Sendable DTOs for cross-actor transfer
        return entries.map { entry in
            HistoryExportDTO(
                timestamp: entry.timestamp,
                url: entry.requestURL,
                method: entry.requestMethod,
                statusCode: entry.responseStatusCode,
                duration: entry.durationMs
            )
        }
    }
}

// Sendable DTO for passing across actors
struct HistoryExportDTO: Sendable {
    let timestamp: Date
    let url: String
    let method: String
    let statusCode: Int
    let duration: Double
}

// Usage from SwiftUI
struct HistoryView: View {
    let container: ModelContainer

    func performCleanup() {
        Task.detached {  // Important: detached to avoid MainActor
            let manager = HistoryManager(modelContainer: container)
            let deleted = try await manager.cleanupOldHistory(olderThan: 30)
            print("Deleted \\(deleted) old entries")
        }
    }
}
```

---

## 4. Migration Strategies

### ALWAYS Use VersionedSchema from Day One

```swift
// MARK: - Schema Versions

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Collection.self,
            Folder.self,
            HTTPRequest.self,
            RequestHeader.self,
            QueryParameter.self,
            Environment.self,
            Variable.self,
            HistoryEntry.self
        ]
    }

    // Define V1 models here
    @Model
    final class Collection {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        // V1 structure...

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.createdAt = Date()
        }
    }

    // ... other V1 models
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Collection.self,
            Folder.self,
            HTTPRequest.self,
            RequestHeader.self,
            QueryParameter.self,
            Environment.self,
            Variable.self,
            HistoryEntry.self
        ]
    }

    @Model
    final class Collection {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date  // NEW in V2
        var colorHex: String?  // NEW in V2

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    // ... other V2 models with updates
}

// MARK: - Migration Plan

enum PostKitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // Lightweight migration (automatic)
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}

// MARK: - Complex Migration Example

enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    // ... models
}

extension PostKitMigrationPlan {
    // Custom migration with data transformation
    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self,
        willMigrate: { context in
            // Pre-migration: Transform data before schema change
            let requests = try context.fetch(FetchDescriptor<SchemaV2.HTTPRequest>())

            for request in requests {
                // Example: Normalize URL format
                if let url = URL(string: request.urlString) {
                    request.urlString = url.absoluteString
                }
            }

            try context.save()
        },
        didMigrate: { context in
            // Post-migration: Clean up or validate
            // This runs after schema is updated to V3
        }
    )
}

// MARK: - Type Aliases (Point to Current Schema)

typealias Collection = SchemaV2.Collection
typealias Folder = SchemaV2.Folder
typealias HTTPRequest = SchemaV2.HTTPRequest
// ... etc
```

### Lightweight vs Custom Migration

| Change Type | Migration Type |
|-------------|----------------|
| Add new property with default | Lightweight |
| Add new model | Lightweight |
| Delete property | Lightweight |
| Rename property/model | Lightweight (with mapping) |
| Change property type | Custom |
| Split/merge models | Custom |
| Transform data values | Custom |

---

## 5. ModelContainer Configuration

### Production Configuration

```swift
import SwiftData
import SwiftUI

@main
struct PostKitApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try Self.createContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \\(error)")
        }
    }

    static func createContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV2.models)

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            // For iCloud sync (see Section 7 for requirements)
            cloudKitDatabase: .automatic
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: PostKitMigrationPlan.self,
            configurations: [config]
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

// MARK: - Multiple Configurations (Advanced)

static func createContainerWithSeparateStores() throws -> ModelContainer {
    let schema = Schema(SchemaV2.models)

    // Main data (synced to iCloud)
    let mainConfig = ModelConfiguration(
        "Main",
        schema: Schema([
            Collection.self,
            Folder.self,
            HTTPRequest.self,
            Environment.self,
            Variable.self
        ]),
        url: URL.documentsDirectory.appending(path: "PostKit.store"),
        cloudKitDatabase: .automatic
    )

    // History (local only, can be large)
    let historyConfig = ModelConfiguration(
        "History",
        schema: Schema([HistoryEntry.self]),
        url: URL.documentsDirectory.appending(path: "PostKitHistory.store"),
        cloudKitDatabase: .none  // Don't sync history
    )

    return try ModelContainer(
        for: schema,
        migrationPlan: PostKitMigrationPlan.self,
        configurations: [mainConfig, historyConfig]
    )
}

// MARK: - Testing Configuration

static func createPreviewContainer() throws -> ModelContainer {
    let schema = Schema(SchemaV2.models)

    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true  // In-memory for previews/tests
    )

    let container = try ModelContainer(
        for: schema,
        configurations: [config]
    )

    // Seed with sample data
    let context = container.mainContext

    let collection = Collection(name: "Sample API")
    let env = Environment(name: "Development")
    env.variables = [
        Variable(key: "BASE_URL", value: "https://api.example.com"),
        Variable(key: "API_KEY", value: "test-key-123")
    ]
    collection.environments = [env]

    context.insert(collection)

    return container
}
```

### Debug Launch Arguments

Add to scheme for debugging:

```
-com.apple.CoreData.SQLDebug 1       // Basic SQL logging
-com.apple.CoreData.SQLDebug 3       // Detailed with EXPLAIN QUERY PLAN
-com.apple.CoreData.ConcurrencyDebug 1  // Thread safety violations
-com.apple.CoreData.CloudKitDebug 1  // iCloud sync debugging
```

---

## 6. Querying Patterns and Predicates

### Basic Query Patterns

```swift
// MARK: - SwiftUI @Query Examples

struct RequestListView: View {
    // Simple sorted query
    @Query(sort: \HTTPRequest.updatedAt, order: .reverse)
    private var requests: [HTTPRequest]

    var body: some View {
        List(requests) { request in
            RequestRow(request: request)
        }
    }
}

struct FilteredRequestsView: View {
    // Filtered and sorted
    @Query(
        filter: #Predicate<HTTPRequest> { $0.method == "GET" },
        sort: \HTTPRequest.name
    )
    private var getRequests: [HTTPRequest]

    var body: some View {
        List(getRequests) { request in
            RequestRow(request: request)
        }
    }
}

// MARK: - Dynamic Filtering (Parent View Pattern)

struct RequestBrowserView: View {
    @State private var selectedMethod: String? = nil
    @State private var searchText: String = ""

    var body: some View {
        // Pass filter parameters to child
        FilteredRequestList(
            method: selectedMethod,
            searchText: searchText
        )
    }
}

struct FilteredRequestList: View {
    let method: String?
    let searchText: String

    // Initialize @Query with parameters
    @Query private var requests: [HTTPRequest]

    init(method: String?, searchText: String) {
        self.method = method
        self.searchText = searchText

        let predicate: Predicate<HTTPRequest>?

        if let method = method, !searchText.isEmpty {
            predicate = #Predicate<HTTPRequest> { request in
                request.method == method &&
                request.name.localizedStandardContains(searchText)
            }
        } else if let method = method {
            predicate = #Predicate<HTTPRequest> { request in
                request.method == method
            }
        } else if !searchText.isEmpty {
            predicate = #Predicate<HTTPRequest> { request in
                request.name.localizedStandardContains(searchText)
            }
        } else {
            predicate = nil
        }

        _requests = Query(
            filter: predicate,
            sort: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
    }

    var body: some View {
        List(requests) { request in
            RequestRow(request: request)
        }
    }
}
```

### Advanced FetchDescriptor Patterns

```swift
// MARK: - ModelContext Fetching

extension ModelContext {

    // Find request by ID
    func findRequest(id: UUID) throws -> HTTPRequest? {
        var descriptor = FetchDescriptor<HTTPRequest>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    // Recent history with limit
    func recentHistory(
        limit: Int = 50,
        statusCodeFilter: Int? = nil
    ) throws -> [HistoryEntry] {
        let predicate: Predicate<HistoryEntry>?

        if let code = statusCodeFilter {
            predicate = #Predicate { $0.responseStatusCode == code }
        } else {
            predicate = nil
        }

        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return try fetch(descriptor)
    }

    // Search across multiple fields
    func searchRequests(query: String) throws -> [HTTPRequest] {
        guard !query.isEmpty else {
            return try fetch(FetchDescriptor<HTTPRequest>())
        }

        let descriptor = FetchDescriptor<HTTPRequest>(
            predicate: #Predicate { request in
                request.name.localizedStandardContains(query) ||
                request.urlString.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.name)]
        )

        return try fetch(descriptor)
    }

    // Requests in folder hierarchy
    func requestsInFolder(_ folder: Folder, includeSubfolders: Bool) throws -> [HTTPRequest] {
        if includeSubfolders {
            // Get all subfolder IDs first
            var folderIds = [folder.id]
            collectSubfolderIds(folder, into: &folderIds)

            // SwiftData predicates can't use arrays directly in some cases
            // So fetch and filter in memory for complex cases
            let descriptor = FetchDescriptor<HTTPRequest>(
                sortBy: [SortDescriptor(\.sortOrder)]
            )
            let all = try fetch(descriptor)
            return all.filter { request in
                guard let folderId = request.folder?.id else { return false }
                return folderIds.contains(folderId)
            }
        } else {
            let folderId = folder.id
            let descriptor = FetchDescriptor<HTTPRequest>(
                predicate: #Predicate { $0.folder?.id == folderId },
                sortBy: [SortDescriptor(\.sortOrder)]
            )
            return try fetch(descriptor)
        }
    }

    private func collectSubfolderIds(_ folder: Folder, into ids: inout [UUID]) {
        for subfolder in (folder.subfolders ?? []) {
            ids.append(subfolder.id)
            collectSubfolderIds(subfolder, into: &ids)
        }
    }
}
```

### Predicate Limitations and Workarounds

```swift
// LIMITATION: Can't use local variables
// BAD - Won't compile
let searchTerm = "api"
let predicate = #Predicate<HTTPRequest> { request in
    let term = searchTerm  // ERROR: Can't create local variables
    request.name.contains(term)
}

// GOOD - Use captured value directly
let searchTerm = "api"
let predicate = #Predicate<HTTPRequest> { request in
    request.name.localizedStandardContains(searchTerm)
}

// LIMITATION: Complex computed properties don't work
// BAD - Computed property access
let predicate = #Predicate<HTTPRequest> { request in
    request.displayName.contains("GET")  // displayName is computed
}

// GOOD - Use stored properties
let predicate = #Predicate<HTTPRequest> { request in
    request.method == "GET" && request.urlString.contains("/api/")
}

// LIMITATION: Can't search inside Codable arrays
// If you stored headers as [String: String], you can't search them!
// That's why we use separate RequestHeader model
```

---

## 7. iCloud Sync Considerations

### Requirements Checklist

```
[ ] Paid Apple Developer Account
[ ] iCloud capability enabled
[ ] CloudKit checkbox selected
[ ] CloudKit container created/selected
[ ] Background Modes capability added
[ ] Remote Notifications checked
[ ] All properties optional OR have defaults
[ ] All relationships optional
[ ] NO @Attribute(.unique) on synced properties
```

### iCloud-Compatible Model Design

```swift
// MARK: - iCloud-Safe Models

@Model
final class Collection {
    // NO: @Attribute(.unique) - Not supported by CloudKit!
    var id: UUID = UUID()  // Use default value instead

    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // All relationships MUST be optional
    @Relationship(deleteRule: .cascade, inverse: \Folder.collection)
    var folders: [Folder]?

    @Relationship(deleteRule: .cascade, inverse: \HTTPRequest.collection)
    var requests: [HTTPRequest]?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class Variable {
    var id: UUID = UUID()
    var key: String = ""
    var value: String = ""
    var isSecret: Bool = false

    var environment: Environment?

    init(key: String, value: String, isSecret: Bool = false) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}
```

### Hybrid Sync Strategy (Recommended for Your App)

```swift
// Sync collections/folders/requests to iCloud
// Keep history local (too much data, not needed across devices)

static func createHybridContainer() throws -> ModelContainer {
    let schema = Schema(SchemaV2.models)

    // Synced data
    let syncedConfig = ModelConfiguration(
        "Synced",
        schema: Schema([
            Collection.self,
            Folder.self,
            HTTPRequest.self,
            RequestHeader.self,
            QueryParameter.self,
            Environment.self,
            Variable.self
        ]),
        url: URL.documentsDirectory.appending(path: "PostKit-Synced.store"),
        cloudKitDatabase: .automatic
    )

    // Local-only history
    let localConfig = ModelConfiguration(
        "Local",
        schema: Schema([HistoryEntry.self]),
        url: URL.documentsDirectory.appending(path: "PostKit-History.store"),
        cloudKitDatabase: .none
    )

    return try ModelContainer(
        for: schema,
        migrationPlan: PostKitMigrationPlan.self,
        configurations: [syncedConfig, localConfig]
    )
}
```

### CloudKit Schema Initialization (Critical!)

```swift
// Call this during development to push schema to CloudKit
// Remove or guard in production!

#if DEBUG
func initializeCloudKitSchema() {
    guard let url = container.configurations.first?.url else { return }

    let options = NSPersistentCloudKitContainerOptions(
        containerIdentifier: "iCloud.com.yourcompany.PostKit"
    )

    do {
        try container.mainContext.managedObjectContext?
            .persistentStoreCoordinator?
            .initializeCloudKitSchema(options: options)
        print("CloudKit schema initialized")
    } catch {
        print("CloudKit schema initialization failed: \\(error)")
    }
}
#endif
```

### iCloud Sync Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| Private database only | No sharing | Use CloudKit directly for sharing |
| No @Attribute(.unique) | Can't enforce uniqueness | Manual deduplication |
| Lightweight migration only | Limited schema changes | Plan schema carefully |
| Account switching clears data | Data loss risk | Warn users, backup option |
| Slow initial sync | UX issue | Show sync progress |
| Simulator unreliable | Testing difficulty | Use real devices |

---

## 8. Common Pitfalls and Anti-Patterns

### MUST AVOID

#### 1. Subclassing SwiftData Models

```swift
// BAD - Will cause issues
@Model
class BaseRequest { }

@Model
class GETRequest: BaseRequest { }  // DON'T DO THIS

// GOOD - Use composition or enums
@Model
final class HTTPRequest {
    var method: HTTPMethod  // enum
}
```

#### 2. Using Arrays/Dictionaries for Searchable Data

```swift
// BAD - Stored as Codable blob, can't query
@Model
final class HTTPRequest {
    var headers: [String: String] = [:]  // NOT SEARCHABLE!
}

// GOOD - Use relationship to separate model
@Model
final class HTTPRequest {
    @Relationship(deleteRule: .cascade, inverse: \RequestHeader.request)
    var headers: [RequestHeader]?
}

@Model
final class RequestHeader {
    var key: String
    var value: String
    var request: HTTPRequest?
}
```

#### 3. Missing Initializers

```swift
// BAD - Missing initializer
@Model
final class Environment {
    var name: String = ""
}

// GOOD - Always provide initializer
@Model
final class Environment {
    var name: String = ""

    init() { }

    init(name: String) {
        self.name = name
    }
}
```

#### 4. Assigning Relationships in Initializers

```swift
// BAD - Can cause duplicate registration
@Model
final class Collection {
    var folders: [Folder]?

    init(folders: [Folder]) {
        self.folders = folders  // DANGEROUS
    }
}

// GOOD - Assign after insertion
let collection = Collection(name: "API")
context.insert(collection)
collection.folders = [folder1, folder2]  // Safe after insert
```

#### 5. Duplicate Insertions

```swift
// BAD - Inserting parent AND children separately
let folder = Folder(name: "Auth")
let request = HTTPRequest(name: "Login", urlString: "/login")
folder.requests = [request]

context.insert(folder)
context.insert(request)  // CRASH: Duplicate registration!

// GOOD - Insert parent only, children auto-inserted
let folder = Folder(name: "Auth")
let request = HTTPRequest(name: "Login", urlString: "/login")
folder.requests = [request]

context.insert(folder)  // request is automatically inserted
```

#### 6. Non-Optional Relationships with .nullify

```swift
// BAD - Will crash when parent deleted
@Model
final class Child {
    var parent: Parent  // Non-optional + default .nullify = crash
}

// GOOD - Either make optional or use .cascade on parent
@Model
final class Child {
    var parent: Parent?  // Optional is safe
}
```

#### 7. Expecting Array Order Preservation

```swift
// BAD - Assuming order is preserved
@Model
final class Folder {
    var requests: [HTTPRequest]?  // Order NOT preserved!
}

// GOOD - Use sortOrder property
@Model
final class HTTPRequest {
    var sortOrder: Int = 0  // Explicit ordering
}

// Query with sort
@Query(sort: \HTTPRequest.sortOrder) var requests: [HTTPRequest]
```

#### 8. Using Transient Properties in Predicates

```swift
// BAD - Compiles but crashes at runtime!
@Model
final class HTTPRequest {
    @Transient var isSelected: Bool = false
}

let predicate = #Predicate<HTTPRequest> { $0.isSelected }  // CRASH

// GOOD - Only use persisted properties in predicates
let predicate = #Predicate<HTTPRequest> { $0.method == "GET" }
```

### Performance Anti-Patterns

```swift
// BAD - Fetching all to check existence
func requestExists(name: String) -> Bool {
    let all = try? context.fetch(FetchDescriptor<HTTPRequest>())
    return all?.contains { $0.name == name } ?? false
}

// GOOD - Use predicate and fetchLimit
func requestExists(name: String) -> Bool {
    var descriptor = FetchDescriptor<HTTPRequest>(
        predicate: #Predicate { $0.name == name }
    )
    descriptor.fetchLimit = 1
    return (try? context.fetchCount(descriptor)) ?? 0 > 0
}

// BAD - Accessing relationships in a loop without prefetch
for request in requests {
    print(request.headers?.count ?? 0)  // N+1 queries!
}

// GOOD - Prefetch relationships
var descriptor = FetchDescriptor<HTTPRequest>()
descriptor.relationshipKeyPathsForPrefetching = [\HTTPRequest.headers]
let requests = try context.fetch(descriptor)
```

---

## Quick Reference Card

### Model Checklist

```
[ ] All relationships are optional
[ ] Inverse relationships defined
[ ] Delete rules explicitly set
[ ] Initializer provided
[ ] No subclassing
[ ] No [String:String] for searchable data
[ ] sortOrder property for ordered collections
[ ] UUID id with default value (not @Attribute(.unique) if using iCloud)
```

### Query Performance Checklist

```
[ ] fetchLimit set for large datasets
[ ] fetchCount() used for counts
[ ] Predicates ordered: fast checks first
[ ] Relationships prefetched when needed
[ ] Indexes on frequently queried properties (iOS 18+)
[ ] Heavy work on ModelActor
```

### iCloud Checklist

```
[ ] All properties have defaults
[ ] All relationships optional
[ ] No @Attribute(.unique)
[ ] Schema pushed to CloudKit (development)
[ ] Test on real device
[ ] Plan for lightweight migrations only
```

---

## Sources

- [Apple SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [Hacking with Swift - SwiftData by Example](https://www.hackingwithswift.com/quick-start/swiftdata)
- [Fatbobman - Key Considerations Before Using SwiftData](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [Fatbobman - Concurrent Programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/)
- [Atomic Robot - Unauthorized Guide to SwiftData Migrations](https://atomicrobot.com/blog/an-unauthorized-guide-to-swiftdata-migrations/)
- [Tanaschita - Migration with SwiftData](https://tanaschita.com/20231120-migration-with-swiftdata/)
- [Wade Tregaskis - SwiftData Pitfalls](https://wadetregaskis.com/swiftdata-pitfalls/)
- [AzamSharp - SwiftData Architecture Patterns](https://azamsharp.com/2025/03/28/swiftdata-architecture-patterns-and-practices.html)
- [BrightDigit - Using ModelActor in SwiftData](https://brightdigit.com/tutorials/swiftdata-modelactor/)
- [Pol Piella - SwiftData Configuration](https://www.polpiella.dev/configuring-swiftdata-in-a-swiftui-app)
