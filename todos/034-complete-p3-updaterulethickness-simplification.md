---
status: complete
priority: p3
issue_id: "034"
tags: [code-review, quality, syntax-highlighting]
dependencies: []
---

# updateRuleThickness Branching Can Be Simplified

## Problem Statement
In `LineNumberRulerView.swift` lines 183-200, `updateRuleThickness` uses three branches (>9999, >999, else) with slightly different formulas. The logic can be expressed as a single calculation.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/LineNumberRulerView.swift:183-200`
- **Agents:** code-simplicity-reviewer

## Proposed Solutions

### Solution A: Single formula (Recommended)
```swift
private func updateRuleThickness(forLineCount lineCount: Int) {
    let digitCount = max(3, "\(lineCount)".count)
    let newThickness: CGFloat = 40 + CGFloat(max(0, digitCount - 3)) * 8
    if abs(ruleThickness - newThickness) > 0.5 {
        ruleThickness = newThickness
    }
}
```

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [ ] Ruler thickness calculation uses a single formula
- [ ] Ruler width still expands correctly for 4+ digit line numbers

## Work Log
- 2026-02-15: Created from PR #5 code review (code-simplicity-reviewer agent)
