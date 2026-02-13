---
status: complete
priority: p1
issue_id: "005"
tags: [code-review, bug]
dependencies: []
---

# onChange References Wrong Value (New Instead of Old)

## Problem Statement

In `ContentView.swift`, the `onChange(of: selectedRequest)` handler references the new value but the logic appears to need the old value (or vice versa). This can cause incorrect state management when switching between requests.

**Why it matters:** Incorrect onChange handling can cause subtle data loss or UI state corruption when users switch between requests.

## Findings

- **ContentView.swift:62-66** — `onChange(of: selectedRequest)` handler logic references the wrong value
- **Confirmed by:** Architecture Strategist, Performance Oracle agents

## Proposed Solutions

### Option A: Fix the onChange closure parameter (Recommended)
- Review the onChange closure and ensure the correct value (old vs new) is referenced
- In Swift 5.9+, `onChange(of:)` with two-parameter closure provides both old and new values
- **Pros:** Direct fix
- **Cons:** None
- **Effort:** Small
- **Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files:** `ContentView.swift`
- **Components:** Navigation, state management

## Acceptance Criteria

- [ ] onChange handler references the correct value
- [ ] Switching between requests preserves correct state
- [ ] No data loss when changing selection

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Confirmed by 2 agents |

## Resources

- Branch: `feat/mvp-architecture`
