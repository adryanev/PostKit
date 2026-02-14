---
status: pending
priority: p3
issue_id: "016"
tags: [code-review, simplicity, cleanup]
dependencies: []
---

# 016: Unused C Shim Functions

## Problem Statement

The C shim layer (`CurlShims.c` and `CurlShims.h`) declares and defines `curl_easy_getinfo_string` and `curl_easy_getinfo_int64` functions that are never called from Swift code. These unused functions represent a YAGNI (You Aren't Gonna Need It) violation, adding maintenance burden and dead code to the codebase.

## Findings

- **File:** `CurlShims.c` and `CurlShims.h`
- **Severity:** P3 (Nice-to-have)
- **Category:** Code simplicity, cleanup

The shim functions `curl_easy_getinfo_string` and `curl_easy_getinfo_int64` are defined in the C shim layer but have no corresponding call from any Swift source file. They add to compile time, binary size (marginally), and cognitive load when reading the shim layer. Dead code should be removed to keep the codebase clean and maintainable.

## Proposed Solutions

### Option A: Remove unused functions (Recommended)

Delete the declarations from `CurlShims.h` and the definitions from `CurlShims.c`.

**Pros:**
- Eliminates dead code
- Reduces maintenance surface area
- Follows YAGNI principle
- Cleaner shim layer that only contains what is actually needed

**Cons:**
- If these functions are needed later, they must be re-added (trivial)

**Effort:** Very low (15-30 minutes)
**Risk:** Very low -- removing unused code with no callers

### Option B: Keep for future use with comment

Add a comment explaining these are reserved for future use.

**Pros:**
- Functions are ready if needed later
- No risk of needing to re-implement

**Cons:**
- Keeps dead code in the codebase
- Comments explaining "future use" tend to become stale
- Violates YAGNI principle

**Effort:** Very low (5 minutes)
**Risk:** None

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Files involved:
- `CurlShims.h` -- function declarations
- `CurlShims.c` -- function definitions

Functions to evaluate for removal:
```c
// In CurlShims.h
CURLcode curl_easy_getinfo_string(CURL *handle, CURLINFO info, char **value);
CURLcode curl_easy_getinfo_int64(CURL *handle, CURLINFO info, int64_t *value);

// In CurlShims.c
CURLcode curl_easy_getinfo_string(CURL *handle, CURLINFO info, char **value) {
    return curl_easy_getinfo(handle, info, value);
}

CURLcode curl_easy_getinfo_int64(CURL *handle, CURLINFO info, int64_t *value) {
    return curl_easy_getinfo(handle, info, value);
}
```

Verification: grep the entire Swift codebase for references to these function names to confirm they are truly unused before removal.

## Acceptance Criteria

- [ ] Verify no Swift code calls `curl_easy_getinfo_string` or `curl_easy_getinfo_int64`
- [ ] Remove unused function declarations from `CurlShims.h`
- [ ] Remove unused function definitions from `CurlShims.c`
- [ ] Only actively used shim functions remain in the files
- [ ] Project builds successfully after removal
- [ ] All existing tests continue to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- File: `PostKit/PostKit/Services/CurlShims.c`
- File: `PostKit/PostKit/Services/CurlShims.h`
