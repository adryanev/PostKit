---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, concurrency, safety]
dependencies: []
---

# 007: @unchecked Sendable Threading Contract Undocumented

## Problem Statement

`CurlTransferContext` is marked `@unchecked Sendable`, which tells the Swift compiler to skip concurrency safety checks. While some fields (`isCancelled`, `didResume`) are protected by `OSAllocatedUnfairLock`, the remaining mutable fields (`responseData`, `headerLines`, `tempFileHandle`, `bytesReceived`) are mutated without explicit synchronization. The threading contract that makes this safe is not documented anywhere in the code.

## Findings

- **File:** `CurlHTTPClient.swift:9-27` (`CurlTransferContext`)
- The class is marked `@unchecked Sendable`, opting out of Swift's compile-time concurrency checks.
- `isCancelled: OSAllocatedUnfairLock<Bool>` -- properly synchronized.
- `didResume: OSAllocatedUnfairLock<Bool>` -- properly synchronized.
- `responseData: Data` -- mutated in `curlWriteCallback`, read after `curl_easy_perform` returns. No explicit lock.
- `headerLines: [String]` -- mutated in `curlHeaderCallback`, read after `curl_easy_perform` returns. No explicit lock.
- `tempFileHandle: FileHandle?` -- set in `curlWriteCallback`, read after `curl_easy_perform` returns. No explicit lock.
- `bytesReceived: Int` -- mutated in `curlWriteCallback`, read in `curlProgressCallback`. No explicit lock.
- The safety argument is likely: all write callbacks and the progress callback are invoked synchronously by `curl_easy_perform` on the same thread, so there is no concurrent access. But this is not documented.
- Future maintainers (or a switch to `curl_multi`) could introduce concurrent access without realizing the threading assumptions.

## Proposed Solutions

### Option A: Document Threading Contract as Code Comments (Recommended)

Add comprehensive comments explaining why `@unchecked Sendable` is safe:

```swift
/// Threading contract:
/// - `responseData`, `headerLines`, `tempFileHandle`, and `bytesReceived` are only
///   mutated from libcurl callbacks (write, header, progress), which are invoked
///   synchronously by `curl_easy_perform` on the same GCD thread.
/// - These fields are only read after `curl_easy_perform` returns, establishing
///   a happens-before relationship.
/// - `isCancelled` and `didResume` are accessed from multiple threads and are
///   protected by `OSAllocatedUnfairLock`.
/// - If migrating to `curl_multi` (async/multiplexed), this threading model must
///   be revisited.
final class CurlTransferContext: @unchecked Sendable { ... }
```

| Aspect | Detail |
|--------|--------|
| **Pros** | No runtime cost; makes the safety argument explicit; warns future maintainers; documents the invariant |
| **Cons** | Does not provide compile-time or runtime enforcement; relies on discipline |
| **Effort** | Very low (documentation only) |
| **Risk** | Very low |

### Option B: Add Lock Protection to All Mutable Fields

Wrap all mutable fields in `OSAllocatedUnfairLock` or use a `Mutex`:

```swift
var responseData: OSAllocatedUnfairLock<Data>
var headerLines: OSAllocatedUnfairLock<[String]>
// etc.
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Provides runtime enforcement; safe even if threading model changes; satisfies strict concurrency requirements |
| **Cons** | Performance overhead on every callback invocation (locks in hot path); more complex code; unnecessary given current single-threaded callback model |
| **Effort** | Medium |
| **Risk** | Low, but introduces unnecessary complexity for the current architecture |

### Option C: Remove @unchecked Sendable, Restructure for Compiler Verification

Refactor `CurlTransferContext` so the compiler can verify `Sendable` conformance, e.g., by using actors or making all fields `let` with mutable state isolated to a single execution context.

| Aspect | Detail |
|--------|--------|
| **Pros** | Full compile-time safety; no `@unchecked` escape hatch |
| **Cons** | Significant refactor; C callback functions cannot call actor methods synchronously; may require architectural changes to how curl callbacks interact with state |
| **Effort** | High |
| **Risk** | Medium -- fighting against the C interop model |

## Recommended Action

_To be filled in after team review._

## Technical Details

- `curl_easy_perform` is a blocking call. All callbacks (WRITEFUNCTION, HEADERFUNCTION, XFERINFOFUNCTION) are invoked synchronously on the thread that called `curl_easy_perform`.
- The GCD queue dispatches `curl_easy_perform` onto a thread. All callbacks execute on that same thread for the duration of the call.
- After `curl_easy_perform` returns, the result is read from `CurlTransferContext` on the same thread (still within the GCD block), then passed to the continuation.
- The continuation may resume on a different thread (the actor's executor), but by that point, the `CurlTransferContext` is no longer mutated.
- `bytesReceived` is read in `curlProgressCallback` and written in `curlWriteCallback`. Both are called synchronously by `curl_easy_perform`, so this is safe -- but this is the most subtle case and deserves explicit documentation.

## Acceptance Criteria

- [ ] Clear documentation exists as code comments on `CurlTransferContext` explaining the threading contract.
- [ ] The documentation covers which fields are lock-protected and which rely on single-threaded callback execution.
- [ ] The documentation warns about implications of switching to `curl_multi`.
- [ ] A reviewer unfamiliar with libcurl's threading model can understand why `@unchecked Sendable` is safe by reading the comments alone.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [libcurl callback documentation](https://curl.se/libcurl/c/CURLOPT_WRITEFUNCTION.html)
- [curl_easy_perform threading](https://curl.se/libcurl/c/curl_easy_perform.html)
- [Swift @unchecked Sendable](https://developer.apple.com/documentation/swift/uncheckedsendable)
- [OSAllocatedUnfairLock](https://developer.apple.com/documentation/os/osallocatedunfairlock)
