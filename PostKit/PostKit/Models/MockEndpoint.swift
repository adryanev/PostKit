import Foundation
import SwiftData

/// Represents a single endpoint in a mock server
@Model
final class MockEndpoint {
    var id: UUID
    var path: String
    var methodRaw: String
    var name: String
    var endpointDescription: String?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    
    @Transient var method: HTTPMethod {
        get { HTTPMethod(rawValue: methodRaw) ?? .get }
        set { methodRaw = newValue.rawValue }
    }
    
    @Relationship(deleteRule: .cascade, inverse: \MockResponse.endpoint)
    var responses: [MockResponse] = []
    
    var server: MockServer?
    
    @Transient var defaultResponse: MockResponse? {
        get { responses.first(where: { $0.isDefault }) ?? responses.first }
    }
    
    init(
        path: String,
        method: HTTPMethod = .get,
        name: String? = nil,
        endpointDescription: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.path = path
        self.methodRaw = method.rawValue
        self.name = name ?? "\(method.rawValue) \(path)"
        self.endpointDescription = endpointDescription
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func duplicated() -> MockEndpoint {
        let copy = MockEndpoint(
            path: path,
            method: method,
            name: "\(name) (Copy)",
            endpointDescription: endpointDescription,
            isEnabled: isEnabled
        )
        for response in responses {
            let responseCopy = response.duplicated()
            responseCopy.endpoint = copy
            copy.responses.append(responseCopy)
        }
        return copy
    }
    
    /// Matches a request path against this endpoint's path pattern
    /// Supports path parameters like /users/{id}
    func matches(requestPath: String, requestMethod: HTTPMethod) -> Bool {
        guard method == requestMethod else { return false }
        
        let endpointParts = path.split(separator: "/")
        let requestParts = requestPath.split(separator: "/")
        
        guard endpointParts.count == requestParts.count else { return false }
        
        for (endpointPart, requestPart) in zip(endpointParts, requestParts) {
            let endpointPartString = String(endpointPart)
            
            // Check if this is a path parameter
            if endpointPartString.hasPrefix("{") && endpointPartString.hasSuffix("}") {
                continue // Path parameter matches anything
            }
            
            // Exact match required
            if endpointPartString != String(requestPart) {
                return false
            }
        }
        
        return true
    }
    
    /// Extracts path parameters from a request path
    func extractPathParameters(from requestPath: String) -> [String: String] {
        var parameters: [String: String] = [:]
        
        let endpointParts = path.split(separator: "/")
        let requestParts = requestPath.split(separator: "/")
        
        for (endpointPart, requestPart) in zip(endpointParts, requestParts) {
            let endpointPartString = String(endpointPart)
            
            if endpointPartString.hasPrefix("{") && endpointPartString.hasSuffix("}") {
                let paramName = String(endpointPartString.dropFirst().dropLast())
                parameters[paramName] = String(requestPart)
            }
        }
        
        return parameters
    }
}

// MARK: - OpenAPI Import Support

extension MockEndpoint {
    /// Creates a mock endpoint from an OpenAPI endpoint definition
    static func from(openAPIEndpoint: OpenAPIEndpoint) -> MockEndpoint {
        let endpoint = MockEndpoint(
            path: openAPIEndpoint.path,
            method: openAPIEndpoint.method,
            name: openAPIEndpoint.name,
            endpointDescription: openAPIEndpoint.description,
            isEnabled: true
        )
        
        // Add a default success response
        let response = MockResponse.defaultJSONResponse()
        response.endpoint = endpoint
        endpoint.responses.append(response)
        
        return endpoint
    }
}
