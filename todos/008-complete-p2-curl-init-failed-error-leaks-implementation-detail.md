---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, architecture, abstraction]
dependencies: []
---

# 008: .curlInitFailed Error Leaks Implementation Detail

## Problem Statement

The `HTTPClientError` enum includes a `.curlInitFailed` case that directly references the libcurl implementation. This error type is part of the public `HTTPClientProtocol` contract shared by all HTTP client implementations. If the HTTP engine is later changed (back to URLSession, or to a different library), this error case becomes semantically incorrect and confusing. Error types in a protocol should be implementation-agnostic.

## Findings

- **File:** `HTTPClient.swift` (`HTTPClientError` enum)
- The error enum is used by both `CurlHTTPClient` and `URLSessionHTTPClient` (via `HTTPClientProtocol`).
- `.curlInitFailed` is only thrown by `CurlHTTPClient` when `curl_easy_init()` returns `nil`.
- `URLSessionHTTPClient` never throws this error, but it exists in the shared error type.
- The error's `localizedDescription` likely mentions "curl", which would be confusing if the user sees it in a non-curl context.
- This violates the abstraction boundary that `HTTPClientProtocol` is meant to provide.
- The project's ADR and architecture documentation emphasize clean abstraction layers between components.

## Proposed Solutions

### Option A: Rename to .engineInitializationFailed (Recommended)

Rename the error case to a generic, implementation-agnostic name:

```swift
case engineInitializationFailed
```

Update the `errorDescription` to be generic:

```swift
case .engineInitializationFailed:
    return "Failed to initialize the HTTP engine."
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Implementation-agnostic; works for any HTTP engine; clear intent; maintains abstraction boundary |
| **Cons** | Slightly less specific in debug logs (can be mitigated with logging the engine name in the throwing code) |
| **Effort** | Low (rename + update references) |
| **Risk** | Very low -- straightforward rename with no behavioral change |

### Option B: Keep As-Is with Documentation

Add a comment explaining that the error case is curl-specific and should be renamed if the engine changes.

| Aspect | Detail |
|--------|--------|
| **Pros** | No code change; addresses the concern with documentation |
| **Cons** | Does not fix the abstraction leak; documentation is easily overlooked; error name still confuses users and developers |
| **Effort** | Very low |
| **Risk** | Low, but the underlying issue persists |

### Option C: Use Associated Value for Engine-Specific Details

```swift
case engineInitializationFailed(engine: String, details: String?)
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Generic name with engine-specific context available for debugging; most informative |
| **Cons** | More complex; associated values affect pattern matching at call sites |
| **Effort** | Low to medium |
| **Risk** | Low |

## Recommended Action

_To be filled in after team review._

## Technical Details

- `HTTPClientError` conforms to `LocalizedError` and provides `errorDescription` for each case.
- The error is thrown in `CurlHTTPClient.execute()` when `curl_easy_init()` returns `nil`.
- `curl_easy_init()` can return `nil` if libcurl fails to allocate memory or if global initialization (`curl_global_init`) was not called. In practice, this is extremely rare.
- The error is caught and displayed by `ResponseViewerPane` (or similar view) via `ErrorView`.
- Other error cases (`.invalidURL`, `.networkError`, `.timeout`, `.cancelled`) are already implementation-agnostic.
- Only `.curlInitFailed` breaks the naming convention.

## Acceptance Criteria

- [ ] The error case name does not reference any specific HTTP client implementation (no "curl", "urlsession", etc.).
- [ ] The `errorDescription` is generic and user-friendly.
- [ ] All references to the old error case are updated.
- [ ] The error is still thrown in the same circumstances within `CurlHTTPClient`.
- [ ] No compile errors or warnings after the rename.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [Swift LocalizedError](https://developer.apple.com/documentation/foundation/localizederror)
- [HTTPClientProtocol in PostKit architecture](../docs/adr/0001-postkit-architecture-decisions.md)
