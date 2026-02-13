# Enhanced Text Viewer & Editor

**Date:** 2026-02-13
**Status:** Brainstorm
**Author:** adryanev + Claude

## What We're Building

A rich text viewing and editing experience across the entire PostKit app, replacing the current plain `Text` and `TextEditor` SwiftUI views with `NSTextView`-based components powered by **Highlightr** for syntax highlighting.

### Target Areas

| Area | Current Component | New Component | Mode |
|------|-------------------|---------------|------|
| Response body | `Text` + `.textSelection(.enabled)` | `CodeViewerView` (NSTextView wrapper) | Read-only |
| Request body editor | `TextEditor` | `CodeEditorView` (NSTextView wrapper) | Editable |
| Response headers | `Text` list | `CodeViewerView` or keep as-is | Read-only |
| cURL import | `TextEditor` | `CodeEditorView` | Editable |

### Features (MVP)

1. **Syntax highlighting** — JSON, XML, HTML, YAML, plain text. Colored keys, values, strings, numbers, booleans, nulls.
2. **Line numbers** — Displayed via `NSRulerView`, scrolls in sync with content.
3. **Find/search** — Built-in `NSTextView` find bar triggered by Cmd+F.
4. **Copy JSON path** — Right-click a JSON value to copy its key path (e.g., `$.data[0].name`).
5. **Text selection** — Full native text selection with Cmd+C support everywhere.
6. **Live syntax highlighting** — In editable areas (request body, cURL import), highlighting updates as you type.

## Why This Approach

### NSTextView + Highlightr (Approach 1)

**Chosen over:**
- Custom tokenizer (Approach 2): More code to maintain, limited language support, edge cases in tokenization.
- SwiftUI-only (Approach 3): Cannot do live syntax highlighting in TextEditor, find/search requires custom implementation.

**Rationale:**
- `NSTextView` is macOS's most mature text component — built-in find bar, undo/redo, excellent selection, context menus, accessibility.
- Highlightr wraps highlight.js with Swift-native API, supports 189 languages and 89 themes.
- The codebase already uses AppKit for `NSSavePanel`/`NSOpenPanel` in `FileExporter.swift`, so bridging is an established pattern.
- Minimal custom code for maximum functionality.

### Highlightr Dependency

- **Package:** [Highlightr](https://github.com/raspu/Highlightr) (SPM-compatible)
- **Size impact:** ~2MB (bundled highlight.js themes + languages)
- **Maintenance:** Well-maintained, MIT license
- **What it provides:** `Highlightr` class that converts source code string → `NSAttributedString` with syntax highlighting.

## Key Decisions

1. **Two reusable components:** `CodeViewerView` (read-only NSTextView wrapper) and `CodeEditorView` (editable NSTextView wrapper) — both backed by NSTextView, differing only in `isEditable`.
2. **Language auto-detection:** Use response `Content-Type` header for response bodies; use `BodyType` enum for request bodies; Highlightr's auto-detection as fallback.
3. **Theme follows system appearance:** Light theme for light mode, dark theme for dark mode, reactive to `@Environment(\.colorScheme)`.
4. **Line numbers via NSRulerView:** Native ruler approach, not a custom side panel.
5. **JSON path copy:** Parse JSON structure, determine cursor position → key path. Available in right-click context menu for read-only JSON views.
6. **Preserve existing Copy button:** The "Copy entire body" button stays alongside the new text selection.
7. **Large response handling:** Keep the existing 10MB `maxDisplaySize` limit. NSTextView handles large text better than SwiftUI Text.

## Scope & Boundaries

### In Scope
- NSViewRepresentable wrappers for NSTextView
- Highlightr integration for syntax highlighting
- Line numbers (NSRulerView)
- Find bar (Cmd+F)
- JSON path copy (context menu)
- Theme support (light/dark)
- All text-based areas: response body, request body, cURL import
- Proper SwiftUI ↔ NSTextView state binding

### Out of Scope (Future)
- Code folding / collapsible JSON sections
- Bracket matching / auto-close
- Auto-completion / IntelliSense
- Diff view between responses
- Image/binary response rendering
- Minimap
- Multiple cursors

## Open Questions

1. **Which Highlightr themes?** There are 89 available. Should we pick a specific pair (light + dark), or expose theme selection in settings?
2. **Headers treatment:** Should response headers also use the code viewer component, or stay as the current key-value list layout? Headers are structured data, not code.
3. **Performance with very large responses:** NSTextView + Highlightr highlighting on 5-10MB of JSON — should we skip highlighting above a certain size threshold and fall back to plain text?
