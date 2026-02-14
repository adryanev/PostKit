---
status: pending
priority: p1
issue_id: "001"
tags: [code-review, security, memory]
dependencies: []
---

# Memory Leak: Unmanaged.passRetained Without Matching Release

## Problem Statement
In `CurlHTTPClient.swift` line 313, `Unmanaged.passRetained(context).toOpaque()` increments the reference count of `CurlTransferContext` but there is no corresponding `takeRetainedValue()` call to decrement it. This means every HTTP request permanently leaks the context object (including any response data it holds). Over time, this will exhaust app memory.

The implementation plan (`docs/plans/2026-02-14-feat-factory-dependency-injection-plan.md`) explicitly noted that `takeRetainedValue()` should be called after `curl_easy_perform`, confirming this was a planned step that was missed.

## Findings
- **Location:** `PostKit/PostKit/Services/CurlHTTPClient.swift:313`
- **Code:** `let contextPtr = Unmanaged.passRetained(context).toOpaque()`
- **Evidence:** No call to `Unmanaged<CurlTransferContext>.fromOpaque(...).takeRetainedValue()` anywhere in the file after `curl_easy_perform` completes
- **Impact:** Every request leaks a `CurlTransferContext` object (64KB+ initial allocation plus response data)
- **Agents:** security-sentinel, architecture-strategist, code-simplicity-reviewer all flagged this

## Proposed Solutions

### Solution A: Add takeRetainedValue after perform (Recommended)
After `curl_easy_perform(handle)` returns and before the continuation resumes, call `Unmanaged<CurlTransferContext>.fromOpaque(contextPtr).takeRetainedValue()` to balance the retain.

**Pros:** Minimal change, directly fixes the leak
**Cons:** Must ensure the pointer isn't used after release
**Effort:** Small
**Risk:** Low

### Solution B: Use passUnretained instead
Change line 313 to `Unmanaged.passUnretained(context).toOpaque()` since the `context` local variable already holds a strong reference for the duration of the closure.

**Pros:** No manual release needed, simpler
**Cons:** If the closure's reference is released early, use-after-free crash; requires careful lifetime analysis
**Effort:** Small
**Risk:** Medium (lifetime must be guaranteed)

## Recommended Action
<!-- Fill during triage -->

## Technical Details
- **Affected Files:** `PostKit/PostKit/Services/CurlHTTPClient.swift`
- **Components:** CurlHTTPClient actor, CurlTransferContext
- **Related:** Finding 002 (activeContexts cleanup)

## Acceptance Criteria
- [ ] Every `passRetained` has a matching `takeRetainedValue`
- [ ] Memory usage remains stable across 100+ sequential requests (verify with Instruments)
- [ ] No use-after-free crashes in stress testing

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-14 | Created from code review of PR #2 | Plan doc explicitly mentioned this step was needed |

## Resources
- PR: https://github.com/adryanev/PostKit/pull/2
- Apple docs: [Unmanaged](https://developer.apple.com/documentation/swift/unmanaged)
