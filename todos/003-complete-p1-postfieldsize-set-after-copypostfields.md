---
status: pending
priority: p1
issue_id: "003"
tags: [code-review, correctness, bug]
dependencies: []
---

# CURLOPT_POSTFIELDSIZE_LARGE Set After CURLOPT_COPYPOSTFIELDS — Body Truncation

## Problem Statement
In `CurlHTTPClient.swift` lines 304-310, `CURLOPT_COPYPOSTFIELDS` is set before `CURLOPT_POSTFIELDSIZE_LARGE`. According to libcurl documentation, `CURLOPT_COPYPOSTFIELDS` copies the data at the time it's set, using `strlen()` to determine the length if `POSTFIELDSIZE` hasn't been set yet. This means any request body containing null bytes (`\0`) will be silently truncated at the first null byte, since `strlen` stops at `\0`.

## Findings
- **Location:** `PostKit/PostKit/Services/CurlHTTPClient.swift:304-310`
- **Code:**
  ```swift
  curl_easy_setopt_pointer(handle, CURLOPT_COPYPOSTFIELDS, ...) // line 307
  curl_easy_setopt_int64(handle, CURLOPT_POSTFIELDSIZE_LARGE, Int(body.count)) // line 310
  ```
- **Evidence:** libcurl docs state: "If you want to send zero bytes, set CURLOPT_POSTFIELDSIZE to zero before this option."
- **Impact:** Binary request bodies (e.g., protobuf, msgpack) or JSON with escaped nulls will be truncated
- **Agents:** security-sentinel, performance-oracle flagged this

## Proposed Solutions

### Solution A: Swap the order (Recommended)
Move `CURLOPT_POSTFIELDSIZE_LARGE` before `CURLOPT_COPYPOSTFIELDS` so libcurl knows the exact size before copying.

**Pros:** One-line fix, correct per libcurl docs
**Cons:** None
**Effort:** Small
**Risk:** Low

### Solution B: Use CURLOPT_POSTFIELDS with manual lifetime
Use `CURLOPT_POSTFIELDS` (no copy) and manage the data lifetime manually until `curl_easy_perform` returns.

**Pros:** Avoids an extra copy of the body data
**Cons:** More complex lifetime management
**Effort:** Medium
**Risk:** Medium

## Recommended Action
<!-- Fill during triage -->

## Technical Details
- **Affected Files:** `PostKit/PostKit/Services/CurlHTTPClient.swift`
- **Components:** `setupHandle` method, request body handling

## Acceptance Criteria
- [ ] `CURLOPT_POSTFIELDSIZE_LARGE` is set before `CURLOPT_COPYPOSTFIELDS`
- [ ] Binary request bodies with null bytes are sent correctly
- [ ] Add a test verifying body data integrity for payloads containing `\0`

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-14 | Created from code review of PR #2 | libcurl order-dependent options are a common footgun |

## Resources
- PR: https://github.com/adryanev/PostKit/pull/2
- libcurl docs: https://curl.se/libcurl/c/CURLOPT_COPYPOSTFIELDS.html
