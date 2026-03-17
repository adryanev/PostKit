# Script Editor Enhancements Brainstorm

**Date:** 2026-02-22
**Status:** Draft
**Author:** Claude Code + User

## Context

The pre-request and post-request script editors in PostKit already use `CodeTextView` with full JavaScript syntax highlighting (Highlightr), line numbers, find bar, and dark/light theme support. However, a layout bug (nested `ScrollView` collapsing the `NSTextView`) prevented the editor from rendering at usable height. That bug has been fixed.

With the editor now functional, we're exploring three enhancements to improve the scripting developer experience.

## What We're Building

### 1. Snippet Insertion Toolbar

A row of quick-insert buttons above the script editor that inject common code patterns at the cursor position.

**Snippet categories:**

| Category | Snippets |
|----------|----------|
| Environment | `pk.environment.get('key')`, `pk.environment.set('key', 'value')` |
| Request (pre-req only) | `pk.request.url`, `pk.request.headers.add('key', 'value')`, `pk.request.headers.remove('key')`, `pk.request.body` |
| Response (post-req only) | `pk.response.code`, `pk.response.json()`, `pk.response.text()`, `pk.response.headers.get('key')`, `pk.response.responseTime` |
| Utility | `console.log()`, `pk.variables.get('key')` |

**Key decisions:**
- Snippets are contextual: pre-request editor shows request snippets, post-request shows response snippets. Shared snippets (environment, utility) appear in both.
- Buttons use compact labels (e.g., "env.get", "res.json") to save horizontal space.
- Inserted at current cursor position in the `NSTextView`, or appended at end if no selection.
- Implemented as a horizontal `ScrollView` of `Button`s above the `CodeTextView`.

### 2. Syntax Validation

Validate JavaScript syntax in the editor before execution, showing errors inline.

**Approach:** Use `JavaScriptCore`'s `JSContext.evaluateScript()` with a `try/catch` wrapper to detect syntax errors without executing side effects. The validation wraps the user script in:

```javascript
try { new Function(userScript); } catch(e) { e.message + '|' + e.line; }
```

`new Function()` parses without executing, catching `SyntaxError` with line numbers.

**Key decisions:**
- Validation runs on a debounce (e.g., 500ms after last keystroke) to avoid excessive JSContext creation.
- Errors display as a compact banner below the editor (red background, error message + line number), not inline gutter marks (too complex for NSTextView without LSP).
- Validation uses a dedicated background `DispatchQueue` to avoid blocking the UI.
- No runtime error detection — only syntax errors. Runtime errors still surface during execution via the Console tab.
- Reuses the existing `JavaScriptCore` dependency (no new dependencies needed).

### 3. API Reference Popover

A `?` help button in the script editor header that opens a popover showing the full `pk.*` API reference.

**Content structure:**
- Grouped by namespace: `pk.environment`, `pk.request`, `pk.response`, `pk.variables`, `console`
- Each method shows: signature, return type, brief description
- Pre-request popover shows request methods; post-request popover shows response methods
- Shared namespaces (environment, variables, console) appear in both

**Key decisions:**
- Implemented as a SwiftUI `.popover()` triggered by a `Button` with `systemImage: "questionmark.circle"`.
- Content is static (hardcoded in a view struct) since the API surface is small and stable.
- Uses monospaced font for method signatures, regular font for descriptions.
- No search/filter needed given the small API surface (~15 methods total).

## Why This Approach

- **Snippet toolbar** reduces friction for users unfamiliar with the `pk.*` API — they can discover and insert patterns without reading docs.
- **Syntax validation** catches typos and missing brackets immediately, rather than requiring a full request send to surface script errors.
- **Popover reference** provides discoverability without consuming permanent screen real estate, fitting PostKit's compact UI philosophy.
- All three features are purely additive — they enhance the existing `ScriptEditor` view without restructuring the editor architecture.
- No new dependencies required — `JavaScriptCore` is already used for execution, `Highlightr` for highlighting.

## Resolved Questions

1. **Snippet cursor placement:** Cursor selects the placeholder text inside quotes (e.g., `pk.environment.get('key')` with `key` selected) so the user can immediately type the real value. Requires NSTextView selection management after insertion.
2. **Error banner behavior:** Always visible when a syntax error exists. Disappears automatically when the error is fixed. No dismiss button — keeps the feedback persistent and honest.

## Out of Scope (Future)

- Auto-completion / IntelliSense for `pk.*` methods (requires deep NSTextView/LSP integration)
- Inline error markers in the gutter (requires custom NSLayoutManager work)
- Script sharing/reuse across requests (library feature)
- `pk.test()` assertion framework
- `pk.sendRequest()` chained requests
- Script templates / example library
