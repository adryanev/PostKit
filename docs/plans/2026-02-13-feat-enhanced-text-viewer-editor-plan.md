---
title: "feat: Enhanced Text Viewer & Editor with Syntax Highlighting"
type: feat
date: 2026-02-13
deepened: 2026-02-13
brainstorm: docs/brainstorms/2026-02-13-enhanced-text-viewer-editor-brainstorm.md
---

# feat: Enhanced Text Viewer & Editor with Syntax Highlighting

## Enhancement Summary

**Deepened on:** 2026-02-13
**Research agents used:** architecture-strategist, performance-oracle, security-sentinel, code-simplicity-reviewer, pattern-recognition-specialist, julik-frontend-races-reviewer, best-practices-researcher

### Key Improvements from Research

1. **Lowered highlighting threshold** from 1MB to 256KB — avoids 500-900ms UI freezes on large JSON
2. **Deferred JSON Path Copy** to follow-up PR — reduces MVP scope by ~200 LOC and removes the most complex/fragile feature
3. **Fixed nested ScrollView bug** — ResponseContentView wraps all tabs in a ScrollView, which conflicts with CodeTextView's internal NSScrollView
4. **Fixed race conditions** — synchronous binding writeback, FindBarAwareScrollView for focus restoration, cached displayString
5. **Fork Highlightr** as a prerequisite — pinning to `branch: master` is a reproducibility risk
6. **TextKit 1 documentation** — manual stack required because CodeAttributedString is incompatible with TextKit 2
7. **Simplified API** — removed `fontSize` and `showLineNumbers` parameters (hardcoded), reduced from 5 phases to 3

### New Risks Discovered

- Nested ScrollView conflict in ResponseContentView (must restructure)
- Guard flag + async writeback creates a race window (use synchronous writeback)
- Theme switch during editing can cause lost keystrokes (debounce required)
- `displayString(for:)` re-parses JSON on every SwiftUI body evaluation (must cache)
- `isJSON` computed property parses entire response just to check format (use Content-Type instead)
- Tab switching destroys/recreates CodeTextView, causing re-highlight (use ZStack + opacity)

---

## Overview

Replace PostKit's plain `Text` and `TextEditor` views with a single reusable `CodeTextView` component backed by `NSTextView` + [Highlightr](https://github.com/raspu/Highlightr) for syntax highlighting. This adds syntax coloring, line numbers, find/search (Cmd+F), and proper text selection across the response body viewer, request body editor, and cURL import sheet.

This is PostKit's **first external dependency** and **first `NSViewRepresentable`** — both are deliberate, justified exceptions to existing ADRs.

## Problem Statement / Motivation

The current text rendering is plain monospaced `Text` (response) and `TextEditor` (request/cURL):
- **No syntax highlighting** — JSON keys, values, strings, numbers all look the same
- **No line numbers** — difficult to reference specific lines
- **No find/search** — cannot Cmd+F within response or request bodies
- **Limited selection UX** — SwiftUI `Text` with `.textSelection(.enabled)` has known macOS quirks

These are table-stakes features for any HTTP API client (Postman, Insomnia, HTTPie Desktop all have them).

## Proposed Solution

A single `CodeTextView` NSViewRepresentable wrapping `NSTextView`, parameterized by:
- `text: Binding<String>` — two-way text binding
- `language: String?` — Highlightr language identifier (e.g., `"json"`, `"xml"`, `"bash"`)
- `isEditable: Bool` — read-only viewer vs. live editor

Font size hardcoded to 13pt (system monospaced). Line numbers always shown via NSRulerView. No configurable parameters beyond the three above — YAGNI.

