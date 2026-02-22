---
status: complete
priority: p1
issue_id: "041"
tags: [security, encoding, input-validation, code-review]
dependencies: []
---

# Unsafe Fallback to Raw Unencoded Input in Percent Encoding

If addingPercentEncoding fails, code falls back to raw input, defeating the purpose of encoding.

## Problem Statement

In `PostmanImporter.swift`, when `addingPercentEncoding` returns nil, the code falls back to the **raw, unencoded input**. This defeats the entire purpose of encoding and could allow malicious input.

**Why this matters:**
- Malicious input with special characters could corrupt body format
- Characters like `=`, `&`, `+`, newlines, null bytes not escaped
- Injection risk for form body parsing

## Findings

- **Location:** `PostmanImporter.swift:305-306, 316-317`
- **Issue pattern:**
```swift
let encodedKey = kv.key.addingPercentEncoding(...) ?? kv.key  // ❌ Fallback to raw!
let encodedValue = (kv.value ?? "").addingPercentEncoding(...) ?? (kv.value ?? "")  // ❌
```

**Why `addingPercentEncoding` can fail:**
- String contains invalid UTF-8 sequences
- String has malformed Unicode
- Extremely long strings

**Characters that could cause issues if not encoded:**
- `=` - key/value delimiter
- `&` - pair delimiter  
- `\n` - stored format separator
- `\0` - null byte injection

## Proposed Solutions

### Option 1: Guard and Skip Invalid Entries (Recommended)

**Approach:** Skip entries that can't be encoded, log warning.

```swift
guard let encodedKey = item.key.addingPercentEncoding(withAllowedCharacters: Self.formURLEncodedAllowed),
      let encodedValue = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: Self.formURLEncodedAllowed) else {
    print("[PostmanImporter] Warning: Skipping malformed form field: \(item.key)")
    return nil
}
return "\(encodedKey)=\(encodedValue)"
```

**Pros:**
- Safe - no unencoded data
- Clear logging for debugging
- Graceful degradation

**Cons:**
- Some form fields may be silently skipped
- User may not notice missing data

**Effort:** 15 minutes

**Risk:** Low

---

### Option 2: Throw Error on Encoding Failure

**Approach:** Fail the entire import if any field can't be encoded.

**Pros:**
- User aware of problem immediately
- No silent data loss

**Cons:**
- Import fails entirely
- May be overly strict

**Effort:** 15 minutes

**Risk:** Low

---

### Option 3: Percent Encode All Non-ASCII

**Approach:** Use custom encoding that always succeeds.

**Pros:**
- Never fails
- All data preserved

**Cons:**
- More complex
- May over-encode

**Effort:** 1 hour

**Risk:** Medium

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Services/PostmanImporter.swift:305-306`
- `PostKit/PostKit/Services/PostmanImporter.swift:316-317`

**Both locations:**
1. urlencoded case (lines 303-309)
2. formdata case (lines 314-320)

## Acceptance Criteria

- [ ] No fallback to raw unencoded input
- [ ] Invalid entries either skipped or throw error
- [ ] Logging for skipped entries
- [ ] Tests for edge cases (invalid UTF-8, special chars)

## Work Log

### 2026-02-21 - Security Review Discovery

**By:** security-sentinel agent

**Actions:**
- Identified unsafe fallback pattern
- Analyzed what could go wrong
- Proposed safer alternatives

**Learnings:**
- `?? rawInput` pattern is dangerous in encoding contexts
- Better to skip/fail than to include unsafe data
