---
status: complete
priority: p3
issue_id: "036"
tags: [code-review, performance, syntax-highlighting]
dependencies: []
---

# O(n) String Equality Check on Every updateNSView Call

## Problem Statement
In `CodeTextView.swift` line 91, `textView.string != text` performs an O(n) character comparison. SwiftUI calls `updateNSView` frequently on any state change in the parent hierarchy. For a 256KB response, this is ~256K character comparisons per update cycle, even when nothing changed.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/CodeTextView.swift:91`
- **Code:** `if textView.string != text { ... }`
- **Agents:** performance-oracle

## Proposed Solutions

### Solution A: Use coordinator's lastWrittenText for fast path (Recommended)
For read-only mode, compare against the coordinator's `lastWrittenText` which is already tracked:
```swift
if !isEditable {
    if text != context.coordinator.lastWrittenText {
        textView.string = text
        context.coordinator.lastWrittenText = text
    }
}
```

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [x] updateNSView avoids O(n) comparison when text hasn't changed
- [x] Text still updates correctly when new response arrives

## Work Log
- 2026-02-15: Created from PR #5 code review (performance-oracle agent)
- 2026-02-16: Implemented fast path comparison using coordinator's lastWrittenText
