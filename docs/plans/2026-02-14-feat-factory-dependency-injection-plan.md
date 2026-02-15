---
title: "feat: Adopt Factory as Dependency Injection Container"
type: feat
date: 2026-02-14
---

# feat: Adopt Factory as Dependency Injection Container

## Enhancement Summary

**Deepened on:** 2026-02-14
**Sections enhanced:** 12
**Review agents used:** Architecture Strategist, Pattern Recognition Specialist, Code Simplicity Reviewer, Performance Oracle, Security Sentinel, Data Integrity Guardian

### Key Improvements
1. **CRITICAL FIX:** Container registration must include `CurlHTTPClient` with `URLSessionHTTPClient` fallback — original plan silently dropped the primary HTTP engine
2. **SECURITY FIX:** Keep `KeychainManager.private init()` and `static let shared` — wrap existing singleton in Factory instead of removing access control
3. **PRE-EXISTING BUGS DISCOVERED:** Keychain cleanup is dead code (never called on delete); UI binds to `variable.value` not `variable.secureValue` (secrets stored in plaintext in SQLite)
4. **Simplification:** Merged `Container+Export.swift` into `Container+Services.swift`; changed `VariableInterpolator` scope to `.singleton`
5. **Security Hardening:** Force-resolve singletons at app launch; add runtime type assertion in release builds
6. **Honest Assessment Added:** Section on whether Factory is over-engineering for this project's scale, with a simpler alternative documented

### New Considerations Discovered
- `PostKitApp.swift` has a `httpClient` stored property with `CurlHTTPClient` fallback that the plan originally missed
- `PostKitApp.importCollection()` also directly instantiates `FileExporter()` — must be migrated
- `HTTPRequest.duplicated()` copies `authConfigData` without duplicating Keychain entries (pre-existing)
- `Variable.secureValue` setter clears plaintext with `try?` — silent data loss on Keychain failure

---

## Overview

