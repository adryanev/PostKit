# Enhanced Text Viewer & Editor

**Date:** 2026-02-13
**Status:** Brainstorm
**Author:** adryanev + Claude

## What We're Building

A rich text viewing and editing experience across the entire PostKit app, replacing the current plain `Text` and `TextEditor` SwiftUI views with `NSTextView`-based components powered by **Highlightr** for syntax highlighting.

### Target Areas

| Area | Current Component | New Component | Mode |
|------|-------------------|---------------|------|
| Response body | `Text` + `.textSelection(.enabled)` | `CodeTextView` (isEditable: false) | Read-only |
| Request body editor | `TextEditor` | `CodeTextView` (isEditable: true) | Editable |
| Response headers | `Text` list | Keep as-is (key-value list) | Read-only |
| cURL import | `TextEditor` | `CodeTextView` (isEditable: true, language: bash) | Editable |

### Features (MVP)

1. **Syntax highlighting** — JSON, XML, HTML, YAML, plain text. Colored keys, values, strings, numbers, booleans, nulls.
2. **Line numbers** — Displayed via `NSRulerView`, scrolls in sync with content.
3. **Find/search** — Built-in `NSTextView` find bar triggered by Cmd+F.
4. **Copy JSON path** — Right-click context menu to copy the key path of a JSON value (e.g., `$.data[0].name`). Requires parsing the JSON and mapping the cursor's character offset to a structural path — this is the most complex MVP feature.
5. **Live syntax highlighting** — In editable areas (request body, cURL import), highlighting updates as you type. Needs debouncing and cursor-position preservation after re-highlighting.

## Why This Approach

### NSTextView + Highlightr (Approach 1)

**Chosen over:**
- Custom tokenizer (Approach 2): More code to maintain, limited language support, edge cases in tokenization.
- SwiftUI-only (Approach 3): Cannot do live syntax highlighting in TextEditor, find/search requires custom implementation.

**Rationale:**
- `NSTextView` is macOS's most mature text component — built-in find bar, undo/redo, excellent selection, context menus, accessibility.
- Highlightr wraps highlight.js with Swift-native API, supports many languages and themes.
- The codebase already uses AppKit for `NSSavePanel`/`NSOpenPanel` in `FileExporter.swift`, so bridging is an established pattern.
- Minimal custom code for maximum functionality.

### Highlightr Dependency

- **Package:** [Highlightr](https://github.com/raspu/Highlightr) (SPM-compatible)
- **Size impact:** ~2MB (bundled highlight.js themes + languages)
- **Maintenance:** Well-maintained, MIT license
- **API:** `Highlightr` class converts source code string → `NSAttributedString` with syntax highlighting.

## Key Decisions

1. **One reusable component:** `CodeTextView` — an `NSViewRepresentable` wrapping `NSTextView` with an `isEditable: Bool` parameter. One component, not two.
2. **Language auto-detection:** Use response `Content-Type` header for response bodies; use `BodyType` enum for request bodies; Highlightr's auto-detection as fallback.
3. **Theme follows system appearance:** `xcode` (light) / `xcode-dark` (dark), reactive to `@Environment(\.colorScheme)`.
4. **Line numbers via NSRulerView:** Native ruler approach, not a custom side panel.
5. **JSON path copy:** Parse JSON structure, determine cursor position → key path. Available in right-click context menu for read-only JSON views.
6. **Preserve existing Copy button:** The "Copy entire body" button stays alongside the new text selection.
7. **Large response handling:** Keep the existing 10MB `maxDisplaySize` limit. Skip syntax highlighting above 1MB (fall back to plain monospaced text).

## Scope & Boundaries

### In Scope
- Single `CodeTextView` NSViewRepresentable wrapping NSTextView
- Highlightr integration for syntax highlighting
- Line numbers (NSRulerView)
- Find bar (Cmd+F)
- JSON path copy (context menu)
- Theme support (xcode light/dark)
- Target areas: response body, request body, cURL import
- SwiftUI ↔ NSTextView two-way text binding (with care to avoid infinite update loops)

### Out of Scope (Future)
- Code folding / collapsible JSON sections
- Bracket matching / auto-close
- Auto-completion / IntelliSense
- Diff view between responses
- Image/binary response rendering
- Minimap
- Multiple cursors

## Resolved Questions

1. **Which Highlightr themes?** → **Xcode pair** (`xcode` for light mode, `xcode-dark` for dark mode). Feels native to macOS development tools.
2. **Headers treatment?** → **Keep as key-value list.** Headers are structured data, not code — the current layout works well for scanning.
3. **Performance with very large responses?** → **Skip highlighting above 1MB.** Fall back to plain monospaced text for responses >1MB to avoid UI lag. The 10MB `maxDisplaySize` display limit still applies.
