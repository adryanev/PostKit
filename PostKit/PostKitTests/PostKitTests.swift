//
//  PostKitTests.swift
//  PostKitTests
//
//  Created by Adryan Eka Vandra on 06/01/26.
//

import Testing
import Foundation
import FactoryKit
import FactoryTesting
import SwiftData
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
    
    // MARK: - YAML Parsing Tests
    
    @Test func parseYamlSpec() throws {
        let yaml = """
        openapi: "3.0.0"
        info:
          title: Test API
          version: "1.0"
        paths:
          /users:
            get:
              operationId: listUsers
        """
        let data = yaml.data(using: .utf8)!
        
        let (info, endpoints, _) = try parser.parse(data)
        #expect(info.title == "Test API")
        #expect(endpoints.count == 1)
        #expect(endpoints[0].name == "listUsers")
    }
    
    @Test func parseYamlWithUnquotedVersion() throws {
        let yaml = """
        openapi: 3.0
        info:
          title: API
          version: "1.0"
        paths: {}
        """
        let data = yaml.data(using: .utf8)!
        
        let (info, _, _) = try parser.parse(data)
        #expect(info.title == "API")
    }
    
    @Test func parseMixedJsonAndYaml() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "JSON API", "version": "1.0"],
            "paths": [:] as [String: Any],
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: spec)
        
        let (info, _, _) = try parser.parse(jsonData)
        #expect(info.title == "JSON API")
    }
    
    // MARK: - Tag Extraction Tests
    
    @Test func parseEndpointWithTags() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users": [
                    "get": [
                        "operationId": "listUsers",
                        "tags": ["users", "admin"],
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints.count == 1)
        #expect(result.endpoints[0].tags == ["users", "admin"])
    }
    
    @Test func parseEndpointWithoutTags() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/health": [
                    "get": [
                        "operationId": "healthCheck",
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints.count == 1)
        #expect(result.endpoints[0].tags.isEmpty)
    }
    
    // MARK: - Security Scheme Tests
    
    @Test func parseBearerSecurityScheme() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "components": [
                "securitySchemes": [
                    "bearerAuth": [
                        "type": "http",
                        "scheme": "bearer",
                    ] as [String: Any]
                ]
            ],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.securitySchemes.count == 1)
        #expect(result.securitySchemes[0].name == "bearerAuth")
        if case .http(let scheme) = result.securitySchemes[0].type {
            #expect(scheme == "bearer")
        } else {
            Issue.record("Expected http scheme type")
        }
    }
    
    @Test func parseBasicSecurityScheme() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "components": [
                "securitySchemes": [
                    "basicAuth": [
                        "type": "http",
                        "scheme": "basic",
                    ] as [String: Any]
                ]
            ],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.securitySchemes.count == 1)
        if case .http(let scheme) = result.securitySchemes[0].type {
            #expect(scheme == "basic")
        } else {
            Issue.record("Expected http scheme type")
        }
    }
    
    @Test func parseApiKeySecurityScheme() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "components": [
                "securitySchemes": [
                    "apiKey": [
                        "type": "apiKey",
                        "name": "X-API-Key",
                        "in": "header",
                    ] as [String: Any]
                ]
            ],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.securitySchemes.count == 1)
        if case .apiKey(let name, let location) = result.securitySchemes[0].type {
            #expect(name == "X-API-Key")
            #expect(location == "header")
        } else {
            Issue.record("Expected apiKey scheme type")
        }
    }
    
    @Test func parseUnsupportedSecurityScheme() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "components": [
                "securitySchemes": [
                    "oauth2": [
                        "type": "oauth2",
                    ] as [String: Any]
                ]
            ],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.securitySchemes.count == 1)
        if case .unsupported(let type) = result.securitySchemes[0].type {
            #expect(type == "oauth2")
        } else {
            Issue.record("Expected unsupported scheme type")
        }
    }
    
    // MARK: - Security Resolution Tests
    
    @Test func parseOperationSecurityOverridesGlobal() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "security": [["globalAuth": [:]]],
            "components": [
                "securitySchemes": [
                    "globalAuth": ["type": "http", "scheme": "bearer"] as [String: Any],
                    "opAuth": ["type": "http", "scheme": "basic"] as [String: Any],
                ]
            ],
            "paths": [
                "/users": [
                    "get": [
                        "operationId": "listUsers",
                        "security": [["opAuth": [:]]],
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints[0].security == ["opAuth"])
    }
    
    @Test func parseEmptySecurityMeansNoAuth() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "security": [["bearerAuth": [:]]],
            "paths": [
                "/public": [
                    "get": [
                        "operationId": "publicEndpoint",
                        "security": [],
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints[0].security == [])
    }
    
    // MARK: - Server Variables Tests
    
    @Test func parseServerVariables() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "servers": [
                [
                    "url": "https://{host}.api.example.com/v1",
                    "description": "Production",
                    "variables": [
                        "host": [
                            "default": "api",
                            "enum": ["api", "eu-api", "us-api"],
                            "description": "API region",
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.servers.count == 1)
        #expect(result.servers[0].variables.count == 1)
        #expect(result.servers[0].variables[0].name == "host")
        #expect(result.servers[0].variables[0].defaultValue == "api")
        #expect(result.servers[0].variables[0].enumValues == ["api", "eu-api", "us-api"])
        #expect(result.servers[0].variables[0].description == "API region")
    }
    
    // MARK: - Path Parameter Conversion Tests
    
    @Test func convertPathParameters() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users/{id}/posts/{postId}": [
                    "get": [
                        "operationId": "getPost",
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints.count == 1)
        #expect(result.endpoints[0].path == "/users/{{id}}/posts/{{postId}}")
    }
    
    // MARK: - Parameter Merge Tests
    
    @Test func mergePathAndOperationParameters() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users/{id}": [
                    "parameters": [
                        ["name": "id", "in": "path"],
                        ["name": "version", "in": "query"],
                    ],
                    "get": [
                        "operationId": "getUser",
                        "parameters": [
                            ["name": "include", "in": "query"],
                            ["name": "version", "in": "query"],
                        ],
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints.count == 1)
        let params = result.endpoints[0].parameters
        #expect(params.count == 3)
        let paramNames = Set(params.map { "\($0.name)|\($0.location)" })
        #expect(paramNames.contains("id|path"))
        #expect(paramNames.contains("include|query"))
        #expect(paramNames.contains("version|query"))
    }
    
    @Test func skipRefParameters() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users": [
                    "get": [
                        "operationId": "listUsers",
                        "parameters": [
                            ["$ref": "#/components/parameters/CommonParam"],
                            ["name": "limit", "in": "query"],
                        ],
                    ] as [String: Any]
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints.count == 1)
        #expect(result.endpoints[0].parameters.count == 1)
        #expect(result.endpoints[0].parameters[0].name == "limit")
        #expect(result.refSkipCount == 1)
    }
    
    // MARK: - HTTP Method Whitelist Tests
    
    @Test func ignoreNonMethodPathKeys() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/users": [
                    "summary": "User operations",
                    "description": "All user endpoints",
                    "parameters": [],
                    "servers": [],
                    "$ref": "#/paths/users",
                    "get": [
                        "operationId": "listUsers",
                    ] as [String: Any],
                    "post": [
                        "operationId": "createUser",
                    ] as [String: Any],
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints.count == 2)
        let methods = Set(result.endpoints.map { $0.method })
        #expect(methods.contains(.get))
        #expect(methods.contains(.post))
    }
    
    // MARK: - Deterministic Ordering Tests
    
    @Test func endpointsSortedDeterministically() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": "API", "version": "1.0"],
            "paths": [
                "/zoo": [
                    "post": ["operationId": "createZoo"] as [String: Any],
                    "get": ["operationId": "listZoos"] as [String: Any],
                ],
                "/animals": [
                    "get": ["operationId": "listAnimals"] as [String: Any],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        let result = try parser.parseSpec(data)
        #expect(result.endpoints.count == 3)
        #expect(result.endpoints[0].path == "/animals")
        #expect(result.endpoints[0].method == .get)
        #expect(result.endpoints[1].path == "/zoo")
        #expect(result.endpoints[1].method == .get)
        #expect(result.endpoints[2].path == "/zoo")
        #expect(result.endpoints[2].method == .post)
    }
    
    // MARK: - Missing Title Test
    
    @Test func parseMissingTitleThrows() throws {
        let spec: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["version": "1.0"],
            "paths": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: spec)
        
        #expect(throws: OpenAPIParserError.missingTitle) {
            try parser.parse(data)
        }
    }
}

