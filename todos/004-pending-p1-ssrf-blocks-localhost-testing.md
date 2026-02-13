---
status: complete
priority: p1
issue_id: "004"
tags: [code-review, bug, architecture]
dependencies: []
---

# SSRF Protection Blocks Localhost / Local API Testing

## Problem Statement

`VariableInterpolator` blocks requests to `localhost`, `127.0.0.1`, `::1`, and private IP ranges (10.x, 172.16-31.x, 192.168.x). For a desktop HTTP client (Postman alternative), testing local APIs is the PRIMARY use case. The SSRF protection actively prevents the app's core functionality.

Additionally, if SSRF protection is kept, it has multiple bypasses (DNS rebinding, decimal IP encoding `2130706433`, IPv6 mapped addresses, HTTP redirects from public to private).

**Why it matters:** Users cannot test their locally running APIs — the #1 use case for an HTTP client tool.

## Findings

- **VariableInterpolator.swift:66-90** — `isBlockedHost()` and `isPrivateIP()` block localhost and private ranges
- SSRF protection is appropriate for server-side apps, NOT desktop HTTP clients
- Even if kept, it's bypassable via DNS rebinding, decimal IPs, IPv6 mapped addresses
- **Confirmed by:** Architecture Strategist, Code Simplicity, Security Sentinel agents

## Proposed Solutions

### Option A: Remove SSRF protection entirely (Recommended)
- Delete `isBlockedHost()` and `isPrivateIP()` methods
- Desktop apps don't need SSRF protection — the user controls what URLs they enter
- **Pros:** Fixes core use case, removes ~25 lines of unnecessary code
- **Cons:** None — this protection is inappropriate for the app type
- **Effort:** Small
- **Risk:** None

### Option B: Make it configurable
- Add a setting to enable/disable SSRF protection
- Default to OFF for desktop usage
- **Pros:** Flexibility
- **Cons:** Unnecessary complexity for a desktop app
- **Effort:** Small
- **Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files:** `VariableInterpolator.swift`
- **Components:** URL interpolation, request sending

## Acceptance Criteria

- [ ] Users can send requests to `localhost` and `127.0.0.1`
- [ ] Users can send requests to private IP ranges
- [ ] Local API testing works without workarounds

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | SSRF protection is a server-side concern, not desktop |

## Resources

- Branch: `feat/mvp-architecture`
