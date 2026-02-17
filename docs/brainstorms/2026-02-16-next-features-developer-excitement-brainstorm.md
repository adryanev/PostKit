# Next Features: Making Developers Excited About PostKit

**Date:** 2026-02-16
**Status:** Brainstorm Complete
**Target User:** Solo indie/startup developers
**Approach:** Migration Blitz — attract users with import, retain with native macOS magic

---

## What We're Building

Six feature groups that transform PostKit from "nice native HTTP client" into "the API client every Mac developer recommends." The strategy is a funnel:

1. **Import/Migration** — Remove switching friction (Postman, OpenAPI YAML, Insomnia/Bruno)
2. **Response Examples** — Save responses as examples, load examples from OpenAPI specs
3. **Pre/Post-Request Scripts** — JavaScript scripting via JavaScriptCore
4. **iCloud Sync** — Sync collections across Macs with no account required
5. **Menu Bar Quick-Send** — Pin favorite requests, one-click send from menu bar
6. **Spotlight Integration** — Search any request from macOS Spotlight

---

## Why This Approach

PostKit's unfair advantage is being **native macOS**. But native doesn't matter if developers can't get their data in. The strategy:

- **Import removes the biggest adoption barrier.** Postman has 30M+ users. If even 0.1% try PostKit, that's 30K users — but only if they can bring their collections.
- **Examples and scripting close the feature gap.** These are the top reasons developers stay on Postman despite its bloat. Without them, users import and then go back.
- **iCloud sync leverages Apple's infrastructure.** No server costs, no accounts, no privacy concerns. Just works.
- **Menu bar and Spotlight are the "wow" factor.** No Electron app can do this. This is what makes developers tweet about PostKit.

---

## Key Decisions

### 1. Import/Migration

**Postman Collection v2.1 Import:**
- Parse Postman's JSON collection format (v2.1 is current standard)
- Map Postman structure to PostKit's model graph:
  - Postman `item[]` → PostKit `Folder` + `HTTPRequest`
  - Postman `request.auth` → PostKit `AuthConfig`
  - Postman `request.header[]` → PostKit `KeyValuePair` encoded headers
  - Postman `request.url.query[]` → PostKit `KeyValuePair` encoded params
  - Postman `variable[]` → PostKit `Variable` (collection-level variables)
