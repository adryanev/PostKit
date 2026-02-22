---
title: "feat: Auto-extract environment variables from OpenAPI imports"
type: feat
status: active
date: 2026-02-22
origin: docs/brainstorms/2026-02-22-openapi-variable-extraction-brainstorm.md
---

# feat: Auto-extract environment variables from OpenAPI imports

## Overview

When importing an OpenAPI spec, automatically extract server URLs, auth credentials, and server variables into PostKit environment variables. Each OpenAPI server definition becomes its own `APIEnvironment` with a `baseUrl` variable, auth credential variables, and server template variables. Requests use `{{baseUrl}}/path` instead of hardcoded URLs, enabling instant server switching via the environment picker.

## Problem Statement

Currently, the OpenAPI importer hardcodes the selected server URL into every request (e.g., `https://api.example.com/v1/users`). Users cannot switch between dev/staging/prod without re-importing. Auth types are detected but credential fields are empty with no environment variables to fill. This forces manual setup after every import. (see brainstorm: `docs/brainstorms/2026-02-22-openapi-variable-extraction-brainstorm.md`)

## Proposed Solution

1. **Replace hardcoded URLs with `{{baseUrl}}/path`** in all imported requests
2. **Create one `APIEnvironment` per OpenAPI server** with `baseUrl` set to the server's URL (trailing slashes stripped)
3. **Convert server URL template variables** (`{var}`) to PostKit's `{{var}}` syntax in `baseUrl` values
4. **Create auth variables** (`bearerToken`, `basicUsername`, `basicPassword`, `apiKeyValue`) based on security schemes
5. **Set `AuthConfig` fields to interpolation templates** (e.g., `token = "{{bearerToken}}"`) and modify `RequestBuilder.applyAuth()` to interpolate them
6. **On re-import**, preserve existing environments/values and only add new environments for new servers and missing variables

## Technical Approach

### Phase 1: Fix Existing Bug + Base URL Variable

**Fix `context.insert(variable)` bug (`OpenAPIImporter.swift:37-44`)**

The current code creates `Variable` objects for server variables but never calls `context.insert(v)`. The PostmanImporter correctly calls `context.insert(variable)` at line 107. Fix this first as all subsequent variable creation depends on it.

**Change request URL construction (`OpenAPIImporter.swift:134`)**

```swift
// Before:
let urlString = serverURL.isEmpty ? endpoint.path : serverURL + endpoint.path

// After:
let urlString = "{{baseUrl}}" + endpoint.path
```

The `serverURL` parameter is no longer needed for URL construction. Remove it from `createRequest()` and `updateRequest()`.

**Update `importNewCollection()` method signature (`OpenAPIImporter.swift:6-9`)**

```swift
// Before:
func importNewCollection(
    spec: OpenAPISpec,
    selectedEndpoints: [OpenAPIEndpoint],
    serverURL: String,
    into context: ModelContext
) throws -> RequestCollection

// After:
func importNewCollection(
    spec: OpenAPISpec,
    selectedEndpoints: [OpenAPIEndpoint],
    into context: ModelContext
) throws -> RequestCollection
```

Remove `serverURL` parameter since all servers become environments. Update callers in `OpenAPIImportViewModel.performImport()`.

**Create `baseUrl` variable in each environment (`OpenAPIImporter.swift:30-45`)**

For each server, create a `baseUrl` variable with the server URL as value. Apply `convertPathParameters()` to the server URL to convert any `{var}` to `{{var}}` syntax. Strip trailing slashes.

```swift
for (index, server) in spec.servers.enumerated() {
    let env = APIEnvironment(name: server.description ?? server.url)
    env.isActive = index == 0
    env.collection = collection
    context.insert(env)

    // baseUrl variable (trailing slash stripped, template vars converted)
    let rawURL = server.url.hasSuffix("/")
        ? String(server.url.dropLast())
        : server.url
    let convertedURL = convertServerURLVariables(rawURL)
    let baseUrlVar = Variable(key: "baseUrl", value: convertedURL, isSecret: false, isEnabled: true)
    baseUrlVar.environment = env
    context.insert(baseUrlVar)

    // Server template variables
    for variable in server.variables {
        let v = Variable(key: variable.name, value: variable.defaultValue, isSecret: false, isEnabled: true)
        v.environment = env
        context.insert(v)
    }
}
```

**Zero servers fallback:**

