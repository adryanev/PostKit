---
status: pending
priority: p2
issue_id: "010"
tags: [code-review, consistency, resource-leak]
dependencies: []
---

# 010: Temp File Naming Inconsistency Between Clients

## Problem Statement

`CurlHTTPClient` names temporary response files `postkit-response-{UUID}.tmp`, while `URLSessionHTTPClient` uses bare UUID names (no prefix, no extension). The cleanup function in `PostKitApp.swift` only matches the `postkit-response-*.tmp` pattern, meaning temp files created by `URLSessionHTTPClient` are never cleaned up on app launch. This creates a silent resource leak when using the URLSession-based client.

## Findings

- **File:** `CurlHTTPClient.swift:88` -- uses `"postkit-response-\(UUID().uuidString).tmp"`
- **File:** `HTTPClient.swift` (URLSessionHTTPClient) -- uses bare UUID filename
- **File:** `PostKitApp.swift` -- cleanup function matches `postkit-response-*.tmp` pattern
- The two HTTP client implementations create temp files with different naming conventions.
- The cleanup logic in `PostKitApp.swift` was written (or updated) to match the `CurlHTTPClient` pattern only.
- If the app is configured to use `URLSessionHTTPClient` (e.g., as a fallback or during testing), orphan temp files accumulate indefinitely.
- Even if `CurlHTTPClient` is the primary client, the inconsistency is a maintenance hazard.

## Proposed Solutions

### Option A: Unify Naming Convention Across Both Clients (Recommended)

Standardize on the `postkit-response-{UUID}.tmp` naming convention in both clients:

```swift
// In both CurlHTTPClient and URLSessionHTTPClient:
let tempFileName = "postkit-response-\(UUID().uuidString).tmp"
let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempFileName)
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Single naming convention; existing cleanup logic works for both clients; clear file provenance (the `postkit-response-` prefix identifies PostKit files in the temp directory) |
| **Cons** | Requires changing URLSessionHTTPClient |
| **Effort** | Low |
| **Risk** | Very low -- only changes the temp file name, no behavioral impact |

### Option B: Update Cleanup to Handle Both Patterns

Modify the cleanup function in `PostKitApp.swift` to match both naming patterns:

```swift
// Match both patterns
let isPostKitTemp = fileName.hasPrefix("postkit-response-") || isUUID(fileName)
```

| Aspect | Detail |
|--------|--------|
| **Pros** | No change to either HTTP client; backward compatible |
| **Cons** | More complex cleanup logic; UUID-only pattern could match non-PostKit files; does not fix the underlying inconsistency |
| **Effort** | Low |
| **Risk** | Medium -- bare UUID matching could accidentally delete unrelated temp files |

### Option C: Extract Temp File Creation to a Shared Utility

Create a shared function in a utility module:

```swift
enum TempFileNaming {
    static func responseFile() -> URL {
        let name = "postkit-response-\(UUID().uuidString).tmp"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Single source of truth; both clients call the same function; easy to change the pattern later |
| **Cons** | Introduces a new utility type (though minimal) |
| **Effort** | Low |
| **Risk** | Very low |

## Recommended Action

_To be filled in after team review._

## Technical Details

- The system temp directory (`FileManager.default.temporaryDirectory`) is shared across all apps, so having a recognizable prefix (`postkit-response-`) helps identify PostKit's files.
- macOS periodically cleans the temp directory, but the interval is unpredictable and should not be relied upon.
- The cleanup function in `PostKitApp.swift` runs on app launch and iterates through the temp directory looking for matching files.
- `URLSessionHTTPClient` uses `downloadTask`, which places the response in a system-managed temp file. The client then moves it to its own temp location if the response exceeds `maxMemorySize`.
- The `.tmp` extension is conventional and helps identify temporary files during debugging.

## Acceptance Criteria

- [ ] Both `CurlHTTPClient` and `URLSessionHTTPClient` use the same temp file naming convention.
- [ ] The cleanup function in `PostKitApp.swift` correctly matches and removes temp files from both clients.
- [ ] No orphan temp files remain after app restart, regardless of which HTTP client was used.
- [ ] The temp file naming convention is documented or centralized in a shared utility.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [FileManager.temporaryDirectory](https://developer.apple.com/documentation/foundation/filemanager/1642996-temporarydirectory)
