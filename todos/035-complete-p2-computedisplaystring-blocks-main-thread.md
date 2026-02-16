---
status: pending
priority: p2
issue_id: "035"
tags: [code-review, performance, syntax-highlighting]
dependencies: []
---

# computeDisplayString Blocks Main Thread for Large JSON

## Problem Statement
In `ResponseViewerPane.swift` lines 139-150, `loadBodyData()` calls `computeDisplayString()` which performs `JSONSerialization.jsonObject` + `JSONSerialization.data(withJSONObject:options:.prettyPrinted)` synchronously. The `.task` modifier runs on the main actor by default since `ResponseBodyView` is a SwiftUI `View`. For a 512KB JSON payload (the `prettyPrintThreshold`), this can take 50-150ms, causing a perceivable frame drop.

## Findings
- **Location:** `PostKit/PostKit/Views/RequestDetail/ResponseViewer/ResponseViewerPane.swift:139-150, 157-169`
- **Code:** `cachedDisplayString = computeDisplayString(for: data, showRaw: showRaw)` called from `loadBodyData()` in `.task` context
- **Evidence:** `.task` runs on the main actor; JSONSerialization is synchronous
- **Impact:** UI freeze of 50-150ms when displaying large JSON responses
- **Agents:** performance-oracle

## Proposed Solutions

### Solution A: Dispatch heavy work off main thread (Recommended)
```swift
private func loadBodyData() async {
    do {
        let data = try response.getBodyData()
        let language = languageForContentType(response.contentType)
        let raw = showRaw
        let json = isJSON
        let threshold = prettyPrintThreshold
        let maxSize = maxDisplaySize

        let displayString = await Task.detached(priority: .userInitiated) {
            // computeDisplayString logic here
        }.value

        bodyData = data
        detectedLanguage = language
        cachedDisplayString = displayString
    } catch {
        loadError = error.localizedDescription
    }
}
```

**Pros:** Keeps main thread responsive; straightforward change
**Cons:** Need to capture all values before dispatching (no self access in detached task)
**Effort:** Small
**Risk:** Low

### Solution B: Use nonisolated method
Mark `computeDisplayString` as `nonisolated` to allow it to run off the main actor.

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [ ] JSON pretty-printing does not block the main thread
- [ ] UI remains responsive while loading large response bodies
- [ ] `onChange(of: showRaw)` path also dispatches off main thread

## Work Log
- 2026-02-15: Created from PR #5 code review (performance-oracle agent)

## Resources
- PR: #5 feat: add syntax highlighting with Highlightr
