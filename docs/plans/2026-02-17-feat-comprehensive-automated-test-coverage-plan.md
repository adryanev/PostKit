---
title: "feat: Comprehensive Automated Test Coverage"
type: feat
status: active
date: 2026-02-17
brainstorm: docs/brainstorms/2026-02-17-automated-test-coverage-brainstorm.md
---

# Comprehensive Automated Test Coverage

## Overview

Eliminate manual testing of PostKit by building comprehensive automated test coverage across three layers: mock foundation, unit/integration tests, and UI tests. The approach is bottom-up — mocks first, then service tests, then ViewModel tests, then XCUITests — so each layer builds on a stable foundation.

**Current state:** 185 tests across 13 test structs, 2 mocks. Well-tested parsers and utilities, but zero tests for importers, FileExporter, RequestBuilder, and OpenAPIImportViewModel.

**Target state:** ~350+ tests covering all services, ViewModels, and key UI flows with 7 new mock implementations.

## Problem Statement

PostKit has solid test coverage for parsers and utilities but significant gaps in:

1. **Import services** (PostmanImporter, OpenAPIImporter) — complex logic with auth mapping, body mode conversion, folder management, and secret handling — all untested
2. **FileExporter** — sensitive header redaction and import/export logic — untested
3. **RequestBuilder** — shared URL building logic with auth and interpolation — only indirectly tested
4. **OpenAPIImportViewModel** — multi-step wizard with navigation state, parsing, diffing — untested
5. **UI flows** — no automated tests for any user-facing workflow

Every change to these components requires manual testing, which is slow, error-prone, and doesn't scale.

## Technical Approach

### Architecture

The bottom-up approach leverages PostKit's existing Factory DI infrastructure:

```
Phase 1: Mock Foundation (7 new mocks)
    ↓
Phase 2: Service Unit Tests (PostmanImporter, FileExporter, OpenAPIImporter, RequestBuilder)
    ↓
Phase 3: ViewModel Tests (OpenAPIImportViewModel, RequestViewModel expansion)
    ↓
Phase 4: XCUITest (core request flow, imports, environments)
```

### Critical Blockers to Address

The SpecFlow analysis identified 4 items that must be addressed before or during implementation:

1. **FileExporter.exportCollection()** — serialization logic is entangled with `NSSavePanel.runModal()`. Must extract serialization into a testable method.
2. **OpenAPIImportViewModel** — hard-codes `OpenAPIParser()` and `OpenAPIDiffEngine()` directly. Needs DI injection. Also, `parseFile()` reads from disk and creates an untracked `Task` — needs a `parseData()` method and exposed task reference.
3. **XCUITest file dialogs** — Import UI flows use `NSOpenPanel.runModal()` which XCUITest cannot drive. Need launch-argument-based test data injection.
4. **Zero accessibility identifiers** — XCUITest cannot locate UI elements without them. Must add to ~15-20 view files.

### Implementation Phases

---

#### Phase 1: Mock Foundation

Create 7 mock implementations following existing patterns from `MockHTTPClient` and `MockKeychainManager`.

**Pattern to follow:**
- Actor mocks for actor protocols, `final class @unchecked Sendable` for class protocols
- Configurable return values (result to return, error to throw)
- Call tracking (call counts, last arguments)
- `reset()` method for state cleanup

##### Phase 1 Tasks

**1.1 Create `MockFileExporter`**

File: `PostKit/PostKitTests/Mocks/MockFileExporter.swift`

```swift
@MainActor
final class MockFileExporter: FileExporterProtocol, @unchecked Sendable {
    var exportResult: URL?
    var exportError: Error?
    var importResult: RequestCollection?
    var importError: Error?
    var exportCallCount = 0
    var importCallCount = 0
    var lastExportedCollection: RequestCollection?
    var lastImportURL: URL?

    func exportCollection(_ collection: RequestCollection) throws -> URL { ... }
    func importCollection(from url: URL, into context: ModelContext) throws -> RequestCollection { ... }
    func reset() { ... }
}
```

**1.2 Create `MockScriptEngine`**

