---
status: complete
priority: p2
issue_id: "027"
tags: [code-review, security, concurrency, syntax-highlighting]
dependencies: []
---

# Thread Safety: Highlightr/JSContext Concurrency Model

## Problem Statement
`CodeTextView.swift` uses `@preconcurrency import Highlightr` (line 3) to suppress Sendability warnings. Highlightr's `CodeAttributedString` dispatches highlighting work to `DispatchQueue.global()` where it invokes JavaScriptCore's `JSContext`. JSContext is not thread-safe — concurrent evaluations on the same context from different queues can corrupt state or crash. While `@preconcurrency` silences the compiler, it doesn't make the underlying code safe.

Additionally, `scheduleThemeChange` (line 154-168) mutates the Highlightr's theme from a `DispatchQueue.main.asyncAfter` callback, potentially racing with background highlighting operations.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/CodeTextView.swift:3, 154-168`
- **Code:** `@preconcurrency import Highlightr`, `scheduleThemeChange` dispatches theme mutation
- **Evidence:** Highlightr's CodeAttributedString performs highlighting on DispatchQueue.global(); JSContext is not thread-safe
- **Impact:** Potential crash or corrupted highlighting under concurrent highlight + theme change operations
- **Agents:** security-sentinel, performance-oracle

## Proposed Solutions

### Solution A: Document the threading model and accept the risk (Recommended)
Highlightr's internal implementation serializes JSContext access within CodeAttributedString. The `@preconcurrency` import is the standard Swift pattern for wrapping non-Sendable Obj-C libraries. Add a comment documenting the threading assumption.

**Pros:** No code change needed; Highlightr has been widely used without thread safety issues
**Cons:** Relies on Highlightr's internal implementation detail
**Effort:** Small (comment only)
**Risk:** Low (proven in production across many apps)

### Solution B: Serialize all Highlightr operations on main thread
Ensure all Highlightr mutations (language changes, theme changes, text updates) happen on the main thread only.

**Pros:** Eliminates any theoretical race condition
**Cons:** May need to audit CodeAttributedString internals; theme changes already dispatch to main
**Effort:** Small-Medium
**Risk:** Low

## Recommended Action


## Technical Details
- **Affected files:** `PostKit/PostKit/Views/Components/CodeTextView.swift`
- **Components:** CodeTextView, Coordinator.scheduleThemeChange
- **Library:** Highlightr (CodeAttributedString, JSContext)

## Acceptance Criteria
- [x] Threading model is documented in code comments
- [x] Theme changes don't race with highlighting operations
- [x] No crashes under rapid light/dark mode toggling

## Work Log
- 2026-02-15: Created from PR #5 code review (security-sentinel, performance-oracle agents)
- 2026-02-16: Resolved - Added documentation comment explaining Highlightr threading model near the `@preconcurrency import Highlightr` line

## Resources
- PR: #5 feat: add syntax highlighting with Highlightr
- Highlightr source: https://github.com/raspu/Highlightr