Syntax highlighting via Highlightr's `CodeAttributedString` (an `NSTextStorage` subclass that highlights in the background as text changes). Themes follow system appearance: `xcode` (light) / `xcode-dark` (dark).

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────┐
│                  CodeTextView                    │
│            (NSViewRepresentable)                 │
│                                                  │
│  @Binding var text: String                       │
│  var language: String?                           │
│  var isEditable: Bool                            │
│  @Environment(\.colorScheme) var colorScheme     │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │     FindBarAwareScrollView (NSScrollView)    │ │
│  │  ┌──────────┬──────────────────────────────┐ │ │
│  │  │ LineNum  │        NSTextView            │ │ │
│  │  │ RulerView│                              │ │ │
│  │  │          │   CodeAttributedString       │ │ │
│  │  │   1      │     (NSTextStorage)          │ │ │
│  │  │   2      │        │                     │ │ │
│  │  │   3      │   NSLayoutManager            │ │ │
│  │  │   4      │        │                     │ │ │
│  │  │   5      │   NSTextContainer            │ │ │
│  │  └──────────┴──────────────────────────────┘ │ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  Coordinator (NSTextViewDelegate)                │
│  - Guard flag (isUpdatingFromSwiftUI)            │
│  - Synchronous writeback to SwiftUI @Binding     │
│  - Selection preservation across updates         │
│  - lastWrittenText cache for fast equality check │
│  - Theme change debouncing                       │
└─────────────────────────────────────────────────┘
```

### Research Insight: Why TextKit 1 Stack Must Be Built Manually

`CodeAttributedString` is an `NSTextStorage` subclass — a **TextKit 1** concept. On macOS 14+, `NSTextView()` defaults to **TextKit 2** (`NSTextLayoutManager` + `NSTextContentStorage`), which is **incompatible** with custom `NSTextStorage` subclasses. Therefore, the full TextKit 1 stack (CodeAttributedString → NSLayoutManager → NSTextContainer → NSTextView) **must** be constructed manually. This is not optional — using a default `NSTextView()` will silently break highlighting.

> Add a prominent code comment in `makeNSView` explaining this. A future maintainer who tries to "simplify" by using `NSTextView()` directly will break highlighting.

### File Layout

```
Views/
  Components/
    CodeTextView.swift              ← NSViewRepresentable + Coordinator + FindBarAwareScrollView
    LineNumberRulerView.swift       ← NSRulerView subclass for line numbers
Models/
  Enums/
    BodyType.swift                  ← Add highlightrLanguage computed property
Services/
  Protocols/
    HTTPClientProtocol.swift        ← Add contentType convenience property
```

### Integration Points (Existing Files Modified)

| File | Change |
|------|--------|
| `ResponseViewerPane.swift` | Replace `Text(displayString)` in `ScrollView` → `CodeTextView`; restructure `ResponseContentView` to use ZStack; cache `displayString` in `@State` |
| `RequestEditorPane.swift:163-169` | Replace `TextEditor(text: binding)` → `CodeTextView(text:, language:, isEditable: true)` |
| `CurlImportSheet.swift:21-24` | Replace `TextEditor(text: $curlCommand)` → `CodeTextView(text:, language: "bash", isEditable: true)`; debounce curl parsing |
| `BodyType.swift` | Add `var highlightrLanguage: String?` computed property |
| `HTTPClientProtocol.swift` | Add `var contentType: String?` computed property on `HTTPResponse` |

### Implementation Phases

#### Phase 1: Foundation — Highlightr + CodeTextView + Line Numbers

**Goal:** Add Highlightr, build the core `CodeTextView` component with highlighting and line numbers, verify it works standalone.

**Tasks:**

- [ ] **Fork Highlightr** to the project's GitHub org/account
  - Fork `https://github.com/raspu/Highlightr` → `https://github.com/adryanev/Highlightr`
  - Tag at a known-good commit (e.g., `1.0.0-postkit`)
  - This gives reproducible builds and protection against upstream breakage

- [ ] **Add Highlightr SPM dependency** to `PostKit.xcodeproj`
  - Package URL: `https://github.com/adryanev/Highlightr.git` (forked)
  - Use tagged version `1.0.0-postkit`
  - Add to the main `PostKit` target only

- [ ] **Add `@preconcurrency import Highlightr`** — Highlightr classes are not `@Sendable`. Add this from the start, not as a later fix.

- [ ] **Add `contentType` computed property** to `HTTPResponse` (`HTTPClientProtocol.swift`):
  ```swift
  var contentType: String? {
      headers["Content-Type"]?.components(separatedBy: ";").first?
          .trimmingCharacters(in: .whitespaces).lowercased()
  }
  ```