File: `PostKit/PostKitTests/Mocks/MockScriptEngine.swift`

```swift
final class MockScriptEngine: ScriptEngineProtocol, @unchecked Sendable {
    var preRequestResult: ScriptPreRequestResult?
    var postRequestResult: ScriptPostRequestResult?
    var preRequestError: Error?
    var postRequestError: Error?
    var executePreRequestCallCount = 0
    var executePostRequestCallCount = 0

    func executePreRequest(script:request:environment:) async throws -> ScriptPreRequestResult { ... }
    func executePostRequest(script:response:environment:) async throws -> ScriptPostRequestResult { ... }
    func reset() { ... }
}
```

**1.3 Create `MockSpotlightIndexer`**

File: `PostKit/PostKitTests/Mocks/MockSpotlightIndexer.swift`

```swift
final class MockSpotlightIndexer: SpotlightIndexerProtocol, @unchecked Sendable {
    var indexCallCount = 0
    var deindexCallCount = 0
    var deindexBatchCallCount = 0
    var reindexAllCallCount = 0
    var lastIndexedRequestID: UUID?

    func indexRequest(_ request: HTTPRequest, collectionName: String?, folderName: String?) async { ... }
    func deindexRequest(id: UUID) async { ... }
    func deindexRequests(ids: [UUID]) async { ... }
    func reindexAll(requests: [HTTPRequest]) async { ... }
    func reset() { ... }
}
```

**1.4 Create `MockCurlParser`**

File: `PostKit/PostKitTests/Mocks/MockCurlParser.swift`

```swift
final class MockCurlParser: CurlParserProtocol, @unchecked Sendable {
    var resultToReturn: ParsedRequest?
    var errorToThrow: Error?
    var parseCallCount = 0
    var lastInput: String?

    func parse(_ curlCommand: String) throws -> ParsedRequest { ... }
    func reset() { ... }
}
```

**1.5 Create `MockOpenAPIParser`**

File: `PostKit/PostKitTests/Mocks/MockOpenAPIParser.swift`

```swift
final class MockOpenAPIParser: OpenAPIParserProtocol, @unchecked Sendable {
    var resultToReturn: (info: OpenAPIInfo, endpoints: [OpenAPIEndpoint], servers: [String])?
    var errorToThrow: Error?
    var parseCallCount = 0

    func parse(_ data: Data) throws -> (info: OpenAPIInfo, endpoints: [OpenAPIEndpoint], servers: [String]) { ... }
    func reset() { ... }
}
```

**1.6 Create `MockPostmanParser`**

File: `PostKit/PostKitTests/Mocks/MockPostmanParser.swift`

```swift
final class MockPostmanParser: PostmanParserProtocol, @unchecked Sendable {
    var collectionToReturn: PostmanCollection?
    var environmentToReturn: PostmanEnvironment?
    var parseError: Error?
    var parseEnvError: Error?
    var parseCallCount = 0
    var parseEnvironmentCallCount = 0

    func parse(_ data: Data) throws -> PostmanCollection { ... }
    func parseEnvironment(_ data: Data) throws -> PostmanEnvironment { ... }
    func reset() { ... }
}
```

**1.7 Create `MockVariableInterpolator`**

File: `PostKit/PostKitTests/Mocks/MockVariableInterpolator.swift`

```swift
final class MockVariableInterpolator: VariableInterpolatorProtocol, @unchecked Sendable {
    var shouldPassthrough = true
    var resultToReturn: String?
    var errorToThrow: Error?
    var interpolateCallCount = 0
    var lastTemplate: String?
    var lastVariables: [String: String]?

    func interpolate(_ template: String, with variables: [String: String]) throws -> String { ... }
    func reset() { ... }
}
```

**1.8 Create shared test helper for in-memory SwiftData**

File: `PostKit/PostKitTests/Helpers/TestModelContainer.swift`

Currently the 6-model schema + `isStoredInMemoryOnly` setup is duplicated ~13 times. Extract into a shared helper:

```swift
import SwiftData
@testable import PostKit

enum TestModelContainer {
    static func create() throws -> ModelContainer {
        let schema = Schema([
            RequestCollection.self,
            Folder.self,
            HTTPRequest.self,
            APIEnvironment.self,
            Variable.self,
            HistoryEntry.self,
            ResponseExample.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
```

Note: Add `ResponseExample.self` which is currently missing from the test schema but exists in the model graph.

---

#### Phase 2: Service Unit Tests

Add test suites for all untested services. Tests go in `PostKit/PostKitTests/PostKitTests.swift` following the existing pattern.

##### Phase 2 Tasks

**2.1 PostmanImporter Tests**

```swift
// MARK: - PostmanImporter Tests
@Suite(.serialized)
@MainActor
struct PostmanImporterTests {
    // MARK: - Positive Cases
    // - previewCollection returns correct counts
    // - importCollection creates RequestCollection with correct name
    // - importCollection creates folders for nested items
    // - importCollection maps bearer auth correctly
    // - importCollection maps basic auth correctly
    // - importCollection maps API key auth correctly
    // - importCollection handles raw body (JSON detection)
    // - importCollection handles raw body (XML detection)
    // - importCollection handles urlencoded body with percent-encoding
    // - importCollection handles formdata body
    // - importCollection handles graphql body
    // - importCollection extracts pre-request scripts
    // - importCollection extracts post-request scripts (test events)
    // - importCollection creates environment from collection variables
    // - importEnvironment creates variables with secretKeys handling
    // - importCollection handles query params from structured URL
    // - importCollection sets headers from Postman headers

    // MARK: - Negative Cases
    // - previewCollection throws on invalid data (parseError)
    // - importCollection throws on invalid data (parseError)
    // - importEnvironment throws on invalid data
    // - importCollection handles request with no body gracefully
    // - importCollection handles request with no auth gracefully
    // - importCollection handles unknown auth type gracefully

    // MARK: - Edge Cases
    // - importCollection respects maxFolderDepth=2 (flattens deep nesting)
    // - importCollection handles empty collection (zero items)
    // - importCollection handles items with empty names
    // - importCollection deduplicates folder names via cache
    // - importCollection handles secret variables (stores via Keychain)
    // - importEnvironment with empty secretKeys set
    // - previewCollection counts scripts correctly (only prerequest/test events)
}
```

**Keychain mock requirement:** Tests involving `isSecret` variables or auth config `storeSecrets` call must have `MockKeychainManager` registered in Factory BEFORE creating SwiftData models that trigger Keychain access:

```swift
Container.shared.manager.push()
defer { Container.shared.manager.pop() }
Container.shared.keychainManager.register { MockKeychainManager() }
```

**2.2 FileExporter Tests**

**Prerequisite refactor:** Extract serialization logic from `FileExporter.exportCollection()` into a testable method. The current implementation mixes data serialization with `NSSavePanel` UI. Refactor into:

```swift
// New testable method in FileExporter.swift
func serializeCollection(_ collection: RequestCollection) throws -> Data {
    // Move lines 56-104 here (everything before NSSavePanel)
    ...
}

func exportCollection(_ collection: RequestCollection) throws -> URL {
    let data = try serializeCollection(collection)
    // NSSavePanel code stays here
    ...
}
```

Then add import round-trip testing via the existing `importCollection(from:into:)` which reads from a URL (can use temp files):

```swift
// MARK: - FileExporter Tests
@Suite(.serialized)
@MainActor
struct FileExporterTests {
    // MARK: - Positive Cases
    // - serializeCollection produces valid JSON
    // - serializeCollection includes all requests with correct fields
    // - serializeCollection includes environments with variables
    // - importCollection creates RequestCollection with correct name
    // - importCollection creates requests with correct method/URL/headers/body
    // - importCollection creates environments with variables
    // - round-trip: serialize then import preserves data

    // MARK: - Negative Cases
    // - importCollection throws on invalid JSON data
    // - importCollection skips requests with unknown HTTP method
    // - importCollection handles missing optional fields

    // MARK: - Edge Cases
    // - serializeCollection redacts sensitive headers (authorization, x-api-key, etc.)
    // - serializeCollection exports secret variables with empty values
    // - serializeCollection handles empty collection (no requests, no environments)
    // - importCollection handles collection with empty request list
    // - serializeCollection produces sorted/pretty JSON
    // - serializeCollection handles requests with openAPI metadata
}
```