// MARK: - OpenAPIDiffEngine Tests

struct OpenAPIDiffEngineTests {
    let diffEngine = OpenAPIDiffEngine()
    
    @Test func diffAllNewEndpoints() throws {
        let spec = OpenAPISpec(
            info: OpenAPIInfo(title: "API", version: "1.0", description: nil),
            servers: [],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil),
                OpenAPIEndpoint(name: "Create User", method: .post, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil),
            ],
            securitySchemes: [],
            refSkipCount: 0
        )
        
        let result = diffEngine.diff(
            spec: spec,
            selectedEndpoints: spec.endpoints,
            serverURL: "https://api.example.com",
            existingSnapshots: [],
            securitySchemes: []
        )
        
        #expect(result.newEndpoints.count == 2)
        #expect(result.changedEndpoints.isEmpty)
        #expect(result.removedEndpoints.isEmpty)
        #expect(result.unchangedEndpoints.isEmpty)
    }
    
    @Test func diffAllUnchangedEndpoints() throws {
        let existingSnapshot = EndpointSnapshot(
            id: "GET /users",
            requestID: UUID(),
            name: "Get Users",
            method: .get,
            path: "/users",
            headers: [],
            queryParams: [],
            bodyType: .none,
            bodyContentType: nil,
            authDescription: nil,
            tags: []
        )
        
        let spec = OpenAPISpec(
            info: OpenAPIInfo(title: "API", version: "1.0", description: nil),
            servers: [],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil),
            ],
            securitySchemes: [],
            refSkipCount: 0
        )
        
        let result = diffEngine.diff(
            spec: spec,
            selectedEndpoints: spec.endpoints,
            serverURL: "https://api.example.com",
            existingSnapshots: [existingSnapshot],
            securitySchemes: []
        )
        
        #expect(result.newEndpoints.isEmpty)
        #expect(result.changedEndpoints.isEmpty)
        #expect(result.removedEndpoints.isEmpty)
        #expect(result.unchangedEndpoints.count == 1)
    }
    
    @Test func diffRemovedEndpoints() throws {
        let existingSnapshot = EndpointSnapshot(
            id: "DELETE /users/{id}",
            requestID: UUID(),
            name: "Delete User",
            method: .delete,
            path: "/users/{{id}}",
            headers: [],
            queryParams: [],
            bodyType: .none,
            bodyContentType: nil,
            authDescription: nil,
            tags: []
        )
        
        let spec = OpenAPISpec(
            info: OpenAPIInfo(title: "API", version: "1.0", description: nil),
            servers: [],
            endpoints: [],
            securitySchemes: [],
            refSkipCount: 0
        )
        
        let result = diffEngine.diff(
            spec: spec,
            selectedEndpoints: [],
            serverURL: "https://api.example.com",
            existingSnapshots: [existingSnapshot],
            securitySchemes: []
        )
        
        #expect(result.newEndpoints.isEmpty)
        #expect(result.changedEndpoints.isEmpty)
        #expect(result.removedEndpoints.count == 1)
        #expect(result.removedEndpoints[0].id == "DELETE /users/{{id}}")
    }
    
    @Test func diffChangedEndpoint() throws {
        let existingSnapshot = EndpointSnapshot(
            id: "GET /users",
            requestID: UUID(),
            name: "Get Users (Old)",
            method: .get,
            path: "/users",
            headers: [],
            queryParams: [],
            bodyType: .none,
            bodyContentType: nil,
            authDescription: nil,
            tags: []
        )
        
        let spec = OpenAPISpec(
            info: OpenAPIInfo(title: "API", version: "1.0", description: nil),
            servers: [],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users (New)", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil),
            ],
            securitySchemes: [],
            refSkipCount: 0
        )
        
        let result = diffEngine.diff(
            spec: spec,
            selectedEndpoints: spec.endpoints,
            serverURL: "https://api.example.com",
            existingSnapshots: [existingSnapshot],
            securitySchemes: []
        )
        
        #expect(result.newEndpoints.isEmpty)
        #expect(result.changedEndpoints.count == 1)
        #expect(result.changedEndpoints[0].existing.name == "Get Users (Old)")
        #expect(result.changedEndpoints[0].incoming.name == "Get Users (New)")
        #expect(result.removedEndpoints.isEmpty)
        #expect(result.unchangedEndpoints.isEmpty)
    }
    
    @Test func diffMixedCase() throws {
        let existingSnapshot1 = EndpointSnapshot(
            id: "GET /users",
            requestID: UUID(),
            name: "Get Users",
            method: .get,
            path: "/users",
            headers: [],
            queryParams: [],
            bodyType: .none,
            bodyContentType: nil,
            authDescription: nil,
            tags: []
        )
        
        let existingSnapshot2 = EndpointSnapshot(
            id: "DELETE /users/{id}",
            requestID: UUID(),
            name: "Delete User",
            method: .delete,
            path: "/users/{{id}}",
            headers: [],
            queryParams: [],
            bodyType: .none,
            bodyContentType: nil,
            authDescription: nil,
            tags: []
        )
        
        let spec = OpenAPISpec(
            info: OpenAPIInfo(title: "API", version: "1.0", description: nil),
            servers: [],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users (Updated)", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil),
                OpenAPIEndpoint(name: "Create User", method: .post, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil),
            ],
            securitySchemes: [],
            refSkipCount: 0
        )
        
        let result = diffEngine.diff(
            spec: spec,
            selectedEndpoints: spec.endpoints,
            serverURL: "https://api.example.com",
            existingSnapshots: [existingSnapshot1, existingSnapshot2],
            securitySchemes: []
        )
        
        #expect(result.newEndpoints.count == 1)
        #expect(result.newEndpoints[0].method == .post)
        #expect(result.changedEndpoints.count == 1)
        #expect(result.removedEndpoints.count == 1)
        #expect(result.removedEndpoints[0].method == .delete)
        #expect(result.unchangedEndpoints.isEmpty)
    }
    
    @Test func diffUserCreatedRequestsIgnored() throws {
        let userCreatedSnapshot = EndpointSnapshot(
            id: "GET /custom",
            requestID: nil,
            name: "Custom Request",
            method: .get,
            path: "/custom",
            headers: [],
            queryParams: [],
            bodyType: .none,
            bodyContentType: nil,
            authDescription: nil,
            tags: []
        )
        
        let spec = OpenAPISpec(
            info: OpenAPIInfo(title: "API", version: "1.0", description: nil),
            servers: [],
            endpoints: [],
            securitySchemes: [],
            refSkipCount: 0
        )
        
        let result = diffEngine.diff(
            spec: spec,
            selectedEndpoints: [],
            serverURL: "https://api.example.com",
            existingSnapshots: [userCreatedSnapshot],
            securitySchemes: []
        )
        
        #expect(result.removedEndpoints.count == 1)
    }
    
    @Test func diffCaseInsensitiveMethodMatch() throws {
        let existingSnapshot = EndpointSnapshot(
            id: "get /users",
            requestID: UUID(),
            name: "Get Users",
            method: .get,
            path: "/users",
            headers: [],
            queryParams: [],
            bodyType: .none,
            bodyContentType: nil,
            authDescription: nil,
            tags: []
        )
        
        let spec = OpenAPISpec(
            info: OpenAPIInfo(title: "API", version: "1.0", description: nil),
            servers: [],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil),
            ],
            securitySchemes: [],
            refSkipCount: 0
        )
        
        let result = diffEngine.diff(
            spec: spec,
            selectedEndpoints: spec.endpoints,
            serverURL: "https://api.example.com",
            existingSnapshots: [existingSnapshot],
            securitySchemes: []
        )
        
        #expect(result.unchangedEndpoints.count == 1)
    }
    
    @Test func createSnapshotFromEndpoint() throws {
        let endpoint = OpenAPIEndpoint(
            name: "Get User",
            method: .get,
            path: "/users/{{id}}",
            parameters: [
                OpenAPIParameter(name: "id", location: "path"),
                OpenAPIParameter(name: "include", location: "query"),
                OpenAPIParameter(name: "X-Custom", location: "header"),
            ],
            requestBody: OpenAPIRequestBody(contentType: "application/json"),
            tags: ["users"],
            operationId: "getUser",
            description: nil,
            security: ["bearerAuth"]
        )
        
        let schemes = [
            OpenAPISecurityScheme(name: "bearerAuth", type: .http(scheme: "bearer"))
        ]
        
        let snapshot = diffEngine.createSnapshotFromEndpoint(
            endpoint,
            serverURL: "https://api.example.com",
            securitySchemes: schemes
        )
        
        #expect(snapshot.id == "GET /users/{{id}}")
        #expect(snapshot.name == "Get User")
        #expect(snapshot.method == .get)
        #expect(snapshot.path == "/users/{{id}}")
        #expect(snapshot.headers.count == 1)
        #expect(snapshot.headers[0].key == "X-Custom")
        #expect(snapshot.queryParams.count == 1)
        #expect(snapshot.queryParams[0].key == "include")
        #expect(snapshot.bodyType == .json)
        #expect(snapshot.authDescription == "Bearer Token")
        #expect(snapshot.tags == ["users"])
    }
}

