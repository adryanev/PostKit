# OpenAPI Full Variable Extraction

**Date:** 2026-02-22
**Status:** Ready for planning
**Author:** Brainstorm session

## What We're Building

When importing an OpenAPI spec, automatically extract all configurable values into PostKit environment variables so users can switch between servers (dev/staging/prod) and fill in credentials without editing individual requests.

### Current Behavior

- Server base URL is **hardcoded** into each request (e.g., `https://api.example.com/v1/users`)
- OpenAPI server variables (e.g., `{environment}`) are created as `Variable` instances but the base URL itself isn't a variable
- Path parameters (`{userId}`) are correctly converted to `{{userId}}`
- Auth types are detected (Bearer, Basic, API Key) but credential fields are left empty with no corresponding environment variables
- Multiple servers in the spec: user picks one at import time, the chosen URL is baked into all requests

### Desired Behavior

- **Base URL as variable:** Requests use `{{baseUrl}}/path` instead of hardcoded URLs
- **One environment per server:** Each OpenAPI server definition becomes a PostKit `APIEnvironment` with its own `baseUrl` value. First server is set as active.
- **Auth variables auto-created:** Based on the security scheme, create pre-named variables:
  - Bearer auth → `{{bearerToken}}` (secret)
  - Basic auth → `{{basicUsername}}`, `{{basicPassword}}` (password is secret)
  - API Key → `{{apiKeyValue}}` (secret)
- **Server variables included:** OpenAPI server variables (e.g., `{port}`, `{basePath}`) are also added to each environment
- **Auth secrets auto-marked:** Auth-related variables are marked as `isSecret = true` by default (stored in Keychain)

## Why This Approach

### One Environment Per Server

This maps naturally to real-world workflows: developers have separate credentials and base URLs for dev, staging, and production. Switching environments in PostKit's toolbar instantly reconfigures all requests — no manual URL editing needed.

### `{{baseUrl}}` Convention

- Matches Postman's convention, making it familiar to users migrating from Postman
- Short, clear, and recognizable
- Already the most common variable name in HTTP client tools

### Auto-Secret Auth Variables

Auth credentials are inherently sensitive. Defaulting to secret (Keychain storage) prevents accidental exposure in exports or screen shares. Users can always un-mark them if desired.

## Key Decisions

1. **Variable name for server URL:** `baseUrl` (matches Postman convention)
2. **Server → Environment mapping:** One `APIEnvironment` per OpenAPI server definition; first server is active
3. **Auth variable naming:**
   - Bearer: `bearerToken`
   - Basic: `basicUsername`, `basicPassword`
   - API Key: `apiKeyValue`
4. **Secret by default:** Auth credential variables (`bearerToken`, `basicPassword`, `apiKeyValue`) are `isSecret = true`. Non-credential variables like `basicUsername` are not secret.
5. **Request URL format:** `{{baseUrl}}/api/users` (variable + path)
6. **Path params:** Already handled by `convertPathParameters()` — no change needed

## Edge Cases

- **Zero servers in spec:** OpenAPI 3.x allows an empty `servers` array (implies relative paths against the host). In this case, create one environment named after the spec title with `baseUrl = ""` so the variable still exists for the user to fill in.
- **Multiple security schemes:** If a spec defines more than one scheme (e.g., both Bearer and API Key), create variables for all of them. Use plain names (`bearerToken`, `apiKeyValue`) since they're differentiated by type, not by scheme name.
- **Re-import (update flow):** `updateCollection` currently does not touch environments. On re-import: leave existing environments and their variable *values* intact (user may have filled in credentials). Only add new variables that didn't exist before (e.g., if the spec adds a new security scheme). Never delete or overwrite user-entered values.
- **Trailing slash normalization:** Server URLs may end with `/` while paths start with `/`. Strip trailing slashes from `baseUrl` values during import to avoid `{{baseUrl}}//users` double-slash issues.

## Scope

### In Scope

- Modify `OpenAPIImporter.importNewCollection()` to use `{{baseUrl}}` in request URLs
- Modify `OpenAPIImporter.importNewCollection()` to create auth variables per environment
- Modify `OpenAPIImporter.updateCollection()` to preserve existing environments and add missing variables on re-import
- Repurpose server picker in `ConfigureStepView` as a read-only preview showing which environments will be created (for new imports) or keep it hidden (for updates, since environments already exist)
- Ensure existing `VariableInterpolator` resolves `{{baseUrl}}` correctly (should work as-is)

### Out of Scope

- Variable scoping (global vs. collection vs. request level) — separate feature
- Variable validation/preview in the request editor — separate feature
- Deleting individual variables in the environment editor — separate feature (known gap)

## Open Questions

None — all key decisions resolved during brainstorm.
