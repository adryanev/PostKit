# OpenAPI YAML/JSON Import with Create/Update

**Date**: 2026-02-13
**Status**: Brainstorm
**Author**: adryanev + Claude

## What We're Building

An enhanced OpenAPI import feature for PostKit that supports both YAML and JSON spec files, with intelligent create-or-update prompting. When importing a spec, users always see their existing collections and can choose to create a new collection or update an existing one. Updates show a side-by-side diff for conflicting endpoints.

### Core Capabilities

1. **YAML + JSON parsing** — Extend the existing `OpenAPIParser` to accept YAML files using the Yams library (first external dependency via SPM)
2. **Always-prompt collection targeting** — On import, show existing collections and let the user choose "Create new" or select one to update
3. **Smart merge with conflict resolution** — New endpoints are added automatically; changed endpoints show a side-by-side diff so the user can choose "Keep existing" or "Replace with new" per endpoint
4. **Tag-based folder grouping** — Map OpenAPI operation tags to `Folder` objects for organized collections
5. **Security scheme extraction** — Parse `securitySchemes` and auto-populate `AuthConfig` (Bearer, Basic, API Key) on imported requests
6. **Environment creation from servers** — Parse server URLs and their variables into `APIEnvironment` + `Variable` entries

## Why This Approach

### Approach Chosen: Enhanced Single Sheet (Multi-Step Wizard)

Evolve the existing `OpenAPIImportSheet` into a multi-step wizard:

- **Step 1 — File Select**: Pick YAML/JSON file, parse and validate
- **Step 2 — Target**: "Create new collection" or pick an existing collection (always shown)
- **Step 3 — Configure**: Server picker, endpoint list with tag-folder preview, auth scheme preview, environment preview
- **Step 4 — Conflicts** (update mode only): Side-by-side diff for endpoints that already exist with changes

**Why this over alternatives:**
- Builds on the existing `OpenAPIImportSheet` code rather than creating parallel UI
- Single entry point (Cmd+Shift+O) for both new imports and updates
- Sheet pattern is consistent with existing cURL import UX
- Wizard steps keep complexity manageable despite the feature richness

### Approaches Rejected

- **Separate Window**: More screen real estate but over-engineered for a dev tool. Introduces a new UX pattern.
- **Two-Phase Import**: Simpler individual flows but doubles the entry points and maintenance burden. Users must know which flow to pick.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Add Yams as first SPM dependency** | Hand-rolling a YAML parser is too much effort and error-prone. Yams is the standard Swift YAML library. Breaks zero-dependency policy but is pragmatic. |
| 2 | **Always prompt for collection target** | No automatic matching by title or source tracking. User sees all collections and explicitly chooses. Simpler logic, full user control. |
| 3 | **Add new endpoints, prompt per conflict** | New endpoints auto-added. For existing endpoints (matched by method + path), show side-by-side diff with keep/replace toggle. Preserves user customizations while allowing selective updates. |
| 4 | **Side-by-side diff for conflicts** | Show old vs new details (URL, params, headers, body type, auth) so users can make informed decisions. |
| 5 | **Map tags to folders** | First tag on an operation determines its folder. Untagged operations go to collection root. On update, create new folders for new tags. |
| 6 | **Extract security schemes** | Parse Bearer, Basic, and API Key schemes from `components/securitySchemes`. Set `AuthConfig` on requests with empty credential values for user to fill in. |
| 7 | **Create environments from servers** | Each server entry becomes an `APIEnvironment`. Server URL variables become `Variable` entries. |
| 8 | **Store OpenAPI path on imported requests** | Imported requests store their original OpenAPI path (e.g., `/users/{id}`) for reliable matching during updates, independent of server URL changes. |
| 9 | **Convert path params to {{var}} syntax** | `/users/{id}` becomes `/users/{{id}}` so it integrates with PostKit's variable substitution and environments. |
| 10 | **Flag removed endpoints in diff** | When updating, endpoints in the collection but not in the new spec appear in the conflict view with Delete/Keep options. User decides per endpoint. |
| 11 | **Move endpoints to new folders on tag change** | If a spec reassigns an operation's tag, the request moves to the new folder. Keeps collection structure in sync with the spec. |

## Scope Boundaries

### In Scope
- YAML and JSON OpenAPI 3.x parsing
- Yams SPM dependency
- Create new or update existing collection prompting
- Side-by-side conflict diff with per-endpoint keep/replace
- Tag-to-folder mapping
- Security scheme extraction (Bearer, Basic, API Key)
- Server-to-environment mapping with variables
- Query parameter extraction (currently only headers are extracted)
- Enhanced body content type mapping (json, xml, form-data, url-encoded)

### Out of Scope (for now)
- `$ref` resolution (only inline definitions)
- Swagger 2.x support
- Remote URL import (only local files)
- OpenAPI spec validation/linting
- Webhook/callback imports
- Response schema previews
- Drag-and-drop file import

## Matching Strategy

Endpoints are matched between the imported spec and existing collection by **HTTP method + OpenAPI path** (e.g., `GET /users/{id}`), NOT the full URL with server prefix. This is the most reliable identifier since:
- `operationId` may not exist in all specs
- Path + method is guaranteed unique per OpenAPI spec
- It survives renames of the operation
- It survives server URL changes between spec versions

To support this, imported requests should store their **original OpenAPI path** (e.g., `/users/{id}`) separately from the full `urlTemplate`. This enables reliable matching even if the server prefix changes.

**Edge case — user-created requests**: When updating, only requests that were originally imported (have a stored OpenAPI path) participate in matching. Manually-added requests are never flagged as "removed" — they are left untouched.

## Resolved Questions

1. **Path parameter templating**: Convert `{param}` to `{{param}}` so it integrates with PostKit's variable substitution system.
2. **Removed endpoints**: Flag them in the conflict/diff view with Delete/Keep options per endpoint. User decides.
3. **Folder conflicts on update**: Move endpoints to the new folder to keep the collection in sync with the spec's tag assignments.
