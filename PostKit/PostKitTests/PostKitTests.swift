//
//  PostKitTests.swift
//  PostKitTests
//
//  Created by Adryan Eka Vandra on 06/01/26.
//

import Testing
import Foundation
@testable import PostKit

// MARK: - CurlParser Tests

struct CurlParserTests {
    let parser = CurlParser()

    @Test func parseSimpleGet() throws {
        let result = try parser.parse("curl https://api.example.com/users")
        #expect(result.method == .get)
        #expect(result.url == "https://api.example.com/users")
        #expect(result.headers.isEmpty)
        #expect(result.body == nil)
        #expect(result.bodyType == .none)
    }

    @Test func parseExplicitGetMethod() throws {
        let result = try parser.parse("curl -X GET https://api.example.com/items")
        #expect(result.method == .get)
        #expect(result.url == "https://api.example.com/items")
    }

    @Test func parsePostWithJsonBody() throws {
        let result = try parser.parse(
            #"curl -X POST https://api.example.com/users -d '{"name":"Alice","email":"alice@example.com"}'"#
        )
        #expect(result.method == .post)
        #expect(result.url == "https://api.example.com/users")
        #expect(result.body == #"{"name":"Alice","email":"alice@example.com"}"#)
        #expect(result.bodyType == .json)
    }

    @Test func parsePostWithRawBody() throws {
        let result = try parser.parse(
            "curl -X POST https://api.example.com/data -d 'key=value&foo=bar'"
        )
        #expect(result.method == .post)
        #expect(result.body == "key=value&foo=bar")
        #expect(result.bodyType == .raw)
    }

    @Test func parseDataImpliesPostMethod() throws {
        // When -d is provided without -X, method should default to POST
        let result = try parser.parse(
            #"curl https://api.example.com/submit -d '{"action":"create"}'"#
        )
        #expect(result.method == .post)
        #expect(result.body == #"{"action":"create"}"#)
        #expect(result.bodyType == .json)
    }

    @Test func parseSingleHeader() throws {
        let result = try parser.parse(
            "curl -H 'Content-Type: application/json' https://api.example.com/data"
        )
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Content-Type")
        #expect(result.headers[0].value == "application/json")
    }

    @Test func parseMultipleHeaders() throws {
        let result = try parser.parse(
            "curl -H 'Content-Type: application/json' -H 'Authorization: Bearer tok123' https://api.example.com/data"
        )
        #expect(result.headers.count == 2)
        #expect(result.headers[0].key == "Content-Type")
        #expect(result.headers[0].value == "application/json")
        #expect(result.headers[1].key == "Authorization")
        #expect(result.headers[1].value == "Bearer tok123")
    }

    @Test func parseLongFormFlags() throws {
        let result = try parser.parse(
            "curl --request PUT --header 'Accept: text/html' https://api.example.com/resource"
        )
        #expect(result.method == .put)
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Accept")
        #expect(result.headers[0].value == "text/html")
    }

    @Test func parseBasicAuth() throws {
        let result = try parser.parse(
            "curl -u admin:secret123 https://api.example.com/secure"
        )
        #expect(result.authConfig?.type == .basic)
        #expect(result.authConfig?.username == "admin")
        #expect(result.authConfig?.password == "secret123")
    }

    @Test func parseCompressedFlag() throws {
        let result = try parser.parse(
            "curl --compressed https://api.example.com/data"
        )
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Accept-Encoding")
        #expect(result.headers[0].value == "gzip, deflate")
    }

    @Test func parseSilentAndLocationFlags() throws {
        let result = try parser.parse(
            "curl -s -L https://api.example.com/redirect"
        )
        #expect(result.url == "https://api.example.com/redirect")
        #expect(result.headers.isEmpty)
    }

    @Test func parseMultilineCommand() throws {
        let command = """
        curl \
          -X DELETE \
          -H 'Authorization: Bearer token' \
          https://api.example.com/items/42
        """
        let result = try parser.parse(command)
        #expect(result.method == .delete)
        #expect(result.url == "https://api.example.com/items/42")
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Authorization")
    }