```swift
if spec.servers.isEmpty {
    let env = APIEnvironment(name: spec.info.title)
    env.isActive = true
    env.collection = collection
    context.insert(env)

    let baseUrlVar = Variable(key: "baseUrl", value: "", isSecret: false, isEnabled: true)
    baseUrlVar.environment = env
    context.insert(baseUrlVar)
}
```

**Add `convertServerURLVariables()` helper (`OpenAPIImporter.swift`)**

Reuse the same regex logic as `OpenAPIParser.convertPathParameters()`:

```swift
private func convertServerURLVariables(_ url: String) -> String {
    let pattern = "\\{(\\w+)\\}"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return url }
    let range = NSRange(url.startIndex..., in: url)
    return regex.stringByReplacingMatches(in: url, range: range, withTemplate: "{{$1}}")
}
```

**Files modified:**
- `PostKit/PostKit/Services/OpenAPIImporter.swift` — `importNewCollection()`, `createRequest()`, `updateRequest()`
- `PostKit/PostKit/ViewModels/OpenAPIImportViewModel.swift` — `performImport()` caller updates

### Phase 2: Auth Variable Creation + Pipeline Integration

**Create auth variables per environment (`OpenAPIImporter.swift`)**

Add a helper method that creates auth-related variables from security schemes:

```swift
private func createAuthVariables(
    from schemes: [OpenAPISecurityScheme],
    for environment: APIEnvironment,
    context: ModelContext
) {
    var createdKeys: Set<String> = []

    for scheme in schemes {
        switch scheme.type {
        case .http(let schemeName):
            if schemeName == "bearer" && !createdKeys.contains("bearerToken") {
                let v = Variable(key: "bearerToken", value: "", isSecret: true, isEnabled: true)
                v.environment = environment
                context.insert(v)
                createdKeys.insert("bearerToken")
            } else if schemeName == "basic" {
                if !createdKeys.contains("basicUsername") {
                    let u = Variable(key: "basicUsername", value: "", isSecret: false, isEnabled: true)
                    u.environment = environment
                    context.insert(u)
                    createdKeys.insert("basicUsername")
                }
                if !createdKeys.contains("basicPassword") {
                    let p = Variable(key: "basicPassword", value: "", isSecret: true, isEnabled: true)
                    p.environment = environment
                    context.insert(p)
                    createdKeys.insert("basicPassword")
                }
            }
        case .apiKey:
            if !createdKeys.contains("apiKeyValue") {
                let v = Variable(key: "apiKeyValue", value: "", isSecret: true, isEnabled: true)
                v.environment = environment
                context.insert(v)
                createdKeys.insert("apiKeyValue")
            }
        case .unsupported:
            break
        }
    }
}
```

Call this in the environment creation loop after server variables.

**Variable name collision guard:** Before creating `baseUrl` or auth variables, check if a server variable already has that key. Skip the auto-generated variable if a collision exists.

**Set `AuthConfig` fields to interpolation templates (`OpenAPIImporter.swift:234-261`)**

Modify `createAuthConfig()` to populate credential fields with template strings:

```swift
case .http(let schemeName):
    if schemeName == "bearer" {
        config.type = .bearer
        config.token = "{{bearerToken}}"
    } else if schemeName == "basic" {
        config.type = .basic
        config.username = "{{basicUsername}}"
        config.password = "{{basicPassword}}"
    }
case .apiKey(let name, let location):
    config.type = .apiKey
    config.apiKeyName = name
    config.apiKeyValue = "{{apiKeyValue}}"
    config.apiKeyLocation = location == "query" ? .queryParam : .header
```

**Modify `RequestBuilder.applyAuth()` to interpolate variables (`RequestBuilder.swift:94-116`)**

Update the method signature to accept variables and interpolate template values:

```swift
func applyAuth(
    _ urlRequest: inout URLRequest,
    authConfig: AuthConfig,
    variables: [String: String]
) {
    switch authConfig.type {
    case .bearer:
        if let token = authConfig.token {
            let resolved = (try? interpolator.interpolate(token, with: variables)) ?? token
            urlRequest.setValue("Bearer \(resolved)", forHTTPHeaderField: "Authorization")
        }
    case .basic:
        if let username = authConfig.username,
           let password = authConfig.password {
            let resolvedUser = (try? interpolator.interpolate(username, with: variables)) ?? username
            let resolvedPass = (try? interpolator.interpolate(password, with: variables)) ?? password
            let credentials = Data("\(resolvedUser):\(resolvedPass)".utf8).base64EncodedString()
            urlRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
    case .apiKey:
        if let name = authConfig.apiKeyName,
           let value = authConfig.apiKeyValue {
            let resolved = (try? interpolator.interpolate(value, with: variables)) ?? value
            if authConfig.apiKeyLocation == .header {
                urlRequest.setValue(resolved, forHTTPHeaderField: name)
            }
        }
    case .none:
        break
    }
}
```

