---
status: complete
priority: p2
issue_id: "011"
tags: [code-review, performance]
dependencies: []
---

# JSON Decode on Every @Transient Property Access

## Problem Statement

`HTTPRequest` uses `@Transient` computed properties that decode JSON `Data` blobs on every access. Since SwiftUI can evaluate view bodies multiple times per frame, `authConfig`, `headersList`, and `queryParamsList` each trigger `JSONDecoder()` on every SwiftUI evaluation cycle.

**Why it matters:** Unnecessary JSON deserialization on every render causes CPU waste and potential frame drops.

## Findings

- **HTTPRequest.swift** — `@Transient` properties like `authConfig` call `JSONDecoder().decode()` on every getter access
- SwiftUI may call view body dozens of times during animations or state changes
- Creating a new `JSONDecoder()` instance on every call adds overhead
- **Confirmed by:** Architecture Strategist, Performance Oracle agents

## Proposed Solutions

### Option A: Cache decoded values (Recommended)
- Store decoded value in a non-persistent `@Transient` stored property
- Invalidate cache when the underlying Data changes
- **Pros:** Eliminates repeated decoding
- **Cons:** Cache invalidation complexity
- **Effort:** Small
- **Risk:** Low

### Option B: Use stored properties directly
- Replace JSON Data blobs with proper SwiftData relationships or stored properties
- **Pros:** No encoding/decoding at all
- **Cons:** Larger data model refactor
- **Effort:** Large
- **Risk:** Medium

## Technical Details

- **Affected files:** `HTTPRequest.swift`

## Acceptance Criteria

- [x] JSON decoding happens once per data change, not per view evaluation
- [x] No performance degradation during rapid UI updates

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | SwiftUI evaluates bodies frequently — avoid work in getters |
| 2026-02-13 | Implemented Option A (cache decoded values) | Added _cachedAuthConfig and _authConfigDataSnapshot backing properties to avoid repeated JSON decoding |

## Resources

- Branch: `feat/mvp-architecture`
