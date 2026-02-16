---
status: complete
priority: p3
issue_id: "018"
tags: [code-review, organization]
dependencies: []
---

# 018: Free Functions at File Scope

## Problem Statement

Several helper functions in `CurlHTTPClient.swift` are defined as free functions at file scope rather than being namespaced under a type. While `internal` by default (file-private if marked), free functions at file scope lack clear ownership and can become harder to discover and organize as the file grows. Namespacing them improves code organization and discoverability.

## Findings

- **File:** `CurlHTTPClient.swift`, lines 29-71
- **Severity:** P3 (Nice-to-have)
- **Category:** Code organization

The following functions are defined at file scope:

1. `sanitizeForCurl()` -- Prepares/sanitizes data for use with libcurl
2. `parseStatusMessage()` -- Extracts the status message from an HTTP response line
3. `parseHeaders()` -- Parses raw header data into key-value pairs

These functions are logically associated with the `CurlHTTPClient` type and would benefit from being namespaced accordingly. This aligns with Swift conventions where helper functions are typically scoped to their associated type.

## Proposed Solutions

### Option A: Move to private extension on CurlHTTPClient (Recommended)

Move the functions into a `private extension CurlHTTPClient` block as static methods.

**Pros:**
- Clear ownership and association with `CurlHTTPClient`
- Follows Swift convention of using extensions for organization
- Functions are discoverable via the type's API
- `private extension` keeps them out of the public API
- Minimal refactoring required

**Cons:**
- Since `CurlHTTPClient` is an actor, static methods in extensions may need careful consideration for Sendable conformance (though static methods with value-type parameters should be fine)

**Effort:** Low (30 minutes - 1 hour)
**Risk:** Very low -- mechanical refactor

### Option B: Create CurlHelpers enum

Create a caseless `enum CurlHelpers` as a namespace for the helper functions.

**Pros:**
- Clean separation from the actor type
- Caseless enum cannot be instantiated (pure namespace)
- Could be reused by other curl-related types if added later

**Cons:**
- Introduces a new type that exists solely for namespacing
- Less discoverable than having methods on `CurlHTTPClient` itself
- Arguably over-engineered for three private helper functions

**Effort:** Low (30 minutes - 1 hour)
**Risk:** Very low -- mechanical refactor

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Current structure:
```swift
// CurlHTTPClient.swift, lines 29-71

func sanitizeForCurl(_ string: String) -> String {
    // ...
}

func parseStatusMessage(from statusLine: String) -> String {
    // ...
}

func parseHeaders(from data: Data) -> [(String, String)] {
    // ...
}

actor CurlHTTPClient: HTTPClientProtocol {
    // uses the above functions
}
```

Proposed structure (Option A):
```swift
actor CurlHTTPClient: HTTPClientProtocol {
    // main implementation
}

private extension CurlHTTPClient {
    static func sanitizeForCurl(_ string: String) -> String {
        // ...
    }

    static func parseStatusMessage(from statusLine: String) -> String {
        // ...
    }

    static func parseHeaders(from data: Data) -> [(String, String)] {
        // ...
    }
}
```

Call sites within `CurlHTTPClient` would change from `parseHeaders(from:)` to `Self.parseHeaders(from:)` or simply `CurlHTTPClient.parseHeaders(from:)`.

## Acceptance Criteria

- [x] `sanitizeForCurl()`, `parseStatusMessage()`, and `parseHeaders()` are no longer free functions at file scope
- [x] Functions are properly namespaced under `CurlHTTPClient` or a helper type
- [x] All call sites are updated to use the new qualified names
- [x] Project builds successfully
- [x] All existing tests continue to pass
- [x] No functional behavior change

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |
| 2026-02-16 | Resolved | Moved functions to private extension with `nonisolated static` methods; updated all call sites to use `Self.` prefix |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- File: `PostKit/PostKit/Services/CurlHTTPClient.swift`
- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
