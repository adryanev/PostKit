---
status: complete
priority: p1
issue_id: "038"
tags: [architecture, mvvm, swiftui, code-review]
dependencies: []
---

# MenuBarView Contains Business Logic (MVVM Violation)

MenuBarView.swift contains 60+ lines of request execution logic that should be in a ViewModel.

## Problem Statement

The `MenuBarView` SwiftUI view contains business logic for HTTP request execution, violating PostKit's MVVM architecture (ADR-004, ADR-013). Views should be thin rendering layers; ViewModels should own business logic.

**Why this matters:**
- Violates core architectural principle defined in ADRs
- Code is untestable without UI
- Duplicates logic from `RequestViewModel.sendRequest()`
- Inconsistent patterns between main window and menu bar

## Findings

- **Location:** `MenuBarView.swift:67-127`
- **Issues found:**
  - `@Injected` services (`httpClient`, `requestBuilder`) in View
  - `sendRequest()` method with 40+ lines of business logic
  - State management (`results`, `sendingRequestIDs`) in View
  - ModelContext access and history persistence in View

**Related ADRs:**
- ADR-004: "Views are thin rendering layers. ViewModels own business logic."
- ADR-013: "Single RequestViewModel pattern with all request-related state"

## Proposed Solutions

### Option 1: Create MenuBarViewModel (Recommended)

**Approach:** Extract all request logic to a new `MenuBarViewModel` class.

**Pros:**
- Follows established MVVM pattern
- Makes code testable
- Centralizes request logic
- Consistent with main window architecture

**Cons:**
- Adds new file
- Requires small refactoring

**Effort:** 1-2 hours

**Risk:** Low

---

### Option 2: Reuse RequestViewModel

**Approach:** Have MenuBarView use the existing RequestViewModel.

**Pros:**
- No new code
- Shared logic

**Cons:**
- RequestViewModel designed for single request editing
- Overkill for simple menu bar execution
- May carry unnecessary state

**Effort:** 2-3 hours

**Risk:** Medium

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Views/MenuBar/MenuBarView.swift:67-127`
- New file needed: `PostKit/PostKit/ViewModels/MenuBarViewModel.swift`

**Pattern to follow:**
```swift
@Observable
final class MenuBarViewModel {
    var results: [UUID: MenuBarResult] = [:]
    var sendingRequestIDs: Set<UUID> = []
    
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.requestBuilder) private var requestBuilder
    private let modelContext: ModelContext
    
    func sendRequest(_ request: HTTPRequest) async { ... }
}
```

## Acceptance Criteria

- [ ] MenuBarViewModel created with all request execution logic
- [ ] MenuBarView only contains UI rendering code
- [ ] @Injected properties marked @ObservationIgnored
- [ ] Unit tests for MenuBarViewModel.sendRequest()
- [ ] All existing menu bar functionality works

## Work Log

### 2026-02-21 - Code Review Discovery

**By:** architecture-strategist agent

**Actions:**
- Identified MVVM violation during code review
- Analyzed scope of refactoring needed
- Proposed two solution approaches

**Learnings:**
- Pattern exactly matches what ADR-004/ADR-013 were designed to prevent
- Similar to RequestViewModel pattern, can follow established conventions
