---
status: complete
priority: p2
issue_id: "013"
tags: [code-review, performance]
dependencies: []
---

# HTTPClient Loads Entire Response Into Memory Before Size Check

## Problem Statement

`URLSessionHTTPClient` uses `URLSession.data(for:)` which downloads the entire response body into memory before checking the size threshold to decide whether to write to disk. A 500MB response will consume 500MB of RAM before the app decides to save it to a file.

**Why it matters:** Large API responses can cause memory pressure or crashes on memory-constrained machines.

## Proposed Solutions

### Option A: Use download task for large responses (Recommended)
- Switch to `URLSession.download(for:)` which streams to disk
- Check Content-Length header to decide strategy before downloading
- **Pros:** Constant memory usage regardless of response size
- **Cons:** Two code paths (data vs download task)
- **Effort:** Medium
- **Risk:** Low

### Option B: Use bytes stream
- Use `URLSession.bytes(for:)` and stream to disk incrementally
- **Pros:** Fine-grained control
- **Cons:** More complex implementation
- **Effort:** Medium
- **Risk:** Low

## Technical Details

- **Affected files:** `HTTPClient.swift`

## Acceptance Criteria

- [ ] Large responses don't consume equivalent RAM
- [ ] Response size threshold still works correctly

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | dataTask loads everything into memory |

## Resources

- Branch: `feat/mvp-architecture`
