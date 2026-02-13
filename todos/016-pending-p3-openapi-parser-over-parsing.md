---
status: complete
priority: p3
issue_id: "016"
tags: [code-review, quality, performance]
dependencies: []
---

# OpenAPI Parser Over-Parses Unused Fields

## Problem Statement

`OpenAPIParser` parses responses, tags, and descriptions from OpenAPI specs, but none of these parsed values are used by the app. This adds unnecessary complexity and processing time.

**Why it matters:** Simpler parser = fewer bugs, faster parsing, easier maintenance.

## Proposed Solutions

### Option A: Remove unused parsing (Recommended)
- Strip parsing of responses, tags, descriptions
- Keep only: paths, methods, parameters, request bodies
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `OpenAPIParser.swift`

## Acceptance Criteria

- [x] Parser only extracts fields that are actually used
- [x] Import functionality still works correctly

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | YAGNI -- don't parse what you don't use |
| 2026-02-13 | Completed | Removed responses, tags, description from OpenAPIEndpoint; simplified OpenAPIParameter to name+location only; simplified OpenAPIRequestBody to contentType only |

## Resources

- Branch: `feat/mvp-architecture`
