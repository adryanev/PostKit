---
status: complete
priority: p2
issue_id: "006"
tags: [code-review, architecture]
dependencies: []
---

# RequestDetailView is a God Object

## Problem Statement

`RequestDetailView` (245 lines) handles 6+ responsibilities: request building, auth configuration, variable interpolation, history recording, HTTP execution, cancellation, and all associated UI. This makes it untestable and hard to maintain.

**Why it matters:** Concentrated logic makes bugs harder to find and prevents unit testing of business logic.

## Findings

- **RequestDetailView.swift** — 245 lines, mixes business logic with UI
- Request building logic (auth headers, body assembly) embedded in view
- History cleanup runs inline after every request
- Variable interpolation called directly from view
- **Confirmed by:** Architecture Strategist, Pattern Recognition agents

## Proposed Solutions

### Option A: Extract a RequestExecutor service (Recommended)
- Move request building, auth injection, interpolation, and history recording into a dedicated service
- View only handles UI state and delegates to the service
- **Pros:** Testable, single responsibility
- **Cons:** New file, slightly more indirection
- **Effort:** Medium
- **Risk:** Low

### Option B: Use a ViewModel/ObservableObject
- Extract state and logic into an `@Observable` class
- View becomes a thin rendering layer
- **Pros:** Standard SwiftUI pattern, testable
- **Cons:** Adds a layer
- **Effort:** Medium
- **Risk:** Low

## Technical Details

- **Affected files:** `RequestDetailView.swift`, new service/viewmodel file
- **Components:** Request execution, UI architecture

## Acceptance Criteria

- [ ] RequestDetailView under 100 lines
- [ ] Business logic testable without UI
- [ ] No change in user-facing behavior

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | God object confirmed by multiple agents |

## Resources

- Branch: `feat/mvp-architecture`
