---
status: pending
priority: p3
issue_id: "021"
tags: [code-review, performance, memory]
dependencies: []
---

# 021: getBodyData() Full Memory Load

## Problem Statement

The `getBodyData()` method on `HTTPResponse` reads file-backed response bodies entirely into memory using `Data(contentsOf:)`. This defeats the purpose of the memory-aware response design in `URLSessionHTTPClient` / `CurlHTTPClient`, which deliberately spills responses larger than 1MB (`maxMemorySize`) to disk to avoid memory pressure. When `getBodyData()` is called on these large responses, the entire file is loaded into a contiguous `Data` buffer, negating the memory savings.

## Findings

- **File:** `HTTPClientProtocol.swift` (`HTTPResponse.getBodyData()`)
- **Severity:** P3 (Nice-to-have)
- **Category:** Performance, memory

The HTTP client architecture carefully avoids loading large responses into memory:
- Responses > 1MB are written to a temporary file on disk
- `HTTPResponse` stores a `bodyFileURL` instead of `bodyData`
- This design prevents memory spikes for large API responses

However, `getBodyData()` undoes this by calling `Data(contentsOf: url)`, which reads the entire file into a contiguous memory allocation. For a 50MB response, this allocates 50MB of RAM in a single block.

Using `Data(contentsOf:options:.mappedIfSafe)` instead would memory-map the file, allowing the OS to page data in and out as needed without requiring the entire file to be resident in RAM simultaneously.

## Proposed Solutions

### Option A: Use .mappedIfSafe option (Recommended)

Change `Data(contentsOf: url)` to `Data(contentsOf: url, options: .mappedIfSafe)`.

**Pros:**
- One-line change
- Memory-maps the file instead of loading it entirely
- OS manages paging -- only accessed portions are loaded into RAM
- Preserves the memory-aware architecture's intent
- Transparent to consumers of the API (same `Data` type returned)

**Cons:**
- Memory-mapped data becomes invalid if the file is deleted while mapped (mitigated by `.mappedIfSafe` falling back to full read if unsafe)
- Slightly different performance characteristics for sequential reads (negligible in practice)

**Effort:** Very low (15 minutes)
**Risk:** Very low -- `.mappedIfSafe` gracefully falls back to full read if mapping is not possible

### Option B: Add streaming API

Introduce a new `getBodyStream() -> InputStream?` method that returns a stream for file-backed responses, allowing consumers to process data incrementally.

**Pros:**
- True streaming with minimal memory footprint
- Most memory-efficient approach for very large responses
- Enables future features like streaming JSON parsing

**Cons:**
- Significant API change -- all consumers need to handle streams
- More complex implementation
- Not all consumers can work with streams (e.g., JSON pretty-printing needs full data)
- Requires careful lifecycle management of the stream

**Effort:** High (4-8 hours)
**Risk:** Medium -- API change with broad impact on consumers

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Current implementation:
```swift
// HTTPClientProtocol.swift
struct HTTPResponse {
    var bodyData: Data?
    var bodyFileURL: URL?

    func getBodyData() -> Data? {
        if let bodyData {
            return bodyData
        }
        if let bodyFileURL {
            return try? Data(contentsOf: bodyFileURL)  // Full memory load
        }
        return nil
    }
}
```

Proposed change (Option A):
```swift
func getBodyData() -> Data? {
    if let bodyData {
        return bodyData
    }
    if let bodyFileURL {
        return try? Data(contentsOf: bodyFileURL, options: .mappedIfSafe)  // Memory-mapped
    }
    return nil
}
```

How `.mappedIfSafe` works:
- The kernel maps the file's pages into the process's virtual address space
- Pages are loaded on demand (lazy loading) as they are accessed
- Pages can be evicted under memory pressure and re-loaded from the file
- If the file cannot be safely mapped (e.g., on a network volume), `Data` falls back to a full read automatically

## Acceptance Criteria

- [ ] `getBodyData()` uses `Data(contentsOf:options:.mappedIfSafe)` for file-backed responses
- [ ] Large file-backed responses do not cause full memory allocation
- [ ] Behavior is identical for in-memory responses (no change to `bodyData` path)
- [ ] Fallback behavior works correctly if memory mapping is not possible
- [ ] All existing tests continue to pass
- [ ] No functional behavior change for consumers of `getBodyData()`

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- File: `PostKit/PostKit/Services/Protocols/HTTPClientProtocol.swift`
- [Apple: Data.ReadingOptions.mappedIfSafe](https://developer.apple.com/documentation/foundation/data/readingoptions/mappedifsafe)
- [Virtual Memory and Memory Mapping](https://developer.apple.com/documentation/kernel/mmap)
