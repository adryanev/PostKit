---
status: complete
priority: p2
issue_id: "025"
tags: [code-review, performance, syntax-highlighting]
dependencies: []
---

# LineNumberRulerView countLines O(n) Scans Entire Document on Every Draw

## Problem Statement
In `LineNumberRulerView.swift` line 125, `countLines(in: text)` is called during every `drawHashMarksAndLabels` invocation. This method (lines 173-181) iterates through every character in the document to count newlines. For a large response (e.g., 500KB JSON), this is ~500K character comparisons on every scroll frame or text edit. Combined with the earlier character-by-character scan at lines 118-123 to find the starting line number, each draw pass does two O(n) scans.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/LineNumberRulerView.swift:125, 173-181`
- **Code:** `let totalLineCount = countLines(in: text)` called inside `drawHashMarksAndLabels`
- **Evidence:** The method iterates `0..<text.length` comparing each character
- **Impact:** Scroll jank and high CPU usage on large documents; draw is called on every scroll event
- **Agents:** performance-oracle, code-simplicity-reviewer

## Proposed Solutions

### Solution A: Cache line count and update on text change (Recommended)
Store `cachedLineCount` as a property. Update it only in `textDidChange(_:)` handler, not during draw.

```swift
private var cachedLineCount: Int = 1

@objc private func textDidChange(_ notification: Notification) {
    if let tv = clientTextView {
        cachedLineCount = countLines(in: tv.string as NSString)
    }
    scheduleRedraw()
}
```

**Pros:** Eliminates O(n) from the hot draw path; simple change
**Cons:** Line count is one text-change behind (acceptable since draw is async anyway)
**Effort:** Small
**Risk:** Low

### Solution B: Use NSString.enumerateSubstrings for counting
Replace character-by-character scan with `enumerateSubstrings(in:, options: .byLines)` which is optimized by Foundation.

**Pros:** Faster than manual iteration; handles Unicode correctly
**Cons:** Still O(n) per call; doesn't solve the "called every draw" problem
**Effort:** Small
**Risk:** Low

### Solution C: Incremental line counting
Track line count and update it incrementally on each text edit by analyzing only the changed range.

**Pros:** O(delta) per edit, optimal
**Cons:** More complex; needs to handle `NSTextStorageDelegate` edited ranges
**Effort:** Medium
**Risk:** Medium (edge cases with bulk replacements)

## Recommended Action


## Technical Details
- **Affected files:** `PostKit/PostKit/Views/Components/LineNumberRulerView.swift`
- **Components:** LineNumberRulerView.drawHashMarksAndLabels, countLines
- **Also note:** Lines 118-123 do a second O(n) scan to find the starting line number for the visible range. This could also be cached/optimized, but it's bounded by the visible range start position, not the full document.

## Acceptance Criteria
- [ ] `countLines` is not called during `drawHashMarksAndLabels`
- [ ] Line count is cached and updated only on text changes
- [ ] Scrolling remains smooth with 500KB+ response bodies
- [ ] Line numbers remain correct after text edits

## Work Log
- 2026-02-15: Created from PR #5 code review (performance-oracle, code-simplicity-reviewer agents)

## Resources
- PR: #5 feat: add syntax highlighting with Highlightr
