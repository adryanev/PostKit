# Automated Test Coverage for PostKit

**Date:** 2026-02-17
**Status:** Brainstorm Complete

## What We're Building

A comprehensive automated test suite that eliminates the need for manual testing of PostKit. This covers three layers:

1. **Mock Foundation** — Mock implementations for all 7 unmocked service protocols, enabling isolated and deterministic testing
2. **Unit/Integration Tests** — Test suites for all untested services (`PostmanImporter`, `FileExporter`, `OpenAPIImporter`, `RequestBuilder`) and ViewModels (`OpenAPIImportViewModel`)
3. **UI Tests (XCUITest)** — End-to-end tests for all major user flows: core request flow, import workflows, and environment management

## Why This Approach (Bottom-Up Mock Foundation)

We chose a bottom-up approach — mocks first, then service tests, then ViewModel tests, then UI tests — for these reasons:

- **Solid foundation:** Mock implementations are reusable across all test types and enable deterministic, fast tests
- **Aligns with existing patterns:** PostKit already uses Factory DI with protocol-based services — mocks plug in naturally
- **Maintainable:** Each layer builds on the previous one. Unit tests catch logic bugs fast; UI tests validate user flows
- **Mock-only networking:** All HTTP tests use `MockHTTPClient`. No real network calls, no flakiness

### Alternatives Considered

- **UI-First (Approach B):** Would immediately test manual flows but results in brittle tests without unit coverage underneath. Harder to diagnose failures.
- **Parallel Tracks (Approach C):** Fastest calendar time but requires coordination. UI tests may need rewriting when mock infrastructure stabilizes.

## Key Decisions

1. **Mock-only for HTTP:** All network interactions use `MockHTTPClient`. No local test server or recorded responses.
2. **Bottom-up order:** Mocks → Service unit tests → ViewModel tests → XCUITests
3. **All major UI flows covered:** Core request (create, edit, send, view response), import (Postman, OpenAPI), and environment management (create, switch, variables, interpolation)
4. **Swift Testing framework:** Continue using `@Test` / `#expect` for all unit/integration tests (not XCTest)
5. **XCUITest for UI layer:** Use Apple's XCUITest framework for UI automation tests (separate test target)
6. **Follow existing test standards:** Positive, negative, and edge cases per `docs/sop/testing-standards.md`

## Scope

### Phase 1: Mock Foundation

Create mock implementations for all unmocked protocols:

| Protocol | Mock Name | Key Behaviors to Mock |
|---|---|---|
| `FileExporterProtocol` | `MockFileExporter` | Return pre-built export data, track export/import calls |
| `ScriptEngineProtocol` | `MockScriptEngine` | Return configurable script results, track execution calls |
| `SpotlightIndexerProtocol` | `MockSpotlightIndexer` | No-op with call tracking |
| `CurlParserProtocol` | `MockCurlParser` | Return configurable parse results |
| `OpenAPIParserProtocol` | `MockOpenAPIParser` | Return configurable parse results |
| `PostmanParserProtocol` | `MockPostmanParser` | Return configurable parse results, environments |
| `VariableInterpolatorProtocol` | `MockVariableInterpolator` | Return input unchanged or configurable result |

### Phase 2: Service Unit Tests

Add test suites for untested services:

| Service | Test Focus |
|---|---|
| `PostmanImporter` | Auth mapping (all types), body mode conversion (raw, urlencoded, formdata, graphql), folder depth limiting, script extraction, environment import, error handling |
| `FileExporter` | Sensitive header redaction, collection export format, import round-trip, empty/edge cases |
| `OpenAPIImporter` | Collection creation from parsed specs, endpoint mapping, parameter handling |
| `RequestBuilder` | `buildURLRequest` with all parameter combinations, `applyAuth` for all auth types, `getActiveEnvironmentVariables`, override parameters |

### Phase 3: ViewModel Tests

| ViewModel | Test Focus |
|---|---|
| `OpenAPIImportViewModel` | Step navigation, spec parsing delegation, diff preview, collection create/update, error states |
| `RequestViewModel` (expand) | Script execution integration, variable interpolation flows, environment switching, Spotlight indexing calls |

### Phase 4: XCUITest Target

Create a new `PostKitUITests` target with tests for:

| Flow | Test Scenarios |
|---|---|
| **Core Request** | Create request, set URL/method/headers/body, send request, verify response display, check history entry |
| **Postman Import** | Import a collection file, verify folder structure, verify requests with auth/headers/body |
| **OpenAPI Import** | Import a spec file, verify wizard steps, verify created collection |
| **Environment Management** | Create environment, add variables, switch environments, verify interpolation in requests |

## Current Test Inventory (Baseline)

- **185 tests** across 13 test structs in `PostKitTests.swift`
- **2 mocks:** `MockHTTPClient`, `MockKeychainManager`
- **Well-tested:** All parsers, VariableInterpolator, JavaScriptEngine, KeyValuePair, AuthConfig, syntax highlighting, basic RequestViewModel
- **Zero tests:** PostmanImporter, FileExporter, OpenAPIImporter, OpenAPIImportViewModel, RequestBuilder, SpotlightIndexer

## Open Questions

None — all key decisions resolved during brainstorming.
