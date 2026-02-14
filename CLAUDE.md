# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PostKit is a native macOS HTTP client (like Postman/Insomnia) built with SwiftUI and SwiftData. Minimal external dependencies — prefer Apple frameworks, third-party packages allowed when justified (see ADR-003).

- **Min macOS:** 14.0 (Sonoma) | **Min Xcode:** 16.0
- **Architecture:** MVVM with `@Observable` ViewModels
- **Persistence:** SwiftData (`@Model`, `@Query`)
- **HTTP Engine:** Actor-based `CurlHTTPClient` with `URLSessionHTTPClient` fallback
- **DI Container:** Factory 2.5.x (`import FactoryKit`)
- **Secrets:** macOS Keychain via `KeychainManager` wrapped in Factory
- **Testing:** Swift Testing framework (`@Test`, `#expect`) with FactoryTesting `.container` trait

## Build & Test Commands

The Xcode project lives in `PostKit/PostKit.xcodeproj` (not the repo root).

```bash
# Build
cd PostKit && xcodebuild build -scheme PostKit -destination 'platform=macOS'

# Run all tests
cd PostKit && xcodebuild test -scheme PostKit -destination 'platform=macOS'

# Open in Xcode
open PostKit/PostKit.xcodeproj
```

In Xcode: `Cmd+B` build, `Cmd+R` run, `Cmd+U` test.

## Architecture

### Three-layer MVVM

```
View (SwiftUI) → ViewModel (@Observable) → Service (Actor/Class)
     ↓                    ↓
  SwiftData           Keychain
```

Views are thin rendering layers. ViewModels own business logic. Services handle I/O.

### SwiftData Model Graph

All relationships use `.cascade` delete rules:

```
RequestCollection
├── folders: [Folder] → requests: [HTTPRequest] → history: [HistoryEntry]
├── requests: [HTTPRequest] → history: [HistoryEntry]
└── environments: [APIEnvironment] → variables: [Variable]
```

All 6 model types must be registered in `PostKitApp.swift` schema array.

### Dependency Injection

PostKit uses Factory 2.5.x as the unified DI container (`import FactoryKit`). All services are registered in `DI/Container+*.swift` extensions and resolved via `@Injected` property wrapper.

**Container Organization:**
- `DI/Container+Services.swift` — httpClient, keychainManager, fileExporter
- `DI/Container+Parsers.swift` — curlParser, openAPIParser, variableInterpolator

**Mandatory Pattern for @Observable Classes:**

Factory `@Injected` properties MUST be marked `@ObservationIgnored` in `@Observable` classes. Without it, the Observation framework tracks dependency resolution as state changes, causing infinite re-render loops or compilation errors.

```swift
@Observable
final class RequestViewModel {
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.variableInterpolator) private var interpolator
}
```

**SwiftData @Model Types:**

`@Model` types cannot use property wrappers. Use `Container.shared` direct resolution:

```swift
// In Variable.swift
Container.shared.keychainManager().store(key: keychainKey, value: newValue)
```

**Testing with Mocks:**

Use the `.container` trait at `@Suite` level for test isolation:

```swift
@Suite(.container)
struct RequestViewModelTests {
    @Test func executeRequestReturnsResponse() async {
        Container.shared.httpClient.register { MockHTTPClient(response: .success) }
        let vm = RequestViewModel(modelContext: mockModelContext)
        // ...
    }
}
```

**What stays as @Environment:**
- `\.modelContext` — SwiftData's `ModelContext` is not `Sendable` and is lifecycle-managed by SwiftUI

## Key Patterns

### @Transient Enum Bridging (used in all models with enums)

SwiftData can't persist Swift enums. Store as `String` raw property, expose via `@Transient` computed property:

```swift
var methodRaw: String                    // persisted
@Transient var method: HTTPMethod {      // type-safe access
    get { HTTPMethod(rawValue: methodRaw) ?? .get }
    set { methodRaw = newValue.rawValue }
}
```

### KeyValuePair Data Encoding (headers, query params)

Headers and query params are `[KeyValuePair]` encoded as `Data` blobs (JSON), not separate SwiftData models. Use `pairs.encode()` and `[KeyValuePair].decode(from: data)`.

### Keychain Integration — Two Entry Points

