---
status: complete
priority: p3
issue_id: "019"
tags: [code-review, bug, architecture]
dependencies: []
---

# FileExporter Calls NSSavePanel Outside @MainActor

## Problem Statement

`FileExporter` calls `NSSavePanel` (an AppKit UI element) without ensuring it runs on the main thread. This can cause crashes or undefined behavior if called from a background context.

**Why it matters:** AppKit UI must run on the main thread — violation can cause crashes.

## Proposed Solutions

### Option A: Add @MainActor annotation (Recommended)
- Mark the save/export methods as `@MainActor`
- Or wrap NSSavePanel calls in `MainActor.run { }`
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `FileExporter.swift`

## Acceptance Criteria

- [x] NSSavePanel always runs on main thread
- [x] No runtime warnings about main thread violations

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | AppKit + async = thread safety matters |
| 2026-02-13 | Fixed: added @MainActor to FileExporter class | All callers are already in @MainActor context (SwiftUI Views) |

## Resources

- Branch: `feat/mvp-architecture`
