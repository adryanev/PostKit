---
status: complete
priority: p2
issue_id: "023"
tags: [code-review, security, memory, syntax-highlighting]
dependencies: []
---

# Crash Risk: `unowned var textView: NSTextView!` in Coordinator

## Problem Statement
In `CodeTextView.swift` line 131, the Coordinator holds an `unowned var textView: NSTextView!` reference. If the NSTextView is deallocated before the Coordinator (e.g., during rapid SwiftUI view lifecycle changes), accessing this property will crash with a dangling pointer. The implicit unwrap (`!`) compounds the risk — even a `nil` check won't protect against use-after-free on `unowned`.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/CodeTextView.swift:131`
- **Code:** `unowned var textView: NSTextView!`
- **Evidence:** `unowned` references crash immediately on access if the referenced object has been deallocated; there is no nil-checking safety net
- **Impact:** App crash during rapid view recycling or dealloc ordering edge cases
- **Agents:** security-sentinel

## Proposed Solutions

### Solution A: Change to `weak var` (Recommended)
Replace `unowned var textView: NSTextView!` with `weak var textView: NSTextView?` and add nil guards at call sites.

**Pros:** Safe against dealloc ordering issues, standard AppKit pattern
**Cons:** Requires optional unwrapping at usage sites (2 locations: `textDidChange` and `updateNSView`)
**Effort:** Small
**Risk:** Low

### Solution B: Keep unowned but remove implicit unwrap
Change to `unowned var textView: NSTextView` and set it in `makeNSView` via a two-phase init.

**Pros:** No optional unwrapping needed
**Cons:** Still crashes if dealloc ordering is wrong; doesn't fully solve the problem
**Effort:** Small
**Risk:** Medium (dealloc ordering still a concern)

## Recommended Action


## Technical Details
- **Affected files:** `PostKit/PostKit/Views/Components/CodeTextView.swift`
- **Components:** CodeTextView.Coordinator
- **Usage sites:** line 72 (assignment), line 146 (textDidChange uses notification.object instead), line 84 (updateNSView uses scrollView.textView instead)

## Acceptance Criteria
- [ ] `textView` reference uses `weak var` with proper nil guards
- [ ] No force-unwraps on the textView reference
- [ ] App does not crash when rapidly switching views

## Work Log
- 2026-02-15: Created from PR #5 code review (security-sentinel agent)

## Resources
- PR: #5 feat: add syntax highlighting with Highlightr
