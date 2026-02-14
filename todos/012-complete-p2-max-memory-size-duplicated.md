---
status: pending
priority: p2
issue_id: "012"
tags: [code-review, duplication]
dependencies: []
---

# 012: maxMemorySize Duplicated

## Problem Statement

The 1MB threshold for spilling response data to disk (`maxMemorySize`) is defined as a private constant in both `CurlHTTPClient.swift` and `HTTPClient.swift` (URLSessionHTTPClient). If the value is changed in one file but not the other, the two HTTP clients will behave differently for the same response sizes, creating subtle inconsistencies that are difficult to diagnose.

## Findings

- **File:** `CurlHTTPClient.swift:6` -- `private let maxMemorySize = 1_048_576`
- **File:** `HTTPClient.swift` -- `private let maxMemorySize = 1_048_576`
- Both constants have the same value (1MB = 1,048,576 bytes).
- Both are declared as `private`, meaning they cannot be shared or accessed from outside their respective files.
- The constant controls the same behavior in both clients: when a response body exceeds this size, it is written to a temp file instead of being held in memory.
- The `PostKitApp.swift` cleanup function and the view model's response handling logic implicitly depend on this threshold being consistent across clients.
- This is a classic DRY (Don't Repeat Yourself) violation.

## Proposed Solutions

### Option A: Move to HTTPClientProtocol as a Static Constant (Recommended)

Define the constant on the protocol or as a protocol extension:

```swift
extension HTTPClientProtocol {
    static var maxMemorySize: Int { 1_048_576 }
}
```

Or as a standalone constant in the protocol file:

```swift
/// Maximum response body size (in bytes) to keep in memory.
/// Responses exceeding this size are spilled to a temporary file.
let httpClientMaxMemorySize: Int = 1_048_576
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Single source of truth; both clients reference the same value; easy to find and change; documents the shared behavior contract |
| **Cons** | Minor refactor to update both clients to reference the shared constant |
| **Effort** | Very low |
| **Risk** | Very low -- purely a refactor with no behavioral change |

### Option B: Move to a Shared Configuration File

Create a configuration namespace:

```swift
enum HTTPClientConfig {
    static let maxMemorySize = 1_048_576  // 1MB
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Clear namespace for HTTP client configuration; extensible for future shared constants |
| **Cons** | Introduces a new type; slightly more indirection |
| **Effort** | Very low |
| **Risk** | Very low |

### Option C: Make It a Protocol Requirement

Add `maxMemorySize` as a property requirement on `HTTPClientProtocol`:

```swift
protocol HTTPClientProtocol {
    var maxMemorySize: Int { get }
    // ...
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Each client can configure its own threshold if needed; protocol-enforced |
| **Cons** | Adds complexity for a value that should be identical across implementations; protocol conformance burden |
| **Effort** | Low |
| **Risk** | Low |

## Recommended Action

_To be filled in after team review._

## Technical Details

- 1MB (1,048,576 bytes) is the threshold. Responses at or below this size are held in `Data` in memory. Responses above this size are streamed to a temp file.
- The `HTTPResponse` struct has both `body: Data?` and `bodyFileURL: URL?` fields. When the response is in memory, `body` is set. When spilled to disk, `bodyFileURL` is set.
- The view model checks `bodyFileURL` first, then falls back to `body` for display.
- If the thresholds diverge between clients, the same response could be in memory with one client and on disk with the other, leading to different memory usage profiles and potentially different behavior in edge cases.

## Acceptance Criteria

- [ ] `maxMemorySize` is defined in exactly one location.
- [ ] Both `CurlHTTPClient` and `URLSessionHTTPClient` reference the same constant.
- [ ] The constant is documented with its purpose and unit (bytes).
- [ ] Changing the value in one place changes the behavior of both clients.
- [ ] No private duplicates of the constant remain in either client file.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [DRY Principle](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself)