**2.3 OpenAPIImporter Tests**

```swift
// MARK: - OpenAPIImporter Tests
@Suite(.serialized)
@MainActor
struct OpenAPIImporterTests {
    // MARK: - Positive Cases
    // - importNewCollection creates collection with spec title
    // - importNewCollection creates requests from selected endpoints
    // - importNewCollection sets URL as serverURL + path
    // - importNewCollection maps header parameters
    // - importNewCollection maps query parameters
    // - importNewCollection maps request body content type
    // - importNewCollection creates folders from tags
    // - importNewCollection creates environments from servers
    // - importNewCollection sets server variables
    // - importNewCollection applies security schemes (bearer, basic, apiKey)
    // - updateCollection adds new endpoints
    // - updateCollection replaces existing endpoints
    // - updateCollection deletes endpoints
    // - updateCollection keeps existing endpoints unchanged
    // - updateCollection cleans up empty folders

    // MARK: - Negative Cases
    // - importNewCollection with empty selectedEndpoints creates empty collection
    // - importNewCollection with empty serverURL uses path only
    // - updateCollection with no decisions makes no changes

    // MARK: - Edge Cases
    // - importNewCollection deduplicates folder names
    // - importNewCollection with endpoint having no tags (no folder)
    // - updateCollection preserves original method and sort order on replace
    // - importNewCollection maps unsupported security scheme type
    // - mapContentTypeToBodyType handles all content type variations
}
```

**2.4 RequestBuilder Tests**

```swift
// MARK: - RequestBuilder Tests
@Suite(.serialized)
@MainActor
struct RequestBuilderTests {
    // MARK: - Positive Cases
    // - buildURLRequest creates request with correct URL
    // - buildURLRequest sets HTTP method
    // - buildURLRequest applies enabled headers with interpolation
    // - buildURLRequest applies enabled query params with interpolation
    // - buildURLRequest sets JSON body with Content-Type
    // - buildURLRequest sets URL-encoded body
    // - buildURLRequest sets XML body
    // - buildURLRequest interpolates URL template with variables
    // - buildURLRequest respects urlOverride parameter
    // - buildURLRequest respects bodyOverride parameter
    // - applyAuth sets Bearer token header
    // - applyAuth sets Basic auth header (base64)
    // - applyAuth sets API key as header
    // - applyAuth adds API key as query param
    // - getActiveEnvironmentVariables returns enabled variables from active environment

    // MARK: - Negative Cases
    // - buildURLRequest throws invalidURL for malformed URL
    // - buildURLRequest throws when interpolation fails
    // - getActiveEnvironmentVariables returns empty when no active environment

    // MARK: - Edge Cases
    // - buildURLRequest skips disabled headers
    // - buildURLRequest skips disabled query params
    // - buildURLRequest with nil bodyContent produces no httpBody
    // - buildURLRequest with formData bodyType skips httpBody
    // - applyAuth with none type adds no auth header
    // - applyAuth with bearer but nil token adds no header
    // - applyAuth with basic but nil username/password adds no header
    // - getActiveEnvironmentVariables returns secureValue for secret variables
}
```

**DI requirement:** RequestBuilder uses `@Injected(\.variableInterpolator)`. Tests need:

```swift
Container.shared.manager.push()
defer { Container.shared.manager.pop() }
Container.shared.variableInterpolator.register { MockVariableInterpolator() }
let builder = RequestBuilder()
```

---

#### Phase 3: ViewModel Tests

##### Phase 3 Tasks

**3.1 OpenAPIImportViewModel — Prerequisite Refactoring**

Before testing, refactor `OpenAPIImportViewModel` for testability:

