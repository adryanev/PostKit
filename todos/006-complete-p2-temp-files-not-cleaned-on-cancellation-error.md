---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, resource-leak]
dependencies: []
---

# 006: Temp Files Not Cleaned on Cancellation/Error

## Problem Statement

When a request is cancelled or encounters an error, any temporary file created for large responses (those exceeding `maxMemorySize`) is never deleted. The temp file's `bodyFileURL` is only returned to the caller on the success path, where the view model is responsible for cleanup. On cancellation or error, the file URL is lost and the file becomes an orphan on disk.

## Findings

- **File:** `CurlHTTPClient.swift`
- The `curlWriteCallback` creates a temp file at `postkit-response-{UUID}.tmp` when the response exceeds `maxMemorySize`.
- On success, the `bodyFileURL` is included in the `HTTPResponse` struct, and the caller (view model) is expected to clean it up.
- On cancellation (`cancel()` method): the continuation resumes with a `.cancelled` error, but the temp file handle is not closed and the file is not deleted.
- On curl errors: the `mapCurlError()` path resumes the continuation with an error, but again the temp file is not cleaned up.
- Over time, orphan temp files accumulate in the system temp directory.
- `PostKitApp.swift` has a cleanup function that runs on launch, but it only catches files from previous sessions, not files orphaned during the current session.

## Proposed Solutions

### Option A: Add Cleanup in cancel() and Error Paths (Recommended)

Explicitly close the file handle and delete the temp file in both the cancellation and error branches:

```swift
// In the error/cancellation handler:
if let handle = context.tempFileHandle {
    try? handle.close()
}
if let url = context.tempFileURL {
    try? FileManager.default.removeItem(at: url)
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Targeted fix; handles each failure mode explicitly; easy to reason about |
| **Cons** | Cleanup logic is duplicated across multiple code paths |
| **Effort** | Low |
| **Risk** | Low -- file deletion is idempotent and uses `try?` to ignore errors |

### Option B: Add defer/finally Cleanup in the Continuation Handler

Use a `defer` block or a cleanup closure that runs regardless of outcome, deleting the temp file unless the success path explicitly "claims" it:

```swift
var claimedFileURL: URL? = nil
defer {
    if claimedFileURL == nil, let url = context.tempFileURL {
        try? FileManager.default.removeItem(at: url)
    }
}
// On success: claimedFileURL = context.tempFileURL
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Single cleanup point; impossible to miss a code path; more robust against future changes |
| **Cons** | Slightly more complex flow with the "claim" pattern; defer scope must encompass all paths |
| **Effort** | Low to medium |
| **Risk** | Low |

## Recommended Action

_To be filled in after team review._

## Technical Details

- Temp files are created in `FileManager.default.temporaryDirectory` with the pattern `postkit-response-{UUID}.tmp`.
- `FileHandle` must be closed before deletion to avoid resource leaks on the file descriptor.
- The `CurlTransferContext` holds both `tempFileHandle: FileHandle?` and `tempFileURL: URL?` (if the spill has occurred).
- Cancellation is triggered via `context.isCancelled` being set, which causes the progress callback to return a non-zero value, which causes `curl_easy_perform` to return `CURLE_ABORTED_BY_CALLBACK`.
- The system temp directory is periodically cleaned by macOS, but relying on this is not appropriate for a production application.

## Acceptance Criteria

- [ ] No orphan temp files remain after a request is cancelled.
- [ ] No orphan temp files remain after a request encounters an error.
- [ ] File handles are properly closed before file deletion.
- [ ] Successful large responses still return `bodyFileURL` for caller-managed cleanup.
- [ ] Verified by cancelling a large download mid-transfer and checking the temp directory.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [FileManager.removeItem(at:)](https://developer.apple.com/documentation/foundation/filemanager/1413590-removeitem)
- [FileHandle.close()](https://developer.apple.com/documentation/foundation/filehandle/1413393-close)
