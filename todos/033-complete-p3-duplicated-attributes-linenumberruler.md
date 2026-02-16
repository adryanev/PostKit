---
status: complete
priority: p3
issue_id: "033"
tags: [code-review, quality, syntax-highlighting]
dependencies: []
---

# Duplicated Attribute Dictionaries in LineNumberRulerView

## Problem Statement
In `LineNumberRulerView.swift`, the same `NSAttributedString` attributes (font, foreground color, paragraph style) are defined twice: once in `precacheLineNumbers()` (lines 44-51) and again in `drawHashMarksAndLabels` (lines 106-113). This violates DRY and risks the two drifting out of sync.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/LineNumberRulerView.swift:44-51, 106-113`
- **Agents:** code-simplicity-reviewer

## Proposed Solutions

### Solution A: Extract shared attributes property (Recommended)
Create a lazy or computed property for the attributes dictionary:
```swift
private var lineNumberAttributes: [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .right
    return [
        .font: lineNumberFont,
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: paragraphStyle
    ]
}
```

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [ ] Attribute dictionary defined once and reused
- [ ] Line numbers render identically

## Work Log
- 2026-02-15: Created from PR #5 code review (code-simplicity-reviewer agent)
