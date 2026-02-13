---
status: complete
priority: p1
issue_id: "001"
tags: [code-review, bug, architecture]
dependencies: []
---

# Broken Request Cancellation (UUID Mismatch)

## Problem Statement

Request cancellation is a complete no-op. `RequestDetailView` creates its own `currentTaskID` (UUID) but never passes it to `httpClient.execute()`. The HTTPClient actor generates its own internal UUID for task tracking. When `cancel(taskID:)` is called with the view's UUID, it never matches the actor's internal task map, so nothing gets cancelled.

**Why it matters:** Users clicking "Cancel" on a long-running request will see no effect. This is a broken core feature confirmed by 4 out of 5 review agents.

## Findings

- **RequestDetailView.swift:69** — `currentTaskID = UUID()` created locally
- **RequestDetailView.swift** — `httpClient.execute(request:)` does not accept or return a task ID
- **HTTPClient.swift** — `execute()` creates its own internal `let taskID = UUID()`, stores it in `activeTasks[taskID]`, but never exposes it to the caller
- **HTTPClient.swift** — `cancel(taskID:)` looks up `activeTasks[taskID]` which will never match the view's UUID
- **Confirmed by:** Security Sentinel, Architecture Strategist, Pattern Recognition, Code Simplicity agents

## Proposed Solutions

### Option A: Return taskID from execute() (Recommended)
- Change `execute()` to return `(HTTPResponse, UUID)` or accept an externally-provided UUID
- View stores the returned UUID and passes it to `cancel()`
- **Pros:** Minimal change, clean contract
- **Cons:** Changes protocol signature
- **Effort:** Small
- **Risk:** Low

### Option B: Use Swift structured concurrency
- Replace manual task tracking with `Task.cancel()` on the Swift Task itself
- View holds reference to the `Task<HTTPResponse, Error>` directly
- **Pros:** Idiomatic Swift, no UUID tracking needed
- **Cons:** Larger refactor, changes HTTPClient interface
- **Effort:** Medium
- **Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files:** `HTTPClient.swift`, `HTTPClientProtocol.swift`, `RequestDetailView.swift`
- **Components:** HTTP networking, request lifecycle

## Acceptance Criteria

- [ ] Clicking "Cancel" actually cancels the in-flight URLSession task
- [ ] UI updates to reflect cancellation
- [ ] Cancelling a completed request is a safe no-op

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Found by 4/5 review agents — high confidence |

## Resources

- Branch: `feat/mvp-architecture`