Migrate PostKit from its current ad-hoc dependency injection patterns (SwiftUI `@Environment`, singleton, direct instantiation) to a unified DI container using [Factory](https://github.com/hmlongco/Factory) 2.5.x. This centralizes the dependency graph, enables ViewModel self-resolution, and unlocks comprehensive testing through mock injection.

**Key value adds:**
1. ViewModels resolve their own dependencies — no more view-to-ViewModel passthrough
2. Test mock injection via `.container` trait with Swift Testing
3. Single source of truth for the entire dependency graph
4. Protocol-based abstractions for all services (currently only `HTTPClientProtocol` exists)

## Problem Statement

PostKit currently uses **three inconsistent DI mechanisms**:

| Pattern | Usage | Limitation |
|---------|-------|------------|
| `@Environment(\.httpClient)` | 1 custom `EnvironmentKey` | Only accessible in SwiftUI views, not ViewModels |
| `KeychainManager.shared` | Singleton accessed from `@Model` types | Untestable, implicit coupling, no protocol |
| Direct instantiation | `CurlParser()`, `OpenAPIParser()`, `VariableInterpolator()`, `FileExporter()` | No abstraction, not mockable, duplicated creation |

**Consequences of the current state:**
- `RequestViewModel` requires `httpClient` and `modelContext` to be passed from the view via `.onAppear` — awkward initialization pattern
- `KeychainManager.shared` is called directly from SwiftData `@Model` types (`Variable.swift:35,41,53` and `AuthType.swift:61,82,102`) — impossible to mock in tests
- No ViewModel tests exist because there is no way to inject mock dependencies
- 5 of 6 services lack protocol abstractions

### Research Insights: Pre-Existing Data Integrity Issues

> **Discovered by: Data Integrity Guardian, Security Sentinel**

The following pre-existing bugs were discovered during the deepening analysis. They are **not caused by the migration** but should be addressed alongside it since the migration already touches the affected code:

**1. Keychain cleanup is dead code (CRITICAL)**

`Variable.deleteSecureValue()` and `AuthConfig.deleteSecrets(forRequestID:)` exist but are **never called from any view or ViewModel**. Every delete path calls `modelContext.delete()` directly:
- `RequestListView.swift:21` — deletes `HTTPRequest` without Keychain cleanup
- `CollectionRow.swift:49` — deletes collection (cascade deletes requests)
- `CollectionRow.swift:127` — deletes folder (cascade deletes requests)
- `EnvironmentPicker.swift:133` — deletes environment (cascade deletes variables)

SwiftData's `.cascade` delete rule does not call custom cleanup logic. This means Keychain entries under `"variable-{uuid}"` and `"auth-{type}-{requestID}"` keys are **orphaned permanently** on every delete.

**2. UI binds to `variable.value`, not `variable.secureValue` (CRITICAL)**

`EnvironmentPicker.swift:199` uses `$variable.value` for the `SecureField` binding, bypassing the `secureValue` computed property entirely. Secret variables are stored in plaintext in the SQLite database. Similarly, `RequestViewModel.getActiveEnvironmentVariables()` reads `variable.value` instead of `variable.secureValue`.

**3. Silent Keychain error swallowing**

`Variable.secureValue.set` uses `try?` and clears plaintext (`value = ""`) regardless of whether the Keychain store succeeded. If the Keychain write fails, the secret is lost from both Keychain and SwiftData.

**Recommendation:** Fix these in a dedicated PR before or alongside the Factory migration. The migration touches `Variable.swift` and `AuthType.swift` anyway, making this a natural opportunity.

## Proposed Solution

Adopt **Factory 2.5.x** (`import FactoryKit`) as the project's DI container. Factory is a lightweight (~1,000 LOC), compile-time safe, Swift 6 concurrency-compatible DI framework that integrates natively with SwiftUI and the Observation framework.

### Why Factory over alternatives

| Alternative | Why Not |
|-------------|---------|
| Keep `@Environment` | Can't inject into ViewModels; no test override mechanism |
| Swinject | Runtime registration, no compile-time safety, heavier |
| swift-dependencies (TCA) | Designed for TCA/Composable, over-engineered for MVVM |
| Manual constructor injection | Already partially used; doesn't scale, requires view passthrough |
| Needle (Uber) | Code generation required, more complex setup |
| Protocol + static var (no framework) | Solves KeychainManager testability only; doesn't address view passthrough or provide unified DI |

Factory was chosen because:
- Zero code generation — computed properties on container extensions
- Native `@Observable` support via `@InjectedObservable` (macOS 14+)
- Swift Testing integration with `.container` trait for test isolation
- Swift 6 strict concurrency support
- Lightweight — ~1,000 LOC, well-maintained (2,740+ stars)
- Same author as Resolver (battle-tested lineage)

### Research Insights: Service Locator Trade-off

> **Discovered by: Architecture Strategist, Code Simplicity Reviewer**

Factory is fundamentally a **service locator** pattern, not true dependency injection. With constructor injection, a missing dependency is a compile error. With `@Injected`, a misconfigured container is a runtime error (though Factory's typed closures catch most issues at compile time). This is an acceptable trade-off for PostKit's scale (single developer, <10 services, flat dependency graph) but should be documented in the ADR.

### Research Insights: Is Factory Over-Engineering?

> **Discovered by: Code Simplicity Reviewer**

**Honest assessment:** PostKit has 6 services and 1 ViewModel in ~4,000 LOC. The Simplicity Reviewer argued that only `KeychainManager` truly *needs* a protocol for testability, and a simpler alternative exists:

```swift
// ~40 lines, zero dependencies:
// 1. Add KeychainManagerProtocol (~10 lines)
// 2. Change `static let shared` to `static var shared: KeychainManagerProtocol`
// 3. In tests: KeychainManager.shared = MockKeychainManager()
```

**Why Factory is still recommended despite this valid criticism:**
1. The view passthrough pattern (`@Environment` → view → ViewModel init) is architecturally awkward and Factory eliminates it
2. Factory provides a consistent DI pattern that scales as the app grows (new ViewModels, new services)
3. The `.container` trait for Swift Testing is significantly more robust than manual `static var` swapping (thread-safe, auto-reset)
4. If the project never grows beyond 6 services, the simpler approach remains a valid fallback — document it in the ADR as an alternative

**Decision:** Proceed with Factory, but keep the scope minimal. Do not create protocols for stateless services unless they provide clear testing value. See Phase 1 for the refined protocol list.

### ADR-003 Justification (Zero Dependencies Policy)

ADR-003 states: "third-party packages allowed when justified." Factory is justified because:
1. DI is infrastructure that touches every layer — getting it wrong is expensive to fix
2. The `@Environment` approach has hit its architectural ceiling (ViewModels can't self-resolve)
3. Factory enables a testing capability that doesn't exist today (ViewModel tests)
4. The library is ~1,000 LOC with no transitive dependencies — minimal risk

The ADR entry should also acknowledge the service locator trade-off and document the simpler `static var` alternative as a fallback if Factory proves to be more ceremony than value.

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Factory Container                   │
│  ┌───────────┐ ┌──────────┐ ┌────────────────────┐  │
│  │ Services  │ │ Parsers  │ │    ViewModels       │  │
│  │ httpClient│ │ curlParser│ │ (not registered —   │  │
│  │ keychain  │ │ openAPI  │ │  uses @Injected     │  │
│  │ fileExport│ │ interpol.│ │  internally)        │  │
│  └───────────┘ └──────────┘ └────────────────────┘  │
└─────────────────────────────────────────────────────┘
         │              │              │
    ┌────▼────┐    ┌────▼────┐   ┌────▼──────────┐
    │ Actors  │    │ Classes │   │ @Observable    │
    │ & Final │    │ Sendable│   │ @MainActor     │
    │ Classes │    │         │   │ ViewModels     │
    └─────────┘    └─────────┘   └───────────────┘
                                        │
                                   SwiftUI Views
                            (create ViewModel with ModelContext)
```

**What stays as `@Environment`:**
- `\.modelContext` — SwiftData's `ModelContext` is not `Sendable` and is lifecycle-managed by SwiftUI
- `\.dismiss`, `\.openWindow`, and other SwiftUI-native environment values

**What moves to Factory:**
- `HTTPClientProtocol` (currently `@Environment(\.httpClient)`)
- `KeychainManager` (currently singleton `.shared`)
- `CurlParser` (currently direct instantiation)
- `OpenAPIParser` (currently direct instantiation)
- `VariableInterpolator` (currently direct instantiation)
- `FileExporter` (currently direct instantiation)

**What does NOT move to Factory:**
- `RequestViewModel` — since `ModelContext` cannot be registered in Factory, the ViewModel is still constructed by the view. It uses `@Injected` internally for its service dependencies.

### Implementation Phases

---

#### Phase 1: Foundation — Add Factory + Protocols (Non-Breaking)

**Goal:** Add Factory SPM dependency, create protocols for services that benefit from abstraction, create the container. No existing code changes yet — purely additive.

##### Tasks

- [x] **Add Factory SPM package** to `PostKit.xcodeproj`
  - URL: `https://github.com/hmlongco/Factory.git`, version `2.5.0`+
  - Add `FactoryKit` product to `PostKit` target
  - Add `FactoryTesting` product to `PostKitTests` target

- [x] **Create service protocols** for services that benefit from abstraction

  > **Research Insight (Code Simplicity Reviewer):** `CurlParser`, `OpenAPIParser`, and `VariableInterpolator` are stateless, pure-function services. You never mock pure functions — you test them with real instances. Protocols for these add indirection without testability gain. However, for **consistency** across all Factory registrations, protocols are included. If this feels like too much ceremony, they can be omitted and the container can register concrete types directly.

  - `Services/Protocols/KeychainManagerProtocol.swift` — **essential** (enables Keychain mocking in tests)
  - `Services/Protocols/CurlParserProtocol.swift` — optional (consistency)
  - `Services/Protocols/OpenAPIParserProtocol.swift` — optional (consistency)
  - `Services/Protocols/VariableInterpolatorProtocol.swift` — optional (consistency)
  - `Services/Protocols/FileExporterProtocol.swift` — optional (consistency, `@MainActor`)
  - Each protocol must be `: Sendable` (matching existing service `Sendable` conformance)
  - `FileExporterProtocol` must be `@MainActor` at the protocol level (not just the container registration)

- [x] **Design `KeychainManagerProtocol` with minimal surface area**

  > **Research Insight (Pattern Recognition, Architecture Strategist):** Define only the three primitive methods. Provide convenience methods as protocol extension defaults to avoid mock implementations needing to implement trivial wrappers.

  ```swift
  protocol KeychainManagerProtocol: Sendable {
      func store(key: String, value: String) throws
      func retrieve(key: String) throws -> String?
      func delete(key: String) throws
  }

  // Default implementations for convenience methods
  extension KeychainManagerProtocol {
      func storeSecrets(_ secrets: [String: String]) throws {
          for (key, value) in secrets {
              try store(key: key, value: value)
          }
      }

      func retrieveSecrets(keys: [String]) throws -> [String: String] {
          var results: [String: String] = [:]
          for key in keys {
              if let value = try retrieve(key: key) {
                  results[key] = value
              }
          }
          return results
      }
  }
  ```

- [x] **Conform existing services** to their new protocols
  - `KeychainManager: KeychainManagerProtocol`
  - `CurlParser: CurlParserProtocol`
  - `OpenAPIParser: OpenAPIParserProtocol`
  - `VariableInterpolator: VariableInterpolatorProtocol`
  - `FileExporter: FileExporterProtocol`

- [x] **Create Factory container extensions** organized by domain:

  > **Research Insight (Pattern Recognition):** `Container+Export.swift` with a single registration is over-segmentation. Merge `fileExporter` into `Container+Services.swift`.

  - `DI/Container+Services.swift` — httpClient, keychainManager, fileExporter
  - `DI/Container+Parsers.swift` — curlParser, openAPIParser, variableInterpolator

- [x] **Build and verify** — project compiles, all existing tests pass

**Files created:**
```
PostKit/PostKit/
├── DI/
│   ├── Container+Services.swift
│   └── Container+Parsers.swift
├── Services/Protocols/
│   ├── KeychainManagerProtocol.swift
│   ├── CurlParserProtocol.swift
│   ├── OpenAPIParserProtocol.swift
│   ├── VariableInterpolatorProtocol.swift
│   └── FileExporterProtocol.swift
```

##### Scope Assignments

```swift
// Container+Services.swift
import FactoryKit

extension Container {
    var httpClient: Factory<HTTPClientProtocol> {
        // CRITICAL: Must include CurlHTTPClient with URLSessionHTTPClient fallback.
        // PostKitApp.swift currently uses CurlHTTPClient as the primary engine.
        // Dropping CurlHTTPClient would silently downgrade the HTTP engine.
        self {
            do {
                return try CurlHTTPClient()
            } catch {
                return URLSessionHTTPClient()
            }
        }.singleton
    }

    var keychainManager: Factory<KeychainManagerProtocol> {
        // Wraps the existing singleton — do NOT remove private init() or static let shared.
        // See Security section for rationale.
        self { KeychainManager.shared }.singleton
    }

    @MainActor
    var fileExporter: Factory<FileExporterProtocol> {
        self { @MainActor in FileExporter() }
    }
}
```

```swift
// Container+Parsers.swift
import FactoryKit

extension Container {
    var curlParser: Factory<CurlParserProtocol> {
        self { CurlParser() }  // .unique (default) — stateless
    }

    var openAPIParser: Factory<OpenAPIParserProtocol> {
        self { OpenAPIParser() }  // .unique — stateless
    }

    var variableInterpolator: Factory<VariableInterpolatorProtocol> {
        // .singleton — VariableInterpolator compiles an NSRegularExpression in init().
        // Avoiding recompilation on every ViewModel creation saves ~3-5μs per creation.
        self { VariableInterpolator() }.singleton
    }
}
```

**Scope rationale (updated per Performance Oracle + Pattern Recognition):**
- `httpClient` → `.singleton` — actor with internal state (`activeTasks`), one instance needed. **Must include CurlHTTPClient fallback.**
- `keychainManager` → `.singleton` — wraps existing singleton, Keychain is a system resource
- `variableInterpolator` → `.singleton` — compiles `NSRegularExpression` in `init()`; `Sendable` and immutable after init
- Parsers → `.unique` — stateless, lightweight, no benefit to caching
- `fileExporter` → `.unique` with `@MainActor` — uses `NSSavePanel`, each call site may need fresh state

### Research Insights: Performance Impact

> **Discovered by: Performance Oracle**

| Dimension | Current | Factory | Delta |
|-----------|---------|---------|-------|
| HTTPClient access | ~1ns (pointer) | ~50-100ns (lock + cache) | Negligible vs network I/O |
| KeychainManager access | ~1ns (static let) | ~50-100ns (lock + cache) | Negligible vs SecItem APIs (~1-2ms) |
| Parser creation | ~10ns (alloc + init) | ~60-110ns (lock + closure) | Negligible |
| Memory | ~0 overhead | ~600 bytes container | Negligible |
| Launch time | N/A | +~0.5-1ms (dyld) | Negligible for macOS |
| Thread contention | None | os_unfair_lock, uncontended | No regression |

**Verdict: No measurable performance regression in any scenario.**

---

#### Phase 2: Migration — Replace Injection Sites

**Goal:** Replace all three existing DI patterns with Factory. Migrate one service at a time, building and testing after each. **Commit after each step for safe rollback.**

##### Migration Order (risk-sorted, lowest risk first)

**Step 2a: Stateless parsers (lowest risk)**

Replace direct instantiation with `@Injected`:

| File | Before | After |
|------|--------|-------|
| `CurlImportSheet.swift:14` | `private let parser = CurlParser()` | `@Injected(\.curlParser) private var parser` |
| `OpenAPIImportSheet.swift:18` | `private let parser = OpenAPIParser()` | `@Injected(\.openAPIParser) private var parser` |

- [x] Update `CurlImportSheet` to use `@Injected(\.curlParser)`
- [x] Update `OpenAPIImportSheet` to use `@Injected(\.openAPIParser)`
- [x] Build and run existing tests — parsers are stateless, behavior unchanged
- [x] Verify SwiftUI Previews still work for these views (default registrations provide real implementations)
- [x] **Commit:** `feat: migrate parsers to Factory DI`

**Step 2b: VariableInterpolator in ViewModel**

| File | Before | After |
|------|--------|-------|
| `RequestViewModel.swift:23` | `private let interpolator = VariableInterpolator()` | `@ObservationIgnored @Injected(\.variableInterpolator) private var interpolator` |

> **Research Insight (All Reviewers):** `@ObservationIgnored` is **mandatory** on all `@Injected` properties in `@Observable` classes. Without it, the Observation framework tracks the property wrapper's internals, causing spurious re-renders or compile errors. Add an inline comment explaining this requirement.

```swift
// Factory @Injected properties MUST be marked @ObservationIgnored in @Observable classes.
// Without it, the Observation framework tracks dependency resolution as state changes,
// causing infinite re-render loops or compilation errors.
@ObservationIgnored @Injected(\.variableInterpolator) private var interpolator
```

- [x] Update `RequestViewModel` to use `@ObservationIgnored @Injected(\.variableInterpolator)`
- [x] Build and verify
- [x] **Commit:** `feat: migrate VariableInterpolator to Factory DI`

**Step 2c: FileExporter**

> **Research Insight (Architecture Strategist):** `PostKitApp.importCollection()` at line ~135 also directly instantiates `FileExporter()`. The original plan referenced "line 87" which is incorrect. Both usage sites must be migrated.

| File | Before | After |
|------|--------|-------|
| `CollectionRow.swift:13` | `private let exporter = FileExporter()` | `@Injected(\.fileExporter) private var exporter` |
| `PostKitApp.swift` `exportCollection()` | `let exporter = FileExporter()` | `let exporter = Container.shared.fileExporter()` |
| `PostKitApp.swift` `importCollection()` | `let exporter = FileExporter()` | `let exporter = Container.shared.fileExporter()` |

- [x] Update `CollectionRow` to use `@Injected(\.fileExporter)`
- [x] Update `PostKitApp.exportCollection()` to resolve from container
- [x] Update `PostKitApp.importCollection()` to resolve from container
- [x] Build and verify
- [x] **Commit:** `feat: migrate FileExporter to Factory DI`

**Step 2d: HTTPClient (replaces @Environment)**

This is the core migration — removing the custom `EnvironmentKey`.

> **Research Insight (Architecture Strategist):** `PostKitApp.swift` has a `httpClient` stored property (lines ~45-52) with `CurlHTTPClient` fallback logic AND an `.environment(\.httpClient, httpClient)` modifier. Both become dead code after migration and must be removed.

| File | Before | After |
|------|--------|-------|
| `RequestDetailView.swift:6` | `@Environment(\.httpClient) private var httpClient` | Remove — ViewModel resolves its own dependency |
| `RequestViewModel.swift:20` | `private let httpClient: HTTPClientProtocol` (constructor param) | `@ObservationIgnored @Injected(\.httpClient) private var httpClient` |
| `PostKitApp.swift:~45` | `private let httpClient: HTTPClientProtocol = { ... }()` | Remove — Factory container handles this |
| `PostKitApp.swift:~79` | `.environment(\.httpClient, httpClient)` | Remove |

- [x] Update `RequestViewModel` — remove `httpClient` from `init`, use `@ObservationIgnored @Injected`
- [x] Update `RequestViewModel.init` — remove `httpClient` parameter, keep only `modelContext`
- [x] Update `RequestDetailView` — remove `@Environment(\.httpClient)`, simplify ViewModel creation
- [x] Remove `httpClient` stored property from `PostKitApp`
- [x] Remove `.environment(\.httpClient, httpClient)` modifier from `PostKitApp`
- [x] Delete `Utilities/Environment+HTTPClient.swift` — no longer needed
- [x] Build and verify
- [x] **Commit:** `feat: migrate HTTPClient to Factory DI, remove @Environment`

**Step 2e: KeychainManager (replaces singleton)**

This is the **highest risk** migration because `KeychainManager.shared` is called from SwiftData `@Model` types (`Variable` and `AuthConfig`), which cannot receive injected dependencies.

> **SECURITY: Do NOT remove `private init()` or `static let shared`**
>
> **Discovered by: Security Sentinel** — Removing `private init()` allows rogue code to construct `KeychainManager()` instances that bypass the DI container and talk directly to the real Keychain. Instead, the Factory registration wraps the existing singleton:
>
> ```swift
> self { KeychainManager.shared }.singleton
> ```
>
> This preserves compile-time access restriction while enabling test overrides through the protocol.

**Strategy:** Since `@Model` types can't use property wrappers or receive injected dependencies, use `Container.shared` direct resolution:

```swift
// Before (in Variable.swift):
KeychainManager.shared.store(...)

// After:
Container.shared.keychainManager().store(...)
```

This is functionally equivalent (both access a singleton) but enables test overrides via `Container.shared.keychainManager.register { MockKeychain() }`.

> **Research Insight (Architecture Strategist):** This is a service locator pattern in `@Model` types — a necessary compromise. Consider extracting Keychain operations from `Variable` and `AuthConfig` into the ViewModel or a dedicated service in a follow-up PR. For this migration, the direct resolution is acceptable.

- [x] **Keep** `private init()` and `static let shared` on `KeychainManager`
- [x] Add `KeychainManagerProtocol` conformance to `KeychainManager`
- [x] Update `Variable.swift` — replace `KeychainManager.shared` with `Container.shared.keychainManager()`
- [x] Update `AuthType.swift` (all 3 methods: `storeSecrets`, `retrieveSecrets`, `deleteSecrets`) — replace `KeychainManager.shared` with `Container.shared.keychainManager()`
- [x] Add `import FactoryKit` to `Variable.swift` and `AuthType.swift`
- [x] Build and verify Keychain operations still work (manual test: create variable with secret, retrieve, delete)
- [x] Verify Keychain cleanup on request/variable deletion
- [x] **Commit:** `feat: migrate KeychainManager to Factory DI`

**Step 2f: Security hardening — Force-resolve singletons at launch**

> **Discovered by: Security Sentinel**

```swift
// In PostKitApp.init():
init() {
    cleanupStaleTempFiles()

    // Force-resolve singletons so the real implementations are cached
    // before any other code can register overrides.
    _ = Container.shared.httpClient()
    _ = Container.shared.keychainManager()

    #if !DEBUG
    // Runtime verification that the Keychain manager has not been tampered with
    assert(Container.shared.keychainManager() is KeychainManager,
           "KeychainManager has been replaced with an unexpected implementation")
    #endif
}
```

- [x] Add singleton force-resolution to `PostKitApp.init()`
- [x] Add runtime type assertion for release builds
- [x] Build and verify
- [x] **Commit:** `feat: add DI security hardening`

**Files modified in Phase 2:**
```
PostKit/PostKit/
├── Views/
│   ├── Import/CurlImportSheet.swift          (Step 2a)
│   ├── Import/OpenAPIImportSheet.swift        (Step 2a)
│   ├── Sidebar/CollectionRow.swift            (Step 2c)
│   └── RequestDetail/RequestDetailView.swift  (Step 2d)
├── ViewModels/RequestViewModel.swift          (Step 2b, 2d)
├── Models/Variable.swift                      (Step 2e)
├── Models/Enums/AuthType.swift                (Step 2e)
├── PostKitApp.swift                           (Step 2c, 2d, 2f)
```

**Files deleted:**
```
├── Utilities/Environment+HTTPClient.swift     (Step 2d)
```

---

#### Phase 3: Testing

**Goal:** Write ViewModel tests using Factory mock injection. Existing parser tests are **not changed** — they correctly test stateless services by direct instantiation.

> **Research Insight (Architecture Strategist):** Existing parser tests (`CurlParserTests`, `VariableInterpolatorTests`, `OpenAPIParserTests`) MUST NOT be changed to use Factory. They test service implementations directly, which is the correct unit testing approach for stateless logic.

##### Step 3a: Create Mock Implementations

- [ ] Create `PostKitTests/Mocks/MockHTTPClient.swift` — conforms to `HTTPClientProtocol`

  > **Security Insight:** All mock types MUST be in the **test target** (`PostKitTests`), not the main target. This ensures they are never compiled into release builds.

  ```swift
  actor MockHTTPClient: HTTPClientProtocol {
      var responseToReturn: HTTPResponse?
      var errorToThrow: Error?

      func execute(_ request: URLRequest, taskID: UUID) async throws -> HTTPResponse {
          if let error = errorToThrow { throw error }
          return responseToReturn ?? HTTPResponse(/* default */)
      }

      func cancel(taskID: UUID) async {
          // no-op for tests
      }
  }
  ```

- [ ] Create `PostKitTests/Mocks/MockKeychainManager.swift` — conforms to `KeychainManagerProtocol`

  > **Security Insight:** Must use in-memory dictionary, never touch real Keychain.

  ```swift
  final class MockKeychainManager: KeychainManagerProtocol, @unchecked Sendable {
      private var store: [String: String] = [:]

      func store(key: String, value: String) throws { store[key] = value }
      func retrieve(key: String) throws -> String? { store[key] }
      func delete(key: String) throws { store.removeValue(forKey: key) }
  }
  ```

##### Step 3b: Write ViewModel Tests

```swift
import Testing
import FactoryTesting
@testable import PostKit

@Suite(.container)
struct RequestViewModelTests {
    // MARK: - Positive Cases

    @Test func executeRequestReturnsResponse() async {
        Container.shared.httpClient.register { MockHTTPClient(response: .success) }
        let vm = RequestViewModel(modelContext: mockModelContext)
        await vm.executeRequest(request)
        #expect(vm.response != nil)
    }

    // MARK: - Negative Cases

    @Test func executeRequestHandlesNetworkError() async {
        Container.shared.httpClient.register { MockHTTPClient(error: .networkError) }
        let vm = RequestViewModel(modelContext: mockModelContext)
        await vm.executeRequest(request)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Edge Cases

    @Test func cancelRequestClearsActiveTask() async {
        Container.shared.httpClient.register { MockHTTPClient(delay: 5.0) }
        let vm = RequestViewModel(modelContext: mockModelContext)
        // start then cancel...
    }
}
```

> **Research Insight (Security Sentinel):** All test suites that exercise Keychain-adjacent code paths should register `MockKeychainManager` to avoid polluting the real Keychain. Use the `.container` trait at `@Suite` level.

- [ ] Write positive, negative, and edge case tests per testing standards
- [ ] Ensure all tests pass with `xcodebuild test`
- [ ] Verify existing parser tests still pass unchanged
- [ ] **Commit:** `test: add ViewModel tests with Factory mock injection`

---

#### Phase 4: Polish — Documentation + Cleanup

**Goal:** Update project documentation and clean up.

- [ ] **Update ADR document** — append ADR-019 (or next number) documenting the decision to adopt Factory:
  - Context: Three inconsistent DI patterns, ViewModels can't self-resolve, no ViewModel tests
  - Decision: Adopt Factory 2.5.x as unified DI container
  - Alternatives: Keep @Environment, Swinject, swift-dependencies, manual DI, **Protocol + static var (simpler alternative)**
  - Consequences: First third-party dependency, all services behind protocols, ViewModel testing enabled
  - **Acknowledge service locator trade-off explicitly**

- [ ] **Update CLAUDE.md** — reflect new DI patterns:
  - Replace "HTTP client is injected via SwiftUI `@Environment(\.httpClient)`" with Factory pattern
  - Add Factory container organization to architecture section
  - Update dependency injection section
  - Add mandatory `@ObservationIgnored @Injected` pattern documentation

- [ ] **Update `docs/sop/developer-guide.md`** — add Factory usage guide:
  - How to register a new service (with code template)
  - How to inject into ViewModels (`@ObservationIgnored @Injected`) vs Views (`@Injected`)
  - How to write tests with `.container` trait
  - **Mandatory pattern:** Always pair `@Injected` with `@ObservationIgnored` in `@Observable` classes

- [ ] **Clean up** — verify `Environment+HTTPClient.swift` is deleted, `PostKitApp.httpClient` property removed, no orphan references
- [ ] **Commit:** `docs: update documentation for Factory DI migration`

### Research Insights: SwiftUI Preview Support

> **Discovered by: Code Simplicity Reviewer**

The original plan included `Container+Previews.swift`. The Simplicity Reviewer found that existing `#Preview` blocks already work fine — they use `.modelContainer(for:..., inMemory: true)` and don't need mock services. Since Factory's default registrations provide real implementations, Previews will work without any mock setup.

**Decision:** Skip `Container+Previews.swift` for now. Only add it if Previews break after migration (unlikely since defaults are real implementations). This avoids premature infrastructure.

## Alternative Approaches Considered

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Keep @Environment** | Zero dependencies, SwiftUI-native | ViewModels can't self-resolve, no test support | Current ceiling reached |
| **Protocol + static var (no framework)** | ~40 LOC, zero deps, solves KeychainManager | Only fixes one problem; no test isolation trait; manual thread safety | Valid fallback if Factory proves too ceremonious |
| **Pure constructor injection** | No framework needed, explicit | Requires view passthrough, doesn't scale | Already partially used, insufficient |
| **swift-dependencies (TCA)** | Apple ecosystem, testable | Designed for Composable Architecture, heavy for MVVM | Over-engineered |
| **Swinject** | Mature, widely used | Runtime registration, no compile-time safety | Risk of runtime crashes |
| **Needle (Uber)** | Compile-time safe | Requires code generation, complex setup | Too heavy |
| **Factory** | Compile-time safe, lightweight, @Observable support, Swift Testing | First dependency, service locator pattern internally | **Selected** |

## Acceptance Criteria

### Functional Requirements

- [ ] All 6 services (`URLSessionHTTPClient`/`CurlHTTPClient`, `KeychainManager`, `CurlParser`, `OpenAPIParser`, `VariableInterpolator`, `FileExporter`) registered in Factory container
- [ ] All 6 services abstracted behind protocols
- [ ] **`httpClient` registration includes `CurlHTTPClient` with `URLSessionHTTPClient` fallback** (CRITICAL)
- [ ] `RequestViewModel` resolves `httpClient` and `variableInterpolator` from Factory (not view passthrough)
- [ ] `KeychainManager.shared` wrapped in Factory `.singleton` scope (**`private init()` and `static let shared` preserved**)
- [ ] SwiftData `@Model` types (`Variable`, `AuthConfig`) access `KeychainManager` via `Container.shared.keychainManager()`
- [ ] `@Environment(\.httpClient)` and `Environment+HTTPClient.swift` removed
- [ ] `PostKitApp.httpClient` stored property and `.environment(\.httpClient, ...)` removed
- [ ] `@Environment(\.modelContext)` remains (SwiftData stays as-is)
- [ ] All existing features work identically (HTTP execution, cURL import, OpenAPI import, Keychain secrets, file export)
- [ ] Singletons force-resolved at app launch for security

### Non-Functional Requirements

- [ ] Project builds with zero warnings under Swift strict concurrency
- [ ] All existing tests pass without modification
- [ ] New ViewModel tests added with positive/negative/edge cases
- [ ] Factory container registrations organized in `DI/` folder
- [ ] Protocols organized in `Services/Protocols/`
- [ ] All mock types in test target (not main target)

### Quality Gates

- [ ] All tests pass: `xcodebuild test -scheme PostKit -destination 'platform=macOS'`
- [ ] ADR document updated with Factory decision (including service locator trade-off)
- [ ] CLAUDE.md updated with new DI patterns
- [ ] Developer guide updated with Factory usage instructions (including mandatory `@ObservationIgnored` pattern)
- [ ] No `KeychainManager.shared` references remain in codebase (except `KeychainManager.swift` definition and Factory registration)
- [ ] No `@Environment(\.httpClient)` references remain in codebase
- [ ] No `PostKitApp.httpClient` stored property remains
- [ ] Code review: no circular dependencies in container graph
- [ ] Runtime type assertion exists for release builds

## Dependencies & Prerequisites

- **Factory 2.5.0+** — available via SPM, macOS 10.15+ (PostKit targets 14.0)
- **Xcode 16+** — already required by project
- **Swift 5.9+** — already used

**No blocking dependencies** — this migration can proceed independently.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **CurlHTTPClient dropped from registration** | Was High (now fixed) | Silent HTTP engine downgrade | Container registration includes try/catch fallback logic |
| `@ObservationIgnored` forgotten on `@Injected` in `@Observable` class | Medium | Build error or UI bugs | Mandatory inline comment; developer guide template; code review checklist |
| `KeychainManager` migration breaks secret storage | Medium | Data loss (stored secrets) | Keep `private init()` + `static let shared`; manual QA; Keychain keys unchanged |
| Mock injection in production | Low | Secret exfiltration | Force-resolve singletons at launch; runtime type assertion; mocks in test target only |
| Circular dependency in container graph | Low | Runtime crash (stack overflow) | Factory provides trace logging; dependency graph is flat (no inter-service deps) |
| Swift 6 `Sendable` warnings with Factory wrappers | Low | Build warnings | Factory 2.5.x is Swift 6 compatible |
| `ModelContext` cannot be registered in Factory | Known | Partial migration | Keep `@Environment(\.modelContext)` — community-accepted approach |
| Test parallelism interference | Low | Flaky tests | Use `.container` trait (serializes container access per test) |
| `Container.shared` mutable in `@Model` types | Low | Unexpected behavior if `reset()` called | Force-resolve at launch; no `reset()` outside `#if DEBUG` |
| Silent `try?` Keychain error swallowing | Pre-existing | Secret data loss | Fix in dedicated PR (see Pre-Existing Issues) |

### Research Insights: Security Checklist

> **Discovered by: Security Sentinel**

- [ ] `KeychainManager.private init()` is preserved
- [ ] `KeychainManager.static let shared` is preserved
- [ ] Factory registration uses `KeychainManager.shared`, not `KeychainManager()`
- [ ] Keychain singleton is force-resolved at app launch
- [ ] Runtime type assertion guards against production mock injection
- [ ] All mock types are in the test target or `#if DEBUG`
- [ ] `MockKeychainManager` uses in-memory storage, not real Keychain
- [ ] All test suites with Keychain paths use `.container` trait
- [ ] `FileExporter` redaction logic is unmodified and verified post-migration
- [ ] Keychain keys (`variable-{id}`, `auth-{type}-{requestID}`) are unchanged
- [ ] `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is preserved
- [ ] No `Container.shared.reset()` calls exist outside `#if DEBUG`

## File Layout After Migration

```
PostKit/PostKit/
├── DI/                                    ← NEW folder
│   ├── Container+Services.swift           ← httpClient, keychainManager, fileExporter
│   └── Container+Parsers.swift            ← curlParser, openAPIParser, variableInterpolator
├── Models/
│   ├── Variable.swift                     ← MODIFIED (Container.shared.keychainManager())
│   └── Enums/AuthType.swift               ← MODIFIED (Container.shared.keychainManager())
├── ViewModels/
│   └── RequestViewModel.swift             ← MODIFIED (@Injected, simplified init)
├── Views/
│   ├── Import/CurlImportSheet.swift       ← MODIFIED (@Injected)
│   ├── Import/OpenAPIImportSheet.swift     ← MODIFIED (@Injected)
│   ├── Sidebar/CollectionRow.swift         ← MODIFIED (@Injected)
│   └── RequestDetail/RequestDetailView.swift ← MODIFIED (simplified ViewModel creation)
├── Services/
│   ├── KeychainManager.swift              ← MODIFIED (add protocol conformance; keep private init + shared)
│   └── Protocols/
│       ├── HTTPClientProtocol.swift       ← EXISTING (unchanged)
│       ├── KeychainManagerProtocol.swift   ← NEW
│       ├── CurlParserProtocol.swift        ← NEW
│       ├── OpenAPIParserProtocol.swift     ← NEW
│       ├── VariableInterpolatorProtocol.swift ← NEW
│       └── FileExporterProtocol.swift      ← NEW
├── Utilities/
│   └── (Environment+HTTPClient.swift)     ← DELETED
└── PostKitApp.swift                       ← MODIFIED (remove httpClient property, add security hardening)

PostKit/PostKitTests/
├── Mocks/
│   ├── MockHTTPClient.swift               ← NEW (test target only)
│   └── MockKeychainManager.swift          ← NEW (test target only, in-memory storage)
└── PostKitTests.swift                     ← MODIFIED (add ViewModel tests)
```

## Success Metrics

- **Unified DI:** All services resolved through Factory container (zero direct instantiation in views/ViewModels)
- **Protocol coverage:** 6/6 services behind protocols (up from 1/6)
- **Test coverage:** ViewModel tests exist (up from zero)
- **Test isolation:** All new tests use `.container` trait for reliable parallel execution
- **Zero regressions:** All existing functionality works identically
- **Security preserved:** Keychain access patterns unchanged; singletons locked at launch

## Pre-Existing Issues to Address (Separate PRs)

> **Discovered by: Data Integrity Guardian, Security Sentinel**

These should be fixed **before or alongside** the Factory migration:

| Issue | Severity | Files | Fix |
|-------|----------|-------|-----|
| Keychain cleanup never called on delete | Critical | `RequestListView.swift`, `CollectionRow.swift`, `EnvironmentPicker.swift` | Call `deleteSecureValue()` / `deleteSecrets()` before `modelContext.delete()` |
| UI binds to `variable.value` not `secureValue` | Critical | `EnvironmentPicker.swift:199`, `RequestViewModel.swift:165` | Use custom `Binding` for `secureValue`; read `secureValue` in ViewModel |
| Silent `try?` error swallowing in secureValue setter | Medium | `Variable.swift:41` | Only clear plaintext if Keychain store succeeds |
| `HTTPRequest.duplicated()` loses auth credentials | Low | `HTTPRequest.swift:77` | Copy Keychain entries to new request ID after duplication |

## Future Considerations

- **Extract Keychain from @Model types:** Move `Variable.secureValue` and `AuthConfig.storeSecrets/retrieveSecrets/deleteSecrets` logic into a dedicated `SecretStorageService` that the ViewModel calls. This eliminates `Container.shared` direct resolution from model types and removes `import FactoryKit` from model files.
- **Additional ViewModels:** As the app grows, follow the same `@ObservationIgnored @Injected` pattern
- **Custom containers:** Only if PostKit grows to have distinct SPM modules
- **Reassess Factory:** If the project stays at 6 services and 1 ViewModel for an extended period, consider whether the simpler `Protocol + static var` approach would suffice

## References

### Internal References

- ADR-003 (Zero Dependencies): `docs/adr/0001-postkit-architecture-decisions.md` — justification for adding Factory
- ADR-010 (DI via Environment): `docs/adr/0001-postkit-architecture-decisions.md` — the pattern being replaced
- Current DI infrastructure: `PostKit/Utilities/Environment+HTTPClient.swift`
- HTTP client protocol: `PostKit/Services/Protocols/HTTPClientProtocol.swift`
- KeychainManager singleton: `PostKit/Services/KeychainManager.swift:27-29`
- CurlHTTPClient (primary engine): `PostKit/Services/CurlHTTPClient.swift`
- PostKitApp httpClient with fallback: `PostKit/PostKitApp.swift:45-52`
- ViewModel constructor injection: `PostKit/ViewModels/RequestViewModel.swift:33-36`
- View passthrough pattern: `PostKit/Views/RequestDetail/RequestDetailView.swift:49-55`
- Variable.secureValue: `PostKit/Models/Variable.swift:34-48`
- AuthConfig Keychain access: `PostKit/Models/Enums/AuthType.swift:60-106`

### External References

- Factory GitHub: https://github.com/hmlongco/Factory
- Factory documentation: https://hmlongco.github.io/Factory/documentation/factorykit
- Factory Swift Testing support: `FactoryTesting` module with `.container` trait
- Import change (2.5.0): `import FactoryKit` replaces `import Factory`
- Swift Package Index: https://swiftpackageindex.com/hmlongco/Factory
