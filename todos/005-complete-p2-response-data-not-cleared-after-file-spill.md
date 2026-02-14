---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, memory, performance]
dependencies: []
---

# 005: responseData Not Cleared After File Spill

## Problem Statement

In the `curlWriteCallback`, when a response exceeds `maxMemorySize` and spills to disk, the initial `responseData` buffer (up to 1MB) is written to the temp file but is never cleared from memory. This means each large response wastes approximately 1MB of memory that is no longer needed, since the full response is now being streamed to disk.

## Findings

- **File:** `CurlHTTPClient.swift:86-98` (`curlWriteCallback`)
- When the cumulative `bytesReceived` exceeds `maxMemorySize`, the callback creates a temp file and writes the existing `responseData` contents to it.
- After writing to the file, subsequent chunks are appended directly to the file handle.
- However, the `responseData` property on `CurlTransferContext` is never cleared (set to `Data()`) after the spill.
- The stale `responseData` remains allocated for the lifetime of the request.
- For users making multiple large requests, this memory waste compounds (1MB per request).
- The `URLSessionHTTPClient` may have the same pattern -- should be checked for consistency.

## Proposed Solutions

### Option A: Clear responseData After Writing to File (Recommended)

After writing `responseData` to the temp file, immediately clear it:

```swift
context.tempFileHandle?.write(context.responseData)
context.responseData = Data()  // Free the memory
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Simple fix; immediately reclaims ~1MB; no behavioral change |
| **Cons** | None significant |
| **Effort** | Very low (single line addition) |
| **Risk** | Very low -- responseData is not read again after spill since all subsequent writes go to the file handle |

### Option B: Use removeAll(keepingCapacity: false)

```swift
context.responseData.removeAll(keepingCapacity: false)
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Explicit about releasing the backing storage |
| **Cons** | Functionally equivalent to Option A; slightly more verbose |
| **Effort** | Very low |
| **Risk** | Very low |

## Recommended Action

_To be filled in after team review._

## Technical Details

- `maxMemorySize` is set to 1MB (1,048,576 bytes).
- The spill logic triggers when `bytesReceived > maxMemorySize`.
- After the spill, the callback checks `if context.tempFileHandle != nil` to decide whether to append to file or to `responseData`.
- Once `tempFileHandle` is set, `responseData` is never accessed again for writes.
- On the success path, the code checks `tempFileHandle != nil` to decide whether to return `bodyFileURL` or `responseData` -- so clearing `responseData` after spill has no effect on the return value.
- Memory impact: 1MB per concurrent large response. With 10 concurrent large downloads, that is 10MB of wasted memory.

## Acceptance Criteria

- [ ] After a response spills to disk, `responseData` is cleared and memory is reclaimed.
- [ ] Memory usage drops by approximately 1MB per large response compared to current behavior.
- [ ] Small responses (under 1MB) continue to work correctly via in-memory `responseData`.
- [ ] Large responses continue to be correctly written to temp files.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [Swift Data type documentation](https://developer.apple.com/documentation/foundation/data)
