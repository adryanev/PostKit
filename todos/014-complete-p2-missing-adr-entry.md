---
status: pending
priority: p2
issue_id: "014"
tags: [code-review, documentation]
dependencies: []
---

# 014: Missing ADR Entry

## Problem Statement

The switch from `URLSession` to `libcurl` as the HTTP client engine is a significant architectural decision, but no Architecture Decision Record (ADR) has been added to document it. The project's `CLAUDE.md` explicitly states: "When adding a new major architectural decision, append a new ADR entry to the existing ADR document following the same format (Context, Decision, Alternatives Considered, Consequences)." This omission means the rationale, alternatives considered, and trade-offs of this decision are not captured for future reference.

## Findings

- **File:** `docs/adr/0001-postkit-architecture-decisions.md`
- The existing ADR document contains 18 Architecture Decision Records (ADR-001 through ADR-018).
- ADR-013 specifically discusses "Actor-Based HTTP Client" using URLSession.
- The PR replaces the URLSession-based HTTP client with a libcurl-based implementation -- this directly supersedes ADR-013.
- No ADR-019 (or similar) entry documents:
  - Why libcurl was chosen over URLSession
  - What alternatives were considered (e.g., AsyncHTTPClient, custom URLSession configuration)
  - What the consequences are (C interop complexity, new dependency, threading model changes)
  - What trade-offs were accepted
- The brainstorm document at `docs/brainstorms/` contains exploration notes about HTTP client engines, but this is not the same as a formal ADR.
- Without an ADR, future maintainers will not understand why this significant architectural change was made.

## Proposed Solutions

### Option A: Add ADR-019 Documenting the libcurl Decision (Recommended)

Append a new ADR entry to `docs/adr/0001-postkit-architecture-decisions.md` following the established format:

```markdown
## ADR-019: Replace URLSession with libcurl for HTTP Client Engine

### Status
Accepted

### Context
[Why the change was needed -- e.g., limitations of URLSession for specific HTTP features,
need for more control over HTTP behavior, etc.]

### Decision
Replace the URLSession-based HTTPClient with a libcurl-based implementation (CurlHTTPClient)
while maintaining the same HTTPClientProtocol interface.

### Alternatives Considered
1. **Enhanced URLSession configuration** -- [why rejected]
2. **Swift AsyncHTTPClient (swift-nio)** -- [why rejected]
3. **Custom CFNetwork usage** -- [why rejected]

### Consequences
**Positive:**
- [Benefits of libcurl]

**Negative:**
- C interop complexity (@unchecked Sendable, unsafe pointers)
- Additional dependency (system libcurl)
- More complex threading model (GCD queue for blocking calls)

**Neutral:**
- HTTPClientProtocol interface unchanged
- Both implementations retained for fallback
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Follows established project conventions; captures rationale for posterity; future maintainers understand the decision; supersedes/updates ADR-013 |
| **Cons** | Requires the PR author to articulate the decision rationale |
| **Effort** | Low (documentation only) |
| **Risk** | Very low |

### Option B: Update ADR-013 Instead of Adding a New Entry

Modify the existing ADR-013 ("Actor-Based HTTP Client") to reflect the new implementation:

| Aspect | Detail |
|--------|--------|
| **Pros** | Keeps related information together; no new entry needed |
| **Cons** | Loses the history of the original decision; ADR best practice is to add new records rather than modify old ones; ADR-013 still has value as a historical record |
| **Effort** | Low |
| **Risk** | Low, but violates ADR conventions |

## Recommended Action

_To be filled in after team review._

## Technical Details

- The ADR document uses a consistent format: numbered header, Status, Context, Decision, Alternatives Considered, Consequences (split into Positive/Negative/Neutral).
- The existing ADR entries cover decisions including: SwiftUI over AppKit (ADR-001), SwiftData over CoreData (ADR-002), zero external dependencies (ADR-003), actor-based HTTP client (ADR-013), Swift Testing (ADR-015), and others.
- ADR-003 ("Minimal External Dependencies") is particularly relevant since libcurl introduces a system dependency. The ADR should address how this aligns with or departs from the minimal-dependency philosophy.
- The brainstorm document at `docs/brainstorms/` may contain useful context that can be distilled into the ADR.
- The commit message for the PR (`feat: Replace HTTP client engine with libcurl`) provides a starting point but lacks the depth of an ADR.

## Acceptance Criteria

- [ ] An ADR entry exists in `docs/adr/0001-postkit-architecture-decisions.md` documenting the switch to libcurl.
- [ ] The ADR follows the established format: Status, Context, Decision, Alternatives Considered, Consequences.
- [ ] The ADR explains why libcurl was chosen over URLSession and other alternatives.
- [ ] The ADR documents the consequences (positive, negative, neutral) of the decision.
- [ ] The ADR references or supersedes ADR-013 as appropriate.
- [ ] The ADR addresses the relationship with ADR-003 (minimal dependencies).

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [Architecture Decision Records](https://adr.github.io/)
- [Existing PostKit ADR document](../docs/adr/0001-postkit-architecture-decisions.md)
- [CLAUDE.md ADR guidance](../CLAUDE.md)
- [Michael Nygard's ADR article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
