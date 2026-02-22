---
status: complete
priority: p2
issue_id: "044"
tags: [reliability, error-handling, code-review]
dependencies: []
---

# Silent Save Failure in MenuBarView

modelContext.save() errors are silently swallowed, history entries could be lost.

## Problem Statement

The code uses `try? modelContext.save()` which silently swallows any save errors. History entries could be lost without any indication to the user.

**Why this matters:**
- Users lose history without knowing
- No debugging capability for save failures
- Data integrity issue

## Findings

- **Location:** `MenuBarView.swift:114`
- **Issue:**
```swift
try? modelContext.save()  // Error silently ignored
```

**What could cause save failures:**
- Validation errors
- Disk full
- Model context in bad state
- Concurrent modification

## Proposed Solutions

### Option 1: Log Error (Recommended)

**Approach:** Log the error for debugging, continue gracefully.

```swift
do {
    try modelContext.save()
} catch {
    print("[MenuBar] Failed to save history: \(error)")
    // Optionally: Analytics.log(error)
}
```

**Pros:**
- Error visible in logs
- Easy debugging
- Graceful degradation

**Cons:**
- Still no user notification

**Effort:** 5 minutes

**Risk:** Low

---

### Option 2: Show Error Indicator

**Approach:** Add error state and show indicator in menu bar.

**Pros:**
- User aware of issue
- Better UX

**Cons:**
- More code
- May be overkill for rare case

**Effort:** 30 minutes

**Risk:** Low

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Views/MenuBar/MenuBarView.swift:114`

**Pattern to follow:** Same as other save operations in app.

## Acceptance Criteria

- [ ] Save errors logged
- [ ] Debugging capability for failed saves
- [ ] Tests for save failure handling

## Work Log

### 2026-02-21 - Security Review Discovery

**By:** security-sentinel agent

**Actions:**
- Identified silent failure pattern
- Analyzed impact on user data
- Proposed logging solution

**Learnings:**
- `try?` hides valuable debugging info
- Even non-critical saves should have error visibility