1. **Inject dependencies via Factory DI** instead of hard-coded `OpenAPIParser()` and `OpenAPIDiffEngine()`:

```swift
// In OpenAPIImportViewModel.swift
@ObservationIgnored @Injected(\.openAPIParser) private var parser
// Note: OpenAPIDiffEngine has no protocol yet — create one or inject directly
private let diffEngine: OpenAPIDiffEngine
```

Since `OpenAPIDiffEngine` has no protocol, either:
- **(Simpler)** Accept it as an `init` parameter with a default value: `init(diffEngine: OpenAPIDiffEngine = OpenAPIDiffEngine())`
- **(Fuller)** Create an `OpenAPIDiffEngineProtocol` and Factory registration

Recommended: init parameter (simpler, YAGNI — the diff engine is already well-tested directly).

2. **Add a `parseData(_:)` method** that accepts `Data` directly, so tests don't need file I/O:

```swift
func parseData(_ data: Data) {
    // Move parsing logic from parseFile(at:), skip Data(contentsOf:)
}
```

3. **Expose the parse Task** so tests can await completion:

```swift
private(set) var parseTask: Task<Void, Never>?
```

4. **Add `performImport` with injected importer** or accept via init parameter.

**3.2 OpenAPIImportViewModel Tests**

```swift
// MARK: - OpenAPIImportViewModel Tests
@Suite(.serialized)
@MainActor
struct OpenAPIImportViewModelTests {
    // MARK: - Positive Cases
    // - initial state is fileSelect step
    // - parseData sets spec and selectedEndpoints
    // - parseData sets selectedServer to first server
    // - parseData sets refSkipWarning when refSkipCount > 0
    // - goNext advances from fileSelect to target
    // - goNext advances from target to configure
    // - goNext from configure triggers runDiff in update mode
    // - goBack moves from configure to target
    // - selectAllEndpoints selects all
    // - deselectAllEndpoints clears selection
    // - runDiff populates diffResult and endpointDecisions
    // - setDecision updates endpointDecisions map
    // - performImport creates new collection (createNew mode)
    // - performImport updates existing collection (updateExisting mode)
    // - loadCollections fetches from ModelContext
    // - reset clears all state

    // MARK: - Negative Cases
    // - parseData sets parseError on invalid data
    // - goNext does nothing when canGoNext is false
    // - goBack does nothing on fileSelect step
    // - performImport does nothing when spec is nil
    // - runDiff does nothing when not in update mode

    // MARK: - Edge Cases
    // - canGoNext requires spec != nil on fileSelect
    // - canGoNext requires non-empty selectedEndpoints on configure
    // - effectiveLastStep is configure for createNew, conflicts for updateExisting
    // - isLastStep correctly identifies last step per mode
    // - isUpdateMode returns true only for updateExisting
}
```

**3.3 Expand RequestViewModel Tests**

Add tests for currently untested flows:

```swift
// Additional tests in existing RequestViewModelTests
// MARK: - Script Integration
// - sendRequest executes pre-request script when present
// - sendRequest applies script URL/body overrides
// - sendRequest executes post-request script after response
// - sendRequest handles pre-request script failure

// MARK: - Spotlight Integration
// - sendRequest indexes successful requests via SpotlightIndexer
```

DI requirement: Register `MockScriptEngine` and `MockSpotlightIndexer` alongside `MockHTTPClient`.

---

#### Phase 4: XCUITest

##### Phase 4 Prerequisites

**4.1 Add Accessibility Identifiers**

Add `.accessibilityIdentifier()` to key UI elements across these view files:

