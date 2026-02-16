---
status: complete
priority: p3
issue_id: "028"
tags: [code-review, quality, syntax-highlighting]
dependencies: []
---

# Dead Code: maxCachedLineNumbers=10000 Always Resolves to 1000

## Problem Statement
In `LineNumberRulerView.swift` line 9, `maxCachedLineNumbers` is set to 10000, but line 53 uses `min(maxCachedLineNumbers, 1000)` which always evaluates to 1000. The constant is misleading dead code.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/LineNumberRulerView.swift:9, 53`
- **Code:** `private let maxCachedLineNumbers = 10000` and `for i in 1...min(maxCachedLineNumbers, 1000)`
- **Agents:** code-simplicity-reviewer

## Proposed Solutions

### Solution A: Remove the constant, inline 1000 (Recommended)
Replace with `for i in 1...1000` and delete the `maxCachedLineNumbers` property.

**Effort:** Small | **Risk:** Low

### Solution B: Fix the min() to use the constant correctly
Change to `for i in 1...maxCachedLineNumbers` if 10000 was the intended cache size.

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [ ] No dead code constants remain
- [ ] Line number caching works correctly

## Work Log
- 2026-02-15: Created from PR #5 code review (code-simplicity-reviewer agent)