    @Test func parseInvalidCommandThrows() throws {
        #expect(throws: CurlParserError.invalidCommand) {
            try parser.parse("wget https://example.com")
        }
    }

    @Test func parseEmptyStringThrows() throws {
        #expect(throws: CurlParserError.invalidCommand) {
            try parser.parse("")
        }
    }

    @Test func parseMissingURLThrows() throws {
        #expect(throws: CurlParserError.missingURL) {
            try parser.parse("curl -X GET -H 'Accept: text/html'")
        }
    }

    @Test func parseWithQueryParams() throws {
        let result = try parser.parse(
            "curl https://api.example.com/search?q=swift&page=1&limit=20"
        )
        #expect(result.method == .get)
        #expect(result.url == "https://api.example.com/search?q=swift&page=1&limit=20")
    }

    @Test func parseHTTPUrl() throws {
        let result = try parser.parse("curl http://localhost:3000/api/health")
        #expect(result.url == "http://localhost:3000/api/health")
    }

    @Test func parseDataRaw() throws {
        let result = try parser.parse(
            #"curl --data-raw '{"id": 1}' https://api.example.com/create"#
        )
        #expect(result.method == .post)
        #expect(result.body == #"{"id": 1}"#)
        #expect(result.bodyType == .json)
    }
}

// MARK: - VariableInterpolator Tests

struct VariableInterpolatorTests {
    let interpolator = VariableInterpolator()

    @Test func interpolateSimpleVariable() throws {
        let result = try interpolator.interpolate(
            "Hello, {{name}}!",
            with: ["name": "World"]
        )
        #expect(result == "Hello, World!")
    }

    @Test func interpolateMultipleVariables() throws {
        let result = try interpolator.interpolate(
            "{{greeting}}, {{name}}! Welcome to {{place}}.",
            with: ["greeting": "Hi", "name": "Alice", "place": "PostKit"]
        )
        #expect(result == "Hi, Alice! Welcome to PostKit.")
    }

    @Test func interpolateMissingVariableLeavesTemplate() throws {
        // Missing variables should be left as their {{key}} template form
        let result = try interpolator.interpolate(
            "Token: {{auth_token}}",
            with: [:]
        )
        #expect(result == "Token: {{auth_token}}")
    }

    @Test func interpolateNoVariablesPassthrough() throws {
        let template = "This is plain text without any variables."
        let result = try interpolator.interpolate(template, with: ["unused": "value"])
        #expect(result == template)
    }

    @Test func interpolateEmptyTemplate() throws {
        let result = try interpolator.interpolate("", with: ["key": "value"])
        #expect(result == "")
    }

    @Test func interpolateBuiltInTimestamp() throws {
        let before = Int(Date().timeIntervalSince1970 * 1000)
        let result = try interpolator.interpolate("ts={{$timestamp}}", with: [:])
        let after = Int(Date().timeIntervalSince1970 * 1000)

        // Extract the numeric portion after "ts="
        let timestampString = String(result.dropFirst(3))
        let timestamp = Int(timestampString)
        #expect(timestamp != nil)
        #expect(timestamp! >= before)
        #expect(timestamp! <= after)
    }

    @Test func interpolateBuiltInUUID() throws {
        let result = try interpolator.interpolate("id={{$uuid}}", with: [:])
        let uuidString = String(result.dropFirst(3))
        #expect(UUID(uuidString: uuidString) != nil)
    }

    @Test func interpolateBuiltInGuid() throws {
        let result = try interpolator.interpolate("id={{$guid}}", with: [:])
        let uuidString = String(result.dropFirst(3))
        #expect(UUID(uuidString: uuidString) != nil)
    }

    @Test func interpolateBuiltInRandomInt() throws {
        let result = try interpolator.interpolate("num={{$randomInt}}", with: [:])
        let numString = String(result.dropFirst(4))
        let num = Int(numString)
        #expect(num != nil)
        #expect(num! >= 0)
        #expect(num! <= 999999)
    }

    @Test func interpolateBuiltInIsoTimestamp() throws {
        let result = try interpolator.interpolate("time={{$isoTimestamp}}", with: [:])
        let isoString = String(result.dropFirst(5))
        let formatter = ISO8601DateFormatter()
        #expect(formatter.date(from: isoString) != nil)
    }

    @Test func interpolateBuiltInRandomString() throws {
        let result = try interpolator.interpolate("rand={{$randomString}}", with: [:])
        let randomStr = String(result.dropFirst(5))
        #expect(randomStr.count == 16)
        // Should only contain lowercase letters
        #expect(randomStr.allSatisfy { $0.isLowercase && $0.isLetter })
    }

    @Test func interpolateVariableWithSpaces() throws {
        // The parser trims whitespace inside braces
        let result = try interpolator.interpolate(
            "Value: {{ name }}",
            with: ["name": "trimmed"]
        )
        #expect(result == "Value: trimmed")
    }

