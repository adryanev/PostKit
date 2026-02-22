---
status: complete
priority: p2
issue_id: "045"
tags: [architecture, consistency, code-review]
dependencies: []
---

# FormData Uses Inconsistent Separator

FormData uses `\n` separator but urlencoded uses `&`, creating internal inconsistency.

## Problem Statement

Form-data body content uses newline (`\n`) as separator while urlencoded uses `&`. This is inconsistent with both the actual `application/x-www-form-urlencoded` wire format and internal consistency.

**Why this matters:**
- Inconsistent internal format
- Reading/editing body shows different separators for similar data
- Round-trip import/export may have issues

## Findings

- **Location:** `PostmanImporter.swift:309, 320`
- **Comparison:**
```swift
// urlencoded (line 309)
httpRequest.bodyContent = pairs.joined(separator: "&")

// formdata (line 320)  
httpRequest.bodyContent = pairs.joined(separator: "\n")
```

**User experience issue:**
- urlencoded body shows: `key1=value1&key2=value2`
- formdata body shows: `key1=value1\nkey2=value2`
- Both are key-value pairs but displayed differently

## Proposed Solutions

### Option 1: Use `&` for Both (Recommended)

**Approach:** Standardize on `&` separator for both formats.

```swift
// Both use same separator
httpRequest.bodyContent = pairs.joined(separator: "&")
```

**Pros:**
- Internal consistency
- Matches standard format
- Simpler code

**Cons:**
- Loses distinction between formats
- May need bodyType to differentiate

**Effort:** 5 minutes

**Risk:** Low

---

### Option 2: Store as Structured Data

**Approach:** Store formData as JSON array for structure preservation.

```swift
// Store as [{"key": "k", "value": "v"}, ...]
```

**Pros:**
- Preserves structure
- No separator issues
- Supports file metadata

**Cons:**
- More complex
- Different from existing pattern

**Effort:** 2 hours

**Risk:** Medium

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Services/PostmanImporter.swift:320`

**Related issues:**
- #039 (FormData not sent)
- #043 (Newline injection)

Consider fixing all three together.

## Acceptance Criteria

- [ ] Consistent separator used
- [ ] Format documented
- [ ] Tests for both formats

## Work Log

### 2026-02-21 - Architecture Review Discovery

**By:** architecture-strategist agent

**Actions:**
- Identified format inconsistency
- Compared to urlencoded implementation
- Proposed standardization

**Learnings:**
- Internal consistency important for maintainability
- FormData vs urlencoded distinction may not need different storage
