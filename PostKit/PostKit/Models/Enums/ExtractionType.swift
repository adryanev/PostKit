import Foundation

/// Types of extraction supported from HTTP responses
enum ExtractionType: String, Codable, CaseIterable, Sendable {
    case jsonPath = "jsonpath"
    case regex = "regex"
    case header = "header"
    case statusCode = "status-code"
    
    var displayName: String {
        switch self {
        case .jsonPath: return "JSONPath"
        case .regex: return "Regex"
        case .header: return "Header"
        case .statusCode: return "Status Code"
        }
    }
    
    var placeholder: String {
        switch self {
        case .jsonPath: return "$.data.token"
        case .regex: return "token\":\"([^\"]+)\""
        case .header: return "X-Auth-Token"
        case .statusCode: return "200"
        }
    }
    
    var description: String {
        switch self {
        case .jsonPath: return "Extract value from JSON response using JSONPath syntax"
        case .regex: return "Extract value using regular expression (first capture group)"
        case .header: return "Extract value from response header"
        case .statusCode: return "Use the HTTP status code"
        }
    }
}
