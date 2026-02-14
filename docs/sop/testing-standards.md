# PostKit Testing Standards

> **Last updated:** 2026-02-14
> **Applies to:** All PostKit code changes
> **Framework:** Swift Testing (`import Testing`)

---

## Rule

Every new feature, service, model, or bug fix **must** include tests covering three categories:

1. **Positive cases** — Verify correct behavior with valid inputs
2. **Negative cases** — Verify proper error handling with invalid inputs
3. **Edge cases** — Verify behavior at boundaries and with unusual-but-valid inputs

A pull request without all three categories is incomplete.

---

## Test Structure

Tests live in `PostKitTests/PostKitTests.swift`, grouped by struct per feature area.

```swift
import Testing
import Foundation
@testable import PostKit

struct MyFeatureTests {
    // MARK: - Positive Cases

    @Test func validInputProducesExpectedOutput() {
        // ...
        #expect(result == expected)
    }

    // MARK: - Negative Cases

    @Test func invalidInputThrowsExpectedError() {
        #expect(throws: MyError.invalidInput) {
            try myFunction(invalid: true)
        }
    }

    // MARK: - Edge Cases

    @Test func emptyInputReturnsEmptyResult() {
        // ...
        #expect(result.isEmpty)
    }
}
```

Use `// MARK: - Positive Cases`, `// MARK: - Negative Cases`, and `// MARK: - Edge Cases` to separate the categories within each test struct.

---

## Category Guidelines

### Positive Cases

Test the happy path — the feature working as designed.

| What to cover | Example |
|---|---|
| Basic functionality | Parse a simple cURL → correct method, URL, headers |
| Multiple valid inputs | Parse GET, POST, PUT, DELETE variants |
| All supported variations | Bearer auth, Basic auth, API Key auth |
| Round-trip integrity | Encode `[KeyValuePair]` → decode → values match |
| Composed behavior | Variable interpolation with mixed user + built-in variables |

Minimum: **one test per public method or distinct behavior path**.

### Negative Cases

Test that failures produce correct, specific errors — not crashes or silent corruption.

| What to cover | Example |
|---|---|
| Invalid input format | `CurlParser.parse("wget ...")` → `CurlParserError.invalidCommand` |
| Missing required data | `CurlParser.parse("curl -X GET")` → `CurlParserError.missingURL` |
| Malformed data | `[KeyValuePair].decode(from: "not json".data(...))` → empty array |
| Unsupported values | OpenAPI version `2.0.0` → `OpenAPIParserError.unsupportedVersion` |
| Nil/missing input | `[KeyValuePair].decode(from: nil)` → empty array |

Use `#expect(throws: SpecificError.self)` to assert the exact error type:

```swift
@Test func rejectsInvalidCommand() {
    #expect(throws: CurlParserError.invalidCommand) {
        try parser.parse("wget https://example.com")
    }
}
```

Minimum: **one test per error case defined in the feature's error enum**.

### Edge Cases

Test boundaries, empty states, and unusual-but-valid scenarios.

| What to cover | Example |
|---|---|
| Empty input | Empty string, empty array, empty dictionary |
| Boundary values | Response exactly at 1MB threshold |
| Whitespace handling | `{{ name }}` with spaces inside braces |
| Repeated values | Same variable used multiple times in one template |
| Special characters | URLs with query params, passwords with `@!#$` |
| Multiline input | cURL commands with `\` line continuations |
| Default/fallback values | `KeyValuePair()` with no arguments → defaults apply |
| Identity uniqueness | Two identical-looking objects have distinct `id`s |
| Large input | 100+ headers, deeply nested JSON |

Minimum: **at least two edge cases per test struct**.

---

## Existing Test Examples

The current test suite demonstrates the pattern:

### CurlParserTests (18 tests)

| Category | Tests |
|---|---|
| Positive | `parseSimpleGet`, `parsePostWithJsonBody`, `parseSingleHeader`, `parseMultipleHeaders`, `parseLongFormFlags`, `parseBasicAuth`, `parseCompressedFlag`, `parseDataImpliesPostMethod`, `parseDataRaw`, `parseHTTPUrl`, `parseWithQueryParams` |
| Negative | `parseInvalidCommandThrows`, `parseEmptyStringThrows`, `parseMissingURLThrows` |
| Edge | `parseMultilineCommand`, `parseSilentAndLocationFlags`, `parseExplicitGetMethod`, `parsePostWithRawBody` |

### VariableInterpolatorTests (14 tests)

| Category | Tests |
|---|---|
| Positive | `interpolateSimpleVariable`, `interpolateMultipleVariables`, `interpolateBuiltIn*` (6 tests) |
| Negative | `interpolateMissingVariableLeavesTemplate` |
| Edge | `interpolateNoVariablesPassthrough`, `interpolateEmptyTemplate`, `interpolateVariableWithSpaces`, `interpolateMixedUserAndBuiltIn`, `interpolateSameVariableMultipleTimes` |

### KeyValuePairTests (7 tests)

| Category | Tests |
|---|---|
| Positive | `encodeDecodeRoundTrip`, `defaultValues`, `hashable` |
| Negative | `decodeNilDataReturnsEmpty`, `decodeInvalidDataReturnsEmpty` |
| Edge | `encodeEmptyArray`, `identifiableUniqueness` |

---

## Checklist

Before submitting a PR, verify:

- [ ] New test struct created (or existing struct extended) for the changed feature
- [ ] Positive cases cover every public method and distinct behavior path
- [ ] Negative cases cover every error type the feature can produce
- [ ] Edge cases cover empty inputs, boundaries, and unusual-but-valid scenarios
- [ ] All tests pass: `Cmd+U` in Xcode or `xcodebuild test -scheme PostKit -destination 'platform=macOS'`
- [ ] Tests use `#expect` (not `XCTAssert`) and `@Test` (not `func test*()`)
- [ ] Test struct uses `// MARK:` comments to separate positive, negative, and edge cases