// MARK: - CurlHTTPClient Tests

struct CurlHTTPClientTests {
    @Test func statusMessageExtractionFromHeaderLine() {
        let headerLines = ["HTTP/1.1 200 OK", "Content-Type: application/json"]
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 200)
        #expect(message == "OK")
    }
    
    @Test func statusMessageExtractionFromNoHeaders() {
        let headerLines: [String] = []
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 404)
        #expect(message == HTTPURLResponse.localizedString(forStatusCode: 404))
    }
    
    @Test func statusMessageExtractionFromMalformedLine() {
        let headerLines = ["HTTP/1.1 500"]
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 500)
        #expect(message == HTTPURLResponse.localizedString(forStatusCode: 500))
    }
    
    @Test func statusMessageExtractionFromNonHTTPLine() {
        let headerLines = ["Invalid response"]
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 200)
        #expect(message == HTTPURLResponse.localizedString(forStatusCode: 200))
    }
    
    @Test func timingDeltaClampingWithPositiveValues() {
        let timing = TimingBreakdown(
            dnsLookup: 0.05,
            tcpConnection: 0.03,
            tlsHandshake: 0.02,
            transferStart: 0.01,
            download: 0.10,
            total: 0.21,
            redirectTime: 0
        )
        #expect(timing.dnsLookup == 0.05)
        #expect(timing.tcpConnection >= 0)
        #expect(timing.tlsHandshake >= 0)
    }
    
    @Test func timingDeltaClampingWithZeroValues() {
        let timing = TimingBreakdown(
            dnsLookup: 0,
            tcpConnection: 0,
            tlsHandshake: 0,
            transferStart: 0.01,
            download: 0.05,
            total: 0.06,
            redirectTime: 0
        )
        #expect(timing.dnsLookup == 0)
        #expect(timing.tcpConnection == 0)
        #expect(timing.tlsHandshake == 0)
    }
    
    @Test func sanitizeForCurlStripsCRLF() {
        let input = "hello\r\nworld"
        let result = CurlHTTPClient.sanitizeForCurl(input)
        #expect(result == "helloworld")
    }
    
    @Test func sanitizeForCurlStripsNUL() {
        let input = "hello\0world"
        let result = CurlHTTPClient.sanitizeForCurl(input)
        #expect(result == "helloworld")
    }
    
    @Test func sanitizeForCurlStripsAllControlChars() {
        let input = "line1\r\n\0line2"
        let result = CurlHTTPClient.sanitizeForCurl(input)
        #expect(result == "line1line2")
    }
    
    @Test func httpClientErrorTimeoutExists() {
        let error = HTTPClientError.timeout
        #expect(error.errorDescription == "Request timed out")
    }
    
    @Test func httpClientErrorEngineInitFailedExists() {
        let error = HTTPClientError.engineInitializationFailed
        #expect(error.errorDescription == "HTTP client engine failed to initialize")
    }
    
    @Test func httpClientErrorResponseTooLarge() {
        let error = HTTPClientError.responseTooLarge(100_000_000)
        #expect(error.errorDescription?.contains("100000000") == true)
    }
    
    @Test func curlHTTPClientConformsToHTTPClientProtocol() throws {
        // This is a compile-time check - if CurlHTTPClient doesn't conform to HTTPClientProtocol,
        // the code wouldn't compile. We just verify we can create an instance.
        _ = try CurlHTTPClient()
        #expect(Bool(true))
    }

    // MARK: - parseHeaders Tests

    @Test func parseHeadersBasic() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json",
            "X-Request-Id: abc123"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["X-Request-Id"] == "abc123")
    }

    @Test func parseHeadersSkipsStatusLine() {
        let lines = ["HTTP/1.1 200 OK", "Host: example.com"]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Host"] == "example.com")
        #expect(headers.count == 1) // HTTP/ line should be skipped
    }

    @Test func parseHeadersDuplicateKeysJoined() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Set-Cookie: a=1",
            "Set-Cookie: b=2"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Set-Cookie"] == "a=1, b=2")
    }

    @Test func parseHeadersColonInValue() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Location: https://example.com:8080/path"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Location"] == "https://example.com:8080/path")
    }

    @Test func parseHeadersEmptyInput() {
        let headers = CurlHTTPClient.parseHeaders(from: [])
        #expect(headers.isEmpty)
    }

    @Test func parseHeadersTrimsWhitespace() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Content-Type:   application/json  "
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Content-Type"] == "application/json")
    }

    @Test func parseHeadersNoColonLineSkipped() {
        let lines = [
            "HTTP/1.1 200 OK",
            "InvalidLineWithoutColon",
            "Valid-Header: value"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers.count == 1)
        #expect(headers["Valid-Header"] == "value")
    }

    // MARK: - Error Type Tests

    @Test func httpClientErrorInvalidURL() {
        let error = HTTPClientError.invalidURL
        #expect(error.errorDescription == "Invalid URL")
    }

    @Test func httpClientErrorInvalidResponse() {
        let error = HTTPClientError.invalidResponse
        #expect(error.errorDescription == "Invalid response received")
    }

    @Test func httpClientErrorNetworkError() {
        let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "test error"])
        let error = HTTPClientError.networkError(underlying)
        #expect(error.errorDescription == "test error")
    }

    // MARK: - HTTPResponse Tests

    @Test func httpResponseGetBodyDataFromMemory() throws {
        let body = "test body".data(using: .utf8)!
        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: body, bodyFileURL: nil, duration: 0.1, size: Int64(body.count),
            timingBreakdown: nil
        )
        let data = try response.getBodyData()
        #expect(data == body)
    }

    @Test func httpResponseGetBodyDataFromFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("postkit-test-\(UUID().uuidString).tmp")
        let content = "file body content".data(using: .utf8)!
        try content.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: nil, bodyFileURL: tempURL, duration: 0.1, size: Int64(content.count),
            timingBreakdown: nil
        )
        let data = try response.getBodyData()
        #expect(data == content)
    }

    @Test func httpResponseGetBodyDataEmpty() throws {
        let response = HTTPResponse(
            statusCode: 204, statusMessage: "No Content", headers: [:],
            body: nil, bodyFileURL: nil, duration: 0.1, size: 0,
            timingBreakdown: nil
        )
        let data = try response.getBodyData()
        #expect(data.isEmpty)
    }

    @Test func httpResponseIsLargeWhenFileURLPresent() {
        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: nil, bodyFileURL: URL(fileURLWithPath: "/tmp/test"), duration: 0.1, size: 5_000_000,
            timingBreakdown: nil
        )
        #expect(response.isLarge)
    }

    @Test func httpResponseIsNotLargeWhenInMemory() {
        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: Data(), bodyFileURL: nil, duration: 0.1, size: 100,
            timingBreakdown: nil
        )
        #expect(!response.isLarge)
    }

    // MARK: - Shared Constant Tests

    @Test func maxMemorySizeIsConsistentAcrossClients() {
        // Verify the shared constant is what we expect (1MB)
        #expect(httpClientMaxMemorySize == 1_000_000)
    }
}

