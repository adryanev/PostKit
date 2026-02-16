---
status: complete
priority: p3
issue_id: "032"
tags: [code-review, quality, syntax-highlighting]
dependencies: []
---

# BodyType.highlightrLanguage: Use Default Case for Nil Returns

## Problem Statement
In `BodyType.swift` lines 22-31, `highlightrLanguage` explicitly returns `nil` for 4 cases (`.none`, `.raw`, `.urlEncoded`, `.formData`). This can be simplified with a `default` case.

## Findings
- **Location:** `PostKit/PostKit/Models/Enums/BodyType.swift:22-31`
- **Agents:** code-simplicity-reviewer

## Proposed Solutions

### Solution A: Use default case (Recommended)
```swift
var highlightrLanguage: String? {
    switch self {
    case .json: return "json"
    case .xml: return "xml"
    default: return nil
    }
}
```

**Effort:** Small | **Risk:** Low
**Note:** Using `default` means new cases added to the enum won't trigger a compiler warning to update this property. Given this is a simple mapping, the trade-off is acceptable.

## Acceptance Criteria
- [x] Redundant nil cases replaced with default
- [x] Language mapping still works correctly

## Work Log
- 2026-02-15: Created from PR #5 code review (code-simplicity-reviewer agent)
- 2026-02-16: Applied fix - replaced 4 explicit nil cases with default case (pr-comment-resolver)
