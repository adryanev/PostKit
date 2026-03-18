import Foundation
import SwiftData

/// Server status enumeration
enum MockServerStatus: String, Codable, Sendable, Equatable {
    case stopped = "stopped"
    case starting = "starting"
    case running = "running"
    case stopping = "stopping"
    case error = "error"
    
    var color: Color {
        switch self {
        case .stopped, .stopping: .gray
        case .starting: .orange
        case .running: .green
        case .error: .red
        }
    }
    
    var systemImage: String {
        switch self {
        case .stopped: "stop.circle"
        case .starting: "circle.dotted"
        case .running: "play.circle.fill"
        case .stopping: "stop.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

import SwiftUI

/// Represents a mock server configuration
@Model
final class MockServer {
    var id: UUID
    var name: String
    var port: Int
    var baseURL: String
    var serverDescription: String?
    var isEnabled: Bool
    var autoStart: Bool
    var corsEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // Runtime state (not persisted)
    @Transient var status: MockServerStatus = .stopped
    @Transient var errorMessage: String?
    @Transient var requestCount: Int = 0
    @Transient var lastRequestTime: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \MockEndpoint.server)
    var endpoints: [MockEndpoint] = []
    
    var sourceCollectionID: UUID?
    
    init(
        name: String,
        port: Int = 3000,
        baseURL: String = "/",
        serverDescription: String? = nil,
        isEnabled: Bool = true,
        autoStart: Bool = false,
        corsEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.port = port
        self.baseURL = baseURL
        self.serverDescription = serverDescription
        self.isEnabled = isEnabled
        self.autoStart = autoStart
        self.corsEnabled = corsEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Returns the server URL as a string
    var serverURL: String {
        "http://localhost:\(port)"
    }
    
    /// Finds a matching endpoint for a request
    func findMatchingEndpoint(path: String, method: HTTPMethod) -> MockEndpoint? {
        endpoints.first { endpoint in
            endpoint.isEnabled && endpoint.matches(requestPath: path, requestMethod: method)
        }
    }
    
    func duplicated() -> MockServer {
        let copy = MockServer(
            name: "\(name) (Copy)",
            port: port + Int.random(in: 1...100), // Avoid port conflicts
            baseURL: baseURL,
            serverDescription: serverDescription,
            isEnabled: false,
            autoStart: false,
            corsEnabled: corsEnabled
        )
        
        for endpoint in endpoints {
            let endpointCopy = endpoint.duplicated()
            endpointCopy.server = copy
            copy.endpoints.append(endpointCopy)
        }
        
        return copy
    }
}

// MARK: - Export/Import Support

extension MockServer {
    /// Export configuration as JSON data
    func exportConfiguration() throws -> Data {
        let exportData = MockServerExportData(from: self)
        return try JSONEncoder().encode(exportData)
    }
    
    /// Import configuration from JSON data
    static func importConfiguration(from data: Data) throws -> MockServer {
        let exportData = try JSONDecoder().decode(MockServerExportData.self, from: data)
        return exportData.toMockServer()
    }
}

/// Export-friendly representation of a mock server
@preconcurrency
struct MockServerExportData: Codable, Sendable {
    let name: String
    let port: Int
    let baseURL: String
    let description: String?
    let corsEnabled: Bool
    let endpoints: [MockEndpointExportData]
    let exportedAt: Date
    let version: String
    
    init(from server: MockServer) {
        self.name = server.name
        self.port = server.port
        self.baseURL = server.baseURL
        self.description = server.serverDescription
        self.corsEnabled = server.corsEnabled
        self.endpoints = server.endpoints.map { MockEndpointExportData(from: $0) }
        self.exportedAt = Date()
        self.version = "1.0"
    }
    
    func toMockServer() -> MockServer {
        let server = MockServer(
            name: name,
            port: port,
            baseURL: baseURL,
            serverDescription: description,
            corsEnabled: corsEnabled
        )
        
        for endpointData in endpoints {
            let endpoint = endpointData.toMockEndpoint()
            endpoint.server = server
            server.endpoints.append(endpoint)
        }
        
        return server
    }
}

struct MockEndpointExportData: Codable {
    let path: String
    let method: String
    let name: String
    let description: String?
    let responses: [MockResponseExportData]
    
    init(from endpoint: MockEndpoint) {
        self.path = endpoint.path
        self.method = endpoint.methodRaw
        self.name = endpoint.name
        self.description = endpoint.endpointDescription
        self.responses = endpoint.responses.map { MockResponseExportData(from: $0) }
    }
    
    func toMockEndpoint() -> MockEndpoint {
        let endpoint = MockEndpoint(
            path: path,
            method: HTTPMethod(rawValue: method) ?? .get,
            name: name,
            endpointDescription: description
        )
        
        for responseData in responses {
            let response = responseData.toMockResponse()
            response.endpoint = endpoint
            endpoint.responses.append(response)
        }
        
        return endpoint
    }
}

struct MockResponseExportData: Codable {
    let name: String
    let statusCode: Int
    let headers: [KeyValuePair]
    let bodyContent: String?
    let bodyType: String
    let delayMs: Int
    let isDefault: Bool
    
    init(from response: MockResponse) {
        self.name = response.name
        self.statusCode = response.statusCode
        self.headers = response.headers
        self.bodyContent = response.bodyContent
        self.bodyType = response.bodyTypeRaw
        self.delayMs = response.delayMs
        self.isDefault = response.isDefault
    }
    
    func toMockResponse() -> MockResponse {
        let response = MockResponse(
            name: name,
            statusCode: statusCode,
            bodyContent: bodyContent ?? "",
            bodyType: MockResponseBodyType(rawValue: bodyType) ?? .json,
            delayMs: delayMs,
            isDefault: isDefault
        )
        response.headers = headers
        return response
    }
}

// MARK: - OpenAPI Import Support

extension MockServer {
    /// Creates a mock server from an OpenAPI spec
    static func from(
        openAPISpec: OpenAPISpec,
        name: String? = nil,
        port: Int = 3000
    ) -> MockServer {
        let server = MockServer(
            name: name ?? openAPISpec.info.title,
            port: port,
            serverDescription: openAPISpec.info.description,
            corsEnabled: true
        )
        
        for endpoint in openAPISpec.endpoints {
            let mockEndpoint = MockEndpoint.from(openAPIEndpoint: endpoint)
            mockEndpoint.server = server
            server.endpoints.append(mockEndpoint)
        }
        
        return server
    }
}
