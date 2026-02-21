---
status: complete
priority: p3
issue_id: "047"
tags: [i18n, edge-case, code-review]
dependencies: []
---

# Unicode Normalization Collision Risk

Using `.lowercased()` for case-insensitive matching can cause unexpected collisions.

## Problem Statement

The `OpenAPIDiffEngine` uses `.lowercased()` for case-insensitive ID matching. Different Unicode strings could produce the same lowercase result, causing incorrect endpoint matching.

**Why this matters:**
- Potential incorrect matches
- Turkish "I" vs "İ" problem
- Diacritic handling inconsistencies

## Findings

- **Location:** `OpenAPIDiffEngine.swift:51, 54`
- **Issue:**
```swift
var unmatchedSnapshots = Dictionary(uniqueKeysWithValues: 
    existingSnapshots.map { ($0.id.lowercased(), $0) })

let matchKey = "\(endpoint.method.rawValue) \(endpoint.path)".lowercased()
```

**Example collisions:**
- Turkish: `"I".lowercased()` → `"i"` (en_US) but different in tr_TR
- Diacritics: `"café"` vs `"cafe\u{301}"` may or may not match

## Proposed Solutions

### Option 1: Use Locale-Aware Folding (Recommended)

**Approach:** Use `folding(options:locale:)` for proper normalization.

```swift
let normalizedID = id.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
```

**Pros:**
- Handles more edge cases
- Locale-aware
- Includes diacritics

**Cons:**
- Slightly more complex
- Locale-dependent behavior

**Effort:** 15 minutes

**Risk:** Low

---

### Option 2: Use Fixed Locale (en_US)

**Approach:** Always use English locale for consistency.

```swift
let normalizedID = id.lowercased(with: Locale(identifier: "en_US"))
```

**Pros:**
- Consistent behavior
- Simple

**Cons:**
- May not match user's expectations in other locales

**Effort:** 10 minutes

**Risk:** Low

## Recommended Action

To be filled during triage. This is low priority as endpoint paths typically use ASCII.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Services/OpenAPIDiffEngine.swift:51`
- `PostKit/PostKit/Services/OpenAPIDiffEngine.swift:54`

## Acceptance Criteria

- [ ] Case normalization uses proper Unicode handling
- [ ] Consistent behavior across locales
- [ ] Tests for edge cases

## Work Log

### 2026-02-21 - Security Review Discovery

**By:** security-sentinel agent

**Actions:**
- Identified Unicode collision risk
- Researched Swift string folding options
- Proposed locale-aware solution

**Learnings:**
- `.lowercased()` without locale is problematic for i18n
- `folding(options:)` provides better control