| View File | Elements to Identify |
|---|---|
| `Views/Sidebar/SidebarView.swift` | Collection list, add collection button, collection rows |
| `Views/RequestList/RequestListView.swift` | Request list, add request button, request rows |
| `Views/RequestDetail/RequestDetailView.swift` | URL field, method picker, send button, response area |
| `Views/RequestDetail/HeadersView.swift` | Headers table, add header button |
| `Views/RequestDetail/BodyView.swift` | Body type picker, body editor |
| `Views/RequestDetail/QueryParamsView.swift` | Query params table |
| `Views/RequestDetail/ResponseView.swift` | Status code label, response body, timing info |
| `Views/Environment/EnvironmentView.swift` | Environment list, add environment button |
| `Views/Environment/VariableRow.swift` | Variable key/value fields, enabled toggle |
| `Views/Import/PostmanImportSheet.swift` | Import button, file picker area |
| `Views/Import/OpenAPIImportSheet.swift` | Import wizard steps, next/back buttons |
| `Views/MenuBar/MenuBarView.swift` | Menu bar items |

**Naming convention:** `"postkit.<area>.<element>"` — e.g., `"postkit.sidebar.addCollection"`, `"postkit.request.urlField"`, `"postkit.request.sendButton"`

**4.2 Test Data Injection via Launch Arguments**

For XCUITests that need pre-populated data (import tests, environment tests), add launch argument handling in `PostKitApp.swift`:

```swift
#if DEBUG
if CommandLine.arguments.contains("--uitesting") {
    // Use in-memory SwiftData store
    // Pre-populate test collections/requests if specific flags are present
}
if CommandLine.arguments.contains("--seed-test-data") {
    // Insert sample collection with requests
}
if let testFilePath = CommandLine.arguments.first(where: { $0.hasPrefix("--import-file=") }) {
    // Auto-import a test file on launch (bypasses NSOpenPanel)
}
#endif
```

**4.3 Bypass NSOpenPanel for Testing**

For import flows, add a `#if DEBUG` path that reads from a bundled test file instead of showing NSOpenPanel:

```swift
// In PostmanImportSheet.swift / OpenAPIImportSheet.swift
#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--uitesting") {
    // Load from test bundle instead of NSOpenPanel
    if let testURL = Bundle.main.url(forResource: "test-collection", withExtension: "json") {
        handleFile(testURL)
        return
    }
}
#endif
```

##### Phase 4 Tasks

**4.4 Core Request Flow Tests**

File: `PostKit/PostKitUITests/PostKitUITests.swift`

```swift
final class CoreRequestFlowTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--seed-test-data"]
        app.launch()
    }

    // - testCreateNewCollection
    // - testCreateNewRequest
    // - testEditRequestURL
    // - testChangeHTTPMethod
    // - testAddHeader
    // - testSetRequestBody
    // - testSendRequestAndViewResponse
    // - testResponseDisplaysStatusCode
    // - testHistoryEntryCreated
}
```

**4.5 Import Flow Tests**

File: `PostKit/PostKitUITests/ImportFlowTests.swift`

```swift
final class ImportFlowTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // - testPostmanImportCreatesCollection
    // - testPostmanImportShowsPreview
    // - testOpenAPIImportWizardNavigation
    // - testOpenAPIImportCreatesCollectionWithEndpoints
}
```

**4.6 Environment Management Tests**

File: `PostKit/PostKitUITests/EnvironmentTests.swift`

```swift
final class EnvironmentTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--seed-test-data"]
        app.launch()
    }

    // - testCreateNewEnvironment
    // - testAddVariableToEnvironment
    // - testSwitchActiveEnvironment
    // - testVariableInterpolationInRequest
    // - testDeleteEnvironment
}
```

**4.7 Add Test Data Files to UI Test Bundle**

Add bundled test files for import tests:
- `PostKit/PostKitUITests/TestData/test-postman-collection.json` — minimal Postman v2.1 collection
- `PostKit/PostKitUITests/TestData/test-openapi-spec.json` — minimal OpenAPI 3.0 spec

## Acceptance Criteria

### Functional Requirements

- [ ] All 7 mock implementations created and working
- [ ] Shared `TestModelContainer` helper extracted and used everywhere
- [ ] PostmanImporter test suite with positive, negative, and edge cases (~25 tests)
- [ ] FileExporter test suite with serialization extracted and tested (~15 tests)
- [ ] OpenAPIImporter test suite (~20 tests)
- [ ] RequestBuilder test suite (~25 tests)
- [ ] OpenAPIImportViewModel test suite (~25 tests)
- [ ] RequestViewModel expanded with script/spotlight tests (~5 tests)
- [ ] Accessibility identifiers added to all key UI elements
- [ ] XCUITest core request flow tests (~9 tests)
- [ ] XCUITest import flow tests (~4 tests)
- [ ] XCUITest environment management tests (~5 tests)
- [ ] All existing 185 tests still pass

