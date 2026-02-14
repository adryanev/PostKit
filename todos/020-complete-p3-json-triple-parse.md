---
status: pending
priority: p3
issue_id: "020"
tags: [code-review, performance]
dependencies: []
---

# 020: JSON Triple-Parse

## Problem Statement

The `ResponseViewerPane` parses JSON response bodies multiple times redundantly. The `isJSON` computed property parses the body with `JSONSerialization` to check validity, then `displayString` parses it again for pretty-printing, and the body view calls `isJSON` on every render cycle. This results in up to three JSON parse operations per render for the same data, which is wasteful and can cause UI jank for large JSON responses.

## Findings

- **File:** `ResponseViewerPane.swift`, lines 126-144
- **Severity:** P3 (Nice-to-have)
- **Category:** Performance

The redundant parsing flow:

1. **`isJSON`** -- Calls `JSONSerialization.jsonObject(with:)` to check if the body is valid JSON. Returns `Bool`.
2. **`displayString`** -- If `isJSON` is true, calls `JSONSerialization.jsonObject(with:)` again, then `JSONSerialization.data(withJSONObject:options:.prettyPrinted)` to format it.
3. **SwiftUI render** -- The view body accesses `isJSON` (triggering parse #1) and conditionally renders the formatted string (triggering parse #2). On every SwiftUI view update, these computed properties are re-evaluated.

For a 1MB JSON response, this means parsing ~3MB of JSON data on every view re-render, which can cause visible UI stuttering.

## Proposed Solutions

### Option A: Cache JSON parse result in @State (Recommended)

Cache the parsed JSON result (or formatted string) in a `@State` property, computed once when the response changes via `.onChange(of:)` or `.task(id:)`.

**Pros:**
- Eliminates all redundant parsing
- JSON is parsed exactly once per response
- Cached result is reused across renders
- Follows SwiftUI best practices for expensive computations

**Cons:**
- Slightly more state to manage
- Need to invalidate cache when response changes

**Effort:** Low (1-2 hours)
**Risk:** Very low -- caching optimization with clear invalidation trigger

### Option B: Combine isJSON check with display formatting

Merge the `isJSON` and `displayString` logic into a single function that returns an optional formatted string (nil if not JSON).

**Pros:**
- Reduces two parses to one
- Simpler logic flow

**Cons:**
- Still re-parses on every render cycle (no caching)
- Only eliminates one of the three parses
- Computed properties in SwiftUI re-evaluate frequently

**Effort:** Low (30 minutes - 1 hour)
**Risk:** Very low

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Current flow (simplified):
```swift
// ResponseViewerPane.swift

var isJSON: Bool {
    guard let data = responseData else { return false }
    return (try? JSONSerialization.jsonObject(with: data)) != nil  // Parse #1
}

var displayString: String {
    guard let data = responseData else { return "" }
    if isJSON {  // Parse #1 again (computed property re-evaluates)
        let obj = try? JSONSerialization.jsonObject(with: data)  // Parse #2
        let pretty = try? JSONSerialization.data(withJSONObject: obj!, options: .prettyPrinted)
        return String(data: pretty!, encoding: .utf8) ?? ""
    }
    return String(data: data, encoding: .utf8) ?? ""
}
```

Proposed approach (Option A):
```swift
struct ResponseViewerPane: View {
    @State private var formattedJSON: String?
    @State private var isJSONResponse: Bool = false

    var body: some View {
        // use isJSONResponse and formattedJSON directly
    }
    .task(id: response?.id) {
        guard let data = responseData else {
            isJSONResponse = false
            formattedJSON = nil
            return
        }
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted) {
            isJSONResponse = true
            formattedJSON = String(data: pretty, encoding: .utf8)
        } else {
            isJSONResponse = false
            formattedJSON = nil
        }
    }
}
```

## Acceptance Criteria

- [ ] JSON response body is parsed at most once per response
- [ ] The parsed/formatted result is cached and reused across render cycles
- [ ] Cache is properly invalidated when the response changes
- [ ] UI behavior remains identical (JSON detection and pretty-printing work as before)
- [ ] Performance improvement is measurable for large JSON responses (optional: add benchmark)
- [ ] All existing tests continue to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- File: `PostKit/PostKit/Views/RequestDetail/ResponseViewerPane.swift`
- [Apple: JSONSerialization](https://developer.apple.com/documentation/foundation/jsonserialization)
- [SwiftUI State Management Best Practices](https://developer.apple.com/documentation/swiftui/state)
