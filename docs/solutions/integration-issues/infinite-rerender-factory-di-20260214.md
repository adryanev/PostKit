---
module: Core Architecture
date: 2026-02-14
problem_type: integration_issue
component: service_object
symptoms:
  - Infinite re-render loops in SwiftUI views using @Observable ViewModels
  - App hangs on launch when using @Injected in @Observable classes
  - "Allocating unbounded memory" crashes
root_cause: config_error
resolution_type: code_fix
severity: high
tags: [factory, dependency-injection, observable, swiftui, observation-framework]
---

# Factory @Injected with @Observable: Infinite Re-render Fix

## Problem

When using Factory's `@Injected` property wrapper in SwiftUI `@Observable` classes, the app experienced infinite re-render loops, hangs on launch, or memory allocation crashes. The Observation framework interpreted dependency resolution as state changes, triggering continuous view updates.

## Environment

- Module: Core Architecture / Dependency Injection
- Platform: macOS 14.0+ (Sonoma)
- Frameworks: SwiftUI, SwiftData, Factory 2.5.x
- Affected Component: `@Observable` ViewModels with `@Injected` dependencies
- Date: 2026-02-14

## Symptoms

- SwiftUI views continuously re-render without user interaction
- App becomes unresponsive on launch
- Console shows repeated observation tracking cycles
- Memory usage grows unbounded until crash
- Compilation errors in some cases due to observation macro conflicts

## What Didn't Work

**Attempted Solution 1:** Using `@Injected` directly in `@Observable` class
- **Why it failed:** The Observation framework tracks all stored property access. When SwiftUI accesses the `@Injected` property, it triggers observation tracking, which causes re-render, which accesses the property again.

**Attempted Solution 2:** Lazy initialization in `init()`
- **Why it failed:** Still tracked by Observation framework; doesn't prevent the observation cycle.

## Solution

Add `@ObservationIgnored` before every `@Injected` property in `@Observable` classes.

**Code changes:**

```swift
// BEFORE (broken):
@Observable
final class RequestViewModel {
    @Injected(\.httpClient) private var httpClient
    @Injected(\.variableInterpolator) private var interpolator
}

// AFTER (fixed):
@Observable
final class RequestViewModel {
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.variableInterpolator) private var interpolator
}
```

## Why This Works

1. **Root Cause:** The Swift Observation framework (`@Observable` macro) automatically tracks all stored properties as observable state. Factory's `@Injected` property wrapper resolves dependencies lazily on first access.

2. **The Conflict:** When SwiftUI accesses an injected property, the Observation framework interprets this as a state change, invalidating the view. The view re-renders, accesses the property again, creating an infinite loop.

3. **The Fix:** `@ObservationIgnored` tells the Observation macro to exclude this property from tracking. The dependency is resolved once and stored, but never triggers observation events.

## Prevention

- **Mandatory pattern:** Always use `@ObservationIgnored @Injected(\.key)` in `@Observable` classes
- **Checklist:** When adding `@Injected` to any class marked `@Observable`, immediately add `@ObservationIgnored`
- **Code review:** Search for `@Injected` not preceded by `@ObservationIgnored` in `@Observable` files

### Quick Reference

| Context | Pattern |
|---------|---------|
| `@Observable` class | `@ObservationIgnored @Injected(\.service) private var service` |
| SwiftUI View (struct) | `@Injected(\.service) private var service` (no `@ObservationIgnored` needed) |
| `@Model` class | `Container.shared.service()` (property wrappers not supported) |
| Test suite | `@Suite(.container)` for Factory container isolation |

### Files Modified

- `PostKit/PostKit/ViewModels/RequestViewModel.swift` — Added `@ObservationIgnored` to injected properties

### Container Organization

```
DI/
├── Container+Services.swift   # httpClient, keychainManager, fileExporter
└── Container+Parsers.swift    # curlParser, openAPIParser, variableInterpolator
```

## Related Issues

- See also: [ADR-020: Factory Dependency Injection Container](../../../docs/adr/0001-postkit-architecture-decisions.md#adr-020-factory-dependency-injection-container)
- See also: [Factory DI Implementation Plan](../../../docs/plans/2026-02-14-feat-factory-dependency-injection-plan.md)
- See also: [Developer Guide - DI Section](../../../docs/sop/developer-guide.md#dependency-injection-via-factory-container)