### Non-Functional Requirements

- [ ] All unit tests run in < 10 seconds total
- [ ] UI tests run in < 60 seconds total
- [ ] No flaky tests (all deterministic, no real network/disk dependencies)
- [ ] Tests follow existing project conventions (Swift Testing, MARK sections, positive/negative/edge structure)

### Quality Gates

- [ ] `xcodebuild test -scheme PostKit -destination 'platform=macOS'` passes all tests
- [ ] No `#if DEBUG` code in production paths (only in test setup helpers)
- [ ] All mocks have `reset()` methods for isolation
- [ ] Factory push/pop used in every test that registers mocks

## Dependencies & Prerequisites

| Dependency | Phase | Notes |
|---|---|---|
| Extract `FileExporter.serializeCollection()` | Phase 2 | Minor refactor, no behavior change |
| Refactor `OpenAPIImportViewModel` for DI | Phase 3 | Add init parameter for diffEngine, inject parser via Factory, add `parseData()` method |
| Add accessibility identifiers | Phase 4 | Touches ~15 view files, non-breaking |
| Add `#if DEBUG` test data injection | Phase 4 | In PostKitApp.swift and import sheets |

## Risk Analysis & Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| `@MainActor` services require serialized tests | Slower test execution | Use `@Suite(.serialized)` only where needed; keep pure logic tests unserialized |
| SwiftData in-memory container may behave differently from persistent | False positives | Test critical persistence paths with assertions on context.save() |
| Keychain access in model setters during tests | Test failures/crashes | Always register `MockKeychainManager` before creating models with secrets |
| XCUITest macOS element lookup fragility | Flaky UI tests | Use consistent accessibility identifiers, not element hierarchies |
| Large PR scope | Review difficulty | Split into 4 PRs (one per phase), each independently mergeable |

## Recommended PR Split

1. **PR 1: Mock Foundation** (Phase 1) — 7 mock files + TestModelContainer helper
2. **PR 2: Service Tests** (Phase 2) — Tests + FileExporter refactor
3. **PR 3: ViewModel Tests** (Phase 3) — Tests + OpenAPIImportViewModel refactor
4. **PR 4: UI Tests** (Phase 4) — Accessibility identifiers + XCUITests + test data injection

Each PR is independently mergeable and valuable on its own.

## References & Research

### Internal References

- Testing standards: `docs/sop/testing-standards.md`
- ADR document: `docs/adr/0001-postkit-architecture-decisions.md`
- Brainstorm: `docs/brainstorms/2026-02-17-automated-test-coverage-brainstorm.md`
- Existing mocks: `PostKit/PostKitTests/Mocks/MockHTTPClient.swift`, `MockKeychainManager.swift`
- Existing tests: `PostKit/PostKitTests/PostKitTests.swift`
- DI containers: `PostKit/PostKit/DI/Container+Services.swift`, `Container+Parsers.swift`
- Factory DI + @Observable gotcha: `docs/solutions/integration-issues/infinite-rerender-factory-di-20260214.md`

### Key File Locations

| File | Purpose | Lines |
|---|---|---|
| `Services/PostmanImporter.swift` | Postman import with auth/body/folder logic | 426 lines |
| `Services/FileExporter.swift` | Export with header redaction, import | 193 lines |
| `Services/OpenAPIImporter.swift` | OpenAPI spec import and update | 262 lines |
| `Services/RequestBuilder.swift` | Shared URL building with interpolation and auth | 141 lines |
| `ViewModels/OpenAPIImportViewModel.swift` | Multi-step import wizard | 256 lines |
| `PostKitUITests/PostKitUITests.swift` | Boilerplate XCUITest (to be replaced) | 42 lines |
