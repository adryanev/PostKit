---
status: pending
priority: p2
issue_id: "011"
tags: [code-review, consistency, architecture]
dependencies: []
---

# 011: Timeout Error Inconsistency

## Problem Statement

`CurlHTTPClient` maps `CURLE_OPERATION_TIMEDOUT` to `HTTPClientError.timeout`, but `URLSessionHTTPClient` wraps `URLError.timedOut` inside `HTTPClientError.networkError(underlyingError)`. This means the same user-facing scenario (a request timing out) produces different error types depending on which HTTP client is active. The `ErrorView` in `ResponseViewerPane` must check for both error types separately, adding unnecessary complexity and fragility.

## Findings

- **File:** `CurlHTTPClient.swift` -- `mapCurlError()` maps `CURLE_OPERATION_TIMEDOUT` to `.timeout`
- **File:** `HTTPClient.swift` -- `URLSessionHTTPClient` catches `URLError.timedOut` and wraps it in `.networkError(error)`
- **File:** Views displaying errors must handle both `.timeout` and `.networkError` where the underlying error is `URLError.timedOut`
- The `.timeout` error case exists in `HTTPClientError` and is used by `CurlHTTPClient`, but `URLSessionHTTPClient` does not use it for timeouts.
- This inconsistency means UI code cannot simply switch on the error type to show a timeout-specific message -- it must also inspect the underlying error of `.networkError`.
- The purpose of `HTTPClientProtocol` is to abstract away implementation differences, but this inconsistency leaks implementation details.

## Proposed Solutions

### Option A: Map URLSession Timeout to .timeout as Well (Recommended)

In `URLSessionHTTPClient`, detect `URLError.timedOut` and map it to `.timeout` before falling through to `.networkError`:

```swift
catch let urlError as URLError where urlError.code == .timedOut {
    throw HTTPClientError.timeout
}
catch {
    throw HTTPClientError.networkError(error)
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Both clients produce the same error for timeouts; UI code simplifies to a single `.timeout` check; maintains the abstraction boundary |
| **Cons** | Minor change to URLSessionHTTPClient error handling |
| **Effort** | Very low |
| **Risk** | Very low -- strictly more correct behavior; no loss of information since `.timeout` is more specific than `.networkError` for this case |

### Option B: Add .timeout Check in ErrorView for Both Patterns

Update the error display logic to check for both `.timeout` and `.networkError` wrapping `URLError.timedOut`:

```swift
if case .timeout = error {
    // show timeout UI
} else if case .networkError(let underlying) = error,
          (underlying as? URLError)?.code == .timedOut {
    // also show timeout UI
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | No changes to HTTP client code; handles both patterns |
| **Cons** | Pushes implementation details into the UI layer; fragile pattern matching; violates the abstraction that HTTPClientProtocol provides |
| **Effort** | Low |
| **Risk** | Medium -- the UI layer should not need to know about URLError |

### Option C: Unify All Error Mapping in a Shared Post-Processing Step

Add a method on `HTTPClientError` or a shared utility that normalizes errors after they are thrown:

```swift
extension HTTPClientError {
    var normalized: HTTPClientError {
        if case .networkError(let e) = self,
           (e as? URLError)?.code == .timedOut {
            return .timeout
        }
        return self
    }
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Centralized normalization; works retroactively for any client |
| **Cons** | Extra processing step; callers must remember to call `.normalized`; does not fix the root cause |
| **Effort** | Low |
| **Risk** | Low |

## Recommended Action

_To be filled in after team review._

## Technical Details

- `HTTPClientError` has these cases: `.invalidURL`, `.networkError(Error)`, `.timeout`, `.cancelled`, `.curlInitFailed` (see also issue #008).
- `URLError.timedOut` has code `NSURLErrorTimedOut` (-1001).
- The `.timeout` case was likely added specifically for the curl migration but was not backported to `URLSessionHTTPClient`.
- `ErrorView` currently displays different messages for `.timeout` vs `.networkError` -- a timeout wrapped in `.networkError` would show a generic network error message instead of the more helpful timeout-specific message.
- This inconsistency affects user experience: the same problem (server not responding in time) produces different error messages depending on the active HTTP engine.

## Acceptance Criteria

- [ ] Both `CurlHTTPClient` and `URLSessionHTTPClient` produce `HTTPClientError.timeout` when a request times out.
- [ ] The UI displays the same timeout-specific error message regardless of which HTTP client is active.
- [ ] No timeout errors are wrapped inside `.networkError`.
- [ ] Other `URLError` codes (not timeout) continue to be wrapped in `.networkError` as before.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [URLError.Code.timedOut](https://developer.apple.com/documentation/foundation/urlerror/code/timedout)
- [CURLE_OPERATION_TIMEDOUT](https://curl.se/libcurl/c/libcurl-errors.html)
