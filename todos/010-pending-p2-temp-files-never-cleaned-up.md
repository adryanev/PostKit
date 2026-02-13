---
status: complete
priority: p2
issue_id: "010"
tags: [code-review, bug, performance]
dependencies: []
---

# Temp Files for Large Responses Never Cleaned Up

## Problem Statement

`URLSessionHTTPClient` writes large response bodies to temporary files (`FileManager.default.temporaryDirectory`) but never deletes them. Over time, this leaks disk space.

**Why it matters:** Users testing APIs with large responses will accumulate orphaned temp files.

## Findings

- **HTTPClient.swift** — writes to temp directory when response exceeds size threshold
- No cleanup logic exists anywhere in the codebase
- `HTTPResponse.bodyFileURL` stores the path but no lifecycle management
- **Confirmed by:** Security Sentinel, Architecture Strategist agents

## Proposed Solutions

### Option A: Clean up on response dismissal (Recommended)
- Delete temp file when the response is replaced or the app closes
- Add cleanup in `HTTPResponse` deinit or in the view's onDisappear
- **Pros:** Simple, prevents accumulation
- **Cons:** Must handle file-in-use edge case
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `HTTPClient.swift`, `HTTPClientProtocol.swift`

## Acceptance Criteria

- [ ] Temp files are deleted when no longer needed
- [ ] No temp file accumulation over time
- [ ] File cleanup handles missing files gracefully

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Disk leak over time |

## Resources

- Branch: `feat/mvp-architecture`