    @Test func interpolateMixedUserAndBuiltIn() throws {
        let result = try interpolator.interpolate(
            "{{baseUrl}}/items?ts={{$timestamp}}",
            with: ["baseUrl": "https://api.test.com"]
        )
        #expect(result.hasPrefix("https://api.test.com/items?ts="))
        let tsString = String(result.split(separator: "=").last!)
        #expect(Int(tsString) != nil)
    }

    @Test func interpolateSameVariableMultipleTimes() throws {
        let result = try interpolator.interpolate(
            "{{sep}}A{{sep}}B{{sep}}",
            with: ["sep": "-"]
        )
        #expect(result == "-A-B-")
    }
}

// MARK: - KeyValuePair Tests

struct KeyValuePairTests {
    @Test func encodeDecodeRoundTrip() throws {
        let pairs = [
            KeyValuePair(key: "Content-Type", value: "application/json", isEnabled: true),
            KeyValuePair(key: "Authorization", value: "Bearer abc123", isEnabled: false),
        ]

        let data = pairs.encode()
        #expect(data != nil)

        let decoded = [KeyValuePair].decode(from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].key == "Content-Type")
        #expect(decoded[0].value == "application/json")
        #expect(decoded[0].isEnabled == true)
        #expect(decoded[1].key == "Authorization")
        #expect(decoded[1].value == "Bearer abc123")
        #expect(decoded[1].isEnabled == false)
    }

    @Test func encodeEmptyArray() throws {
        let pairs: [KeyValuePair] = []
        let data = pairs.encode()
        #expect(data != nil)

        let decoded = [KeyValuePair].decode(from: data)
        #expect(decoded.isEmpty)
    }

    @Test func decodeNilDataReturnsEmpty() {
        let decoded = [KeyValuePair].decode(from: nil)
        #expect(decoded.isEmpty)
    }

    @Test func decodeInvalidDataReturnsEmpty() {
        let invalidData = "not json".data(using: .utf8)!
        let decoded = [KeyValuePair].decode(from: invalidData)
        #expect(decoded.isEmpty)
    }

    @Test func defaultValues() {
        let pair = KeyValuePair()
        #expect(pair.key == "")
        #expect(pair.value == "")
        #expect(pair.isEnabled == true)
    }

    @Test func identifiableUniqueness() {
        let a = KeyValuePair(key: "same", value: "same")
        let b = KeyValuePair(key: "same", value: "same")
        #expect(a.id != b.id)
    }

    @Test func hashable() {
        let pair = KeyValuePair(key: "X", value: "Y")
        var set: Set<KeyValuePair> = []
        set.insert(pair)
        #expect(set.contains(pair))
    }
}

// MARK: - AuthConfig Tests

struct AuthConfigTests {
    @Test func defaultConfig() {
        let config = AuthConfig()
        #expect(config.type == .none)
        #expect(config.token == nil)
        #expect(config.username == nil)
        #expect(config.password == nil)
        #expect(config.apiKeyName == nil)
        #expect(config.apiKeyValue == nil)
        #expect(config.apiKeyLocation == nil)
    }

    @Test func encodeDecodeBearer() throws {
        var config = AuthConfig(type: .bearer)
        config.token = "eyJhbGciOiJIUzI1NiJ9.test.signature"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .bearer)
        #expect(decoded.token == "eyJhbGciOiJIUzI1NiJ9.test.signature")
        #expect(decoded.username == nil)
        #expect(decoded.password == nil)
    }

    @Test func encodeDecodeBasic() throws {
        var config = AuthConfig(type: .basic)
        config.username = "admin"
        config.password = "p@ssw0rd!"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .basic)
        #expect(decoded.username == "admin")
        #expect(decoded.password == "p@ssw0rd!")
        #expect(decoded.token == nil)
    }

    @Test func encodeDecodeAPIKeyHeader() throws {
        var config = AuthConfig(type: .apiKey)
        config.apiKeyName = "X-API-Key"
        config.apiKeyValue = "sk-abc123xyz"
        config.apiKeyLocation = .header

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .apiKey)
        #expect(decoded.apiKeyName == "X-API-Key")
        #expect(decoded.apiKeyValue == "sk-abc123xyz")
        #expect(decoded.apiKeyLocation == .header)
    }

    @Test func encodeDecodeAPIKeyQueryParam() throws {
        var config = AuthConfig(type: .apiKey)
        config.apiKeyName = "api_key"
        config.apiKeyValue = "key-456"
        config.apiKeyLocation = .queryParam

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .apiKey)
        #expect(decoded.apiKeyName == "api_key")
        #expect(decoded.apiKeyValue == "key-456")
        #expect(decoded.apiKeyLocation == .queryParam)
    }

    @Test func authTypeDisplayNames() {
        #expect(AuthType.none.displayName == "No Auth")
        #expect(AuthType.bearer.displayName == "Bearer Token")
        #expect(AuthType.basic.displayName == "Basic Auth")
        #expect(AuthType.apiKey.displayName == "API Key")
    }

    @Test func authTypeRawValues() {
        #expect(AuthType.none.rawValue == "none")
        #expect(AuthType.bearer.rawValue == "bearer")
        #expect(AuthType.basic.rawValue == "basic")
        #expect(AuthType.apiKey.rawValue == "api-key")
    }

    @Test func authTypeCaseIterable() {
        #expect(AuthType.allCases.count == 4)
    }
}