- [ ] **Add `highlightrLanguage` computed property** to `BodyType` enum (`BodyType.swift`):
  ```swift
  var highlightrLanguage: String? {
      switch self {
      case .none: return nil
      case .json: return "json"
      case .xml: return "xml"
      case .raw: return "plaintext"
      case .urlEncoded: return "plaintext"
      case .formData: return nil
      }
  }
  ```

- [ ] **Create `Views/Components/CodeTextView.swift`**

  **API (3 parameters only):**
  ```swift
  struct CodeTextView: NSViewRepresentable {
      @Binding var text: String
      var language: String?
      var isEditable: Bool
      @Environment(\.colorScheme) private var colorScheme
  }
  ```

  **`makeNSView`** — Build full TextKit 1 stack manually:
  1. `CodeAttributedString` (set language, theme, font 13pt monospaced)
  2. `NSLayoutManager`
  3. `NSTextContainer` (`widthTracksTextView: true` for editable; `false` with infinite width for read-only to allow horizontal scroll)
  4. `NSTextView` (configure: isEditable, isSelectable, allowsUndo, disable smart quotes/dashes/replacement/spelling, `usesFindBar = true`, `isIncrementalSearchingEnabled = true`)
  5. `FindBarAwareScrollView` wrapper (custom NSScrollView subclass that restores focus when find bar closes)
  6. **Line numbers**: Create `LineNumberRulerView`, attach as `scrollView.verticalRulerView`, set `scrollView.rulersVisible = true`
  7. Add **TextKit 1 comment** explaining why the stack is built manually

  **`updateNSView`** — Three-guard loop prevention pattern:
  1. Always refresh `context.coordinator.parent = self` (struct is value type, gets stale)
  2. **Guard 1**: Check `isUpdatingFromSwiftUI` flag
  3. **Guard 2**: Fast path — compare `text == coordinator.lastWrittenText` (O(1) reference check). Only fall back to `textView.string != text` if binding changed.
  4. **Guard 3**: Only set text if it actually differs (with selection preservation)
  5. Update theme if `colorScheme` changed — **debounce with 100ms coalescing** to prevent multiple re-highlights during macOS appearance transitions. Re-apply `setCodeFont` after `setTheme`.
  6. Update language if it changed
  7. **Skip writeback logic entirely when `isEditable == false`** — no need for `textDidChange` processing in read-only mode
  8. **Check `scrollView.isFindBarVisible`** before setting text — setting text while find bar is open can dismiss it

  **`Coordinator`** as `NSTextViewDelegate`:
  1. `textDidChange` → **synchronous** writeback: set flag, write `parent.text = textView.string`, clear flag. No `DispatchQueue.main.async` — it introduces a race window where the flag and actual state are inconsistent. Synchronous is correct because `textDidChange` is already on the main thread.
  2. `lastWrittenText: String` cache — updated on every writeback, used for fast equality check in `updateNSView`
  3. `unowned var textView: NSTextView!` — coordinator does not outlive the view
  4. `var textStorage: CodeAttributedString?` — weak/unowned reference for theme/language updates
  5. Track `currentThemeName` and `currentLanguage` to detect changes
  6. `themeDebounceWorkItem: DispatchWorkItem?` for coalesced theme switching

  **`FindBarAwareScrollView`** (NSScrollView subclass, same file):
  ```swift
  final class FindBarAwareScrollView: NSScrollView {
      weak var textView: NSTextView?
      override var isFindBarVisible: Bool {
          didSet {
              if oldValue && !isFindBarVisible {
                  window?.makeFirstResponder(textView)
              }
          }
      }
  }
  ```

  **Highlighting threshold (256KB):**
  - If `text.utf8.count > 262_144`, set `textStorage.language = nil` (plain monospaced, no highlighting)
  - This keeps initial highlight time under 150ms on M-series Macs

