---
status: complete
priority: p1
issue_id: "040"
tags: [security, concurrency, swiftdata, code-review]
dependencies: []
---

# Data Race: SwiftData Model Accessed Outside MainActor

MenuBarView captures SwiftData @Model object and accesses it after async suspension, violating thread safety.

## Problem Statement

The code captures `request` (a SwiftData `@Model` object) and accesses it outside the `MainActor` context after `await httpClient.execute(...)`. SwiftData model objects are NOT thread-safe.

**Why this matters:**
- Undefined behavior - potential crashes
- Data races / memory corruption
- Stale/corrupted data reads
- Model context corruption

## Findings

- **Location:** `MenuBarView.swift:75-127`
- **Issue pattern:**
```swift
let (urlRequest, requestCopy) = await MainActor.run {
    return (urlRequest, request)  // 'request' is @Model, NOT a copy
}

// After await - outside MainActor:
await MainActor.run {
    results[requestCopy.id] = ...           // ❌ accessing model
    let entry = HistoryEntry(
        method: requestCopy.method,         // ❌ accessing model property
        url: requestCopy.urlTemplate,       // ❌ accessing model property
    )
    entry.request = requestCopy             // ❌ assigning relationship
}
```

**The `requestCopy` is NOT a copy - it's the same @Model reference!**

## Proposed Solutions

### Option 1: Capture Primitives Before MainActor Exit (Recommended)

**Approach:** Extract all needed primitive values inside MainActor, use those after.

```swift
let (urlRequest, requestID, method, urlTemplate) = await MainActor.run {
    _ = sendingRequestIDs.insert(request.id)
    let variables = requestBuilder.getActiveEnvironmentVariables(from: modelContext)
    let urlRequest = try? requestBuilder.buildURLRequest(for: request, with: variables)
    return (urlRequest, request.id, request.method, request.urlTemplate)
}

// Now safe to use primitives:
await MainActor.run {
    results[requestID] = MenuBarResult(...)
    let entry = HistoryEntry(method: method, url: urlTemplate, ...)
}
```

**Pros:**
- Thread-safe
- Clear data flow
- No model context issues

**Cons:**
- More verbose
- Need to fetch request again for relationship

**Effort:** 30 minutes

**Risk:** Low

---

### Option 2: Refetch Model Inside MainActor

**Approach:** Keep only the ID, fetch fresh inside each MainActor block.

**Pros:**
- Always fresh data
- No stale references

**Cons:**
- Extra fetch operations
- More complex

**Effort:** 1 hour

**Risk:** Low

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Views/MenuBar/MenuBarView.swift:75-127`

**Properties accessed outside MainActor:**
- `request.id`
- `request.method`
- `request.urlTemplate`

**SwiftData threading rules:**
- @Model objects are MainActor-bound
- Access must be on MainActor
- Crossing async boundaries requires value capture

## Acceptance Criteria

- [ ] All @Model access confined to single MainActor block
- [ ] Only primitive values captured and used after await
- [ ] No compiler warnings about Sendable
- [ ] Thread sanitizer shows no data races

## Work Log

### 2026-02-21 - Security Review Discovery

**By:** security-sentinel agent

**Actions:**
- Identified data race pattern in async code
- Traced model access across MainActor boundaries
- Documented properties being unsafely accessed

**Learnings:**
- `requestCopy = request` is NOT a copy for @Model
- SwiftData models require MainActor confinement
- Async boundaries break model access safety