// MARK: - OpenAPIParser Tests

struct OpenAPIParserTests {
    let parser = OpenAPIParser()

    @Test func parseMinimalSpec() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "Test API", "version": "1.0.0"],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        let (info, endpoints, servers) = try parser.parse(data)
        #expect(info.title == "Test API")
        #expect(info.version == "1.0.0")
        #expect(info.description == nil)
        #expect(endpoints.isEmpty)
        #expect(servers.isEmpty)
    }

    @Test func parseWithServers() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.1",
            "info": ["title": "API", "version": "2.0"],
            "servers": [
                ["url": "https://api.prod.example.com"],
                ["url": "https://api.staging.example.com"],
            ],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        let (_, _, servers) = try parser.parse(data)
        #expect(servers.count == 2)
        #expect(servers[0] == "https://api.prod.example.com")
        #expect(servers[1] == "https://api.staging.example.com")
    }

    @Test func parseEndpointWithOperationId() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users": [
                    "get": [
                        "operationId": "listUsers",
                        "summary": "List all users",
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        let (_, endpoints, _) = try parser.parse(data)
        #expect(endpoints.count == 1)
        #expect(endpoints[0].name == "listUsers")
        #expect(endpoints[0].method == .get)
        #expect(endpoints[0].path == "/users")
    }

    @Test func parseEndpointWithParameters() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users/{id}": [
                    "get": [
                        "operationId": "getUser",
                        "parameters": [
                            ["name": "id", "in": "path"],
                            ["name": "include", "in": "query"],
                        ],
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        let (_, endpoints, _) = try parser.parse(data)
        #expect(endpoints.count == 1)
        #expect(endpoints[0].parameters.count == 2)
        #expect(endpoints[0].parameters[0].name == "id")
        #expect(endpoints[0].parameters[0].location == "path")
        #expect(endpoints[0].parameters[1].name == "include")
        #expect(endpoints[0].parameters[1].location == "query")
    }

    @Test func parseEndpointWithRequestBody() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users": [
                    "post": [
                        "operationId": "createUser",
                        "requestBody": [
                            "content": [
                                "application/json": [
                                    "schema": ["type": "object"]
                                ]
                            ]
                        ],
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        let (_, endpoints, _) = try parser.parse(data)
        #expect(endpoints.count == 1)
        #expect(endpoints[0].method == .post)
        #expect(endpoints[0].requestBody != nil)
        #expect(endpoints[0].requestBody?.contentType == "application/json")
    }

    @Test func parseInfoDescription() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": [
                "title": "My API",
                "version": "3.2.1",
                "description": "A test API for unit testing",
            ],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        let (info, _, _) = try parser.parse(data)
        #expect(info.title == "My API")
        #expect(info.version == "3.2.1")
        #expect(info.description == "A test API for unit testing")
    }

    @Test func parseInvalidFormatThrows() throws {
        let data = "not json at all".data(using: .utf8)!
        #expect(throws: OpenAPIParserError.invalidFormat) {
            try parser.parse(data)
        }
    }

    @Test func parseMissingOpenAPIVersionThrows() throws {
        let spec: [String: Any] = [
            "info": ["title": "API", "version": "1.0"],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        #expect(throws: OpenAPIParserError.invalidFormat) {
            try parser.parse(data)
        }
    }

    @Test func parseUnsupportedVersionThrows() throws {
        let spec: [String: Any] = [
            "openapi": "2.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        #expect(throws: OpenAPIParserError.unsupportedVersion) {
            try parser.parse(data)
        }
    }

    @Test func parseMissingInfoThrows() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        #expect(throws: OpenAPIParserError.missingInfo) {
            try parser.parse(data)
        }
    }

    @Test func parseFallbackNameFromSummary() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/health": [
                    "get": [
                        "summary": "Health check"
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)

        let (_, endpoints, _) = try parser.parse(data)
        #expect(endpoints.count == 1)
        #expect(endpoints[0].name == "Health check")
    }
}
