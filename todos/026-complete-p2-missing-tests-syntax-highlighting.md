---
status: pending
priority: p2
issue_id: "026"
tags: [code-review, testing, syntax-highlighting]
dependencies: []
---

# Missing Tests for Syntax Highlighting Feature

## Problem Statement
The project's testing standards (`docs/sop/testing-standards.md`) require every change to include tests with positive, negative, and edge cases. PR #5 adds ~557 lines of new code across multiple components but includes zero tests. Key testable logic includes content-type to language mapping, body type to language mapping, display string computation, and the highlighting threshold logic.

## Findings
- **Location:** Multiple new/modified files with no corresponding test additions
- **Evidence:** No test files added or modified in the PR diff
- **Impact:** Regressions in language detection, display logic, or threshold behavior won't be caught
- **Agents:** security-sentinel (informational), code-simplicity-reviewer

## Proposed Solutions

### Solution A: Unit tests for pure logic functions (Recommended)
Add tests for the testable pure functions without needing to instantiate AppKit views:

1. `HTTPResponse.contentType` — test various header casings and formats
2. `BodyType.highlightrLanguage` — test all body type mappings
3. `ResponseBodyView.languageForContentType` — test content-type to language mapping (needs to be extracted to a free function or static method for testability)
4. `ResponseBodyView.computeDisplayString` — test JSON pretty-printing, raw mode, threshold behavior

**Pros:** Covers the most important logic; fast tests; no AppKit dependency
**Cons:** Doesn't test the NSViewRepresentable integration
**Effort:** Small-Medium
**Risk:** Low

### Solution B: Full integration tests with view hosting
Use `NSHostingView` or XCTest view hosting to test CodeTextView rendering.

**Pros:** Tests the full integration path
**Cons:** Slow, flaky, depends on AppKit run loop; overkill for this PR
**Effort:** Large
**Risk:** Medium (flaky tests)

## Recommended Action


## Technical Details
- **Affected files:** `PostKit/PostKitTests/PostKitTests.swift` (add new test sections)
- **Functions to test:**
  - `HTTPResponse.contentType` (HTTPClientProtocol.swift:35-38)
  - `BodyType.highlightrLanguage` (BodyType.swift:22-31)
  - `languageForContentType` (ResponseViewerPane.swift:171-181)
  - `computeDisplayString` (ResponseViewerPane.swift:157-169)

## Acceptance Criteria
- [ ] Tests for `HTTPResponse.contentType` with various header formats
- [ ] Tests for `BodyType.highlightrLanguage` covering all cases
- [ ] Tests for language detection from content types
- [ ] Tests for display string computation (pretty-print, raw, threshold)
- [ ] All tests pass with `xcodebuild test`

## Work Log
- 2026-02-15: Created from PR #5 code review (multiple agents)

## Resources
- PR: #5 feat: add syntax highlighting with Highlightr
- Testing standards: docs/sop/testing-standards.md
