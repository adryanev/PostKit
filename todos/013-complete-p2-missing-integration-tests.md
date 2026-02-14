---
status: pending
priority: p2
issue_id: "013"
tags: [code-review, testing]
dependencies: []
---

# 013: Missing Integration Tests

## Problem Statement

The existing test suite covers helper functions (`parseHeaders`, `parseStatusMessage`, `sanitizeForCurl`) but lacks integration tests for the core HTTP client functionality. Critical paths such as `execute()`, cancellation flow, large response file spill, error mapping, and concurrent request handling have no test coverage. This means regressions in these areas will not be caught until manual testing or production use.

## Findings

- **File:** `PostKitTests/PostKitTests.swift`
- Current test coverage includes:
  - `CurlParserTests` -- parsing curl commands
  - `VariableInterpolatorTests` -- variable substitution
  - `KeyValuePairTests` -- key-value pair encoding/decoding
  - `AuthConfigTests` -- authentication configuration
  - `OpenAPIParserTests` -- OpenAPI import
- Missing test coverage:
  - `execute()` method on both `CurlHTTPClient` and `URLSessionHTTPClient`
  - Request cancellation (`cancel()` method)
  - Large response handling (file spill when response exceeds `maxMemorySize`)
  - Error mapping (`mapCurlError()` function, URLError to HTTPClientError mapping)
  - Concurrent request execution
  - Progress callback behavior
  - Header parsing from raw curl callbacks
  - Timeout behavior
- The project's testing standards document (`docs/sop/testing-standards.md`) requires "positive, negative, and edge cases" for every change.
- The PR introduces a new HTTP client implementation but no tests for it.

## Proposed Solutions

### Option A: Add MockHTTPServer-Based Integration Tests (Recommended)

Create a lightweight mock HTTP server using Swift's `Network` framework or a simple `URLProtocol` subclass that can return controlled responses:

```swift
struct CurlHTTPClientTests {
    @Test func executeSimpleGETRequest() async throws {
        let server = MockHTTPServer()
        server.respond(with: .ok, body: "Hello")
        let client = CurlHTTPClient()
        let response = try await client.execute(request, progress: nil)
        #expect(response.statusCode == 200)
    }

    @Test func cancellingRequestThrowsCancelled() async throws { ... }
    @Test func largeResponseSpillsToFile() async throws { ... }
    @Test func timeoutProducesTimeoutError() async throws { ... }
    @Test func concurrentRequestsExecuteInParallel() async throws { ... }
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Tests actual HTTP client behavior end-to-end; catches integration issues; can test timeouts, large responses, and error conditions; MockHTTPServer is reusable |
| **Cons** | More complex setup; mock server must handle concurrent connections; network tests can be flaky if not carefully designed |
| **Effort** | Medium to high |
| **Risk** | Low -- tests are additive and do not change production code |

### Option B: Add Unit Tests with Mock Curl Handle

Create a mock/stub for the curl handle that returns predetermined results, testing the logic around `curl_easy_perform` without actually making network calls:

```swift
struct CurlHTTPClientTests {
    @Test func mapCurlErrorMapsTimeoutCorrectly() {
        let error = mapCurlError(CURLE_OPERATION_TIMEDOUT)
        #expect(error == .timeout)
    }

    @Test func parseHeadersExtractsContentType() {
        let headers = parseHeaders(from: ["Content-Type: application/json"])
        #expect(headers["Content-Type"] == "application/json")
    }
}
```

| Aspect | Detail |
|--------|--------|
| **Pros** | Fast; no network dependency; tests pure logic (error mapping, header parsing); easy to write |
| **Cons** | Does not test actual HTTP execution; does not catch integration issues with libcurl; limited coverage of the execute() flow |
| **Effort** | Low to medium |
| **Risk** | Very low |

### Option C: Combine Both Approaches

Use unit tests for pure functions (error mapping, header parsing) and integration tests with a mock server for end-to-end flows:

| Aspect | Detail |
|--------|--------|
| **Pros** | Comprehensive coverage; fast unit tests for logic, thorough integration tests for flows; best of both worlds |
| **Cons** | More tests to write and maintain; highest effort |
| **Effort** | High |
| **Risk** | Very low |

## Recommended Action

_To be filled in after team review._

## Technical Details

- The project uses Swift Testing framework (`@Test`, `#expect`), not XCTest.
- All tests are in a single file: `PostKitTests/PostKitTests.swift`, grouped by struct with `// MARK:` separators.
- `HTTPClientProtocol` is the protocol both clients conform to, making it possible to write tests that work against either implementation.
- For mock server approaches, consider:
  - `URLProtocol` subclass (works for URLSession-based client but not for curl-based client)
  - `Network.framework` NWListener (works for both clients but requires actual TCP connections)
  - A simple Python/Node HTTP server launched as a subprocess
- For testing large response file spill, generate a response body larger than `maxMemorySize` (1MB) and verify that `bodyFileURL` is set and `body` is nil.
- For testing cancellation, start a request against a slow endpoint and call `cancel()` after a short delay.
- The `CurlHTTPClient` helper functions (`parseHeaders`, `parseStatusMessage`, `sanitizeForCurl`) that are already tested are global/static functions, separate from the HTTP client struct itself.

## Acceptance Criteria

- [ ] Tests exist for `execute()` with a simple GET request returning a successful response.
- [ ] Tests exist for request cancellation producing `HTTPClientError.cancelled`.
- [ ] Tests exist for large response file spill (response > 1MB uses `bodyFileURL`).
- [ ] Tests exist for error mapping (curl errors and/or URLSession errors map to correct `HTTPClientError` cases).
- [ ] Tests exist for concurrent request execution (multiple requests do not block each other).
- [ ] All new tests follow the project's testing standards (Swift Testing, positive/negative/edge cases).
- [ ] Tests are added to `PostKitTests.swift` following the existing structure.

## Work Log

| Date | Author | Action |
|------|--------|--------|
| 2026-02-14 | Code Review | Finding identified in PR #2 |

## Resources

- [Swift Testing framework](https://developer.apple.com/documentation/testing)
- [PostKit Testing Standards](../docs/sop/testing-standards.md)
- [URLProtocol for mocking](https://developer.apple.com/documentation/foundation/urlprotocol)
- [Network.framework NWListener](https://developer.apple.com/documentation/network/nwlistener)
