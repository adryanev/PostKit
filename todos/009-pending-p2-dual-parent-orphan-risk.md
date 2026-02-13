---
status: complete
priority: p2
issue_id: "009"
tags: [code-review, architecture, data-model]
dependencies: []
---

# Dual-Parent Relationship Creates Orphan Risk

## Problem Statement

`HTTPRequest` has two optional parent references: `collection: RequestCollection?` and `folder: Folder?`. Both are optional, so a request can end up with neither parent (orphaned), or have inconsistent parent state. The cURL import sheet creates requests with `collection: nil`, immediately orphaning them.

**Why it matters:** Orphaned requests are invisible in the UI — they exist in the database but appear nowhere in the navigation.

## Findings

- **HTTPRequest.swift** — `var collection: RequestCollection?` and `var folder: Folder?` both optional
- **CurlImportSheet.swift** — creates requests without setting a collection, orphaning them
- No validation ensures at least one parent is set
- **Confirmed by:** Architecture Strategist agent

## Proposed Solutions

### Option A: Require collection, make folder optional (Recommended)
- Make `collection` non-optional (every request belongs to a collection)
- Folder remains optional (requests can be at collection root or in a folder)
- Fix cURL import to require a target collection
- **Pros:** Prevents orphans, clear ownership
- **Cons:** Migration needed if data already exists
- **Effort:** Medium
- **Risk:** Low

### Option B: Add validation
- Keep both optional but add runtime validation
- Reject saves where both parents are nil
- **Pros:** Less structural change
- **Cons:** Runtime errors instead of compile-time safety
- **Effort:** Small
- **Risk:** Medium

## Technical Details

- **Affected files:** `HTTPRequest.swift`, `CurlImportSheet.swift`, `OpenAPIImportSheet.swift`

## Acceptance Criteria

- [x] No request can exist without a parent collection
- [x] Import flows require selecting a target collection
- [ ] Existing orphaned requests are surfaced or cleaned up

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | cURL import creates orphans right now |
| 2026-02-13 | Fixed import sheets | CurlImportSheet now requires non-optional collection; PostKitApp auto-creates "Imported" collection; OpenAPIImportSheet already safe |

## Resources

- Branch: `feat/mvp-architecture`
