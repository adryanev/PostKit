---
status: pending
priority: p2
issue_id: "009"
tags: [code-review, correctness, portability]
dependencies: []
---

# 009: Progress Callback Type Mismatch (Int vs Int64)

## Problem Statement

The `curlProgressCallback` function uses `Int` parameters for download/upload totals and current values, but libcurl's `CURLOPT_XFERINFOFUNCTION` expects `curl_off_t` parameters, which is `Int64`. On 64-bit platforms (all modern Apple platforms), `Int` and `Int64` are the same size, so this works by coincidence. However, it is technically incorrect per the libcurl API contract and could cause issues on hypothetical 32-bit platforms or if the code is reused in a cross-platform Swift context.

## Findings

- **File:** `CurlHTTPClient.swift:133`
- The callback signature uses `Int` for the progress values.
- libcurl's `CURLOPT_XFERINFOFUNCTION` is defined as:
  ```c
  int progress_callback(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow);
  ```
- `curl_off_t` is typedef'd to `int64_t` (i.e., `Int64` in Swift).
- On Apple's current platforms (macOS, iOS, etc.), `Int` is 64-bit, so `Int` and `Int64` have the same representation.
- Swift's C interop imports `curl_off_t` as `Int64`.
- If the function signature does not exactly match what libcurl expects, the behavior is technically undefined, even if it happens to work.

## Proposed Solutions

### Option A: Change Parameter Types to Int64 (Recommended)

Update the callback signature to use `Int64` (matching `curl_off_t`):

```swift
func curlProgressCallback(
    clientp: UnsafeMutableRawPointer?,
    dltotal: Int64,
    dlnow: Int64,
    ultotal: Int64,
    ulnow: Int64
) -> Int32 {
    // ...
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Matches the libcurl API contract exactly; correct by specification; no ambiguity; portable |
| **Cons** | May require minor adjustments where these values are used (e.g., casting to Int for Swift APIs) |
| **Effort** | Very low (type annotation change) |
| **Risk** | Very low -- functionally identical on current platforms; strictly more correct |

### Option B: Keep As-Is with Platform Assumption Comment

Add a comment documenting that `Int` == `Int64` on all supported Apple platforms:

```swift
// Note: Int is 64-bit on all supported Apple platforms, matching curl_off_t (Int64).
// If targeting 32-bit platforms in the future, change these to Int64.
```

| Aspect | Detail |
|--------|--------|
| **Pros** | No code change; documents the assumption |
| **Cons** | Still technically incorrect; relies on platform-specific behavior; the comment is easy to overlook |
| **Effort** | Very low |
| **Risk** | Low on current platforms, but leaves a latent bug |

## Recommended Action

_To be filled in after team review._

## Technical Details

- `curl_off_t` is defined in `<curl/system.h>` as `int64_t` on all modern platforms.
- Swift imports C `int64_t` as `Int64`.
- On macOS (arm64 and x86_64), `Int` is 64-bit. On watchOS (32-bit armv7k, now deprecated), `Int` would be 32-bit.
- The callback is set via `CURLOPT_XFERINFOFUNCTION`. If the types do not match, the compiler may warn or the values may be truncated/misinterpreted.
- In practice, Swift's C interop coerces the function pointer types, so the current code compiles and runs correctly on 64-bit platforms.
- The progress callback also returns `Int32` (matching libcurl's expected `int` return type), which is correct.

## Acceptance Criteria

- [ ] The progress callback signature uses `Int64` for all four progress parameters.
- [ ] The callback compiles without warnings when passed to `CURLOPT_XFERINFOFUNCTION`.
- [ ] Progress reporting continues to work correctly (download/upload progress displayed in UI).
- [ ] Any downstream usage of the progress values handles the `Int64` type appropriately.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [CURLOPT_XFERINFOFUNCTION](https://curl.se/libcurl/c/CURLOPT_XFERINFOFUNCTION.html)
- [curl_off_t definition](https://curl.se/libcurl/c/curl_off_t.html)
- [Swift Int size documentation](https://developer.apple.com/documentation/swift/int)
