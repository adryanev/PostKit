---
status: pending
priority: p1
issue_id: "002"
tags: [code-review, memory, performance]
dependencies: ["001"]
---

# activeContexts Dictionary Never Cleaned on Success Path

## Problem Statement
In `CurlHTTPClient.swift`, the `activeContexts` dictionary stores `CurlTransferContext` objects keyed by `UUID` task IDs (line 169: `activeContexts[taskID] = context`). The dictionary is only cleaned in the `cancel()` method (line 240), but never on the success or error completion path. This means every successful request permanently grows the dictionary, leaking both the UUID keys and context values.

## Findings
- **Location:** `PostKit/PostKit/Services/CurlHTTPClient.swift:169` (insert) and `240` (only removal)
- **Evidence:** `cancel(taskID:)` at line 236-241 is the only place `activeContexts.removeValue(forKey:)` is called. The success path (lines 220-222) and error path (lines 214-218) never remove the entry.
- **Impact:** Unbounded dictionary growth; combined with Finding 001, doubly retains context objects
- **Agents:** performance-oracle, architecture-strategist flagged this

## Proposed Solutions

### Solution A: Add cleanup in continuation handler (Recommended)
Add `self.activeContexts.removeValue(forKey: taskID)` in the `didResume` block after the continuation is resumed (both success and error paths), using a `defer` block.

**Pros:** Clean, catches all paths
**Cons:** Requires accessing actor-isolated state from nonisolated context — need to restructure
**Effort:** Small
**Risk:** Low

### Solution B: Clean up in withTaskCancellationHandler's body after continuation
After `withCheckedThrowingContinuation` returns (line 228), add cleanup. This runs on the actor since `execute` is an actor method.

**Pros:** Runs in actor isolation naturally
**Cons:** None significant
**Effort:** Small
**Risk:** Low

## Recommended Action
<!-- Fill during triage -->

## Technical Details
- **Affected Files:** `PostKit/PostKit/Services/CurlHTTPClient.swift`
- **Components:** CurlHTTPClient actor

## Acceptance Criteria
- [ ] `activeContexts` count returns to 0 after all requests complete
- [ ] Dictionary is cleaned on success, error, and cancellation paths
- [ ] No retain cycles between dictionary and context objects

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-14 | Created from code review of PR #2 | Related to memory leak in Finding 001 |

## Resources
- PR: https://github.com/adryanev/PostKit/pull/2
