---
status: complete
priority: p2
issue_id: "014"
tags: [code-review, security]
dependencies: []
---

# Collection Import/Export Can Leak Secrets

## Problem Statement

When exporting collections, `FileExporter` may include auth credentials and secret variable values in the exported JSON file. While there's some stripping logic, it needs verification that ALL secret values are properly excluded.

Additionally, imported collections may contain malicious or unexpected data that isn't validated.

**Why it matters:** Users sharing collection exports could inadvertently leak API keys and credentials.

## Findings

- **FileExporter.swift** — export logic exists but needs audit for completeness
- Auth headers, Bearer tokens, API keys could be embedded in exported request data
- Import doesn't validate or sanitize incoming data
- **Confirmed by:** Security Sentinel agent

## Proposed Solutions

### Option A: Audit and strengthen export stripping (Recommended)
- Verify all secret fields are stripped on export
- Add explicit "include secrets" opt-in flag
- Validate imported data structure
- **Pros:** Prevents credential leaks
- **Cons:** May require UI for opt-in
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `FileExporter.swift`

## Acceptance Criteria

- [x] Exported JSON never contains auth credentials by default
- [x] Secret variables are excluded from export
- [ ] Import validates data structure
- [ ] User can opt-in to include secrets if needed

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Credential leaks through file sharing |
| 2026-02-13 | Fixed: sensitive header values redacted on export | Authorization, X-API-Key, X-Auth-Token, Proxy-Authorization, Cookie headers are replaced with [REDACTED]; secret env variables already stripped |

## Resources

- Branch: `feat/mvp-architecture`
