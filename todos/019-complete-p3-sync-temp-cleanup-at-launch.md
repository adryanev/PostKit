---
status: pending
priority: p3
issue_id: "019"
tags: [code-review, performance, ux]
dependencies: []
---

# 019: Sync Temp Cleanup at Launch

## Problem Statement

The `cleanupStaleTempFiles()` function is called synchronously in `PostKitApp.init()`, meaning it scans the temporary directory on the main thread during app launch. This blocks the main thread and can contribute to slower app startup times, especially if the temp directory contains many files. File system operations should not block the main thread.

## Findings

- **File:** `PostKitApp.swift`, lines 54-56
- **Severity:** P3 (Nice-to-have)
- **Category:** Performance, UX

The cleanup function performs file system I/O operations (directory listing, file stat calls, file deletion) synchronously on the main thread during `init()`. While typically fast, this can cause noticeable delays when:

- The temp directory contains a large number of stale files
- The file system is slow (e.g., network-mounted volumes, spinning disk)
- The system is under I/O pressure

This violates the principle of keeping the main thread free for UI rendering, especially during app launch when responsiveness is critical for perceived performance.

## Proposed Solutions

### Option A: Dispatch to Task {} (Recommended)

Wrap the cleanup call in a Swift `Task {}` to run it asynchronously off the main thread.

**Pros:**
- Uses modern Swift concurrency
- Consistent with the rest of the codebase's async patterns
- Simple one-line change
- Does not block app launch
- Cleanup still runs promptly, just not synchronously

**Cons:**
- Cleanup may complete slightly after app is visible (acceptable since it's background housekeeping)
- Error handling in detached tasks requires explicit consideration

**Effort:** Very low (15 minutes)
**Risk:** Very low -- cleanup is fire-and-forget housekeeping

### Option B: Use DispatchQueue.global().async

Use Grand Central Dispatch to run cleanup on a background queue.

**Pros:**
- Well-understood concurrency primitive
- Explicit control over QoS priority (e.g., `.utility` or `.background`)

**Cons:**
- Mixes GCD with Swift concurrency patterns used elsewhere in the codebase
- More verbose than `Task {}`
- Less idiomatic for a modern Swift concurrency codebase

**Effort:** Very low (15 minutes)
**Risk:** Very low -- cleanup is fire-and-forget housekeeping

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Current implementation:
```swift
// PostKitApp.swift, lines 54-56
init() {
    // ...
    cleanupStaleTempFiles()
}
```

Proposed change (Option A):
```swift
init() {
    // ...
    Task.detached(priority: .utility) {
        cleanupStaleTempFiles()
    }
}
```

Or if `cleanupStaleTempFiles` is not async:
```swift
init() {
    // ...
    Task.detached(priority: .utility) {
        await MainActor.run { } // not needed if func is nonisolated
        cleanupStaleTempFiles()
    }
}
```

Considerations:
- Ensure `cleanupStaleTempFiles()` is safe to call from a non-main thread (no UI updates, no main-actor-isolated state)
- The function should be `nonisolated` or `Sendable`-compatible
- Use `.utility` or `.background` priority since this is housekeeping work

## Acceptance Criteria

- [ ] `cleanupStaleTempFiles()` no longer runs synchronously on the main thread during `init()`
- [ ] Cleanup runs on a background thread/task at app launch
- [ ] App launch is not blocked by temp file cleanup
- [ ] Cleanup still executes reliably (no silent failures)
- [ ] All existing tests continue to pass
- [ ] No functional behavior change

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- File: `PostKit/PostKit/PostKitApp.swift`
- [Swift Concurrency: Tasks](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Tasks-and-Task-Groups)
