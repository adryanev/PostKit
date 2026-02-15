# PostKit Developer Guide

> **Last updated:** 2026-02-14
> **Applies to:** PostKit v1.0 (MVP)
> **Audience:** New contributors, future maintainers

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Development Setup](#2-development-setup)
3. [Project Structure](#3-project-structure)
4. [Architecture Patterns](#4-architecture-patterns)
5. [Adding a New Feature](#5-adding-a-new-feature)
6. [Coding Conventions](#6-coding-conventions)
7. [Security Practices](#7-security-practices)
8. [Testing](#8-testing)
9. [Git Workflow](#9-git-workflow)
10. [Checklists](#10-checklists)
- [Appendix A: Keyboard Shortcuts](#appendix-a-keyboard-shortcuts)
- [Appendix B: Key File Reference](#appendix-b-key-file-reference)

---

## 1. Project Overview

**PostKit** is a native macOS HTTP client for API development and testing — a lightweight alternative to Postman and Insomnia, designed to feel native on macOS.

### Tech Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | SwiftUI with NSViewRepresentable for code editing |
| Persistence | SwiftData (`@Model`, `@Query`) |
| Architecture | MVVM with `@Observable` ViewModels |
| HTTP Engine | libcurl via `CurlHTTPClient` with `URLSessionHTTPClient` fallback |
| DI Container | Factory 2.5.x (`import FactoryKit`) |
| Syntax Highlighting | Highlightr 2.3.0 (via highlight.js) |
| Secret Storage | macOS Keychain (Security framework) |
| Testing | Swift Testing (`@Test`, `#expect`) with FactoryTesting |

### Key Stats

| Metric | Value |
|--------|-------|
| Lines of Code | ~5,000 |
| Swift Files | 48 |
| SwiftData Models | 6 |
| External Dependencies | 2 (Factory, Highlightr) |
| Minimum macOS | 14.0 (Sonoma) |
| Minimum Xcode | 16.0 |

### Core Features

- Full HTTP method support (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS)
- Collections, folders, and request organization
- Environment variables with `{{variable}}` interpolation
- Bearer, Basic Auth, and API Key authentication
- cURL and OpenAPI 3.x import
- JSON export with automatic credential redaction
- Keychain-backed secret storage
- Request history tracking
- Syntax highlighting (JSON, XML, YAML, HTML, CSS, JavaScript, Bash) via Highlightr
- Line numbers and find/search (Cmd+F) in code editors

---

## 2. Development Setup

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 16.0+
- Network access for Swift Package Manager (to resolve Factory dependency)

### Quick Start

```bash
# Clone the repository
git clone git@github.com:adryanev/PostKit.git
cd PostKit

# Open in Xcode
open PostKit.xcodeproj
```

1. Xcode will automatically resolve the Factory Swift Package dependency
2. Select the **PostKit** scheme in Xcode's scheme selector
3. Press `Cmd+B` to build
4. Press `Cmd+R` to run
5. Press `Cmd+U` to run tests

### Troubleshooting

| Issue | Fix |
|-------|-----|
| Build fails on macOS 13 | PostKit requires macOS 14+. Update your Mac. |
| Keychain permission dialog | Click "Always Allow" when prompted during first run. |
| SwiftData migration error | Delete `~/Library/Containers/com.postkit/` and rebuild. |

---

## 3. Project Structure

```
PostKit/
├── PostKit.xcodeproj
├── PostKit/                          # Main app target
│   ├── PostKitApp.swift              # @main entry, SwiftData schema, menu commands
│   ├── PostKit.entitlements          # App Sandbox + network + file access
│   ├── DI/                           # Factory DI container
│   │   ├── Container+Services.swift  # httpClient, keychainManager, fileExporter
│   │   └── Container+Parsers.swift   # curlParser, openAPIParser, variableInterpolator
│   ├── Models/
│   │   ├── RequestCollection.swift   # Top-level collection with cascade relationships
│   │   ├── Folder.swift              # Nested folder within a collection
│   │   ├── HTTPRequest.swift         # Request model with @Transient enum bridging
│   │   ├── APIEnvironment.swift      # Environment with variables, isActive flag
│   │   ├── Variable.swift            # Key-value with Keychain-backed secureValue
│   │   ├── HistoryEntry.swift        # Request execution history record
│   │   └── Enums/
│   │       ├── HTTPMethod.swift      # GET, POST, PUT, etc. with Color mapping
│   │       ├── BodyType.swift        # JSON, XML, form-data, etc. with contentType
│   │       └── AuthType.swift        # Auth types + AuthConfig Keychain integration
│   ├── ViewModels/
│   │   └── RequestViewModel.swift    # @Observable VM: execution, history, auth, interpolation
│   ├── Views/
│   │   ├── ContentView.swift         # NavigationSplitView 3-pane layout
│   │   ├── PostKitCommands.swift     # Menu bar commands (Send, Cancel, Duplicate)
│   │   ├── Sidebar/
│   │   │   ├── CollectionsSidebar.swift
│   │   │   └── CollectionRow.swift
│   │   ├── RequestList/
│   │   │   ├── RequestListView.swift
│   │   │   └── RequestRow.swift
│   │   ├── RequestDetail/
│   │   │   ├── RequestDetailView.swift
│   │   │   ├── RequestEditor/
│   │   │   │   ├── RequestEditorPane.swift
│   │   │   │   └── URLBar.swift
│   │   │   └── ResponseViewer/
│   │   │       └── ResponseViewerPane.swift
│   │   ├── Environment/
│   │   │   └── EnvironmentPicker.swift
│   │   └── Import/
│   │       ├── CurlImportSheet.swift
│   │       └── OpenAPIImportSheet.swift
│   ├── Services/
│   │   ├── CurlHTTPClient.swift      # libcurl-based HTTP client (primary engine)
│   │   ├── HTTPClient.swift          # URLSession fallback client
│   │   ├── CurlParser.swift          # cURL command tokenizer and parser
│   │   ├── OpenAPIParser.swift       # OpenAPI 3.x spec parser
│   │   ├── FileExporter.swift        # JSON export/import with credential redaction
│   │   ├── VariableInterpolator.swift # {{variable}} template engine
│   │   ├── KeychainManager.swift     # macOS Keychain wrapper singleton
│   │   └── Protocols/
│   │       ├── HTTPClientProtocol.swift    # Protocol + HTTPResponse struct
│   │       ├── KeychainManagerProtocol.swift
│   │       ├── CurlParserProtocol.swift
│   │       ├── OpenAPIParserProtocol.swift
│   │       ├── VariableInterpolatorProtocol.swift
│   │       └── FileExporterProtocol.swift
│   └── Utilities/
│       ├── FocusedValues.swift       # FocusedValueKeys for menu commands
│       └── KeyValuePair.swift        # Codable struct for headers/params
├── PostKitTests/
│   ├── PostKitTests.swift            # All unit tests
│   └── Mocks/                        # Mock implementations for Factory-based testing
│       ├── MockHTTPClient.swift
│       └── MockKeychainManager.swift
└── PostKitUITests/
    ├── PostKitUITests.swift
    └── PostKitUITestsLaunchTests.swift
```

### Naming Conventions

| Directory | Contains | Naming Pattern |
|-----------|----------|----------------|
| `Models/` | SwiftData `@Model` classes | Noun (e.g., `HTTPRequest`) |
| `Models/Enums/` | Shared enums and value types | Noun (e.g., `HTTPMethod`, `AuthType`) |
| `ViewModels/` | `@Observable` view models | `*ViewModel` (e.g., `RequestViewModel`) |
| `Views/` | SwiftUI views, grouped by feature | `*View`, `*Pane`, `*Row`, `*Sheet` |
| `Services/` | Business logic, parsing, I/O | Noun (e.g., `CurlParser`, `HTTPClient`) |
| `Utilities/` | Shared helpers, extensions | Descriptive (e.g., `KeyValuePair`) |

---

## 4. Architecture Patterns

### MVVM Overview

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   View       │────▶│   ViewModel      │────▶│   Service        │
│ (SwiftUI)    │     │ (@Observable)    │     │ (Actor/Class)    │
│              │◀────│                  │◀────│                  │
└─────────────┘     └──────────────────┘     └──────────────────┘
       │                     │
       ▼                     ▼
┌─────────────┐     ┌──────────────────┐
│  SwiftData   │     │   Keychain       │
│  (@Model)    │     │   Manager        │
└─────────────┘     └──────────────────┘
```

**Views** are thin rendering layers. They own no business logic beyond simple UI state (e.g., which tab is selected).

**ViewModels** own business logic: building URL requests, applying auth, interpolating variables, saving history.

**Services** handle I/O: HTTP execution, Keychain access, file export, cURL/OpenAPI parsing.

### SwiftData Model Graph

```
RequestCollection
├── folders: [Folder]              (cascade delete)
│   └── requests: [HTTPRequest]    (cascade delete)
├── requests: [HTTPRequest]        (cascade delete)
│   └── history: [HistoryEntry]    (cascade delete)
└── environments: [APIEnvironment] (cascade delete)
    └── variables: [Variable]      (cascade delete)
```

Every relationship uses `.cascade` delete rules. Deleting a collection removes all its folders, requests, environments, variables, and history.

### Dependency Injection via Factory Container

PostKit uses **Factory 2.5.x** (`import FactoryKit`) as the unified dependency injection container. All services are registered in `DI/Container+*.swift` extensions and resolved via the `@Injected` property wrapper.

#### Container Organization

```swift
// DI/Container+Services.swift
extension Container {
    var httpClient: Factory<HTTPClientProtocol> {
        self {
            do { return try CurlHTTPClient() }
            catch { return URLSessionHTTPClient() }
        }.singleton
    }
    
    var keychainManager: Factory<KeychainManagerProtocol> {
        self { KeychainManager.shared }.singleton
    }
    
    @MainActor
    var fileExporter: Factory<FileExporterProtocol> {
        self { @MainActor in FileExporter() }
    }
}

// DI/Container+Parsers.swift
extension Container {
    var curlParser: Factory<CurlParserProtocol> {
        self { CurlParser() }  // .unique (default)
    }
    
    var variableInterpolator: Factory<VariableInterpolatorProtocol> {
        self { VariableInterpolator() }.singleton
    }
}
```

#### MANDATORY Pattern for @Observable Classes

Factory `@Injected` properties **MUST** be marked `@ObservationIgnored` in `@Observable` classes. Without it, the Observation framework tracks dependency resolution as state changes, causing infinite re-render loops or compilation errors.

```swift
@Observable
final class RequestViewModel {
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.variableInterpolator) private var interpolator
}
```

#### Injection in Views

```swift
struct CurlImportSheet: View {
    @Injected(\.curlParser) private var parser
    // ...
}
```

#### Direct Resolution in @Model Types

`@Model` types cannot use property wrappers. Use `Container.shared` direct resolution:

```swift
// In Variable.swift
Container.shared.keychainManager().store(key: keychainKey, value: newValue)
```

#### Testing with Mocks

Use the `.container` trait at `@Suite` level for test isolation:

```swift
import FactoryTesting

@Suite(.container)
struct RequestViewModelTests {
    @Test func executeRequestReturnsResponse() async {
        Container.shared.httpClient.register { MockHTTPClient(response: .success) }
        let vm = RequestViewModel(modelContext: mockModelContext)
        // ...
    }
}
```

#### What Stays as @Environment

- `\.modelContext` — SwiftData's `ModelContext` is not `Sendable` and is lifecycle-managed by SwiftUI

### @Transient Enum Bridging

SwiftData cannot persist Swift enums directly. The pattern used throughout:

```swift
// Stored property (persisted by SwiftData)
var methodRaw: String

// Computed property (not persisted, provides type safety)
@Transient var method: HTTPMethod {
    get { HTTPMethod(rawValue: methodRaw) ?? .get }
    set { methodRaw = newValue.rawValue }
}
```

This pattern appears in `HTTPRequest` (method, bodyType, authConfig) and `HistoryEntry` (method).

---

## 5. Adding a New Feature

This section walks through adding a hypothetical feature: **request tagging** (adding color-coded tags to requests).

### Step 1: Define the Model

Create `PostKit/Models/Tag.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String

    var request: HTTPRequest?

    init(name: String, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}
```

**Checklist:**
- [ ] `@Attribute(.unique)` on `id`
- [ ] Relationship back to parent model
- [ ] `init` sets all required fields

### Step 2: Add the Relationship

In `HTTPRequest.swift`, add:

```swift
@Relationship(deleteRule: .cascade, inverse: \Tag.request)
var tags: [Tag] = []
```

### Step 3: Register in the Schema

In `PostKitApp.swift`, add `Tag.self` to the schema array:

```swift
let schema = Schema([
    RequestCollection.self,
    Folder.self,
    HTTPRequest.self,
    APIEnvironment.self,
    Variable.self,
    HistoryEntry.self,
    Tag.self  // <-- Add here
])
```

### Step 4: Create the View

Create `PostKit/Views/RequestDetail/TagEditor.swift` — a SwiftUI view for managing tags on a request.

### Step 5: Add Tests

In `PostKitTests/PostKitTests.swift`, add a new test struct:

```swift
struct TagTests {
    @Test func createTag() {
        let tag = Tag(name: "Auth", colorHex: "#FF0000")
        #expect(tag.name == "Auth")
        #expect(tag.colorHex == "#FF0000")
    }
}
```

### Step 6: Update Export/Import (if applicable)

If tags should be included in exports, add `ExportedTag` to `FileExporter.swift` and update the export/import logic.

---

## 6. Coding Conventions

### File Organization

Every Swift file follows this order:
1. `import` statements (Apple frameworks first)
2. Type definition (`struct`, `class`, `enum`, `actor`)
3. `// MARK: -` sections for logical grouping

Example from `RequestViewModel.swift`:

```swift
import Foundation
import Observation
import SwiftData

@Observable
final class RequestViewModel {
    // MARK: - UI State
    // MARK: - Dependencies
    // MARK: - History Cleanup
    // MARK: - Init
    // MARK: - Public Methods
    // MARK: - Request Building
    // MARK: - Environment Variables
    // MARK: - Auth
    // MARK: - History
}
```

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| SwiftData model | PascalCase noun | `HTTPRequest`, `Variable` |
| ViewModel | `*ViewModel` | `RequestViewModel` |
| View | `*View`, `*Pane`, `*Row`, `*Sheet`, `*Bar` | `URLBar`, `ResponseViewerPane` |
| Service | PascalCase noun/verb | `CurlParser`, `FileExporter` |
| Protocol | `*Protocol` | `HTTPClientProtocol` |
| Enum | PascalCase noun | `HTTPMethod`, `BodyType` |
| Enum case | camelCase | `.get`, `.post`, `.urlEncoded` |
| Stored property (raw) | `*Raw` suffix for enum backing | `methodRaw`, `bodyTypeRaw` |
| Error enum | `*Error` | `HTTPClientError`, `CurlParserError` |

### Error Handling

All custom errors conform to `LocalizedError` with `errorDescription`:

```swift
enum CurlParserError: LocalizedError {
    case invalidCommand
    case missingURL

    var errorDescription: String? {
        switch self {
        case .invalidCommand: return "Invalid cURL command format"
        case .missingURL: return "No URL found in cURL command"
        }
    }
}
```

### Sendable Conformance

Types shared across concurrency boundaries must be `Sendable`:

| Type | Approach |
|------|----------|
| `HTTPClientProtocol` | Protocol inherits `Sendable` |
| `URLSessionHTTPClient` | `actor` (inherently Sendable) |
| `KeychainManager` | `final class: Sendable` (no mutable state after init) |
| `CurlParser` | `final class: Sendable` (no stored mutable state) |
| `KeyValuePair` | `struct: Sendable` (value type) |
| `HTTPMethod`, `BodyType`, `AuthType` | `enum: Sendable` (value types) |

### Data Encoding Pattern

For arrays of value types stored in SwiftData, use the `KeyValuePair` pattern:

```swift
// Encoding
let pairs = [KeyValuePair(key: "Content-Type", value: "application/json")]
request.headersData = pairs.encode()  // -> Data?

// Decoding
let headers = [KeyValuePair].decode(from: request.headersData)  // -> [KeyValuePair]
```

---

## 7. Security Practices

### Keychain Usage

All sensitive values are stored in the macOS Keychain via `KeychainManager.shared`. The service identifier is `com.postkit.secrets`.

**Key accessibility flag:** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Available only when the device is unlocked
- Never synced to other devices via iCloud Keychain

Two integration points:

#### 1. Environment Variables (`Variable.secureValue`)

```swift
// Reading — transparently falls back to Keychain for secrets
let value = variable.secureValue  // Keychain lookup if isSecret == true

// Writing — stores in Keychain, clears plaintext
variable.secureValue = "sk-abc123"  // Keychain store, value = ""
```

The `secureValue` computed property uses the variable's UUID as the Keychain key: `"variable-\(id.uuidString)"`.

#### 2. Auth Config (`AuthConfig.storeSecrets`)

```swift
// Store auth secrets to Keychain, clear plaintext
var config = request.authConfig
config.storeSecrets(forRequestID: request.id.uuidString)
request.authConfig = config

// Retrieve for request execution
let fullConfig = request.authConfig.retrieveSecrets(forRequestID: request.id.uuidString)
```

Auth secrets use request-scoped Keychain keys:
- `auth-token-{requestID}` for Bearer tokens
- `auth-password-{requestID}` for Basic Auth passwords
- `auth-apikey-{requestID}` for API key values

### Cleanup on Delete

When deleting a request or variable, always clean up Keychain entries:

```swift
// For variables
variable.deleteSecureValue()

// For auth config
AuthConfig.deleteSecrets(forRequestID: request.id.uuidString)
```

### Export Redaction

The `FileExporter` automatically redacts sensitive data on export:

| Data Type | Behavior |
|-----------|----------|
| Authorization header | Value replaced with `"[REDACTED]"` |
| X-API-Key header | Value replaced with `"[REDACTED]"` |
| X-Auth-Token header | Value replaced with `"[REDACTED]"` |
| Proxy-Authorization header | Value replaced with `"[REDACTED]"` |
| Cookie header | Value replaced with `"[REDACTED]"` |
| Secret environment variable | Value exported as empty string `""` |

The full list of sensitive header keys is in `FileExporter.sensitiveHeaderKeys`. Comparison is case-insensitive.

### App Sandbox

PostKit runs in an App Sandbox with three entitlements:

| Entitlement | Purpose |
|-------------|---------|
| `com.apple.security.app-sandbox` | Enable sandboxing |
| `com.apple.security.network.client` | Outgoing HTTP requests |
| `com.apple.security.files.user-selected.read-write` | File import/export via dialogs |

---

## 8. Testing

### Framework: Swift Testing + FactoryTesting

PostKit uses Apple's Swift Testing framework (not XCTest) with FactoryTesting for DI test isolation. Tests are defined as structs with `@Test` functions.

```swift
import Testing
import FactoryKit
import FactoryTesting
@testable import PostKit

@Suite(.container)  // Isolates Factory container for this test suite
struct MyFeatureTests {
    @Test func basicBehavior() {
        let result = myFunction()
        #expect(result == expectedValue)
    }

    @Test func errorCase() {
        #expect(throws: MyError.invalidInput) {
            try myThrowingFunction(invalid: true)
        }
    }
    
    @Test func withMockDependency() async {
        // Register mock for this test
        Container.shared.httpClient.register { MockHTTPClient(response: .success) }
        let vm = RequestViewModel(modelContext: mockModelContext)
        // ...
    }
}
```

### Key Differences from XCTest

| XCTest | Swift Testing |
|--------|--------------|
| `class MyTests: XCTestCase` | `struct MyTests` |
| `func testSomething()` | `@Test func something()` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertThrowsError` | `#expect(throws: ErrorType.self)` |
| `setUp() / tearDown()` | Use `init()` or local setup in each test |

### Test Organization

All tests are in `PostKitTests/`. Tests are grouped by struct:

| Struct | What It Tests | Test Count |
|--------|--------------|------------|
| `CurlParserTests` | cURL command parsing (methods, headers, body, auth) | 18 |
| `VariableInterpolatorTests` | `{{variable}}` interpolation and built-in variables | 14 |
| `KeyValuePairTests` | Encode/decode round-trips, edge cases | 7 |
| `AuthConfigTests` | Auth config serialization and type properties | 10 |
| `OpenAPIParserTests` | OpenAPI 3.x spec parsing | 12 |
| `CurlHTTPClientTests` | HTTP client internals, timing, headers | 25 |
| `RequestViewModelTests` | ViewModel request building, execution, cancellation | 13 |
| `KeychainManagerProtocolTests` | Mock Keychain behavior | 5 |

Mock implementations are in `PostKitTests/Mocks/`:
- `MockHTTPClient` — Actor-based mock for HTTP testing
- `MockKeychainManager` — In-memory Keychain mock for unit tests

### What to Test

| Layer | What to Test | Example |
|-------|-------------|---------|
| Services | Input parsing, output format | `CurlParser.parse("curl ...")` |
| Value types | Encode/decode round-trips | `KeyValuePair` encode → decode |
| Enums | Raw values, display names | `AuthType.bearer.displayName` |
| ViewModel | Request building, auth application | `buildURLRequest(for:)` |

### Running Tests

```bash
# In Xcode
Cmd+U

# From command line (requires xcodebuild)
cd PostKit
xcodebuild test -scheme PostKit -destination 'platform=macOS'
```

---

## 9. Git Workflow

### Branch Naming

```
feat/description     # New features
fix/description      # Bug fixes
docs/description     # Documentation changes
refactor/description # Code restructuring
test/description     # Test additions/changes
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add request tagging with color-coded labels
fix: resolve memory leak in response viewer for large payloads
docs: add ADR for SwiftData migration strategy
refactor: extract auth logic from RequestViewModel
test: add parameterized tests for cURL parser edge cases
```

### Development Phases

PostKit was built in 5 phases, visible in the git history:

| Phase | Focus |
|-------|-------|
| Phase 1 | Core models, SwiftData schema, basic CRUD |
| Phase 2 | HTTP client, request execution, response viewer |
| Phase 3 | Authentication, environments, variable interpolation |
| Phase 4 | Import (cURL, OpenAPI) and export features |
| Phase 5 | Polish, accessibility, keyboard shortcuts, code review fixes |

New features should follow a similar incremental approach: model first, then service, then view, then tests.

---

## 10. Checklists

### New Feature Checklist

- [ ] SwiftData model created with `@Attribute(.unique)` on `id`
- [ ] Relationships use `.cascade` delete rules
- [ ] Model registered in `PostKitApp.swift` schema array
- [ ] Enum properties use `@Transient` computed property pattern
- [ ] Service is `Sendable` if accessed across concurrency boundaries
- [ ] View delegates logic to ViewModel (no business logic in views)
- [ ] Secrets stored in Keychain, not plaintext in SwiftData
- [ ] Export logic redacts sensitive data
- [ ] Tests added for parsing/logic (not just UI)
- [ ] Keyboard shortcut added if it's a primary action

### Pre-Commit Checklist

- [ ] `Cmd+B` builds without warnings
- [ ] `Cmd+U` all tests pass
- [ ] No hardcoded secrets or API keys in source
- [ ] No `print()` statements left in production code
- [ ] Commit message follows conventional format
- [ ] File organization follows project structure conventions

### Security Review Checklist

- [ ] Auth credentials flow through Keychain, not stored in SwiftData
- [ ] `Variable.deleteSecureValue()` called when deleting secret variables
- [ ] `AuthConfig.deleteSecrets(forRequestID:)` called when deleting requests
- [ ] New headers added to `FileExporter.sensitiveHeaderKeys` if sensitive
- [ ] No new entitlements added to sandbox without justification
- [ ] `Sendable` conformance on types shared across concurrency boundaries

---

## Appendix A: Keyboard Shortcuts

| Shortcut | Action | Defined In |
|----------|--------|-----------|
| `Cmd+Return` | Send request | `PostKitCommands.swift` |
| `Cmd+.` | Cancel request | `PostKitCommands.swift` |
| `Cmd+D` | Duplicate request | `PostKitCommands.swift` |
| `Cmd+S` | Save request (update timestamp) | `PostKitCommands.swift` |
| `Cmd+Shift+I` | Import cURL command | `PostKitApp.swift` |
| `Cmd+Shift+O` | Import OpenAPI specification | `PostKitApp.swift` |
| `Cmd+Option+I` | Import collection from JSON | `PostKitApp.swift` |
| `Ctrl+Tab` | Cycle focus between panes | `ContentView.swift` |

Shortcuts are implemented via two mechanisms:
1. **`PostKitCommands`** — Custom `Commands` struct using `@FocusedValue` to bridge menu actions to the active view
2. **`PostKitApp.body`** — `CommandGroup(after: .newItem)` for import actions

---

## Appendix B: Key File Reference

| # | File | Purpose |
|---|------|---------|
| 1 | `PostKitApp.swift` | App entry point, SwiftData schema, import menus, singleton force-resolution |
| 2 | `PostKit.entitlements` | App Sandbox configuration |
| 3 | `DI/Container+Services.swift` | Factory registrations: httpClient, keychainManager, fileExporter |
| 4 | `DI/Container+Parsers.swift` | Factory registrations: curlParser, openAPIParser, variableInterpolator |
| 5 | `Models/RequestCollection.swift` | Top-level collection with cascade relationships |
| 6 | `Models/Folder.swift` | Folder within a collection |
| 7 | `Models/HTTPRequest.swift` | Request model, @Transient enum bridging, authConfig caching |
| 8 | `Models/APIEnvironment.swift` | Environment with isActive flag |
| 9 | `Models/Variable.swift` | Key-value with Keychain-backed secureValue, Factory resolution |
| 10 | `Models/HistoryEntry.swift` | Execution history record |
| 11 | `Models/Enums/HTTPMethod.swift` | HTTP methods with color mapping |
| 12 | `Models/Enums/BodyType.swift` | Body types with contentType mapping |
| 13 | `Models/Enums/AuthType.swift` | Auth types, AuthConfig, Keychain integration via Factory |
| 14 | `ViewModels/RequestViewModel.swift` | @Observable VM with @ObservationIgnored @Injected deps |
| 15 | `Views/ContentView.swift` | NavigationSplitView 3-pane layout |
| 16 | `Views/PostKitCommands.swift` | Menu bar keyboard shortcuts |
| 17 | `Views/Sidebar/CollectionsSidebar.swift` | Collection list with CRUD |
| 18 | `Views/Sidebar/CollectionRow.swift` | Single collection row with Keychain cleanup |
| 19 | `Views/RequestList/RequestListView.swift` | Request list with Keychain cleanup on delete |
| 20 | `Views/RequestList/RequestRow.swift` | Single request row (method badge + name) |
| 21 | `Views/RequestDetail/RequestDetailView.swift` | Request editor + response viewer split |
| 22 | `Views/RequestDetail/RequestEditor/RequestEditorPane.swift` | Headers, params, body, auth tabs |
| 23 | `Views/RequestDetail/RequestEditor/URLBar.swift` | Method picker + URL field + Send button |
| 24 | `Views/RequestDetail/ResponseViewer/ResponseViewerPane.swift` | Body, headers, timing tabs |
| 25 | `Views/Environment/EnvironmentPicker.swift` | Toolbar environment selector, Keychain cleanup |
| 26 | `Views/Import/CurlImportSheet.swift` | cURL paste-and-import with @Injected parser |
| 27 | `Views/Import/OpenAPIImportSheet.swift` | OpenAPI file picker with @Injected parser |
| 28 | `Services/CurlHTTPClient.swift` | libcurl-based HTTP client (primary engine) |
| 29 | `Services/HTTPClient.swift` | URLSession fallback client |
| 30 | `Services/CurlParser.swift` | cURL command tokenizer and parser |
| 31 | `Services/OpenAPIParser.swift` | OpenAPI 3.x spec parser |
| 32 | `Services/FileExporter.swift` | JSON export with redaction, import |
| 33 | `Services/VariableInterpolator.swift` | `{{variable}}` template engine |
| 34 | `Services/KeychainManager.swift` | macOS Keychain CRUD wrapper singleton |
| 35 | `Services/Protocols/HTTPClientProtocol.swift` | Protocol + HTTPResponse struct |
| 36 | `Services/Protocols/KeychainManagerProtocol.swift` | Keychain protocol with extension defaults |
| 37 | `Services/Protocols/CurlParserProtocol.swift` | cURL parser protocol |
| 38 | `Services/Protocols/OpenAPIParserProtocol.swift` | OpenAPI parser protocol |
| 39 | `Services/Protocols/VariableInterpolatorProtocol.swift` | Interpolator protocol |
| 40 | `Services/Protocols/FileExporterProtocol.swift` | File exporter protocol |
| 41 | `Utilities/FocusedValues.swift` | FocusedValueKeys for menu-to-view bridging |
| 42 | `Utilities/KeyValuePair.swift` | Codable struct for headers/params with encode/decode |
| 43 | `PostKitTests/PostKitTests.swift` | All unit tests (8 test suites, 104+ tests) |
| 44 | `PostKitTests/Mocks/MockHTTPClient.swift` | Actor-based HTTP mock for testing |
| 45 | `PostKitTests/Mocks/MockKeychainManager.swift` | In-memory Keychain mock for testing |
| 46 | `PostKitUITests/PostKitUITests.swift` | UI test placeholder |

> **Note:** All file paths are relative to `PostKit/PostKit/` (the Xcode source target root).

---

## Revision History

| Date | Change |
|------|--------|
| 2026-02-13 | Initial developer guide for PostKit MVP |
| 2026-02-14 | Updated for Factory DI container, libcurl HTTP client, added ViewModel tests |