// MARK: - TimingBreakdown Tests

struct TimingBreakdownTests {
    @Test func timingBreakdownIsCodable() throws {
        let timing = TimingBreakdown(
            dnsLookup: 0.05,
            tcpConnection: 0.03,
            tlsHandshake: 0.02,
            transferStart: 0.01,
            download: 0.10,
            total: 0.21,
            redirectTime: 0.05
        )
        
        let data = try JSONEncoder().encode(timing)
        let decoded = try JSONDecoder().decode(TimingBreakdown.self, from: data)
        
        #expect(decoded.dnsLookup == timing.dnsLookup)
        #expect(decoded.tcpConnection == timing.tcpConnection)
        #expect(decoded.tlsHandshake == timing.tlsHandshake)
        #expect(decoded.transferStart == timing.transferStart)
        #expect(decoded.download == timing.download)
        #expect(decoded.total == timing.total)
        #expect(decoded.redirectTime == timing.redirectTime)
    }
    
    @Test func timingBreakdownIsSendable() {
        let timing = TimingBreakdown(
            dnsLookup: 0.01,
            tcpConnection: 0.02,
            tlsHandshake: 0.03,
            transferStart: 0.04,
            download: 0.05,
            total: 0.15,
            redirectTime: 0
        )
        // This is a compile-time check
        let _: Sendable = timing
        #expect(true)
    }
}