- Handle Postman-specific patterns:
  - `{{variable}}` syntax (already matches PostKit's interpolation syntax)
  - Pre-request/test scripts: store raw script text on the imported `HTTPRequest` but don't execute. Show a "Scripts imported (requires scripting feature)" badge in the UI. Scripts become runnable once P4 ships.
  - Postman environments (separate JSON file) → PostKit `APIEnvironment`
- Edge cases: deeply nested folders, binary body references, GraphQL bodies (store as raw JSON for now)

**OpenAPI YAML Import:**
- Add `Yams` (Swift YAML parser) as justified dependency per ADR-003
- Plug YAML parsing into existing `OpenAPIParser` — the parser already handles the OpenAPI structure, just needs a YAML → Dictionary frontend
- Reuse existing create/update flow, diff engine, tag-to-folder mapping, security scheme extraction

**Insomnia/Bruno Import:**
- Insomnia: Parse their JSON export format (similar structure to Postman but different schema)
- Bruno: Parse `.bru` files (Bruno's plain-text format) — simpler than JSON parsing, regex-friendly
- Lower priority than Postman import — smaller user base but growing

### 2. Response Examples

**Per-Request Examples with OpenAPI Sync:**
- New SwiftData model: `ResponseExample` linked to `HTTPRequest`
  - Fields: `name`, `statusCode`, `headersData` (encoded KeyValuePair), `body` (String), `contentType`, `createdAt`
  - Relationship: `HTTPRequest.examples: [ResponseExample]` with `.cascade` delete
- "Save as Example" button in response viewer → names it, saves current response
- "Examples" tab in request detail → list saved examples, click to view, delete
- OpenAPI import enhancement: when spec contains `responses.*.content.*.example` or `examples`, create `ResponseExample` entries automatically
- View example in response viewer (read-only mode) for quick reference
- MVP scope: text-based responses only (JSON, XML, HTML). Binary/image examples deferred — aligns with current response viewer capabilities.

### 3. Pre/Post-Request Scripts (JavaScript via JavaScriptCore)

**Why JavaScriptCore:**
- Built into macOS — zero external dependencies (aligns with ADR-003 minimal dependencies philosophy)
- Familiar to Postman users — can provide migration-friendly API
- Sandboxed by default — no file system or network access from scripts
- Fast startup — no JIT compilation overhead for short scripts

**Script Execution Model:**
- Pre-request script runs before HTTP request is sent
  - Can modify: headers, query params, body, URL, auth tokens
  - Has access to: environment variables, collection variables, built-in variables (`$timestamp`, etc.)
- Post-request script runs after response is received
  - Can read: response body, headers, status code, timing data
  - Can set: environment variables (e.g., extract token from login response)
  - Can assert: status codes, response body content (test assertions)

**MVP API Surface (Postman-compatible subset):**

The `pk.*` namespace mirrors Postman's `pm.*` mental model. MVP ships only the core APIs needed for auth flows and variable extraction — the two most common scripting use cases.

```javascript
// MVP — Pre-request
pk.environment.get("baseUrl")
pk.environment.set("token", "abc123")
pk.variables.get("collectionVar")
pk.request.headers.add({ key: "X-Custom", value: "test" })

// MVP — Post-request
pk.response.code          // 200
pk.response.json()        // parsed JSON body
pk.response.headers       // response headers
pk.response.responseTime  // ms
```

**Deferred (post-MVP):**
- `pk.test()` assertions — full test runner is a separate feature, not part of initial scripting
- `pk.sendRequest()` — executing requests from within scripts
- `pk.cookies` — cookie jar integration
- `pk.require()` — external library loading

**Notes:**
- Use `pk.*` namespace (not `pm.*`) to avoid trademark issues
- Auto-map `pm.*` → `pk.*` for Postman import compatibility (resolved decision)
- Provide a migration doc showing the mapping

**Storage:**
- Script text stored as `String?` properties on `HTTPRequest` model:
  - `preRequestScript: String?`
  - `postRequestScript: String?`
- Script editor: reuse CodeTextView with JavaScript syntax highlighting (Highlightr already supports JS)

### 4. iCloud Sync

**SwiftData + CloudKit Integration:**
- SwiftData supports CloudKit sync via `ModelConfiguration(cloudKitDatabase: .automatic)`
- Minimal code change: update `ModelContainer` configuration in `PostKitApp.swift`
- Handles: create, update, delete sync across devices
- Conflict resolution: last-writer-wins (CloudKit default) — acceptable for solo dev use case

**Known Risk — CloudKit Model Compatibility:**
CloudKit requires ALL relationships to be optional and NO unique constraints. PostKit's current model graph uses `.cascade` delete rules and non-optional relationships (e.g., `Folder.requests`, `HTTPRequest.history`). Enabling CloudKit may require:
- Making relationships optional across all 6+ model types
- Removing any unique constraints (if present)
- Adding a 7th model (`ResponseExample`) that must also be CloudKit-compatible from day one
- Testing merge behavior when existing local data meets an empty cloud store

This audit should happen during the planning phase — it could surface model refactoring work that affects the effort estimate.

**Other Considerations:**
- Keychain secrets do NOT sync (by design — secrets stay per-device)
- `@Transient` properties won't sync (expected — they're computed)
- Add sync status indicator in UI (syncing/synced/error)

### 5. Menu Bar Quick-Send

**Implementation:**
- SwiftUI `MenuBarExtra` (available macOS 13+, we target 14+)
- Show pinned/favorite requests (add `isPinned: Bool` to `HTTPRequest`)
- Each menu item: request name + method badge → click to send
- Show result inline: status code + response time
- "Open in PostKit" option to jump to full app
- Configurable: show/hide menu bar icon in Preferences

**UX Flow:**
1. In main app, right-click request → "Pin to Menu Bar"
2. Click menu bar icon → see pinned requests
3. Click request → sends immediately, shows result as submenu
4. Option-click → opens request in main app

### 6. Spotlight Integration

**Implementation:**
- Use `CSSearchableIndex` (Core Spotlight framework)
- Index: request name, URL, method, collection name, folder name
- Update index when requests are created/modified/deleted
- Search result opens PostKit and navigates to the request

**Indexed Attributes:**
- `title`: request name
- `contentDescription`: `GET https://api.example.com/users`
- `keywords`: collection name, folder name, HTTP method
- `thumbnailData`: method badge icon (colored GET/POST/PUT etc.)

---

## Feature Priority & Sequencing

| Priority | Feature | Effort Estimate | Dependencies |
|----------|---------|-----------------|--------------|
| P1 | Postman Collection v2.1 Import | Medium | New `PostmanParser` service |
| P1 | OpenAPI YAML Import | Small | Yams dependency, existing `OpenAPIParser` |
| P2 | Insomnia/Bruno Import | Medium | New parsers |
| P3 | Response Examples (save + view) | Medium | New `ResponseExample` model |
| P3 | OpenAPI Example Loading | Small | Existing `OpenAPIParser` enhancement |
| P4 | Pre-request Scripts (JS) | Large | JavaScriptCore integration, `pk.*` API |
| P4 | Post-request Scripts (JS) | Medium | Builds on pre-request infrastructure |
| P5 | iCloud Sync | Medium-Large | CloudKit audit, model compatibility |
| P6 | Menu Bar Quick-Send | Medium | `MenuBarExtra`, pinned requests |
| P7 | Spotlight Integration | Small | `CSSearchableIndex` |

---

## PostKit's Competitive Position After These Features

| Feature | Postman | Insomnia | Bruno | HTTPie | **PostKit** |
|---------|---------|----------|-------|--------|-------------|
| Native macOS | No (Electron) | No (Electron) | No (Electron) | No (Electron) | **Yes** |
| Privacy-first | No (telemetry) | Partial | Yes | Partial | **Yes** |
| Postman import | N/A | Yes | Yes | No | **Yes (planned)** |
| OpenAPI import | Yes | Yes | Yes (partial) | No | **Yes (JSON done, YAML planned)** |
| Pre/post scripts | Yes (JS) | Plugins | Yes (JS) | No | **Yes (JS, planned)** |
| Response examples | Yes | No | No | No | **Yes (planned)** |
| iCloud sync | No | No | No | No | **Yes (planned)** |
| Menu bar | No | No | No | No | **Yes (planned)** |
| Spotlight | No | No | No | No | **Yes (planned)** |
| Timing waterfall | Basic | Basic | No | No | **Detailed (DNS/TCP/TLS/TTFB)** |
| Keychain secrets | No | No | No | No | **Yes** |

**PostKit's unique story:** "The only API client that lives in your menu bar, syncs via iCloud, and shows up in Spotlight — with full Postman import and JavaScript scripting. No account required."

---

## Open Questions

1. **Bruno `.bru` format stability:** Bruno's file format may evolve. Should we commit to full support, or treat it as best-effort? (Leaning best-effort — lower priority than Postman/Insomnia import.)

---

## Resolved Decisions

- **Target user:** Solo indie/startup developers
- **Approach:** Migration Blitz — imports first, then feature depth, then native macOS magic
- **Scripting engine:** JavaScript via JavaScriptCore (built-in, zero dependencies)
- **Script compatibility:** Auto-map Postman `pm.*` calls to PostKit `pk.*` equivalents transparently. Zero migration friction for imported scripts. Can deprecate `pm.*` shim later.
- **Examples model:** Per-request examples with OpenAPI sync (import examples from spec)
- **iCloud mechanism:** SwiftData + CloudKit automatic sync
- **iCloud scope:** Environments and variables sync via iCloud. Secret values remain in per-device Keychain (by design — Keychain doesn't sync).
- **Menu bar tech:** SwiftUI `MenuBarExtra`, integrated in main app process (simpler architecture, sufficient for solo devs)
- **Spotlight tech:** `CSSearchableIndex`
- **Priority order:** Import → Examples → Scripts → iCloud → Menu bar → Spotlight
