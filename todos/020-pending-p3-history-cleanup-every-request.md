---
status: complete
priority: p3
issue_id: "020"
tags: [code-review, performance]
dependencies: []
---

# History Cleanup Runs After Every Request

## Problem Statement

History cleanup (deleting old entries beyond a threshold) runs synchronously after every HTTP request. This is wasteful — cleanup should be periodic or lazy, not on every request.

**Why it matters:** Unnecessary work on the hot path of sending requests.

## Proposed Solutions

### Option A: Debounce or schedule cleanup (Recommended)
- Run cleanup on app launch or every Nth request
- Or use a timer-based background cleanup
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `RequestDetailView.swift`

## Acceptance Criteria

- [ ] History cleanup doesn't run on every request send
- [ ] Old history entries are still eventually cleaned up

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Don't do O(n) work on the hot path |

## Resources

- Branch: `feat/mvp-architecture`