Update the call site in `buildURLRequest()` (line 86) to pass `variables` through.

**Also update API Key query param path in `buildURLRequest()` (lines 42-48):**

The API Key query param handling reads `authConfig.apiKeyValue` directly without going through `applyAuth()`. It also needs interpolation:

```swift
if authConfig.type == .apiKey,
   authConfig.apiKeyLocation == .queryParam,
   let name = authConfig.apiKeyName,
   let value = authConfig.apiKeyValue {
    let resolved = (try? interpolator.interpolate(value, with: variables)) ?? value
    queryItems.append(URLQueryItem(name: name, value: resolved))
}
```

**Important:** The `variables` parameter is already available in `buildURLRequest(for:with:)` — just pass it through to `applyAuth()`.

Update `MenuBarView` which also calls `applyAuth()` or `buildURLRequest()`.

**Files modified:**
- `PostKit/PostKit/Services/OpenAPIImporter.swift` — `createAuthVariables()`, `createAuthConfig()`
- `PostKit/PostKit/Services/RequestBuilder.swift` — `applyAuth()`, `buildURLRequest()`
- `PostKit/PostKit/Views/MenuBar/MenuBarView.swift` — if it calls `applyAuth()` directly

### Phase 3: Re-Import Environment Preservation

**Add `openAPIServerURL` property to `APIEnvironment` model (`APIEnvironment.swift`)**

Add a stored property for matching environments to servers on re-import:

```swift
@Model
final class APIEnvironment {
    var id: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date
    var openAPIServerURL: String?  // NEW: for re-import matching

    @Relationship(deleteRule: .cascade, inverse: \Variable.environment)
    var variables: [Variable] = []
    var collection: RequestCollection?
}
```

Set this during import: `env.openAPIServerURL = server.url`

**Update `updateCollection()` to handle environments (`OpenAPIImporter.swift:51-122`)**

After processing endpoint decisions, handle environment updates:

```swift
// Match existing environments by openAPIServerURL, then by name
let existingEnvs = collection.environments
for server in spec.servers {
    let matchingEnv = existingEnvs.first { $0.openAPIServerURL == server.url }
        ?? existingEnvs.first { $0.name == (server.description ?? server.url) }

    if let env = matchingEnv {
        // Add missing variables only
        let existingKeys = Set(env.variables.map { $0.key })
        addMissingVariables(to: env, server: server, schemes: spec.securitySchemes,
                           existingKeys: existingKeys, context: context)
    } else {
        // New server: create new environment
        let env = APIEnvironment(name: server.description ?? server.url)
        env.isActive = false  // Don't change active environment on re-import
        env.openAPIServerURL = server.url
        env.collection = collection
        context.insert(env)
        // Create all variables (baseUrl, server vars, auth vars)
        createAllVariables(for: env, server: server, schemes: spec.securitySchemes, context: context)
    }
}
```

**Update `updateRequest()` to use `{{baseUrl}}` URLs (`OpenAPIImporter.swift:171-204`)**

When a `replaceExisting` decision is chosen, update the URL to use `{{baseUrl}}/path`:

```swift
let urlString = "{{baseUrl}}" + endpoint.path
```

For `keepExisting`, leave URLs as-is (user may have customized them).

**Update `updateCollection()` method signature** — remove `serverURL` parameter.

**Update `OpenAPIDiffEngine.diff()` and `createSnapshotFromEndpoint()` (`OpenAPIDiffEngine.swift:40-122`)**

Both methods accept `serverURL: String`. On re-import, pass `"{{baseUrl}}"` so that incoming snapshots use `{{baseUrl}}/path` URLs. This ensures the diff engine correctly identifies unchanged endpoints — without this, every endpoint would show as "changed" because the URL format shifted from hardcoded to templated.

The `createSnapshotFromRequest()` path (line 124+) reads from the stored `HTTPRequest` model, so requests imported with the new format will naturally match.

**Files modified:**
- `PostKit/PostKit/Models/APIEnvironment.swift` — add `openAPIServerURL` property
- `PostKit/PostKit/Services/OpenAPIImporter.swift` — `updateCollection()`, `updateRequest()`
- `PostKit/PostKit/ViewModels/OpenAPIImportViewModel.swift` — caller updates, pass `"{{baseUrl}}"` to diff engine
- `PostKit/PostKit/Services/OpenAPIDiffEngine.swift` — no signature change needed, just receives `"{{baseUrl}}"` from caller

