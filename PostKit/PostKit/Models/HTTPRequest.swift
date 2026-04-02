import Foundation
import SwiftData

@Model
final class HTTPRequest {
    var id: UUID
    var name: String
    var methodRaw: String
    var urlTemplate: String
    var headersData: Data?
    var queryParamsData: Data?
    var pathVariablesData: Data?
    var bodyTypeRaw: String
    var bodyContent: String?
    var authConfigData: Data?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var openAPIPath: String?
    var openAPIMethod: String?
    var preRequestScript: String?
    var postRequestScript: String?
    var isPinned: Bool = false
    
    var collection: RequestCollection?
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \HistoryEntry.request)
    var history: [HistoryEntry] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ResponseExample.request)
    var examples: [ResponseExample] = []
    
    @Transient var method: HTTPMethod {
        get { HTTPMethod(rawValue: methodRaw) ?? .get }
        set { methodRaw = newValue.rawValue }
    }
    
    @Transient var bodyType: BodyType {
        get { BodyType(rawValue: bodyTypeRaw) ?? .none }
        set { bodyTypeRaw = newValue.rawValue }
    }
    
    @Transient private var _cachedAuthConfig: AuthConfig?
    @Transient private var _authConfigDataSnapshot: Data?

    @Transient var authConfig: AuthConfig {
        get {
            if let cached = _cachedAuthConfig, _authConfigDataSnapshot == authConfigData {
                return cached
            }
            guard let data = authConfigData else { return AuthConfig() }
            let config = (try? JSONDecoder().decode(AuthConfig.self, from: data)) ?? AuthConfig()
            _cachedAuthConfig = config
            _authConfigDataSnapshot = authConfigData
            return config
        }
        set {
            _cachedAuthConfig = newValue
            authConfigData = try? JSONEncoder().encode(newValue)
            _authConfigDataSnapshot = authConfigData
        }
    }
    
    @Transient private var _cachedHeaders: [KeyValuePair]?
    @Transient private var _headersDataSnapshot: Data?
    
    @Transient var headers: [KeyValuePair] {
        get {
            if let cached = _cachedHeaders, _headersDataSnapshot == headersData {
                return cached
            }
            let decoded = [KeyValuePair].decode(from: headersData)
            _cachedHeaders = decoded
            _headersDataSnapshot = headersData
            return decoded
        }
        set {
            _cachedHeaders = newValue
            headersData = newValue.encode()
            _headersDataSnapshot = headersData
        }
    }
    
    @Transient private var _cachedQueryParams: [KeyValuePair]?
    @Transient private var _queryParamsDataSnapshot: Data?
    
    @Transient var queryParams: [KeyValuePair] {
        get {
            if let cached = _cachedQueryParams, _queryParamsDataSnapshot == queryParamsData {
                return cached
            }
            let decoded = [KeyValuePair].decode(from: queryParamsData)
            _cachedQueryParams = decoded
            _queryParamsDataSnapshot = queryParamsData
            return decoded
        }
        set {
            _cachedQueryParams = newValue
            queryParamsData = newValue.encode()
            _queryParamsDataSnapshot = queryParamsData
        }
    }
    
    @Transient private var _cachedPathVariables: [KeyValuePair]?
    @Transient private var _pathVariablesDataSnapshot: Data?
    
    @Transient var pathVariables: [KeyValuePair] {
        get {
            if let cached = _cachedPathVariables, _pathVariablesDataSnapshot == pathVariablesData {
                return cached
            }
            let decoded = [KeyValuePair].decode(from: pathVariablesData)
            _cachedPathVariables = decoded
            _pathVariablesDataSnapshot = pathVariablesData
            return decoded
        }
        set {
            _cachedPathVariables = newValue
            pathVariablesData = newValue.encode()
            _pathVariablesDataSnapshot = pathVariablesData
        }
    }
    
    init(name: String, method: HTTPMethod = .get, url: String = "", openAPIPath: String? = nil, openAPIMethod: String? = nil) {
        self.id = UUID()
        self.name = name
        self.methodRaw = method.rawValue
        self.urlTemplate = url
        self.bodyTypeRaw = BodyType.none.rawValue
        self.sortOrder = 0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.openAPIPath = openAPIPath
        self.openAPIMethod = openAPIMethod
    }

    func duplicated() -> HTTPRequest {
        let copy = HTTPRequest(name: "\(name) (Copy)")
        copy.methodRaw = methodRaw
        copy.urlTemplate = urlTemplate
        copy.headersData = headersData
        copy.queryParamsData = queryParamsData
        copy.pathVariablesData = pathVariablesData
        copy.bodyTypeRaw = bodyTypeRaw
        copy.bodyContent = bodyContent
        copy.authConfigData = authConfigData
        copy.preRequestScript = preRequestScript
        copy.postRequestScript = postRequestScript
        return copy
    }
}
