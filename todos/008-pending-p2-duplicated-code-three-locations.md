---
status: complete
priority: p2
issue_id: "008"
tags: [code-review, quality, duplication]
dependencies: []
---

# Duplicated Code in Three Locations

## Problem Statement

Three pieces of logic are duplicated across multiple files:

1. **`methodColor(for:)`** — duplicated in `CurlImportSheet` and `OpenAPIImportSheet`, when `HTTPMethod.color` already exists on the enum
2. **`duplicateRequest()`** — duplicated in `RequestListView` and `PostKitCommands`
3. **`formatBytes()`** — duplicated in `ResponseBodyView` and `ResponseStatusBar` (same file, two copies)

**Why it matters:** Duplicated code means bugs must be fixed in multiple places and behavior can diverge.

## Findings

- **CurlImportSheet.swift** and **OpenAPIImportSheet.swift** — local `methodColor(for:)` functions that duplicate `HTTPMethod.color`
- **RequestListView.swift** and **PostKitCommands.swift** — both implement `duplicateRequest()` with slightly different approaches
- **ResponseViewerPane.swift:137** and **ResponseViewerPane.swift:186** — identical `formatBytes()` helper in two structs
- **Confirmed by:** Architecture Strategist, Pattern Recognition, Code Simplicity agents

## Proposed Solutions

### Option A: Use existing APIs and extract shared helpers (Recommended)
- Replace `methodColor(for:)` calls with `method.color` (already exists on HTTPMethod)
- Extract `duplicateRequest()` into a shared function or model extension
- Extract `formatBytes()` into a single utility or extension
- **Pros:** DRY, uses existing code
- **Cons:** Minor refactor
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `CurlImportSheet.swift`, `OpenAPIImportSheet.swift`, `RequestListView.swift`, `PostKitCommands.swift`, `ResponseViewerPane.swift`

## Acceptance Criteria

- [x] No duplicate `methodColor` functions — use `HTTPMethod.color`
- [x] Single `duplicateRequest` implementation
- [x] Single `formatBytes` implementation
- [x] All call sites updated

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | 3 distinct duplications found |
| 2026-02-13 | Resolved all 3 duplications | Deleted methodColor from CurlImportSheet & OpenAPIImportSheet, added HTTPRequest.duplicated(), added Int64.formattedBytes extension |

## Resources

- Branch: `feat/mvp-architecture`