1. **Environment variables:** `Variable.secureValue` — uses `"variable-\(id)"` as Keychain key
2. **Auth credentials:** `AuthConfig.storeSecrets(forRequestID:)` / `retrieveSecrets(forRequestID:)` — uses `"auth-{type}-{requestID}"` keys

When deleting requests/variables, always clean up Keychain entries via `deleteSecureValue()` / `AuthConfig.deleteSecrets(forRequestID:)`.

### Export Redaction

`FileExporter` auto-redacts sensitive headers (`authorization`, `x-api-key`, `x-auth-token`, `proxy-authorization`, `cookie`) and exports secret variables with empty values. The sensitive key set is in `FileExporter.sensitiveHeaderKeys`.

### Memory-Aware Responses

`URLSessionHTTPClient` uses `downloadTask` for all requests. Responses >1MB (`maxMemorySize`) stay on disk via `bodyFileURL`; smaller responses load into memory.

## File Layout

All source is under `PostKit/PostKit/` (the Xcode target root):

- `DI/` — Factory container extensions (`Container+Services.swift`, `Container+Parsers.swift`)
- `Models/` — SwiftData `@Model` classes + `Enums/` for `HTTPMethod`, `BodyType`, `AuthType`
- `ViewModels/` — Single `RequestViewModel.swift` (execution, history, auth, interpolation)
- `Views/` — Grouped by feature: `Sidebar/`, `RequestList/`, `RequestDetail/`, `Environment/`, `Import/`
- `Services/` — `HTTPClient`, `CurlParser`, `OpenAPIParser`, `FileExporter`, `VariableInterpolator`, `KeychainManager`, `Protocols/`
- `Utilities/` — `KeyValuePair`, `FocusedValues`

Tests are in `PostKit/PostKitTests/`:
- `PostKitTests.swift` — Test suites grouped by struct (`CurlParserTests`, `VariableInterpolatorTests`, `KeyValuePairTests`, `AuthConfigTests`, `OpenAPIParserTests`, `RequestViewModelTests`)
- `Mocks/` — Mock implementations (`MockHTTPClient`, `MockKeychainManager`) for Factory-based testing

## Documentation

- **ADR:** `docs/adr/0001-postkit-architecture-decisions.md` — 20 Architecture Decision Records covering all major choices (SwiftUI over AppKit, SwiftData over CoreData, minimal dependencies, actor-based HTTP client, Keychain for secrets, Factory DI, Swift Testing, etc.). Consult before proposing architectural changes.
- **Developer Guide:** `docs/sop/developer-guide.md` — Onboarding guide with setup instructions, architecture patterns, step-by-step feature addition walkthrough, coding conventions, security practices, and pre-commit/security checklists.
- **Testing Standards:** `docs/sop/testing-standards.md` — **Every change must include tests with positive, negative, and edge cases.** Tests use Swift Testing (`@Test`, `#expect`), grouped by struct in `PostKitTests/PostKitTests.swift`, with `// MARK:` separators for each category.
- **Brainstorms:** `docs/brainstorms/` — Exploration documents for upcoming features (HTTP client engine, text viewer/editor, OpenAPI import).
- **Plans:** `docs/plans/` — Implementation plans for upcoming features, including the original MVP architecture plan.

When adding a new major architectural decision, append a new ADR entry to the existing ADR document following the same format (Context, Decision, Alternatives Considered, Consequences).

## Conventions

- **Naming:** Models = nouns (`HTTPRequest`), ViewModels = `*ViewModel`, Views = `*View`/`*Pane`/`*Row`/`*Sheet`/`*Bar`, Services = nouns (`CurlParser`), Protocols = `*Protocol`, Errors = `*Error`
- **Sendable:** All types crossing concurrency boundaries must be `Sendable`. The HTTP client is an `actor`; `KeychainManager` and `CurlParser` are `final class: Sendable`
- **Error types:** Conform to `LocalizedError` with `errorDescription`
- **File organization:** imports → type definition → `// MARK: -` sections
- **Commits:** Conventional Commits format (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`)
- **Branches:** `feat/`, `fix/`, `docs/`, `refactor/`, `test/` prefixes
- **Variable interpolation:** `{{variableName}}` syntax; built-in variables: `$timestamp`, `$uuid`, `$randomInt`, `$isoTimestamp`, `$randomString`
