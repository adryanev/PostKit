import Foundation

enum BodyType: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case json = "json"
    case formData = "form-data"
    case urlEncoded = "x-www-form-urlencoded"
    case raw = "raw"
    case xml = "xml"
    
    var contentType: String? {
        switch self {
        case .none: return nil
        case .json: return "application/json"
        case .formData: return "multipart/form-data"
        case .urlEncoded: return "application/x-www-form-urlencoded"
        case .raw: return "text/plain"
        case .xml: return "application/xml"
        }
    }
    
    var highlightrLanguage: String? {
        switch self {
        case .json: return "json"
        case .xml: return "xml"
        default: return nil
        }
    }
}