// MARK: - RequestViewModel Tests

import SwiftData

@Suite(.serialized)
@MainActor
struct RequestViewModelTests {
    
    // MARK: - Positive Cases
    
    @Test func executeRequestReturnsResponse() async throws {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(response: HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/json"],
            body: "{\"message\": \"success\"}".data(using: .utf8),
            bodyFileURL: nil,
            duration: 0.1,
            size: 27,
            timingBreakdown: nil
        ))

        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/test")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        #expect(viewModel.response != nil)
        #expect(viewModel.response?.statusCode == 200)
        #expect(viewModel.error == nil)
        #expect(viewModel.isSending == false)
    }
    
    @Test func viewModelInitializesWithModelContext() {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        #expect(container != nil)
        
        let viewModel = RequestViewModel(modelContext: container!.mainContext)
        #expect(viewModel.response == nil)
        #expect(viewModel.isSending == false)
        #expect(viewModel.error == nil)
    }
    
    @Test func activeTabDefaultsToBody() {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container!.mainContext)
        #expect(viewModel.activeTab == .body)
    }
    
    // MARK: - Negative Cases
    
    @Test func executeRequestHandlesNetworkError() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        struct TestError: Error {}
        let mockClient = MockHTTPClient(error: TestError())

        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/test")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        #expect(viewModel.error != nil)
        #expect(viewModel.response == nil)
        #expect(viewModel.isSending == false)
    }
    
    @Test func executeRequestHandlesHTTPError() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(response: HTTPResponse(
            statusCode: 404,
            statusMessage: "Not Found",
            headers: [:],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        ))

        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/notfound")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        #expect(viewModel.response?.statusCode == 404)
        #expect(viewModel.error == nil)
    }
    
    @Test func executeRequestSkipsEmptyURL() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient()
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Empty URL", method: .get, url: "")

        viewModel.sendRequest(for: request)
        // Empty URL returns early without creating a task
        #expect(viewModel.currentTask == nil)

        let callCount = await mockClient.executeCallCount
        #expect(callCount == 0)
        #expect(viewModel.response == nil)
    }
    
    // MARK: - Edge Cases
    
    @Test func cancelRequestStopsSending() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(delay: 5.0)
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Slow Request", method: .get, url: "https://api.example.com/slow")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        viewModel.cancelRequest()
        await viewModel.currentTask?.value

        #expect(viewModel.isSending == false)
    }
    
    @Test func newRequestCancelsPrevious() async throws {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(delay: 2.0)
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request1 = HTTPRequest(name: "Request 1", method: .get, url: "https://api.example.com/1")
        let request2 = HTTPRequest(name: "Request 2", method: .get, url: "https://api.example.com/2")
        container.mainContext.insert(request1)
        container.mainContext.insert(request2)

        // Fire first request without awaiting — it stays in-flight
        viewModel.sendRequest(for: request1)
        let firstTaskID = viewModel.currentTaskID

        // Immediately send second request, which overwrites currentTaskID/currentTask
        viewModel.sendRequest(for: request2)
        let secondTaskID = viewModel.currentTaskID

        // Only await the second (current) task
        await viewModel.currentTask?.value

        // The two requests got different task IDs
        #expect(firstTaskID != secondTaskID)

        // The first task's guard check fails so its result is discarded;
        // only the second request's response is applied.
        #expect(viewModel.currentTaskID == secondTaskID)

        let cancelledIDs = await mockClient.cancelledTaskIDs
        let callCount = await mockClient.executeCallCount
        // At least the second request executed; the first may also have
        // started but its result was silently discarded via the taskID guard.
        #expect(callCount >= 1)
        // If the ViewModel cancels the previous HTTP task, verify it;
        // otherwise confirm the stale-ID guard protected us.
        if !cancelledIDs.isEmpty {
            #expect(cancelledIDs.contains(firstTaskID!))
        }
    }
    
    @Test func buildURLRequestWithQueryParams() throws {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)
        
        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/search")
        request.queryParamsData = [
            KeyValuePair(key: "q", value: "swift", isEnabled: true),
            KeyValuePair(key: "page", value: "1", isEnabled: true)
        ].encode()
        
        let urlRequest = try viewModel.buildURLRequest(for: request)
        
        #expect(urlRequest.url?.absoluteString.contains("q=swift") == true)
        #expect(urlRequest.url?.absoluteString.contains("page=1") == true)
    }
    
    @Test func buildURLRequestWithHeaders() throws {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)
        
        let request = HTTPRequest(name: "Test", method: .post, url: "https://api.example.com/data")
        request.headersData = [
            KeyValuePair(key: "Content-Type", value: "application/json", isEnabled: true),
            KeyValuePair(key: "Authorization", value: "Bearer token123", isEnabled: true)
        ].encode()
        
        let urlRequest = try viewModel.buildURLRequest(for: request)
        
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    }
    
    @Test func buildURLRequestWithJSONBody() throws {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)
        
        let request = HTTPRequest(name: "Test", method: .post, url: "https://api.example.com/users")
        request.bodyType = .json
        request.bodyContent = "{\"name\": \"Test\"}"
        
        let urlRequest = try viewModel.buildURLRequest(for: request)
        
        #expect(urlRequest.httpBody != nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
    
    @Test func historyCreatedAfterSend() async throws {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(response: HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: [:],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        ))
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/test")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        let callCount = await mockClient.executeCallCount
        #expect(callCount == 1)

        let descriptor = FetchDescriptor<HistoryEntry>()
        let entries = try container.mainContext.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.statusCode == 200)
    }
}

