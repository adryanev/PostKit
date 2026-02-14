---
status: pending
priority: p3
issue_id: "015"
tags: [code-review, simplicity]
dependencies: []
---

# 015: SetupResult Enum Should Use throws

## Problem Statement

The `CurlHTTPClient` defines a custom `SetupResult` enum with `success`/`failure` cases to communicate the outcome of `setupHandle`. This duplicates Swift's native error handling mechanism (`throws`), adding unnecessary complexity and deviating from idiomatic Swift patterns. The function should simply throw errors directly instead of wrapping them in a result enum.

## Findings

- **File:** `CurlHTTPClient.swift`, lines 243-246
- **Severity:** P3 (Nice-to-have)
- **Category:** Code simplicity

The `SetupResult` enum provides `success` and `failure` cases, which is functionally identical to what Swift's `throws` mechanism provides natively. Every call site must pattern match on the result instead of using standard `do`/`catch` blocks. This creates unnecessary boilerplate and makes the code harder to read for developers expecting idiomatic Swift error handling.

## Proposed Solutions

### Option A: Make setupHandle throw instead (Recommended)

Remove the `SetupResult` enum and refactor `setupHandle` to throw errors directly. Call sites switch from pattern matching to `do`/`catch`.

**Pros:**
- Idiomatic Swift error handling
- Reduces boilerplate at call sites
- Eliminates a custom type that duplicates language-level functionality
- Better composability with other throwing functions

**Cons:**
- Requires updating all call sites of `setupHandle`

**Effort:** Low (1-2 hours)
**Risk:** Low -- straightforward mechanical refactor

### Option B: Keep as-is

Leave the `SetupResult` enum in place.

**Pros:**
- No code changes required
- Explicit result type visible in function signature

**Cons:**
- Non-idiomatic Swift
- Extra boilerplate at call sites
- Maintains a type that duplicates built-in language functionality

**Effort:** None
**Risk:** None

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Current pattern:
```swift
enum SetupResult {
    case success
    case failure(CurlError)
}

func setupHandle(...) -> SetupResult {
    // ...
    return .failure(.setupFailed("..."))
    // ...
    return .success
}
```

Proposed pattern:
```swift
func setupHandle(...) throws {
    // ...
    throw CurlError.setupFailed("...")
    // ...
    // implicit success by not throwing
}
```

Call sites change from:
```swift
switch setupHandle(...) {
case .success: ...
case .failure(let error): ...
}
```

To:
```swift
do {
    try setupHandle(...)
    // success path
} catch {
    // failure path
}
```

## Acceptance Criteria

- [ ] `SetupResult` enum is removed from `CurlHTTPClient.swift`
- [ ] `setupHandle` method uses `throws` instead of returning `SetupResult`
- [ ] All call sites are updated to use `do`/`catch` or `try`
- [ ] All existing tests continue to pass
- [ ] No functional behavior change

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- [Swift Error Handling Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/)
- File: `PostKit/PostKit/Services/CurlHTTPClient.swift`
