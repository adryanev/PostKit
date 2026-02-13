---
status: complete
priority: p3
issue_id: "018"
tags: [code-review, quality, security]
dependencies: []
---

# cURL Parser Validation Gaps

## Problem Statement

`CurlParser` has two minor gaps:

1. URL validation only checks `hasPrefix("http")` — doesn't validate scheme properly (e.g., `httpevil://` would pass)
2. Tokenizer doesn't handle backslash escape characters within quoted strings

**Why it matters:** Malformed cURL commands could produce unexpected requests.

## Proposed Solutions

### Option A: Strengthen validation (Recommended)
- Use `URL(string:)` for proper URL validation
- Handle `\"` escape sequences in tokenizer
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `CurlParser.swift`

## Acceptance Criteria

- [x] Invalid URLs are rejected with clear error
- [x] Escaped characters in quoted strings are handled

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Defense in depth for import functionality |

## Resources

- Branch: `feat/mvp-architecture`
