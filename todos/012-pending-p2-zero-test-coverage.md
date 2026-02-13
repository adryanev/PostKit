---
status: complete
priority: p2
issue_id: "012"
tags: [code-review, quality, testing]
dependencies: []
---

# Zero Test Coverage

## Problem Statement

`PostKitTests.swift` is an empty scaffold (17 lines). There are no unit tests, integration tests, or UI tests for any functionality. Core services like `HTTPClient`, `CurlParser`, `OpenAPIParser`, `VariableInterpolator`, and `FileExporter` are entirely untested.

**Why it matters:** Without tests, regressions go undetected and refactoring is risky.

## Findings

- **PostKitTests.swift** — empty test scaffold, only boilerplate
- All services are pure logic that could be easily unit tested
- `HTTPClientProtocol` exists but no mock implementation for testing
- **Confirmed by:** Architecture Strategist, Pattern Recognition agents

## Proposed Solutions

### Option A: Add tests for core services (Recommended)
- Write unit tests for `CurlParser`, `OpenAPIParser`, `VariableInterpolator`, `FileExporter`
- Create a mock `HTTPClientProtocol` implementation for view testing
- Start with parsers (pure functions, easiest to test)
- **Pros:** Catches bugs, enables safe refactoring
- **Cons:** Time investment
- **Effort:** Large
- **Risk:** None

## Technical Details

- **Affected files:** `PostKitTests/`, all service files

## Acceptance Criteria

- [ ] CurlParser has tests for valid and invalid input
- [ ] OpenAPIParser has tests for valid and malformed specs
- [ ] VariableInterpolator has tests for substitution and edge cases
- [ ] FileExporter round-trip test (export then import)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Pure service logic is ideal for unit testing |

## Resources

- Branch: `feat/mvp-architecture`