- [ ] **Create `Views/Components/LineNumberRulerView.swift`**
  - Subclass `NSRulerView`
  - Initialize with `clientView` set to the NSTextView
  - Observe `NSText.didChangeNotification` and `NSView.frameDidChangeNotification`
  - **Coalesce redraws**: Use a `pendingRedraw` flag + `DispatchQueue.main.async` to avoid notification storms during re-highlighting
  - Override `drawHashMarksAndLabels(in:)`:
    1. Get visible glyph range from layout manager
    2. Count lines before visible range to determine starting line number
    3. Iterate glyphs, draw line numbers right-aligned with matching y-positions
  - **Cache line number attributed strings** (numbers 1-9999) to avoid allocations during scroll
  - Track `lastDrawnLineRange` — skip redraw if visible range hasn't changed
  - Font: monospaced 11pt. Background: match theme background.
  - Dynamic `ruleThickness` based on digit count (40pt base, expand for >999 lines)
  - **Unregister from NotificationCenter in `deinit`** to prevent zombie handlers

**Success criteria:** A standalone `CodeTextView` that renders highlighted JSON, supports typing with live re-highlighting, has Cmd+F search, shows line numbers, and switches themes with system appearance.

#### Phase 2: Integration — Replace Existing Views

**Goal:** Swap in `CodeTextView` at all three integration points with proper performance handling.

**Tasks:**

- [ ] **Restructure `ResponseContentView`** to eliminate nested ScrollView conflict:

  **Problem:** `ResponseContentView` wraps all tabs (body, headers, timing) in a single `ScrollView`. But `CodeTextView` has its own `NSScrollView` internally. A SwiftUI ScrollView containing an NSScrollView causes conflicting scroll gestures and broken inertia.

  **Solution:** Use `ZStack` + `opacity` instead of `switch` for tab switching. This:
  1. Eliminates the outer ScrollView for the body tab
  2. Keeps `CodeTextView` alive across tab switches (avoids re-highlighting on tab switch)
  3. Each tab manages its own scrolling

  ```swift
  ZStack {
      ResponseBodyView(response: response)
          .opacity(activeTab == .body ? 1 : 0)
          .allowsHitTesting(activeTab == .body)

      ScrollView {
          ResponseHeadersView(headers: response.headers)
      }
      .opacity(activeTab == .headers ? 1 : 0)
      .allowsHitTesting(activeTab == .headers)

      ScrollView {
          ResponseTimingView(duration: response.duration, size: response.size)
      }
      .opacity(activeTab == .timing ? 1 : 0)
      .allowsHitTesting(activeTab == .timing)
  }
  ```

- [ ] **Cache `displayString` and `isJSON` in ResponseBodyView** — currently, `displayString(for:)` calls `JSONSerialization` on every SwiftUI body evaluation. This is a 50-100ms parse for a 5MB response firing dozens of times.

  **Solution:**
  ```swift
  @State private var cachedDisplayString: String = ""
  @State private var detectedLanguage: String?

  // In .task or .onChange(of: bodyData):
  if let data = bodyData {
      let ct = response.contentType
      detectedLanguage = languageForContentType(ct)
      cachedDisplayString = computeDisplayString(for: data, showRaw: showRaw)
  }
  ```

  **Use Content-Type header** for JSON detection instead of parsing the entire body:
  ```swift
  private var isJSON: Bool {
      response.contentType == "application/json"
  }
  ```

- [ ] **Add pretty-printing size limit of 512KB** — pretty-printing a 5MB JSON response consumes 55-65MB peak memory. Skip pretty-printing above 512KB, display raw JSON instead.

- [ ] **Replace ResponseBodyView** (`ResponseViewerPane.swift`):
  - Remove the `ScrollView([.horizontal, .vertical]) { Text(...) }` block
  - Replace with `CodeTextView(text: .constant(cachedDisplayString), language: detectedLanguage, isEditable: false)`
  - When "Raw" toggle is on, set language to `nil` and use raw body string
  - Keep the existing "Copy" button
  - Use `.id(response.hashValue)` to force recreation when response changes entirely (avoids re-highlight-mid-highlight race)

- [ ] **Replace BodyEditor** (`RequestEditorPane.swift:163-169`):
  - Remove the `TextEditor(text: Binding(...))` block
  - Replace with `CodeTextView(text: bodyContentBinding, language: request.bodyType.highlightrLanguage, isEditable: true)`
  - Maintain the same `nil` ↔ empty string binding wrapper for `bodyContent`