### Phase 4: UI Updates

**Repurpose server picker in `ConfigureStepView` (`OpenAPIImportSheet.swift:288-383`)**

For **new imports**: replace the interactive server dropdown with a read-only preview:

```swift
if !spec.servers.isEmpty {
    VStack(alignment: .leading, spacing: 8) {
        Text("Environments to create:")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        ForEach(Array(spec.servers.enumerated()), id: \.offset) { index, server in
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(index == 0 ? .green : .secondary)
                Text(server.description ?? server.url)
                    .font(.subheadline)
                if index == 0 {
                    Text("(active)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(1 + server.variables.count) vars + auth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(8)
} else {
    // Zero servers: show fallback info
    HStack {
        Image(systemName: "info.circle")
        Text("No servers defined. A default environment will be created.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
```

For **updates**: hide the server section entirely (environments already exist).

**Remove `selectedServer` from `OpenAPIImportViewModel`** — it's no longer needed for new imports. For the diff engine in updates, pass `"{{baseUrl}}"` instead.

**Files modified:**
- `PostKit/PostKit/Views/Import/OpenAPIImportSheet.swift` — `ConfigureStepView`
- `PostKit/PostKit/ViewModels/OpenAPIImportViewModel.swift` — remove `selectedServer`

### Phase 5: Tests

Create `OpenAPIImporterTests` in `PostKitTests/PostKitTests.swift` or as a new file. The importer requires a real `ModelContext` — follow the pattern from `PostmanImporterTests` using in-memory `ModelContainer`.

**Test cases for `importNewCollection()`:**
- `importCreatesOneEnvironmentPerServer` — spec with 2 servers, verify 2 environments with correct names and `baseUrl` values
- `importSetsFirstEnvironmentActive` — verify `isActive` flags
- `importCreatesBaseUrlVariable` — verify `baseUrl` variable exists with correct value in each environment
- `importStripsTrailingSlashFromBaseUrl` — server URL `https://api.example.com/v1/` becomes `https://api.example.com/v1`
- `importConvertsServerURLTemplateVariables` — `https://{env}.api.example.com` becomes `https://{{env}}.api.example.com`
- `importCreatesServerVariables` — server with `{port}` variable creates `port` variable with default value
- `importCreatesBearerTokenVariable` — bearer security scheme creates `bearerToken` (secret)
- `importCreatesBasicAuthVariables` — basic auth creates `basicUsername` (not secret) and `basicPassword` (secret)
- `importCreatesApiKeyVariable` — API key scheme creates `apiKeyValue` (secret)
- `importSetsAuthConfigTemplates` — verify `AuthConfig.token = "{{bearerToken}}"` on imported requests
- `importRequestsUseBaseUrlVariable` — requests have URL `{{baseUrl}}/path`, not hardcoded
- `importZeroServersCreatesFallbackEnvironment` — empty servers array creates one environment with empty `baseUrl`
- `importSkipsVariableOnNameCollision` — server variable named `baseUrl` takes precedence over auto-generated `baseUrl`
- `importMultipleSecuritySchemes` — spec with Bearer + API Key creates both variable sets

**Test cases for `updateCollection()`:**
- `updatePreservesExistingEnvironmentValues` — re-import doesn't overwrite user-entered variable values
- `updateAddsMissingVariables` — new security scheme in spec adds variables to existing environments
- `updateCreatesNewEnvironmentForNewServer` — new server in spec creates new environment
- `updateDoesNotDeleteRemovedServerEnvironments` — removed server's environment is kept
- `updateReplacedRequestsUseBaseUrlVariable` — replaced requests get `{{baseUrl}}/path` URLs

**Test cases for `RequestBuilder.applyAuth()`:**
- `applyAuthInterpolatesBearerToken` — `{{bearerToken}}` resolved from variables
- `applyAuthInterpolatesBasicCredentials` — `{{basicUsername}}` and `{{basicPassword}}` resolved
- `applyAuthInterpolatesApiKeyValue` — `{{apiKeyValue}}` resolved
- `applyAuthFallsBackToLiteralIfNoVariable` — unresolved templates pass through

**Files created/modified:**
- `PostKit/PostKitTests/PostKitTests.swift` — add `OpenAPIImporterTests` struct with `// MARK: - OpenAPI Importer Tests`
- OR `PostKit/PostKitTests/OpenAPIImporterTests.swift` — new file if test file is too large

## System-Wide Impact

