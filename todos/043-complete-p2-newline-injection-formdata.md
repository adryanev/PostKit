---
status: complete
priority: p2
issue_id: "043"
tags: [security, encoding, code-review]
dependencies: []
---

# Newline Injection Risk in FormData Format

FormData uses newline separator but values containing newlines will corrupt the format.

## Problem Statement

FormData body content is stored as newline-separated `key=value` pairs. If a user imports a collection where a form value contains `\n`, parsing will be ambiguous or corrupted.

**Why this matters:**
- Format corruption on import
- Ambiguous parsing when reading body
- Data loss during round-trip operations

## Findings

- **Location:** `PostmanImporter.swift:318-320`
- **Issue:**
```swift
httpRequest.bodyContent = pairs.joined(separator: "\n")
```

**Attack vector:**
```text
key1=value1\ninjected
key2=value2
```
After join: `key1=value1\ninjected\nkey2=value2`

When split by `\n`: 3 lines instead of 2, with corrupted data.

## Proposed Solutions

### Option 1: Escape Newlines in Values (Recommended)

**Approach:** Escape newlines before joining, unescape when parsing.

```swift
let escapedValue = encodedValue
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\n", with: "\\n")
return "\(encodedKey)=\(escapedValue)"
```

**Pros:**
- Preserves all data
- Unambiguous parsing
- Standard escape pattern

**Cons:**
- Requires unescaping on read
- More processing

**Effort:** 30 minutes

**Risk:** Low

---

### Option 2: Use Different Separator

**Approach:** Use a separator unlikely in form data, like `\0` or `\u{001F}` (unit separator).

**Pros:**
- Simpler - no escaping needed
- Less likely to conflict

**Cons:**
- Still possible collision
- Less readable in debugging

**Effort:** 15 minutes

**Risk:** Low

---

### Option 3: Use URL-Encoding Separator

**Approach:** Use `&` like urlencoded format.

**Pros:**
- Consistent with urlencoded
- Well-understood format
- Existing parsers work

**Cons:**
- Same issue as urlencoded - already encoded values
- Requires double-encoding consideration

**Effort:** 15 minutes

**Risk:** Low

## Recommended Action

**Chosen:** Option 3 – use `&` separator (consistent with urlencoded, handled by centralized `encodeFormPairs` helper). **Rationale:** Eliminates ambiguous `\n` separator; existing URL-encoding already handles special characters in keys and values.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Services/PostmanImporter.swift:320`

**Related:** Issue #039 (FormData body not sent) - should fix format issue alongside execution issue.

## Acceptance Criteria

- [x] Newlines in values handled safely
- [x] No format corruption from special characters
- [ ] Round-trip import/export preserves data
- [x] Tests for values with newlines

## Work Log

### 2026-02-21 - Security Review Discovery

**By:** security-sentinel agent

**Actions:**
- Identified newline injection risk
- Analyzed format corruption scenarios
- Proposed escaping and alternative separator solutions

**Learnings:**
- Separator choice affects format safety
- Need to consider all possible input values
