---
status: complete
priority: p3
issue_id: "017"
tags: [code-review, architecture]
dependencies: []
---

# Double HTTPClient Instantiation

## Problem Statement

`Environment+HTTPClient.swift` provides a default value that creates a new `URLSessionHTTPClient()` instance. `PostKitApp` also creates one and injects it. This means a default unused instance is created on first access of the environment key, wasting resources.

**Why it matters:** Minor resource waste and confusing DI setup.

## Proposed Solutions

### Option A: Use a fatal default or optional (Recommended)
- Make the environment value optional or use `fatalError("HTTPClient not configured")` as default
- Ensures the injected instance is always used
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `Environment+HTTPClient.swift`, `PostKitApp.swift`

## Acceptance Criteria

- [x] Only one HTTPClient instance exists at runtime

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Default environment values can create unused instances |
| 2026-02-13 | Resolved: removed duplicate instantiation from PostKitApp | Rely on EnvironmentKey defaultValue as the single source of truth |

## Resources

- Branch: `feat/mvp-architecture`
