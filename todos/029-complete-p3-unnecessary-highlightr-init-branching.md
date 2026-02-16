---
status: complete
priority: p3
issue_id: "029"
tags: [code-review, quality, syntax-highlighting]
dependencies: []
---

# Unnecessary Highlightr Init Fallback Branching

## Problem Statement
In `CodeTextView.swift` lines 22-27, the code creates a `Highlightr()` instance and then branches on whether it's nil. However, `CodeAttributedString()` (the else branch) also creates its own internal Highlightr. The if/else provides no meaningful fallback — both paths end up with a Highlightr-backed CodeAttributedString.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/CodeTextView.swift:22-27`
- **Code:**
  ```swift
  let highlightr = Highlightr()
  let textStorage: CodeAttributedString
  if let highlightr = highlightr {
      textStorage = CodeAttributedString(highlightr: highlightr)
  } else {
      textStorage = CodeAttributedString()
  }
  ```
- **Agents:** code-simplicity-reviewer

## Proposed Solutions

### Solution A: Simplify to single init (Recommended)
```swift
let textStorage = CodeAttributedString()
```
The default init creates its own Highlightr internally. If Highlightr init fails (missing highlight.js bundle), both paths fail equally.

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [ ] Highlightr init branching is simplified
- [ ] Syntax highlighting still works correctly

## Work Log
- 2026-02-15: Created from PR #5 code review (code-simplicity-reviewer agent)
