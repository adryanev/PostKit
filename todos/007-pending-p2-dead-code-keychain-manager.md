---
status: complete
priority: p2
issue_id: "007"
tags: [code-review, quality, dead-code]
dependencies: ["002"]
---

# Dead Code: KeychainManager (108 Lines, Never Used)

## Problem Statement

`KeychainManager.swift` is a 108-line fully implemented Keychain wrapper that is never called anywhere in the codebase. It's dead code that adds maintenance burden.

**Why it matters:** Dead code confuses developers and inflates the codebase. However, this should be wired up (see #002) rather than deleted, since secrets ARE currently stored in plaintext.

## Findings

- **KeychainManager.swift** — 108 lines, `KeychainManager.shared` only referenced within its own file
- No import or usage in any other Swift file
- **Confirmed by:** Architecture Strategist, Pattern Recognition, Code Simplicity agents

## Proposed Solutions

### Option A: Wire it up for credential storage (Recommended)
- Integrate with #002 to store auth credentials in Keychain
- This turns dead code into essential infrastructure
- **Pros:** Solves two issues at once
- **Cons:** Requires #002 first
- **Effort:** Medium (part of #002)
- **Risk:** Low

### Option B: Delete it
- Remove `KeychainManager.swift` entirely
- **Pros:** Reduces codebase by 108 lines
- **Cons:** Will need to rewrite when #002 is addressed
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `KeychainManager.swift`
- **Dependencies:** Blocked by #002 decision

## Acceptance Criteria

- [ ] KeychainManager is either integrated or removed
- [ ] No dead code remaining

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Wire up rather than delete — solves #002 |
| 2026-02-13 | Resolved via #002 implementation | KeychainManager now used by Variable.secureValue and AuthConfig extension |

## Resources

- Branch: `feat/mvp-architecture`
