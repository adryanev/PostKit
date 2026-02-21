import Testing
import Foundation
import FactoryKit
import FactoryTesting
@testable import PostKit

@Suite(.container)
struct PostmanParserTests {
    let parser = PostmanParser()

    // MARK: - Positive Cases

    @Test func parseSimpleCollection() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [
                [
                    "name": "Get Users",
                    "request": [
                        "method": "GET",
                        "url": "https://api.example.com/users"
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let collection = try parser.parse(data)
        #expect(collection.info.name == "Test Collection")
        #expect(collection.items.count == 1)
        #expect(collection.items[0].name == "Get Users")
        #expect(collection.items[0].request?.method == "GET")
        #expect(collection.items[0].request?.url.rawValue == "https://api.example.com/users")
    }
    
    @Test func parseNestedFolders() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [
                [
                    "name": "Folder 1",
                    "item": [
                        [
                            "name": "Request 1",
                            "request": [
                                "method": "GET",
                                "url": "https://api.example.com/1"
                            ]
                        ],
                        [
                            "name": "Folder 2",
                            "item": [
                                [
                                    "name": "Request 2",
                                    "request": [
                                        "method": "POST",
                                        "url": "https://api.example.com/2"
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let collection = try parser.parse(data)
        #expect(collection.items.count == 1)
        #expect(collection.items[0].name == "Folder 1")
        #expect(collection.items[0].items?.count == 2)
        #expect(collection.items[0].items?[0].request?.method == "GET")
        #expect(collection.items[0].items?[1].name == "Folder 2")
    }
    
    @Test func parseWithAuth() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [
                [
                    "name": "Protected Request",
                    "request": [
                        "method": "GET",
                        "url": "https://api.example.com/protected",
                        "auth": [
                            "type": "bearer",
                            "bearer": [
                                ["key": "token", "value": "my-token-123"]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let collection = try parser.parse(data)
        let auth = collection.items[0].request?.auth
        #expect(auth?.type == "bearer")
        #expect(auth?.bearer?.first?.key == "token")
        #expect(auth?.bearer?.first?.value == "my-token-123")
    }
    
    @Test func parseWithEnvironmentVariables() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [],
            "variable": [
                ["key": "baseUrl", "value": "https://api.example.com"],
                ["key": "apiKey", "value": "secret-key", "type": "secret"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let collection = try parser.parse(data)
        #expect(collection.variables.count == 2)
        #expect(collection.variables[0].key == "baseUrl")
        #expect(collection.variables[0].value == "https://api.example.com")
        #expect(collection.variables[1].type == "secret")
    }
    
    @Test func parseWithPreRequestScript() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [
                [
                    "name": "Request with Script",
                    "request": [
                        "method": "GET",
                        "url": "https://api.example.com/test"
                    ],
                    "event": [
                        [
                            "listen": "prerequest",
                            "script": [
                                "exec": ["console.log('pre-request');", "pm.environment.set('token', '123');"]
                            ]
                        ],
                        [
                            "listen": "test",
                            "script": [
                                "exec": ["pm.test('Status is 200', function() {", "  pm.response.to.have.status(200);", "});"]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let collection = try parser.parse(data)
        let events = collection.items[0].events
        #expect(events?.count == 2)
        #expect(events?[0].listen == "prerequest")
        #expect(events?[0].script?.exec?.count == 2)
    }

    @Test func parseWithHeaders() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [
                [
                    "name": "Request",
                    "request": [
                        "method": "POST",
                        "url": "https://api.example.com/data",
                        "header": [
                            ["key": "Content-Type", "value": "application/json", "enabled": true],
                            ["key": "Authorization", "value": "Bearer token", "enabled": true],
                            ["key": "X-Disabled", "value": "disabled", "enabled": false]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let collection = try parser.parse(data)
        let headers = collection.items[0].request?.headers ?? []
        #expect(headers.count == 3)
        #expect(headers[0].key == "Content-Type")
        #expect(headers[0].value == "application/json")
        #expect(headers[2].enabled == false)
    }

    @Test func parseWithBody() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [
                [
                    "name": "POST Request",
                    "request": [
                        "method": "POST",
                        "url": "https://api.example.com/users",
                        "body": [
                            "mode": "raw",
                            "raw": "{\"name\": \"John\", \"email\": \"john@example.com\"}"
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let collection = try parser.parse(data)
        let body = collection.items[0].request?.body
        #expect(body?.mode == "raw")
        #expect(body?.raw?.contains("John") == true)
    }

    @Test func parseEnvironment() throws {
        let json: [String: Any] = [
            "name": "Development",
            "values": [
                ["key": "baseUrl", "value": "https://dev.api.example.com", "enabled": true],
                ["key": "apiKey", "value": "dev-key-123", "type": "secret", "enabled": true]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let env = try parser.parseEnvironment(data)
        #expect(env.name == "Development")
        #expect(env.values.count == 2)
        #expect(env.values[0].key == "baseUrl")
        #expect(env.values[1].type == "secret")
    }

    // MARK: - Negative Cases

    @Test func rejectV1Format() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Old Collection",
                "schema": "https://schema.getpostman.com/json/collection/v1.0.0/collection.json"
            ],
            "item": []
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        #expect(throws: PostmanParserError.unsupportedVersion) {
            try parser.parse(data)
        }
    }
    
    @Test func rejectInvalidJSON() throws {
        let data = "not valid json".data(using: .utf8)!
        
        #expect(throws: PostmanParserError.invalidFormat) {
            try parser.parse(data)
        }
    }
    
    // MARK: - Edge Cases

    @Test func handleMissingOptionalFields() throws {
        let json: [String: Any] = [
            "info": [
                "name": "Minimal Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let collection = try parser.parse(data)
        #expect(collection.info.name == "Minimal Collection")
        #expect(collection.items.isEmpty)
        #expect(collection.variables.isEmpty)
    }
}
