import Testing
import Foundation
import FactoryKit
import FactoryTesting
@testable import PostKit

@Suite(.container)
struct OpenAPIDiffEngineTests {
    let diffEngine = OpenAPIDiffEngine()

    // MARK: - Positive Cases

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
            tags: [],
            historyCount: 0
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
            tags: [],
            historyCount: 0
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
        #expect(result.removedEndpoints[0].id == "DELETE /users/{id}")
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
            tags: [],
            historyCount: 0
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
            tags: [],
            historyCount: 0
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
            tags: [],
            historyCount: 0
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
        #expect(result.newEndpoints[0].method == HTTPMethod.post)
        #expect(result.changedEndpoints.count == 1)
        #expect(result.removedEndpoints.count == 1)
        #expect(result.removedEndpoints[0].method == HTTPMethod.delete)
        #expect(result.unchangedEndpoints.isEmpty)
    }
    
    // MARK: - Edge Cases

    @Test func diffUnmatchedSnapshotsAreRemoved() throws {
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
            tags: [],
            historyCount: 0
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
            tags: [],
            historyCount: 0
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
