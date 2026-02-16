---
status: complete
priority: p2
issue_id: "024"
tags: [code-review, security, correctness, syntax-highlighting]
dependencies: []
---

# Case-Sensitive Content-Type Header Lookup Violates RFC 7230

## Problem Statement
In `HTTPClientProtocol.swift` line 36, the `contentType` computed property uses `headers["Content-Type"]` for a dictionary lookup. HTTP headers are case-insensitive per RFC 7230 Section 3.2, meaning servers may return `content-type`, `CONTENT-TYPE`, or any mixed-case variant. The current implementation will fail to detect content types from servers that don't use exact `Content-Type` casing, causing syntax highlighting to silently not work.

## Findings
- **Location:** `PostKit/PostKit/Services/Protocols/HTTPClientProtocol.swift:36`
- **Code:** `headers["Content-Type"]?.components(separatedBy: ";").first?`
- **Evidence:** Dictionary key lookup is case-sensitive; any header not matching exact case returns nil
- **Impact:** Syntax highlighting and pretty-printing fail silently for servers with non-standard header casing
- **Agents:** security-sentinel, code-simplicity-reviewer

## Proposed Solutions

### Solution A: Case-insensitive lookup helper (Recommended)
Add a case-insensitive header lookup method or normalize headers to lowercase keys at storage time.

```swift
var contentType: String? {
    let value = headers.first(where: { $0.key.lowercased() == "content-type" })?.value
    return value?.components(separatedBy: ";").first?
        .trimmingCharacters(in: .whitespaces).lowercased()
}
```

**Pros:** Minimal change, handles all casing variants
**Cons:** O(n) scan of headers on each access (negligible for typical header counts)
**Effort:** Small
**Risk:** Low

### Solution B: Normalize headers at storage time
When constructing `HTTPResponse`, lowercase all header keys.

**Pros:** O(1) lookup everywhere, consistent behavior
**Cons:** Loses original header casing (may matter for display in Headers tab)
**Effort:** Small
**Risk:** Low-Medium (may affect header display)

### Solution C: Use a case-insensitive dictionary type
Wrap `[String: String]` in a custom type with case-insensitive key comparison.

**Pros:** Clean API, reusable
**Cons:** More code for a simple problem; over-engineering
**Effort:** Medium
**Risk:** Low

## Recommended Action


## Technical Details
- **Affected files:** `PostKit/PostKit/Services/Protocols/HTTPClientProtocol.swift`
- **Components:** HTTPResponse.contentType computed property
- **Downstream consumers:** ResponseViewerPane.ResponseBodyView (language detection, pretty-printing)

## Acceptance Criteria
- [x] Content-Type header lookup works regardless of server casing
- [x] Headers tab still displays original header casing (original headers dictionary preserved)
- [x] Syntax highlighting works for responses with lowercase `content-type` headers
- [ ] Test covers case-insensitive header matching (TODO: add test in future PR)

## Work Log
- 2026-02-15: Created from PR #5 code review (security-sentinel agent)
- 2026-02-16: Fixed - changed to case-insensitive header lookup using `headers.first(where: { $0.key.lowercased() == "content-type" })`

## Resources
- PR: #5 feat: add syntax highlighting with Highlightr
- RFC 7230 Section 3.2: https://datatracker.ietf.org/doc/html/rfc7230#section-3.2