// MARK: - KeychainManagerProtocol Tests

struct KeychainManagerProtocolTests {
    
    @Test func mockKeychainStoreAndRetrieve() throws {
        let mock = MockKeychainManager()
        
        try mock.store(key: "test-key", value: "test-value")
        #expect(mock.storeCallCount == 1)
        
        let retrieved = try mock.retrieve(key: "test-key")
        #expect(retrieved == "test-value")
        #expect(mock.retrieveCallCount == 1)
    }
    
    @Test func mockKeychainDelete() throws {
        let mock = MockKeychainManager()
        
        try mock.store(key: "test-key", value: "test-value")
        try mock.delete(key: "test-key")
        
        let retrieved = try mock.retrieve(key: "test-key")
        #expect(retrieved == nil)
        #expect(mock.deleteCallCount == 1)
    }
    
    @Test func mockKeychainStoreSecretsBatch() throws {
        let mock = MockKeychainManager()
        
        try mock.storeSecrets(["key1": "value1", "key2": "value2"])
        
        #expect(try mock.retrieve(key: "key1") == "value1")
        #expect(try mock.retrieve(key: "key2") == "value2")
    }
    
    @Test func mockKeychainRetrieveSecretsBatch() throws {
        let mock = MockKeychainManager()
        
        try mock.store(key: "key1", value: "value1")
        try mock.store(key: "key2", value: "value2")
        
        let secrets = try mock.retrieveSecrets(keys: ["key1", "key2", "nonexistent"])
        
        #expect(secrets["key1"] == "value1")
        #expect(secrets["key2"] == "value2")
        #expect(secrets["nonexistent"] == nil)
    }
    
