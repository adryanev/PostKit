---
status: pending
priority: p2
issue_id: "004"
tags: [code-review, performance]
dependencies: []
---

# 004: Serial GCD Queue Serializes All Requests

## Problem Statement

The `CurlHTTPClient` uses a serial `DispatchQueue` to perform all `curl_easy_perform` calls. Because the queue is serial, only one request can execute at a time. If a single request takes 30 seconds (e.g., a slow server or large download), all other requests queued behind it must wait, creating a bottleneck that directly impacts user experience in a tool designed for concurrent API testing.

## Findings

- **File:** `CurlHTTPClient.swift:146`
- **Code:** `DispatchQueue(label: "com.postkit.curl-perform", qos: .userInitiated)`
- The queue is created without the `.concurrent` attribute, making it serial by default.
- Every call to `execute()` dispatches `curl_easy_perform` onto this single serial queue.
- `curl_easy_perform` is a blocking call that does not return until the entire HTTP transaction completes (or times out).
- If a user fires multiple requests (common workflow: testing several endpoints), each request must wait for the previous one to finish.
- This effectively negates one of the benefits of using libcurl, which supports concurrent operations.

## Proposed Solutions

### Option A: Use a Concurrent Queue (Recommended)

Change the queue declaration to use the `.concurrent` attribute:

```swift
DispatchQueue(label: "com.postkit.curl-perform", qos: .userInitiated, attributes: .concurrent)
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Minimal code change; requests execute in parallel; each `curl_easy_perform` call operates on its own `CURL` handle so there is no shared mutable state between requests |
| **Cons** | Slightly higher resource usage under heavy load; need to verify no shared state between requests |
| **Effort** | Low (single line change) |
| **Risk** | Low -- each request already creates its own `CURL` handle and `CurlTransferContext`, so concurrent execution should be safe |

### Option B: Use curl_multi Interface

Replace `curl_easy_perform` with the `curl_multi` interface, which supports non-blocking multiplexed transfers on a single thread.

| Aspect | Detail |
|--------|--------|
| **Pros** | Most efficient approach; supports HTTP/2 multiplexing; single-threaded event loop avoids threading issues |
| **Cons** | Significant refactor; more complex API; requires managing a run loop or select/poll mechanism |
| **Effort** | High (major refactor of the HTTP client) |
| **Risk** | Medium -- new concurrency model introduces new failure modes |

### Option C: Create Per-Request Queues

Create a new `DispatchQueue` for each request invocation rather than sharing a single queue.

| Aspect | Detail |
|--------|--------|
| **Pros** | Guarantees no serialization; simple to implement |
| **Cons** | Unbounded queue creation; no backpressure if many requests are fired simultaneously; wastes system resources |
| **Effort** | Low |
| **Risk** | Medium -- could create too many threads under load, leading to thread explosion |

## Recommended Action

_To be filled in after team review._

## Technical Details

- `curl_easy_perform` is documented as a blocking call: it performs the entire transfer and returns only when complete or on error.
- Each call to `execute()` creates a fresh `CURL` handle via `curl_easy_init()`, so there is no shared curl state between concurrent requests.
- The `CurlTransferContext` is also per-request, so write callbacks and header callbacks are isolated.
- GCD concurrent queues use a thread pool managed by the system, so Option A benefits from OS-level thread management.
- The serial queue was likely chosen for simplicity during initial implementation, not as a deliberate architectural constraint.

## Acceptance Criteria

- [ ] Multiple requests execute concurrently when fired in quick succession.
- [ ] No request is blocked waiting for an unrelated request to complete.
- [ ] No data corruption or race conditions under concurrent execution.
- [ ] Verified with at least two simultaneous requests where one has a delayed response.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [libcurl easy interface documentation](https://curl.se/libcurl/c/libcurl-easy.html)
- [libcurl multi interface documentation](https://curl.se/libcurl/c/libcurl-multi.html)
- [GCD Concurrent Queues](https://developer.apple.com/documentation/dispatch/dispatchqueue)
