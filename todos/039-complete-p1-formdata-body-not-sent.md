---
status: complete
priority: p1
issue_id: "039"
tags: [security, bug, http, code-review]
dependencies: []
---

# FormData Body Type Not Sent in HTTP Requests

RequestBuilder silently skips .formData bodyType, causing requests with form data to be sent with empty bodies.

## Problem Statement

When `bodyType == .formData`, the `RequestBuilder` simply breaks without setting `httpBody`. The PostmanImporter stores formData as newline-separated `key=value` pairs in `bodyContent`, but this content is **never sent** in the actual HTTP request.

**Why this matters:**
- Requests with form data are sent with empty bodies
- API authentication failures (missing required form fields)
- Silent data loss - users expect their data to be transmitted
- Functional bug affecting core use case

## Findings

- **Location:** `RequestBuilder.swift:77-79`
- **Root cause:** 
```swift
case .formData, .none:
    break  // Does nothing - body never set
```
- **Impact:** All imported Postman collections with form-data are broken

**Data flow issue:**
1. PostmanImporter encodes formdata to `bodyContent` as `key=value\nkey2=value2`
2. RequestBuilder sees `bodyType == .formData`
3. RequestBuilder does `break` - no `httpBody` is set
4. HTTP request sent with empty body

## Proposed Solutions

### Option 1: Convert FormData to URL-Encoded (Recommended)

**Approach:** Treat formData the same as urlEncoded since the encoding is identical.

```swift
case .urlEncoded, .formData:
    if !interpolatedBody.isEmpty {
        request.httpBody = interpolatedBody
            .replacingOccurrences(of: "\n", with: "&")
            .data(using: .utf8)
    }
```

**Pros:**
- Minimal code change
- Immediate fix
- Works for simple key-value forms

**Cons:**
- Doesn't support file uploads
- Content-Type header may not match

**Effort:** 30 minutes

**Risk:** Low

---

### Option 2: Implement Full Multipart/Form-Data

**Approach:** Build proper multipart/form-data with boundary.

**Pros:**
- Correct implementation
- Supports file uploads
- Matches Postman behavior

**Cons:**
- More complex
- Requires boundary generation
- More testing needed

**Effort:** 4-6 hours

**Risk:** Medium

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Services/RequestBuilder.swift:77-79`
- Related: `PostKit/PostKit/Services/PostmanImporter.swift:311-321`

**Current storage format:**
```
key1=value1
key2=value2
```

**Required HTTP body format:**
- `application/x-www-form-urlencoded`: `key1=value1&key2=value2`
- `multipart/form-data`: With boundary delimiters

## Acceptance Criteria

- [ ] FormData requests include body in HTTP request
- [ ] Form values properly transmitted to server
- [ ] Tests for formData body type execution
- [ ] Content-Type header set correctly

## Work Log

### 2026-02-21 - Security Review Discovery

**By:** security-sentinel agent

**Actions:**
- Identified RequestBuilder gap during security review
- Traced data flow from import to execution
- Confirmed body is never set for formData

**Learnings:**
- Critical to trace full data path, not just import
- Test coverage gap - no integration tests for formdata execution