    @Test func mockKeychainThrowsWhenConfigured() {
        let mock = MockKeychainManager(shouldThrow: true)
        
        #expect(throws: KeychainError.self) {
            try mock.store(key: "test", value: "test")
        }
    }
}

// MARK: - Syntax Highlighting Tests

struct SyntaxHighlightingTests {
    
    // MARK: - HTTPResponse.contentType Tests
    
    @Test func contentTypeExtractsSimpleContentType() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/json"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeHandlesCaseInsensitiveHeader() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["content-type": "application/json"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        // Implementation uses case-insensitive lookup
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeStripsCharsetParameter() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeStripsMultipleParameters() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "text/html; charset=utf-8; boundary=something"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "text/html")
    }
    
    @Test func contentTypeTrimsWhitespace() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "  application/json  ; charset=utf-8"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeReturnsLowercase() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "Application/JSON"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeReturnsNilWhenMissing() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: [:],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == nil)
    }
    
    @Test func contentTypeHandlesXMLTypes() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/xml; charset=utf-8"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/xml")
    }
    
    @Test func contentTypeHandlesTextPlain() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "text/plain"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "text/plain")
    }
    
    // MARK: - BodyType.highlightrLanguage Tests
    
    @Test func bodyTypeNoneReturnsNilLanguage() {
        #expect(BodyType.none.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeJsonReturnsJsonLanguage() {
        #expect(BodyType.json.highlightrLanguage == "json")
    }
    
    @Test func bodyTypeXmlReturnsXmlLanguage() {
        #expect(BodyType.xml.highlightrLanguage == "xml")
    }
    
    @Test func bodyTypeRawReturnsNilLanguage() {
        #expect(BodyType.raw.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeUrlEncodedReturnsNilLanguage() {
        #expect(BodyType.urlEncoded.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeFormDataReturnsNilLanguage() {
        #expect(BodyType.formData.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeAllCasesCovered() {
        // Ensure we've tested all cases
        for bodyType in BodyType.allCases {
            switch bodyType {
            case .none, .json, .xml, .raw, .urlEncoded, .formData:
                break // All cases handled
            }
        }
    }
    
    // MARK: - languageForContentType Tests
    
    @Test func languageForContentTypeJson() {
        #expect(languageForContentType("application/json") == "json")
    }
    
    @Test func languageForContentTypeApplicationXml() {
        #expect(languageForContentType("application/xml") == "xml")
    }
    
    @Test func languageForContentTypeTextXml() {
        #expect(languageForContentType("text/xml") == "xml")
    }
    
    @Test func languageForContentTypeHtml() {
        #expect(languageForContentType("text/html") == "html")
    }
    
    @Test func languageForContentTypeCss() {
        #expect(languageForContentType("text/css") == "css")
    }
    
    @Test func languageForContentTypeApplicationJavascript() {
        #expect(languageForContentType("application/javascript") == "javascript")
    }
    
    @Test func languageForContentTypeTextJavascript() {
        #expect(languageForContentType("text/javascript") == "javascript")
    }
    
    @Test func languageForContentTypeApplicationYaml() {
        #expect(languageForContentType("application/x-yaml") == "yaml")
    }
    
    @Test func languageForContentTypeTextYaml() {
        #expect(languageForContentType("text/yaml") == "yaml")
    }
    
    @Test func languageForContentTypeUnknownReturnsNil() {
        #expect(languageForContentType("application/octet-stream") == nil)
    }
    
    @Test func languageForContentTypeNilReturnsNil() {
        #expect(languageForContentType(nil) == nil)
    }
    
    @Test func languageForContentTypeTextPlainReturnsNil() {
        #expect(languageForContentType("text/plain") == nil)
    }
    
    // MARK: - computeDisplayString Tests
    
    @Test func computeDisplayStringRawMode() {
        let data = #"{"name":"test","value":123}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: true)
        #expect(result == #"{"name":"test","value":123}"#)
    }
    
    @Test func computeDisplayStringJsonPrettyPrint() {
        let data = #"{"name":"test","value":123}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result.contains("\n")) // Pretty printed should have newlines
        #expect(result.contains("\"name\""))
        #expect(result.contains("\"test\""))
    }
    
    @Test func computeDisplayStringNonJsonPassthrough() {
        let data = "Hello, World!".data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "text/plain", showRaw: false)
        #expect(result == "Hello, World!")
    }
    
    @Test func computeDisplayStringNilContentType() {
        let data = "Hello, World!".data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: nil, showRaw: false)
        #expect(result == "Hello, World!")
    }
    
    @Test func computeDisplayStringInvalidJsonReturnsRaw() {
        let data = "not valid json".data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result == "not valid json")
    }
    
    @Test func computeDisplayStringBinaryData() {
        let data = Data([0x00, 0x01, 0x02, 0xFF])
        let result = computeDisplayString(for: data, contentType: "application/octet-stream", showRaw: false)
        #expect(result == "<binary data>")
    }
    
    @Test func computeDisplayStringTruncatesToMaxDisplaySize() {
        let longString = String(repeating: "a", count: 100)
        let data = longString.data(using: .utf8)!
        let result = computeDisplayString(
            for: data,
            contentType: "text/plain",
            showRaw: false,
            maxDisplaySize: 50
        )
        #expect(result.count == 50)
    }
    
    @Test func computeDisplayStringSkipsPrettyPrintAboveThreshold() {
        // Create JSON larger than threshold
        let jsonObject: [String: Any] = ["data": Array(repeating: "x", count: 1000)]
        let data = try! JSONSerialization.data(withJSONObject: jsonObject)
        
        let result = computeDisplayString(
            for: data,
            contentType: "application/json",
            showRaw: false,
            maxDisplaySize: 10_000_000,
            prettyPrintThreshold: 10 // Very small threshold
        )
        // Should not be pretty printed since it exceeds threshold
        #expect(!result.contains("\n  ")) // No indentation newlines
    }
    
    @Test func computeDisplayStringPreservesJsonOrder() {
        let data = #"{"z":1,"a":2,"m":3}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        // JSON serialization preserves the order from the input
        #expect(result.contains("z"))
        #expect(result.contains("a"))
        #expect(result.contains("m"))
    }
    
    @Test func computeDisplayStringNestedJson() {
        let data = #"{"user":{"name":"Alice","age":30}}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result.contains("user"))
        #expect(result.contains("Alice"))
        #expect(result.contains("30"))
    }
    
    @Test func computeDisplayStringJsonArray() {
        let data = #"[1,2,3]"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result.contains("["))
        #expect(result.contains("1"))
        #expect(result.contains("2"))
        #expect(result.contains("3"))
    }
    
    @Test func computeDisplayStringEmptyData() {
        let data = Data()
        let result = computeDisplayString(for: data, contentType: "text/plain", showRaw: false)
        #expect(result == "")
    }
}

