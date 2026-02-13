---
status: complete
priority: p3
issue_id: "015"
tags: [code-review, quality, dead-code]
dependencies: []
---

# Dead Code Cleanup (Multiple Locations)

## Problem Statement

Several pieces of dead code exist across the codebase:

1. **`extractVariables(from:)`** in `VariableInterpolator` — declared but never called
2. **`FocusedValues.selectedCollection`** — FocusedValueKey declared and published but never consumed
3. **`HTTPClientProtocol`** — protocol exists but no tests use it (premature abstraction)
4. **`HistoryEntry.requestSnapshot`** — property never populated
5. **`HistoryEntry.responseFilePath`** — property never used

**Why it matters:** Dead code adds cognitive load and maintenance burden.

## Proposed Solutions

### Option A: Remove all dead code (Recommended)
- Delete `extractVariables` method
- Remove `FocusedValues.selectedCollection` and related wiring
- Consider removing `HTTPClientProtocol` until tests are written
- Remove unused HistoryEntry properties
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `VariableInterpolator.swift`, `FocusedValues.swift`, `HTTPClientProtocol.swift`, `HistoryEntry.swift`

## Acceptance Criteria

- [ ] No unused methods, properties, or types remain
- [ ] Build succeeds after removal

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | ~50+ lines of dead code across 4 files |

## Resources

- Branch: `feat/mvp-architecture`
