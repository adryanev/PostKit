---
status: complete
priority: p3
issue_id: "037"
tags: [code-review, performance, syntax-highlighting]
dependencies: []
---

# Redundant text.utf8.count O(n) Calls

## Problem Statement
In `CodeTextView.swift` lines 33 and 117, `text.utf8.count` is called to check against `highlightingThreshold`. `String.utf8.count` iterates the string's UTF-8 representation, making it O(n). It's called both in `makeNSView` and `updateNSView` (when language changes).

## Findings
- **Location:** `PostKit/PostKit/Views/Components/CodeTextView.swift:33, 117`
- **Code:** `text.utf8.count <= highlightingThreshold`
- **Agents:** performance-oracle

## Proposed Solutions

### Solution A: Cache byte count in coordinator (Recommended)
Compute once per text change and store in the coordinator:
```swift
// In coordinator
var lastTextByteCount: Int = 0

// In updateNSView, compute once if text changed
let byteCount = text.utf8.count
context.coordinator.lastTextByteCount = byteCount
```

**Effort:** Small | **Risk:** Low

### Solution B: Pass byte count as parameter
Since `ResponseBodyView` already knows the data size, pass it to `CodeTextView`.

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [x] `text.utf8.count` is not called redundantly
- [x] Highlighting threshold still works correctly

## Work Log
- 2026-02-15: Created from PR #5 code review (performance-oracle agent)
- 2026-02-16: Added lastTextByteCount to Coordinator, compute once per text change in makeNSView, updateNSView (read-only), and textDidChange
