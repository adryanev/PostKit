---
status: complete
priority: p3
issue_id: "030"
tags: [code-review, quality, syntax-highlighting]
dependencies: []
---

# Over-Engineered Theme Debounce for Rare Event

## Problem Statement
In `CodeTextView.swift` lines 154-168, `scheduleThemeChange` uses a `DispatchWorkItem` + `asyncAfter(deadline: .now() + 0.1)` debounce pattern. Theme changes only occur when the user toggles macOS light/dark mode, which happens at most once per user action. The debounce adds 12 lines of complexity (work item management, cancellation, weak self capture) for an event that doesn't need debouncing.

## Findings
- **Location:** `PostKit/PostKit/Views/Components/CodeTextView.swift:137, 154-168`
- **Code:** `scheduleThemeChange` with `themeDebounceWorkItem`, `DispatchWorkItem`, `asyncAfter`
- **Agents:** code-simplicity-reviewer

## Proposed Solutions

### Solution A: Apply theme change directly (Recommended)
Replace the debounce with a direct theme application:
```swift
func applyThemeChange(to theme: String, textStorage: CodeAttributedString?) {
    textStorage?.highlightr.setTheme(to: theme)
    textStorage?.highlightr.theme.setCodeFont(.monospacedSystemFont(ofSize: 13, weight: .regular))
    currentThemeName = theme
}
```

**Effort:** Small | **Risk:** Low

## Acceptance Criteria
- [ ] Theme changes apply immediately without debounce machinery
- [ ] `themeDebounceWorkItem` property is removed
- [ ] Light/dark mode switching still works correctly

## Work Log
- 2026-02-15: Created from PR #5 code review (code-simplicity-reviewer agent)