- [ ] **Replace CurlImportSheet** (`CurlImportSheet.swift:21-24`):
  - Remove `TextEditor(text: $curlCommand)`
  - Replace with `CodeTextView(text: $curlCommand, language: "bash", isEditable: true)`
  - **Debounce curl parsing** — add 150ms debounce to `.onChange(of: curlCommand)` to reduce @State churn while CodeAttributedString is highlighting:
    ```swift
    .onChange(of: curlCommand) { _, _ in
        curlParseWorkItem?.cancel()
        let item = DispatchWorkItem { parseCurlCommand() }
        curlParseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }
    ```

- [ ] **Content-type → language mapping** (private function in ResponseBodyView):
  ```swift
  private func languageForContentType(_ contentType: String?) -> String? {
      switch contentType {
      case "application/json": return "json"
      case "application/xml", "text/xml": return "xml"
      case "text/html": return "html"
      case "text/css": return "css"
      case "application/javascript", "text/javascript": return "javascript"
      case "application/x-yaml", "text/yaml": return "yaml"
      default: return nil
      }
  }
  ```

**Success criteria:** All three areas display syntax-highlighted content. Editing works with live re-highlighting. Language auto-detected for responses. Cmd+F search works. No nested scroll conflicts. No UI freezes on large responses.

#### Phase 3: Polish & Documentation

**Goal:** Handle edge cases, update documentation, amend ADRs.

**Tasks:**

- [ ] **Accessibility:** Verify VoiceOver still works with CodeAttributedString. NSTextView has built-in accessibility — the custom TextKit stack should preserve it.

- [ ] **Performance verification:** Test with response bodies at key thresholds:

  | Size | Expected Behavior | Highlight Time SLA |
  |------|-------------------|-------------------|
  | 1KB | Highlighted instantly | <5ms |
  | 100KB | Highlighted smoothly | <80ms |
  | 256KB | Highlighted (at boundary) | <150ms |
  | 256KB+ | Plain monospaced text (no highlighting) | <10ms |
  | 512KB+ | Plain text, no pretty-printing | <20ms |
  | 5MB | Plain text render | <50ms |
  | 10MB | "Response too large" warning | N/A |

- [ ] **Theme switching:** Verify debounced theme switch works during macOS appearance transition. Confirm no lost keystrokes when editing during theme change.

- [ ] **Empty state:** Verify CodeTextView handles empty string gracefully (no crashes, no "undefined").

- [ ] **Binary data:** Verify existing `<binary data>` fallback string displays without highlighting.

- [ ] **Undo/redo:** Verify undo/redo works in editable mode (`allowsUndo = true`).

- [ ] **Find bar:** Verify Cmd+F opens find bar. Verify focus returns to text view when find bar closes (FindBarAwareScrollView).

- [ ] **Amend ADR-003** (Zero External Dependencies):
  - Document Highlightr as a justified exception
  - Note: forked and pinned to tagged version for reproducibility
  - Note: JSC adds ~2-4MB resident memory, ~50-100ms cold-start latency

- [ ] **Amend ADR-001** (SwiftUI over UIKit/AppKit):
  - Document `NSViewRepresentable` as an accepted bridging pattern for text editing
  - Note: required because SwiftUI TextEditor does not support attributed text

- [ ] **Update developer guide** (`docs/sop/developer-guide.md`):
  - Highlightr as a dependency (forked)
  - `CodeTextView` as the standard text display component
  - NSViewRepresentable pattern for AppKit bridging
  - TextKit 1 requirement for CodeAttributedString

## Deferred to Follow-up PR: JSON Path Copy

**Rationale for deferral (from simplicity review):** JSON path copy requires a custom NSTextView subclass (`CodeNSTextView` for `menu(for:)` override), a non-trivial JSON parser mapping character offsets to key paths, and pretty-print/offset synchronization. This is ~150-200 lines of fragile code for a feature that:
- Only works for JSON responses (not XML, HTML, YAML)
- Relies on pretty-printed text exactly matching offset math
- Is not a blocker for any other feature
- Can be added cleanly later without changing the core CodeTextView API

**When to implement:** If users request it after shipping syntax highlighting. The core CodeTextView does not need modification — the JSON path feature would add a custom NSTextView subclass and a context menu handler.

