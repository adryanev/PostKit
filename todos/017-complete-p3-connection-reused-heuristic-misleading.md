---
status: pending
priority: p3
issue_id: "017"
tags: [code-review, ux, correctness]
dependencies: []
---

# 017: connectionReused Heuristic Misleading

## Problem Statement

The `connectionReused` property in `ResponseViewerPane.swift` uses a heuristic that checks whether DNS, TCP, and TLS timings are all less than 1ms to infer connection reuse. This heuristic can produce false positives on fast local connections (e.g., localhost, LAN servers) where these phases genuinely complete in under 1ms without connection reuse. The UI presents this as a definitive statement rather than an inference.

## Findings

- **File:** `ResponseViewerPane.swift`, lines 271-273
- **Severity:** P3 (Nice-to-have)
- **Category:** UX, correctness

The current implementation:
```swift
var connectionReused: Bool {
    timing.dnsLookup < 0.001 && timing.tcpHandshake < 0.001 && timing.tlsHandshake < 0.001
}
```

This heuristic is inherently unreliable for:
- Connections to `localhost` or `127.0.0.1` where DNS is near-instant
- LAN connections with very low latency
- Connections where DNS is cached at the OS level

The UI displays this as a factual indicator, which could mislead users into thinking a connection was definitively reused when it may not have been.

## Proposed Solutions

### Option A: Add "likely" qualifier to UI text (Recommended)

Change the UI label to indicate uncertainty, e.g., "Connection likely reused" instead of "Connection reused." Keep the same heuristic logic.

**Pros:**
- Honest representation of what the heuristic can determine
- Minimal code change
- No additional libcurl API complexity
- Still provides useful information to the user

**Cons:**
- Less definitive UX (but more accurate)

**Effort:** Very low (15-30 minutes)
**Risk:** Very low -- UI text change only

### Option B: Use CURLINFO_CONN_ID from libcurl

Query libcurl's `CURLINFO_CONN_ID` (available in newer libcurl versions) to get a definitive connection identifier, then compare across requests to determine actual reuse.

**Pros:**
- Accurate, non-heuristic connection reuse detection
- Leverages libcurl's internal knowledge

**Cons:**
- Requires additional C shim function for the new CURLINFO type
- CURLINFO_CONN_ID may not be available in all libcurl versions
- More complex implementation requiring state tracking across requests
- May require minimum libcurl version bump

**Effort:** Medium (2-4 hours)
**Risk:** Low-medium -- depends on libcurl version compatibility

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Current heuristic location:
```swift
// ResponseViewerPane.swift, lines 271-273
var connectionReused: Bool {
    timing.dnsLookup < 0.001 && timing.tcpHandshake < 0.001 && timing.tlsHandshake < 0.001
}
```

Option A change -- update the UI label where `connectionReused` is displayed:
```swift
// Change from:
Text("Connection reused")
// To:
Text("Connection likely reused")
```

Option B would require:
1. Adding `curl_easy_getinfo` call for `CURLINFO_CONN_ID` in the C shim
2. Storing the connection ID in the timing/response metadata
3. Comparing connection IDs across sequential requests

## Acceptance Criteria

- [ ] UI text for connection reuse indicates appropriate level of uncertainty
- [ ] The indicator does not present heuristic results as definitive facts
- [ ] Tooltip or help text explains what the indicator means (optional)
- [ ] All existing tests continue to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- File: `PostKit/PostKit/Views/RequestDetail/ResponseViewerPane.swift`
- [libcurl CURLINFO_CONN_ID documentation](https://curl.se/libcurl/c/CURLINFO_CONN_ID.html)
