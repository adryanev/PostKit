---
status: complete
priority: p3
issue_id: "046"
tags: [simplicity, refactoring, code-review]
dependencies: []
---

# Duplicate Form Encoding Logic

urlencoded and formdata cases have identical encoding logic with different separators.

## Problem Statement

The `PostmanImporter.swift` has duplicate encoding logic in both `urlencoded` and `formdata` cases. The only difference is the separator (`&` vs `\n`).

**Why this matters:**
- Code duplication
- Maintenance burden
- Bug fixes needed in two places

## Findings

- **Location:** `PostmanImporter.swift:300-321`
- **Duplication:**
```swift
// urlencoded (lines 303-309)
let pairs = encoded.compactMap { kv -> String? in
    guard !kv.key.isEmpty else { return nil }
    let encodedKey = kv.key.addingPercentEncoding(...) ?? kv.key
    let encodedValue = (kv.value ?? "").addingPercentEncoding(...) ?? (kv.value ?? "")
    return "\(encodedKey)=\(encodedValue)"
}
httpRequest.bodyContent = pairs.joined(separator: "&")

// formdata (lines 314-320) - identical except separator
let pairs = formData.compactMap { item -> String? in
    guard !item.key.isEmpty else { return nil }
    let encodedKey = item.key.addingPercentEncoding(...) ?? item.key
    let encodedValue = (item.value ?? "").addingPercentEncoding(...) ?? (item.value ?? "")
    return "\(encodedKey)=\(encodedValue)"
}
httpRequest.bodyContent = pairs.joined(separator: "\n")
```

## Proposed Solutions

### Option 1: Extract Common Method (Recommended)

**Approach:** Create shared encoding method.

```swift
private func encodeFormPairs(_ pairs: [(key: String, value: String?)], separator: String) -> String? {
    let encoded = pairs.compactMap { item -> String? in
        guard !item.key.isEmpty else { return nil }
        guard let encodedKey = item.key.addingPercentEncoding(withAllowedCharacters: Self.formURLEncodedAllowed),
              let encodedValue = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: Self.formURLEncodedAllowed) else {
            return nil
        }
        return "\(encodedKey)=\(encodedValue)"
    }
    return encoded.isEmpty ? nil : encoded.joined(separator: separator)
}
```

**Pros:**
- Single source of truth
- Easier maintenance
- ~8 LOC saved

**Cons:**
- Need to adapt PostmanKeyValue and PostmanFormData types

**Effort:** 30 minutes

**Risk:** Low

## Recommended Action

To be filled during triage.

## Technical Details

**Affected files:**
- `PostKit/PostKit/Services/PostmanImporter.swift:300-321`

**Types to unify:**
- `PostmanKeyValue` - has `key`, `value`, `enabled`
- `PostmanFormData` - has `key`, `value`, `type`, `src`

## Acceptance Criteria

- [ ] Single encoding method
- [ ] Both cases use shared method
- [ ] Tests pass

## Work Log

### 2026-02-21 - Code Simplicity Review

**By:** code-simplicity-reviewer agent

**Actions:**
- Identified duplicate code pattern
- Analyzed differences between cases
- Proposed extraction

**Learnings:**
- Similar code often indicates missing abstraction
- Separator parameter can unify nearly identical code
