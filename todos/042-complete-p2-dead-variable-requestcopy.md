---
status: complete
priority: p2
issue_id: "042"
tags: [simplicity, code-quality, code-review]
dependencies: []
---

# Dead Variable: requestCopy Adds No Value

`requestCopy` in MenuBarView is just `request` renamed, adds confusion with no benefit.

## Problem Statement

The variable `requestCopy` suggests it's a copy of `request`, but it's actually the same reference. This is misleading and adds unnecessary complexity.

**Why this matters:**
- Confusing variable name suggests a copy exists
- Developers might assume it's a value type
- Adds unnecessary tuple destructuring

## Findings

- **Location:** `MenuBarView.swift:75-80`
- **Issue:**
```swift
let (urlRequest, requestCopy) = await MainActor.run {
    return (urlRequest, request)  // requestCopy = request, no actual copy!
}

// All uses of requestCopy.id could just be request.id
```

**The name implies a defensive copy, but `request` is a class reference - it's the same object.**

## Proposed Solutions

### Option 1: Remove the Tuple, Use request Directly (Recommended)

**Approach:** Simplify by removing the useless tuple element.

```swift
let urlRequest = await MainActor.run {
    _ = sendingRequestIDs.insert(request.id)
    let variables = requestBuilder.getActiveEnvironmentVariables(from: modelContext)
    return try? requestBuilder.buildURLRequest(for: request, with: variables)
}

// Use `request` directly instead of `requestCopy`
```

**Pros:**
- Clearer code
- Less confusion
- Fewer lines

**Cons:**
- None

**Effort:** 10 minutes

**Risk:** Low

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Views/MenuBar/MenuBarView.swift:75-80`

**Note:** This is related to but separate from issue #040 (data race). Even after fixing the data race, `requestCopy` should be removed if it provides no value.

## Acceptance Criteria

- [ ] No `requestCopy` variable
- [ ] Use `request` directly where safe
- [ ] Code is simpler and clearer
- [ ] All tests pass

## Work Log

### 2026-02-21 - Code Simplicity Review

**By:** code-simplicity-reviewer agent

**Actions:**
- Identified dead variable pattern
- Analyzed whether copy was needed
- Determined it provides no value

**Learnings:**
- Variable names should reflect reality
- "Copy" implies value semantics - misleading for references
