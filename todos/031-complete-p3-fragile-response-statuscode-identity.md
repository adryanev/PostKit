---
status: pending
priority: p3
issue_id: "031"
tags: [code-review, correctness, syntax-highlighting]
dependencies: []
---

# Fragile `.id(response.statusCode)` View Identity

## Problem Statement
In `ResponseViewerPane.swift` line 121, `.id(response.statusCode)` is used to force view recreation when the response changes. However, if two consecutive responses have the same status code (e.g., both 200 OK), SwiftUI won't recreate the CodeTextView, potentially showing stale content.

## Findings
- **Location:** `PostKit/PostKit/Views/RequestDetail/ResponseViewer/ResponseViewerPane.swift:121`
- **Code:** `.id(response.statusCode)`
- **Agents:** code-simplicity-reviewer

## Proposed Solutions

### Solution A: Use a unique response identifier (Recommended)
Add a `UUID` or combine status code with a hash of content:
```swift
.id(response.statusCode.hashValue ^ response.size.hashValue ^ response.duration.hashValue)
```
Or better, add an `id: UUID = UUID()` property to `HTTPResponse`.

**Effort:** Small | **Risk:** Low

### Solution B: Remove .id() entirely
The `cachedDisplayString` binding already updates the text content. If the CodeTextView properly reacts to text changes via `updateNSView`, the `.id()` may not be needed at all.

**Effort:** Small | **Risk:** Low (needs testing)

## Acceptance Criteria
- [ ] Consecutive responses with same status code display correctly
- [ ] View updates reliably when new response arrives

## Work Log
- 2026-02-15: Created from PR #5 code review (code-simplicity-reviewer agent)
