# PostKit Architecture Decision Records

> **Last updated:** 2026-02-14
> **Applies to:** PostKit v1.0 (MVP)
> **Total decisions:** 20

This document consolidates all significant architecture decisions made during the development of PostKit, a native macOS API client. Each decision follows the standard ADR format: Context, Decision, Alternatives Considered, and Consequences.

---

## Table of Contents

| # | Decision |
|---|----------|
| [001](#adr-001-swiftui-over-uikitappkit) | SwiftUI over UIKit/AppKit |
| [002](#adr-002-swiftdata-over-coredata) | SwiftData over CoreData |
| [003](#adr-003-minimal-external-dependencies) | Minimal external dependencies |
| [004](#adr-004-mvvm-over-tcaviper) | MVVM over TCA/VIPER |
| [005](#adr-005-actor-based-http-client) | Actor-based HTTP client |
| [006](#adr-006-keychain-for-secrets) | Keychain for secrets |
| [007](#adr-007-swift-testing-over-xctest) | Swift Testing over XCTest |
| [008](#adr-008-navigationsplitview-without-coordinator) | NavigationSplitView (no Coordinator) |
| [009](#adr-009-observable-over-combineobservableobject) | @Observable over Combine/ObservableObject |
| [010](#adr-010-protocol-based-dependency-injection) | Protocol-based DI (HTTPClientProtocol) |
| [011](#adr-011-memory-aware-responses) | Memory-aware responses (1MB threshold) |
| [012](#adr-012-export-with-sensitive-data-redaction) | Export with sensitive data redaction |
| [013](#adr-013-single-viewmodel-pattern) | Single ViewModel pattern |
| [014](#adr-014-cascade-delete-rules-on-all-relationships) | Cascade delete rules on all relationships |
| [015](#adr-015-transient-computed-properties-for-enums) | @Transient computed properties for enums |
| [016](#adr-016-keyvaluepair-data-encoding-for-swiftdata) | KeyValuePair Data encoding for SwiftData |
| [017](#adr-017-app-sandbox-with-minimal-entitlements) | App Sandbox with minimal entitlements |
| [018](#adr-018-macos-14-sonoma-minimum-target) | macOS 14+ (Sonoma) minimum target |
| [019](#adr-019-libcurl-http-client-engine) | libcurl HTTP Client Engine |
| [020](#adr-020-factory-dependency-injection-container) | Factory Dependency Injection Container |

---

### ADR-001: SwiftUI over UIKit/AppKit

**Status:** Accepted

**Context:** PostKit requires a three-pane layout (collections sidebar, request list, request detail) typical of macOS productivity apps. The UI needs to be responsive to data changes in real-time as users edit requests and receive responses.

**Decision:** Use SwiftUI as the sole UI framework with no AppKit usage beyond system-level APIs (e.g., `NSSavePanel` for file export).

**Alternatives Considered:**
- **AppKit (Cocoa):** Mature and full-featured, but imperative style leads to significant boilerplate for data-driven UIs. Steeper learning curve for modern Swift developers.
- **UIKit with Catalyst:** Limited macOS-native feel. Catalyst apps often feel like iPad ports and lack native menu bar, toolbar, and window management integration.

**Consequences:**
- (+) Declarative syntax drastically reduces UI boilerplate
- (+) Native `NavigationSplitView` provides three-pane layout for free
- (+) Direct integration with SwiftData via `@Query` and `@Bindable`
- (+) Single framework for all UI, reducing cognitive overhead
- (-) Some macOS-specific features (e.g., `NSSavePanel`) still require AppKit bridging
- (-) SwiftUI `TextEditor` does not support attributed text — syntax highlighting requires `NSViewRepresentable` bridging to `NSTextView`
- (-) Fewer online resources compared to AppKit for advanced macOS patterns

**AppKit Bridging Pattern (NSViewRepresentable):**

For features where SwiftUI lacks native support (syntax highlighting with attributed text), `NSViewRepresentable` is the accepted bridging mechanism. The pattern wraps AppKit views while maintaining SwiftUI semantics:

- **CodeTextView** (`Views/Components/CodeTextView.swift`) — Wraps `NSTextView` + `CodeAttributedString` (Highlightr) for syntax-highlighted code editing
- The view is fully controlled by SwiftUI via `@Binding` for text content
- Theme follows system appearance via `@Environment(\.colorScheme)`
- All text manipulation (find, copy, undo) delegates to NSTextView's built-in features

**References:**
- `PostKit/Views/ContentView.swift` — NavigationSplitView three-pane layout
- `PostKit/Views/RequestDetail/RequestDetailView.swift` — HSplitView for editor/response split
- `PostKit/Views/Components/CodeTextView.swift` — NSViewRepresentable pattern for syntax highlighting

---

### ADR-002: SwiftData over CoreData

**Status:** Accepted

**Context:** PostKit needs persistent storage for collections, requests, environments, variables, and history entries. The data model has relationships (collection -> folders -> requests) and requires cascade deletes.

**Decision:** Use SwiftData with `@Model` macros for all persistence. No `.xcdatamodeld` files.

**Alternatives Considered:**
- **CoreData:** Battle-tested but requires XML model files, manual `NSManagedObject` subclasses, and verbose fetch request boilerplate.
- **SQLite (raw or GRDB):** Full control but requires manual schema management, migration logic, and relationship handling.
- **Realm:** Third-party dependency, which conflicts with our zero-dependency goal.

**Consequences:**
- (+) Models are plain Swift classes with `@Model` — no separate schema files
- (+) `@Query` property wrapper enables reactive UI updates directly in SwiftUI views
- (+) Relationship management and cascade deletes are declarative via `@Relationship`
- (+) Schema migrations are automatic for simple changes
- (-) SwiftData is relatively new (iOS 17/macOS 14); less community knowledge
- (-) Complex queries are harder to express than raw SQL
- (-) Requires macOS 14+ minimum deployment target

**References:**
- `PostKit/PostKitApp.swift:11-27` — Schema registration with all 6 model types
- `PostKit/Models/RequestCollection.swift` — `@Model` with `@Relationship(deleteRule: .cascade)`

---

### ADR-003: Minimal External Dependencies

**Status:** Supersedes "Zero External Dependencies" (2026-02-14)

**Context:** PostKit is a developer tool that handles sensitive data (API keys, auth tokens). Supply-chain attacks via compromised dependencies are a real risk for this category of software. However, a strict zero-dependency policy increases development effort for features where well-maintained, narrowly-scoped libraries provide significant value (e.g., YAML parsing, syntax highlighting). The goal is to minimize attack surface while allowing pragmatic exceptions.

**Decision:** Prefer Apple frameworks for core functionality. Third-party dependencies are permitted when **all** of the following criteria are met:

1. **No viable Apple framework alternative** — the functionality is not reasonably achievable with Foundation, SwiftUI, SwiftData, Security, or other system frameworks
2. **Narrowly scoped** — the library does one thing well, with minimal transitive dependencies
3. **Well maintained** — active maintenance, responsive to security issues, broad adoption in the Swift ecosystem
4. **Added via Swift Package Manager** — no CocoaPods, Carthage, or vendored binaries

Each new dependency must be justified in this ADR or in a new ADR entry.

**Alternatives Considered:**
- **Zero dependencies (previous policy):** Maximizes security and build simplicity, but increases boilerplate for features where mature libraries exist (e.g., writing a YAML parser from scratch).
- **Unrestricted dependencies:** Faster feature development but unacceptable supply-chain risk for a tool that handles API credentials.

**Consequences:**
- (+) Pragmatic — avoids reinventing well-solved problems
- (+) Still minimal attack surface — dependencies must pass the 4-criteria gate
- (+) Each dependency is explicitly justified and auditable
- (+) SPM-only keeps dependency management consistent
- (-) Requires discipline — each addition needs a justification check
- (-) Introduces (minimal) SPM resolution time and potential version conflicts

**Current Dependencies:**
- **Factory 2.5.x** (`https://github.com/hmlongco/Factory.git`) — Unified dependency injection container. Justified: DI is infrastructure touching every layer; `@Environment` approach hit architectural ceiling (ViewModels can't self-resolve); enables ViewModel testing; ~1,000 LOC with no transitive dependencies. See ADR-020 for full decision rationale.
- **Highlightr 2.3.0** (`https://github.com/raspu/Highlightr.git`) — Syntax highlighting via highlight.js. Justified: Syntax highlighting is table-stakes for API clients (Postman, Insomnia all have it); implementing from scratch would require a lexer for every language; wraps highlight.js (actively maintained, 90+ languages); adds ~2-4MB resident memory via JavaScriptCore; single maintainer but stable API. Uses `@preconcurrency` import to handle non-Sendable classes.

**References:**
- `PostKit/Services/KeychainManager.swift` — Direct Security framework usage (no KeychainAccess needed)
- `PostKit/Services/CurlParser.swift` — Custom cURL tokenizer/parser (no third-party parser needed)
- `PostKit/Services/OpenAPIParser.swift` — Custom OpenAPI 3.x JSON parser (YAML support would likely require a dependency)

---

### ADR-004: MVVM over TCA/VIPER

**Status:** Accepted

**Context:** The app needs a clear separation between UI and business logic. At ~4,000 LOC with a single main feature (HTTP request editing and execution), the architecture should be simple and familiar.

**Decision:** Use MVVM (Model-View-ViewModel) with `@Observable` view models. Views are thin rendering layers; ViewModels own business logic and state.

**Alternatives Considered:**
- **TCA (The Composable Architecture):** Powerful for large teams, but adds significant complexity (reducers, effects, stores) that is disproportionate for a single-developer project at this scale.
- **VIPER:** Over-engineered for a SwiftUI project. Router/Interactor/Presenter layers add friction without benefit when SwiftUI handles navigation declaratively.
- **MV (Model-View, "SwiftUI native"):** Tempting for simplicity, but mixing business logic into views makes testing difficult and views bloated.

**Consequences:**
- (+) Natural fit for SwiftUI's declarative paradigm
- (+) ViewModels are testable without UI infrastructure
- (+) `@Observable` provides fine-grained updates without Combine boilerplate
- (+) Familiar pattern — low onboarding friction for contributors
- (-) Single ViewModel class may grow as features are added
- (-) No enforced unidirectional data flow (unlike TCA)

**References:**
- `PostKit/ViewModels/RequestViewModel.swift` — Central ViewModel with MARK sections
- `PostKit/Views/RequestDetail/RequestDetailView.swift` — Thin view delegating to ViewModel

---

### ADR-005: Actor-based HTTP Client

**Status:** Accepted

**Context:** HTTP requests are inherently asynchronous and may be cancelled mid-flight. The client needs to track active tasks and allow cancellation without data races on shared mutable state.

**Decision:** Implement the HTTP client as a Swift `actor` (`URLSessionHTTPClient`), providing compile-time isolation for the `activeTasks` dictionary and all mutable state.

**Alternatives Considered:**
- **Class with `@MainActor`:** Forces all HTTP work onto the main thread, which is inappropriate for network I/O.
- **Class with manual locking (NSLock/DispatchQueue):** Error-prone — forgotten locks lead to data races that are hard to reproduce.
- **Struct-based stateless client:** Cannot track active tasks for cancellation.

**Consequences:**
- (+) Compile-time data race safety — the compiler enforces actor isolation
- (+) `activeTasks` dictionary is safely mutated without locks
- (+) Clean integration with Swift concurrency (`async/await`)
- (+) Cancellation is thread-safe via `cancel(taskID:)`
- (-) All access is async, even for simple property reads
- (-) Actor re-entrancy requires careful reasoning (mitigated by keeping methods simple)

**References:**
- `PostKit/Services/HTTPClient.swift:3` — `actor URLSessionHTTPClient: HTTPClientProtocol`
- `PostKit/Services/HTTPClient.swift:5` — `private var activeTasks: [UUID: URLSessionTask] = [:]`

---

### ADR-006: Keychain for Secrets

**Status:** Accepted

**Context:** PostKit stores sensitive values: Bearer tokens, Basic Auth passwords, API keys, and secret environment variables. These must not be stored in plaintext in the SwiftData database or in exported files.

**Decision:** Use the macOS Keychain Services API via a singleton `KeychainManager`. Secrets are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility, meaning they are only available when the device is unlocked and never synced to other devices.

**Alternatives Considered:**
- **Encrypted SwiftData fields:** SwiftData does not natively support per-field encryption. Manual encryption would require key management, which the Keychain already solves.
- **Separate encrypted file:** Adds complexity for key derivation and storage, with less OS integration than Keychain.
- **1Password SDK / third-party secrets manager:** Violates zero-dependency policy and adds external service coupling.

**Consequences:**
- (+) OS-managed encryption — Apple handles key storage and hardware-backed encryption
- (+) Per-device isolation — secrets never leave the machine via iCloud Keychain
- (+) Transparent to the user — no master password required beyond device login
- (+) Dual-layer integration: `Variable.secureValue` for env vars, `AuthConfig.storeSecrets(forRequestID:)` for auth
- (-) Keychain API is C-based and verbose (mitigated by `KeychainManager` wrapper)
- (-) Secrets are lost if the user migrates to a new Mac without Keychain migration

**References:**
- `PostKit/Services/KeychainManager.swift:27-108` — Singleton with store/retrieve/delete operations
- `PostKit/Models/Variable.swift:32-47` — `secureValue` computed property with Keychain fallback
- `PostKit/Models/Enums/AuthType.swift:40-107` — `AuthConfig` Keychain extension for auth secrets

---

### ADR-007: Swift Testing over XCTest

**Status:** Accepted

**Context:** The project needs a testing framework for unit tests. Swift Testing (introduced in Swift 5.10 / Xcode 16) is Apple's modern replacement for XCTest.

**Decision:** Use the Swift Testing framework (`import Testing`) with `@Test` attributes and `#expect` macros for all unit tests.

**Alternatives Considered:**
- **XCTest:** Established but verbose — requires class inheritance, `test` prefix naming, `XCTAssert*` functions, and `setUp`/`tearDown` lifecycle.
- **Quick/Nimble:** Third-party BDD framework — violates zero-dependency policy.

**Consequences:**
- (+) Tests are structs, not classes — no inheritance overhead
- (+) `@Test` attribute is more explicit than naming conventions
- (+) `#expect` macro provides better failure messages than `XCTAssertEqual`
- (+) Parameterized tests with `@Test(arguments:)` reduce boilerplate
- (+) Concise syntax — tests are shorter and more readable
- (-) Requires Xcode 16+ for full support
- (-) Smaller ecosystem of examples and tutorials than XCTest

**References:**
- `PostKitTests/PostKitTests.swift:8` — `import Testing`
- `PostKitTests/PostKitTests.swift:14-170` — `CurlParserTests` struct with `@Test` functions
- `PostKitTests/PostKitTests.swift:174-288` — `VariableInterpolatorTests` with built-in variable tests

---

### ADR-008: NavigationSplitView without Coordinator

**Status:** Accepted

**Context:** PostKit's primary UI is a three-pane layout: collections sidebar, request list, and request detail. Navigation state is simple — selecting a collection reveals its requests; selecting a request reveals its detail.

**Decision:** Use `NavigationSplitView` with `@State` selection bindings directly in `ContentView`. No Coordinator pattern or navigation state machine.

**Alternatives Considered:**
- **Coordinator pattern:** Useful for deep navigation hierarchies (e.g., multi-screen flows), but PostKit has flat navigation — every view is always visible in one of three columns.
- **Router/NavigationPath:** Designed for stack-based push/pop navigation, not split-view column selection.
- **Custom navigation state machine:** Over-engineered for two selection bindings.

**Consequences:**
- (+) Minimal state management — two `@State` properties handle all navigation
- (+) Native macOS three-pane behavior (resizable columns, column visibility)
- (+) SwiftUI handles persistence of column widths and visibility automatically
- (+) `ContentUnavailableView` provides zero-state UX for free
- (-) Complex navigation flows (e.g., deep-linking to a specific request) would require refactoring
- (-) No programmatic navigation history

**References:**
- `PostKit/Views/ContentView.swift:16-46` — `NavigationSplitView` with sidebar, content, and detail
- `PostKit/Views/ContentView.swift:6-7` — `@State` selection bindings for collection and request

---

### ADR-009: @Observable over Combine/ObservableObject

**Status:** Accepted

**Context:** ViewModels need to publish state changes to SwiftUI views. Swift 5.9 introduced the `@Observable` macro as a simpler alternative to `ObservableObject` + `@Published`.

**Decision:** Use the `@Observable` macro (from the Observation framework) for all view models instead of the older `ObservableObject` protocol.

**Alternatives Considered:**
- **ObservableObject + @Published:** Works but requires `@StateObject`/`@ObservedObject` in views, and triggers view updates for *any* property change (not just the ones the view reads).
- **Combine publishers:** Low-level reactive streams — powerful but complex for simple state binding.

**Consequences:**
- (+) Fine-grained observation — views only re-render when the specific properties they read change
- (+) No `@Published` wrapper needed — all stored properties are automatically observed
- (+) `@State` in views instead of `@StateObject` — simpler ownership semantics
- (+) Less boilerplate — no conformance to `ObservableObject` required
- (-) Requires macOS 14+ (Sonoma)
- (-) Debugging observation tracking is less transparent than explicit `@Published`

**References:**
- `PostKit/ViewModels/RequestViewModel.swift:8-9` — `@Observable final class RequestViewModel`
- `PostKit/Views/RequestDetail/RequestDetailView.swift:9` — `@State private var viewModel: RequestViewModel?`

---

### ADR-010: Protocol-based Dependency Injection

**Status:** Accepted

**Context:** The HTTP client must be swappable for testing (mock client) and potentially for different configurations (e.g., custom URLSession). SwiftUI provides `EnvironmentValues` for dependency propagation.

**Decision:** Define `HTTPClientProtocol` as the contract for HTTP execution, inject the concrete implementation via SwiftUI's `@Environment(\.httpClient)`, and use a custom `EnvironmentKey` with a default value.

**Alternatives Considered:**
- **Direct instantiation:** Hardcoding `URLSessionHTTPClient()` in ViewModels makes testing impossible without network calls.
- **Swinject / third-party DI container:** Violates zero-dependency policy and adds runtime complexity.
- **Singleton pattern:** Testable via stubbing `shared`, but makes dependencies implicit and order-dependent.

**Consequences:**
- (+) ViewModels accept `HTTPClientProtocol`, enabling test doubles
- (+) SwiftUI Environment provides natural DI scope — no manual wiring
- (+) Default value (`URLSessionHTTPClient()`) means zero configuration for production
- (+) Protocol is `Sendable`, ensuring thread-safe injection across actors
- (-) Protocol conformance requires all methods to match — changes to the protocol require updating all implementations
- (-) Environment injection is only available from SwiftUI views

**References:**
- `PostKit/Services/Protocols/HTTPClientProtocol.swift:3-6` — Protocol definition with `Sendable` conformance
- `PostKit/Utilities/Environment+HTTPClient.swift:6-15` — EnvironmentKey with default `URLSessionHTTPClient`
- `PostKit/Views/RequestDetail/RequestDetailView.swift:6` — `@Environment(\.httpClient)` usage

---

### ADR-011: Memory-aware Responses

**Status:** Accepted

**Context:** API responses can be arbitrarily large. Loading a multi-gigabyte response into `Data` would cause out-of-memory (OOM) crashes. PostKit must handle large responses gracefully.

**Decision:** Use `URLSession.downloadTask` for all requests (not `dataTask`). Responses are first streamed to a temporary file on disk. If the file size exceeds 1MB (`maxMemorySize`), the file URL is retained and `body` is set to `nil`. If under 1MB, the file is read into memory and the temp file is deleted.

**Alternatives Considered:**
- **Always in-memory (`dataTask`):** Simple but unsafe for large responses.
- **Always on-disk:** Unnecessary file I/O overhead for small responses (majority of API calls return < 1KB).
- **Streaming with chunked processing:** Complex to implement and not needed for a response viewer that ultimately displays the full body.

**Consequences:**
- (+) Prevents OOM crashes regardless of response size
- (+) Small responses (< 1MB) remain in-memory for fast display
- (+) Large responses are accessible via `bodyFileURL` for lazy loading
- (+) `HTTPResponse.isLarge` computed property lets the UI adapt its rendering
- (-) 1MB threshold is hardcoded — may need tuning for different use cases
- (-) Temporary files must be cleaned up manually (handled in `RequestViewModel.sendRequest`)

**References:**
- `PostKit/Services/HTTPClient.swift:7` — `private let maxMemorySize: Int64 = 1_000_000`
- `PostKit/Services/HTTPClient.swift:75-99` — Size check and branching logic
- `PostKit/Services/Protocols/HTTPClientProtocol.swift:17-19` — `isLarge` computed property

---

### ADR-012: Export with Sensitive Data Redaction

**Status:** Accepted

**Context:** Users export collections to share with teammates or back up their API configurations. Exported JSON files could accidentally contain API keys, Bearer tokens, and other credentials embedded in headers.

**Decision:** The `FileExporter` automatically redacts sensitive header values on export. A hardcoded set of sensitive header keys (`authorization`, `x-api-key`, `x-auth-token`, `proxy-authorization`, `cookie`) is compared case-insensitively, and matching values are replaced with `"[REDACTED]"`. Secret environment variables export with empty values.

**Alternatives Considered:**
- **No redaction (user responsibility):** High risk of accidental credential leaks. Users often forget to sanitize exports.
- **Optional redaction toggle:** Adds UI complexity and a footgun — the default should be safe.
- **Full encryption of exported files:** Requires shared keys between import/export, adds friction to sharing.

**Consequences:**
- (+) Safe-by-default — credential leaks are prevented without user action
- (+) Exported files remain valid JSON and importable (redacted values appear as `[REDACTED]`)
- (+) Case-insensitive matching catches common header variations
- (+) Secret environment variables export as empty strings, not their Keychain values
- (-) Users cannot export with credentials included (by design)
- (-) Hardcoded sensitive key list may miss custom sensitive headers

**References:**
- `PostKit/Services/FileExporter.swift:45-51` — `sensitiveHeaderKeys` set
- `PostKit/Services/FileExporter.swift:65-71` — Redaction logic during header export
- `PostKit/Services/FileExporter.swift:91` — Secret variable value cleared on export

---

### ADR-013: Single ViewModel Pattern

**Status:** Accepted

**Context:** The request detail view needs a ViewModel for HTTP execution, response state, history recording, variable interpolation, and auth handling. The question is whether to split this across multiple ViewModels or keep it unified.

**Decision:** Use a single `RequestViewModel` class with MARK sections organizing its responsibilities: UI State, Dependencies, Public Methods, Request Building, Environment Variables, Auth, and History.

**Alternatives Considered:**
- **Multiple ViewModels (RequestExecutionVM, HistoryVM, AuthVM):** Cleaner separation but adds inter-VM communication complexity and fragmented state.
- **View-embedded logic:** Tempting for SwiftUI but makes the view untestable and bloated.

**Consequences:**
- (+) All request-related state in one place — easy to reason about
- (+) No inter-ViewModel communication overhead
- (+) MARK sections provide logical grouping within the file
- (+) Single point of injection for dependencies (`httpClient`, `modelContext`)
- (-) The class will grow as features are added (may need splitting beyond ~500 LOC)
- (-) All responsibilities share the same lifecycle

**References:**
- `PostKit/ViewModels/RequestViewModel.swift` — ~237 LOC with 7 MARK sections
- `PostKit/Views/RequestDetail/RequestDetailView.swift:51-55` — ViewModel created per detail view instance

---

### ADR-014: Cascade Delete Rules on All Relationships

**Status:** Accepted

**Context:** PostKit's data model has a tree structure: `RequestCollection` -> `Folder`/`HTTPRequest`/`APIEnvironment` -> `Variable`/`HistoryEntry`. Deleting a collection should clean up all descendants. Orphaned records would waste storage and cause UI inconsistencies.

**Decision:** All parent-to-child relationships use `deleteRule: .cascade`. When a parent is deleted, all related children are automatically deleted by SwiftData.

**Alternatives Considered:**
- **Nullify (`.nullify`):** Sets the relationship to nil on children, leaving orphaned records that must be cleaned up separately.
- **Deny (`.deny`):** Prevents deletion if children exist — adds friction to the user experience.
- **Manual cleanup:** Error-prone and requires remembering to delete children in every delete code path.

**Consequences:**
- (+) No orphaned records — clean semantics guaranteed by the persistence layer
- (+) Single delete call removes the entire subtree
- (+) Consistent behavior across all relationships
- (+) No manual cleanup code required
- (-) Accidental deletion of a collection removes all its data irrecoverably
- (-) Large collections may trigger slow cascade deletions (not yet an issue at PostKit's scale)

**References:**
- `PostKit/Models/RequestCollection.swift:13-19` — Cascade on `folders`, `requests`, `environments`
- `PostKit/Models/Folder.swift:12-13` — Cascade on `requests`
- `PostKit/Models/APIEnvironment.swift:11-12` — Cascade on `variables`
- `PostKit/Models/HTTPRequest.swift:22-23` — Cascade on `history`

---

### ADR-015: @Transient Computed Properties for Enums

**Status:** Accepted

**Context:** SwiftData persists all stored properties of `@Model` classes. Swift enums with associated types or custom raw values cannot be directly persisted by SwiftData. We need type-safe access to enums like `HTTPMethod` and `BodyType` while storing their `String` raw values.

**Decision:** Store enum values as raw `String` properties (e.g., `methodRaw`, `bodyTypeRaw`) and provide `@Transient` computed properties that convert between the raw string and the typed enum. The `@Transient` attribute prevents SwiftData from attempting to persist the computed property.

**Alternatives Considered:**
- **Store enums directly:** SwiftData cannot persist custom enums reliably, especially with raw values that differ from the case name.
- **Use `String` everywhere:** Loses type safety — callers must remember to validate strings.
- **Custom Codable transformer:** More complex than a computed property and harder to debug.

**Consequences:**
- (+) Type-safe enum access throughout the codebase (`request.method` returns `HTTPMethod`)
- (+) SwiftData persists a simple `String` — no custom transformers needed
- (+) Fallback defaults (e.g., `.get`, `.none`) prevent crashes from invalid stored data
- (+) Pattern reused consistently across all models
- (-) Two properties per enum (raw + computed) — slight redundancy
- (-) Requires discipline to always use the computed property, not the raw one

**References:**
- `PostKit/Models/HTTPRequest.swift:25-28` — `@Transient var method: HTTPMethod` backed by `methodRaw`
- `PostKit/Models/HTTPRequest.swift:30-33` — `@Transient var bodyType: BodyType` backed by `bodyTypeRaw`
- `PostKit/Models/HistoryEntry.swift:16-19` — Same pattern for `HistoryEntry.method`

---

### ADR-016: KeyValuePair Data Encoding for SwiftData

**Status:** Accepted

**Context:** HTTP requests have collections of key-value pairs for headers and query parameters. Each request may have 0-20+ headers and 0-10+ query params. SwiftData requires that related objects be `@Model` classes with their own table.

**Decision:** Encode `[KeyValuePair]` arrays as `Data` blobs (JSON-encoded) stored directly on the `HTTPRequest` model (`headersData`, `queryParamsData`). `KeyValuePair` is a simple `Codable` struct, not a SwiftData model.

**Alternatives Considered:**
- **Separate `@Model` class for KeyValuePair:** Creates a many-to-one relationship table. For N requests with M headers each, this means N*M database rows and relationship management overhead.
- **Dictionary `[String: String]`:** Loses ordering and the `isEnabled` toggle state.
- **Comma-separated strings:** Fragile parsing, no support for values containing the delimiter.

**Consequences:**
- (+) Compact storage — one `Data` blob per array instead of N relationship rows
- (+) No additional SwiftData model or migration needed
- (+) Encode/decode is a single line via the `Array<KeyValuePair>` extensions
- (+) Preserves order, keys, values, and enabled state
- (-) Cannot query individual headers via SwiftData predicates
- (-) Entire array must be decoded to read or modify a single entry

**References:**
- `PostKit/Utilities/KeyValuePair.swift:3-14` — `Codable` struct definition
- `PostKit/Utilities/KeyValuePair.swift:16-25` — `encode()` and `decode(from:)` extensions
- `PostKit/Models/HTTPRequest.swift:10-11` — `headersData: Data?` and `queryParamsData: Data?`

---

### ADR-017: App Sandbox with Minimal Entitlements

**Status:** Accepted

**Context:** PostKit is intended for App Store distribution. The App Sandbox is required for App Store apps and limits the damage from potential security vulnerabilities.

**Decision:** Enable App Sandbox with exactly three entitlements:
1. `com.apple.security.app-sandbox` — Enable sandboxing
2. `com.apple.security.network.client` — Allow outgoing HTTP requests
3. `com.apple.security.files.user-selected.read-write` — Allow import/export via file dialogs

**Alternatives Considered:**
- **No sandbox (developer-signed only):** Allows unrestricted filesystem and network access but blocks App Store distribution and increases attack surface.
- **Broader entitlements (e.g., arbitrary file read, camera, contacts):** Not needed. Only network and user-selected files are required.

**Consequences:**
- (+) App Store compatible
- (+) Minimal attack surface — the app can only access the network and user-selected files
- (+) Users can trust that PostKit cannot access files outside their explicit selection
- (+) Keychain access is automatically scoped to the app's sandbox
- (-) Cannot programmatically read/write files without user interaction (e.g., no auto-import from a watched folder)
- (-) Network requests are unrestricted within the sandbox (no per-domain filtering)

**References:**
- `PostKit/PostKit.entitlements` — Plist with 3 entitlements
- `PostKit/Services/FileExporter.swift:102-108` — `NSSavePanel` for sandboxed file export

---

### ADR-018: macOS 14+ (Sonoma) Minimum Target

**Status:** Accepted

**Context:** PostKit relies on SwiftData (`@Model`, `@Query`, `ModelContainer`) and the Observation framework (`@Observable`). Both were introduced in macOS 14 Sonoma (2023). The README currently lists macOS 15.0+ as the requirement.

**Decision:** Target macOS 14.0 (Sonoma) as the minimum deployment target. This is the lowest version that supports both SwiftData and `@Observable`, the two foundational frameworks for PostKit's architecture.

**Alternatives Considered:**
- **macOS 13 (Ventura):** Would require replacing SwiftData with CoreData and `@Observable` with `ObservableObject`, fundamentally changing the architecture.
- **macOS 15 (Sequoia):** Unnecessarily restricts the user base. No macOS 15-specific APIs are used.
- **macOS 12 or earlier:** Incompatible with SwiftUI's modern features (`NavigationSplitView`, `ContentUnavailableView`).

**Consequences:**
- (+) Access to SwiftData, @Observable, NavigationSplitView, ContentUnavailableView, and Swift Testing
- (+) Covers the vast majority of active macOS users (Sonoma+ adoption is >80% among developers)
- (+) Allows use of modern Swift concurrency features (actors, structured concurrency)
- (-) Excludes users on macOS 13 Ventura and earlier
- (-) Must track Apple's deprecation timeline for API stability

**References:**
- `PostKit/PostKitApp.swift:1-2` — `import SwiftUI` + `import SwiftData` (both require macOS 14+)
- `PostKit/ViewModels/RequestViewModel.swift:2` — `import Observation` (macOS 14+)

---

### ADR-019: libcurl HTTP Client Engine

**Status:** Accepted

**Context:** URLSession provides no public API for detailed timing breakdown (DNS lookup, TCP connection, TLS handshake, TTFB, download phases). Users of API development tools expect timing waterfall charts similar to browser DevTools, Postman, and Insomnia. URLSession's delegate-based timing API (via `URLSessionTaskMetrics`) provides some timing data but lacks the granularity available through libcurl's `CURLINFO_*` APIs.

**Decision:** Replace the primary HTTP engine with libcurl via a vendored curl-apple xcframework (v8.18.0 with OpenSSL). Keep `URLSessionHTTPClient` as an automatic fallback if `curl_global_init` fails. Use C shim wrappers for libcurl's variadic functions (`curl_easy_setopt`, `curl_easy_getinfo`). Bundle Mozilla's root CA certificates (`cacert.pem`) with SHA-256 build-time verification. Implement as an actor using GCD for the blocking `curl_easy_perform` call.

**Alternatives Considered:**
- **URLSessionTaskMetrics:** Provides transaction-level timing but lacks DNS/TCP/TLS breakdown per-request.
- **Network.framework (NWConnection):** Lower-level but still doesn't expose timing for HTTP semantics.
- **SwiftNIO + AsyncHTTPClient:** Full async HTTP stack but heavyweight dependency, no timing breakdown APIs.
- **curl_multi interface:** Better for concurrent requests but more complex; deferred to future iteration.

**Consequences:**
- (+) Detailed timing waterfall with 7 phases (DNS, TCP, TLS, TTFB, download, total, redirect)
- (+) Protocol abstraction via `HTTPClientProtocol` unchanged — views are unaware of engine
- (+) Graceful fallback to URLSession ensures the app always works
- (-) ~160MB vendored xcframework increases repository size (includes iOS slices that should be stripped)
- (-) C interop complexity with `Unmanaged` pointers and `@convention(c)` callbacks
- (-) Bundled CA certificates require periodic updates
- (-) Export compliance review needed for bundled OpenSSL

**References:**
- `PostKit/Services/LibCurlHTTPClient.swift` — Actor-based libcurl HTTP client implementation
- `PostKit/Services/HTTPClient.swift` — URLSession fallback client
- `PostKit/Services/Protocols/HTTPClientProtocol.swift` — Shared protocol abstraction

---

### ADR-020: Factory Dependency Injection Container

**Status:** Accepted

**Context:** PostKit had three inconsistent dependency injection mechanisms:
1. `@Environment(\.httpClient)` — SwiftUI Environment, only accessible in views, not ViewModels
2. `KeychainManager.shared` — Singleton accessed from SwiftData `@Model` types, untestable
3. Direct instantiation — `CurlParser()`, `OpenAPIParser()`, `VariableInterpolator()`, `FileExporter()`

These patterns caused:
- `RequestViewModel` required `httpClient` to be passed from the view via `.onAppear` — awkward initialization
- `KeychainManager.shared` called directly from `@Model` types — impossible to mock in tests
- No ViewModel tests existed because there was no way to inject mock dependencies
- 5 of 6 services lacked protocol abstractions

**Decision:** Adopt Factory 2.5.x (`import FactoryKit`) as the unified DI container. Factory is a lightweight (~1,000 LOC), compile-time safe, Swift 6 concurrency-compatible framework with native `@Observable` support and Swift Testing integration.

**Alternatives Considered:**
- **Keep `@Environment`:** ViewModels cannot self-resolve; no test override mechanism
- **Protocol + static var (simpler):** Solves KeychainManager testability only; doesn't address view passthrough; no test isolation trait
- **Swinject:** Runtime registration, no compile-time safety, heavier
- **swift-dependencies (TCA):** Designed for Composable Architecture, over-engineered for MVVM
- **Needle (Uber):** Code generation required, complex setup

**Consequences:**
- (+) ViewModels resolve their own dependencies — no view-to-ViewModel passthrough
- (+) Test mock injection via `.container` trait with Swift Testing
- (+) Single source of truth for the dependency graph in `DI/Container+*.swift`
- (+) Protocol-based abstractions for all services (6/6 up from 1/6)
- (+) Compile-time type safety with Factory's typed closures
- (+) First third-party dependency justified under ADR-003
- (-) Service locator pattern internally (acceptable trade-off for PostKit's scale)
- (-) `@ObservationIgnored` required on all `@Injected` properties in `@Observable` classes
- (-) `@Model` types use `Container.shared` direct resolution (compromise for SwiftData constraints)

**Security Considerations:**
- `KeychainManager.private init()` and `static let shared` preserved — Factory wraps existing singleton
- Singletons force-resolved at app launch to prevent runtime mock injection
- Runtime type assertion in release builds guards against production tampering
- All mock types in test target only, never compiled into release builds

**Scope Assignments:**
- `httpClient` → `.singleton` (actor with internal state, includes CurlHTTPClient with URLSessionHTTPClient fallback)
- `keychainManager` → `.singleton` (wraps existing singleton, Keychain is system resource)
- `variableInterpolator` → `.singleton` (compiles NSRegularExpression in init)
- Parsers → `.unique` (stateless, lightweight)
- `fileExporter` → `.unique` with `@MainActor` (uses NSSavePanel)

**References:**
- `PostKit/DI/Container+Services.swift` — httpClient, keychainManager, fileExporter registrations
- `PostKit/DI/Container+Parsers.swift` — curlParser, openAPIParser, variableInterpolator registrations
- `PostKit/Services/Protocols/` — All protocol definitions
- `PostKitTests/Mocks/` — MockHTTPClient, MockKeychainManager implementations

---

## Revision History

| Date | Change |
|------|--------|
| 2026-02-13 | Initial document — 18 ADRs for PostKit MVP |
| 2026-02-14 | ADR-003: Updated from "Zero External Dependencies" to "Minimal External Dependencies" |
| 2026-02-14 | ADR-019: Added libcurl HTTP Client Engine decision |
| 2026-02-14 | ADR-020: Added Factory Dependency Injection Container decision |
