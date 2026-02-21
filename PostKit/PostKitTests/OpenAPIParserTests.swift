import Testing
import Foundation
@testable import PostKit

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