- **RequestBuilder.applyAuth()**: Signature changes to accept `variables` parameter. All callers (`buildURLRequest`, `MenuBarView`) must pass variables through. Non-OpenAPI requests with manually-entered auth values (no `{{}}` templates) continue to work because the interpolator returns non-template strings unchanged.
- **Existing OpenAPI imports**: Previously imported collections are unaffected — they keep their hardcoded URLs. Only new imports and `replaceExisting` re-import decisions use the new `{{baseUrl}}` format.
- **`APIEnvironment` model change**: Adding `openAPIServerURL` property requires SwiftData to handle the schema migration. SwiftData handles lightweight migrations (adding optional properties) automatically — no manual migration code needed.
- **Global environment scope**: The existing limitation where `isActive` is global (not collection-scoped) still applies. This feature amplifies it since every import creates multiple environments. Documented as a known limitation — separate feature to fix.

## Acceptance Criteria

- [x] Imported requests use `{{baseUrl}}/path` format, not hardcoded server URLs
- [x] Each OpenAPI server creates a separate `APIEnvironment` with `baseUrl` variable
- [x] First environment is set as active
- [x] Server URL template variables (`{var}`) converted to `{{var}}` in `baseUrl` values
- [x] Trailing slashes stripped from `baseUrl` values
- [x] Bearer auth creates `bearerToken` (secret) variable per environment
- [x] Basic auth creates `basicUsername` (not secret) and `basicPassword` (secret) variables
- [x] API Key auth creates `apiKeyValue` (secret) variable
- [x] `AuthConfig` fields contain interpolation templates (e.g., `token = "{{bearerToken}}"`)
- [x] `RequestBuilder.applyAuth()` interpolates auth templates from environment variables
- [x] Zero-server specs create a fallback environment with empty `baseUrl`
- [x] Re-import preserves existing environment values (never overwrites user data)
- [x] Re-import creates new environments for new servers in the spec
- [x] Re-import adds missing variables to existing environments
- [x] Server picker in import wizard shows read-only environment preview (new imports)
- [x] Server picker hidden for update imports
- [x] Variable name collisions with server variables handled (skip auto-generated)
- [x] `context.insert(variable)` bug fixed for all variable creation
- [x] All test cases pass (see Phase 5)

## Dependencies & Risks

- **SwiftData lightweight migration**: Adding `openAPIServerURL: String?` to `APIEnvironment` is an optional property addition — SwiftData handles this automatically. No migration code needed.
- **`applyAuth()` signature change**: This is a breaking change to an internal API. All callers must be updated. The `variables` parameter is already available at every call site (it's passed to `buildURLRequest()`), so this is straightforward.
- **Existing auth behavior**: Non-OpenAPI requests with manually entered auth values will pass through the interpolator, but since they don't contain `{{}}` templates, the interpolator returns them unchanged. No behavior change for existing requests.
- **Global `isActive` scope**: Multiple imports creating multiple environments could lead to confusion. Mitigated by only setting `isActive = true` on first import, and never changing active state on re-import.

## Known Limitations

- **Global environment scope**: The `EnvironmentPicker` shows environments from all collections, not scoped to the active collection. Separate feature to address.
- **Multiple API Key schemes**: If a spec defines two different API Key security schemes, a single `apiKeyValue` variable cannot distinguish between them. Document this limitation.
- **No variable deletion in editor**: The `EnvironmentVariablesEditor` lacks a delete button. Users cannot remove individual auto-created variables. Separate feature.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-02-22-openapi-variable-extraction-brainstorm.md](docs/brainstorms/2026-02-22-openapi-variable-extraction-brainstorm.md) — Key decisions: `baseUrl` variable name, one env per server, auth variable naming, secret-by-default for credentials.

### Internal References

- `OpenAPIImporter.swift:6-49` — `importNewCollection()` (primary modification target)
- `OpenAPIImporter.swift:126-134` — `createRequest()` URL construction
- `OpenAPIImporter.swift:234-261` — `createAuthConfig()` (add template values)
- `RequestBuilder.swift:94-116` — `applyAuth()` (add interpolation)
- `OpenAPIParser.swift:297-310` — `convertPathParameters()` (reference for URL variable conversion)
- `PostmanImporter.swift:92-113` — Variable creation pattern (reference)
- `Variable.swift:36-57` — `secureValue` computed property (Keychain integration)
- `docs/solutions/integration-issues/infinite-rerender-factory-di-20260214.md` — `@ObservationIgnored @Injected` pattern (relevant if ViewModel adds injected dependencies)