## Acceptance Criteria

### Functional Requirements

- [ ] Response bodies display with syntax-highlighted JSON, XML, HTML, YAML
- [ ] Request body editor has live syntax highlighting while typing
- [ ] cURL import sheet has bash syntax highlighting
- [ ] Line numbers visible in all code text areas
- [ ] Cmd+F opens find bar in any code text area
- [ ] Theme switches automatically between xcode (light) and xcode-dark (dark)
- [ ] "Raw" toggle in response viewer disables highlighting (shows plain text)
- [ ] Existing "Copy" button in response viewer still works
- [ ] Tab switching preserves CodeTextView state (no re-highlight flicker)

### Non-Functional Requirements

- [ ] Responses up to 256KB render with syntax highlighting within 150ms
- [ ] Responses above 256KB fall back to plain monospaced text (no highlighting)
- [ ] Responses above 512KB skip JSON pretty-printing (display raw)
- [ ] Responses above 10MB show the existing size warning
- [ ] No infinite update loops between SwiftUI and NSTextView
- [ ] No nested ScrollView conflicts
- [ ] Theme switch completes within 200ms including debounce
- [ ] Per-keystroke highlight completes within 16ms (one frame at 60fps)
- [ ] VoiceOver reads code content correctly
- [ ] Undo/redo works in editable text areas

### Quality Gates

- [ ] All existing functionality preserved (no regressions)
- [ ] ADR-001 and ADR-003 amended with rationale
- [ ] Developer guide updated
- [ ] Highlightr forked and pinned to tagged version

## Dependencies & Prerequisites

