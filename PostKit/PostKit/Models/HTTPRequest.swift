import Foundation
import SwiftData

@Model
final class HTTPRequest {
    @Attribute(.unique) var id: UUID
    var name: String
    var methodRaw: String
    var urlTemplate: String
    var headersData: Data?
    var queryParamsData: Data?
    var bodyTypeRaw: String
    var bodyContent: String?
    var authConfigData: Data?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    
    var collection: RequestCollection?
    var folder: Folder?
    var history: [HistoryEntry] = []
    
    @Transient var method: HTTPMethod {
        get { HTTPMethod(rawValue: methodRaw) ?? .get }
        set { methodRaw = newValue.rawValue }
    }
    
    @Transient var bodyType: BodyType {
        get { BodyType(rawValue: bodyTypeRaw) ?? .none }
        set { bodyTypeRaw = newValue.rawValue }
    }
    
    @Transient var authConfig: AuthConfig {
        get {
            guard let data = authConfigData else { return AuthConfig() }
            return (try? JSONDecoder().decode(AuthConfig.self, from: data)) ?? AuthConfig()
        }
        set {
            authConfigData = try? JSONEncoder().encode(newValue)
        }
    }
    
    init(name: String, method: HTTPMethod = .get, url: String = "") {
        self.id = UUID()
        self.name = name
        self.methodRaw = method.rawValue
        self.urlTemplate = url
        self.bodyTypeRaw = BodyType.none.rawValue
        self.sortOrder = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
