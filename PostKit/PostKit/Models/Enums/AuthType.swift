import Foundation

enum AuthType: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case bearer = "bearer"
    case basic = "basic"
    case apiKey = "api-key"
    
    var displayName: String {
        switch self {
        case .none: return "No Auth"
        case .bearer: return "Bearer Token"
        case .basic: return "Basic Auth"
        case .apiKey: return "API Key"
        }
    }
}

struct AuthConfig: Codable, Sendable {
    var type: AuthType
    var token: String?
    var username: String?
    var password: String?
    var apiKeyName: String?
    var apiKeyValue: String?
    var apiKeyLocation: APIKeyLocation?
    
    enum APIKeyLocation: String, Codable, Sendable {
        case header
        case queryParam
    }
    
    init(type: AuthType = .none) {
        self.type = type
    }
}