| Dependency | Type | Risk |
|------------|------|------|
| [Highlightr](https://github.com/raspu/Highlightr) (forked, tagged) | SPM package | Low — forked and pinned. Library wraps highlight.js (actively maintained). Fallback: [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) |
| macOS 14+ | Platform | None — already the minimum target |
| JavaScriptCore | System framework | None — used internally by Highlightr, available in all macOS apps. Adds ~2-4MB resident memory, ~50-100ms cold-start. |

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Highlightr abandoned / breaks on future macOS | Medium | High | Forked and pinned. Library wraps highlight.js (actively maintained). The NSTextView wrapper is ours and independent. Fallback: HighlighterSwift. |
| Infinite update loop in NSViewRepresentable | High (during dev) | Medium | Three-guard pattern: (1) `isUpdatingFromSwiftUI` flag, (2) `lastWrittenText` equality cache, (3) `textView.string != text` check. Synchronous writeback eliminates async race window. |
| Nested ScrollView conflict | High | High | Restructure ResponseContentView to ZStack + opacity. Each tab manages own scrolling. |
| Performance lag on large responses | Low | Medium | 256KB highlighting threshold. 512KB pretty-printing threshold. CodeAttributedString highlights only edited paragraphs during typing. |
| Theme switch during editing causes lost keystrokes | Medium | Medium | 100ms debounced theme application via DispatchWorkItem. |
| `displayString` re-parses JSON on every body evaluation | High | Medium | Cache in @State, compute once during .task load. Use Content-Type for JSON detection. |
| `setTheme(to:)` resets font | High (gotcha) | Low | Always call `theme.setCodeFont(...)` immediately after `setTheme(to:)`. Document in code comment. |
| Swift 6 strict concurrency warnings | Medium | Low | `@preconcurrency import Highlightr` from Phase 1. |
| Tab switch re-highlights entire response | Medium | Medium | ZStack + opacity keeps CodeTextView alive across tab switches. |
| Find bar dismissal loses focus | Medium | Low | FindBarAwareScrollView subclass restores first responder. |
| Response change mid-highlight | Medium | Medium | `.id(response.hashValue)` forces recreation on new response. |

## References & Research

### Internal References

- Brainstorm: `docs/brainstorms/2026-02-13-enhanced-text-viewer-editor-brainstorm.md`
- ADR-001 (SwiftUI over UIKit/AppKit): `docs/adr/0001-postkit-architecture-decisions.md:36-59`
- ADR-003 (Zero External Dependencies): `docs/adr/0001-postkit-architecture-decisions.md:90-109`
- ADR-011 (Memory-aware Responses): `docs/adr/0001-postkit-architecture-decisions.md:309-334`
- Developer guide: `docs/sop/developer-guide.md`
- Response body view: `Views/RequestDetail/ResponseViewer/ResponseViewerPane.swift:61-145`
- Request body editor: `Views/RequestDetail/RequestEditor/RequestEditorPane.swift:148-182`
- cURL import sheet: `Views/Import/CurlImportSheet.swift:21-27`
- BodyType enum: `Models/Enums/BodyType.swift`
- HTTPResponse struct: `Services/Protocols/HTTPClientProtocol.swift:8-16`

### External References

- [Highlightr GitHub](https://github.com/raspu/Highlightr) — SPM package, MIT license
- [highlight.js](https://highlightjs.org/) — underlying engine, actively maintained
- [Chris Eidhof — NSViewRepresentable patterns](https://chris.eidhof.nl/post/view-representable/) — the definitive community guide
- [WWDC22 — Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/) — Apple's official guidance
- [Matt Massicotte — SwiftUI Coordinator Parent](https://www.massicotte.org/swiftui-coordinator-parent/) — stale parent trap
- [MacEditorTextView SwiftUI gist](https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0)
- [NSTextView-LineNumberView (NSRulerView)](https://github.com/yichizhang/NSTextView-LineNumberView)
- [Christian Tietze — NSTextView Find Bar](https://christiantietze.de/posts/2018/02/nstextview-find-bar-disappear/)
- [HighlighterSwift (alternative)](https://github.com/smittytone/HighlighterSwift)

### Key Implementation Patterns

**Three-Guard Loop Prevention (from WWDC22 + Chris Eidhof + community):**
```swift
// Guard 1: Flag in Coordinator
guard !coordinator.isUpdatingFromSwiftUI else { return }

// Guard 2: Fast equality check (O(1) reference comparison)
guard text != coordinator.lastWrittenText else { return }

// Guard 3: Actual text comparison before setting
if textView.string != text {
    coordinator.isUpdatingFromSwiftUI = true
    let selectedRanges = textView.selectedRanges
    textView.string = text
    textView.selectedRanges = selectedRanges
    coordinator.isUpdatingFromSwiftUI = false
}
```

**Synchronous Writeback (from race condition review):**
```swift
func textDidChange(_ notification: Notification) {
    guard !isUpdatingFromSwiftUI else { return }
    guard let textView = notification.object as? NSTextView else { return }
    isUpdatingFromSwiftUI = true
    parent.text = textView.string
    lastWrittenText = textView.string
    isUpdatingFromSwiftUI = false
}
```

**Debounced Theme Switching:**
```swift
func scheduleThemeChange(to theme: String) {
    themeDebounceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.textStorage?.highlightr.setTheme(to: theme)
        self.textStorage?.highlightr.theme.setCodeFont(
            .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        self.currentThemeName = theme
    }
    themeDebounceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
}
```

### Key API Gotchas

1. **TextKit 1 vs TextKit 2** — CodeAttributedString requires TextKit 1. Build the stack manually. NSTextView() defaults to TextKit 2 on macOS 14+.
2. **`setTheme(to:)` resets font** — always re-apply `theme.setCodeFont(...)` after theme change
3. **`CodeAttributedString()` default init force-unwraps** — prefer `init(highlightr:)` with a guard
4. **Theme name is case-sensitive** — use lowercase: `"xcode"`, `"xcode-dark"`
5. **Find bar focus loss** — use FindBarAwareScrollView to restore focus when find bar closes
6. **No Swift 6 strict concurrency** — use `@preconcurrency import Highlightr`
7. **Always refresh `coordinator.parent = self` in updateNSView** — the struct is a value type and gets stale
8. **Nested ScrollView** — CodeTextView has its own NSScrollView; do not wrap in a SwiftUI ScrollView
9. **Disable smart substitutions** — isAutomaticQuoteSubstitutionEnabled, isAutomaticDashSubstitutionEnabled, isAutomaticTextReplacementEnabled, isAutomaticSpellingCorrectionEnabled must all be false for code editing
