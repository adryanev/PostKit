import Foundation
import SwiftData

/// Defines the response content type for a mock endpoint
enum MockResponseBodyType: String, Codable, Sendable, CaseIterable {
    case json = "json"
    case text = "text"
    case xml = "xml"
    case html = "html"
    case binary = "binary"
    
    var contentType: String {
        switch self {
        case .json: return "application/json"
        case .text: return "text/plain"
        case .xml: return "application/xml"
        case .html: return "text/html"
        case .binary: return "application/octet-stream"
        }
    }
}

/// Defines a mock response for an endpoint
@Model
final class MockResponse {
    var id: UUID
    var name: String
    var statusCode: Int
    var headersData: Data?
    var bodyContent: String?
    var bodyTypeRaw: String
    var delayMs: Int
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    
    @Transient var bodyType: MockResponseBodyType {
        get { MockResponseBodyType(rawValue: bodyTypeRaw) ?? .json }
        set { bodyTypeRaw = newValue.rawValue }
    }
    
    @Transient var headers: [KeyValuePair] {
        get {
            guard let data = headersData else { return [] }
            return [KeyValuePair].decode(from: data)
        }
        set {
            headersData = newValue.encode()
        }
    }
    
    var endpoint: MockEndpoint?
    
    init(
        name: String = "Response",
        statusCode: Int = 200,
        bodyContent: String = "",
        bodyType: MockResponseBodyType = .json,
        delayMs: Int = 0,
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.statusCode = statusCode
        self.bodyContent = bodyContent
        self.bodyTypeRaw = bodyType.rawValue
        self.delayMs = delayMs
        self.isDefault = isDefault
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func duplicated() -> MockResponse {
        let copy = MockResponse(
            name: "\(name) (Copy)",
            statusCode: statusCode,
            bodyContent: bodyContent ?? "",
            bodyType: bodyType,
            delayMs: delayMs,
            isDefault: false
        )
        copy.headersData = headersData
        return copy
    }
}

// MARK: - Default Responses

extension MockResponse {
    static func defaultJSONResponse() -> MockResponse {
        let response = MockResponse(
            name: "Success",
            statusCode: 200,
            bodyContent: """
            {
              "message": "Mock response",
              "success": true
            }
            """,
            bodyType: .json,
            isDefault: true
        )
        response.headers = [
            KeyValuePair(key: "Content-Type", value: "application/json"),
            KeyValuePair(key: "X-Mock-Server", value: "PostKit")
        ]
        return response
    }
    
    static func defaultErrorResponse() -> MockResponse {
        let response = MockResponse(
            name: "Error",
            statusCode: 500,
            bodyContent: """
            {
              "error": "Internal Server Error",
              "message": "Mock error response"
            }
            """,
            bodyType: .json,
            isDefault: false
        )
        response.headers = [
            KeyValuePair(key: "Content-Type", value: "application/json")
        ]
        return response
    }
}
