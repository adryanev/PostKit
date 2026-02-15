import Foundation
import SwiftData

@MainActor
final class OpenAPIImporter {
    func importNewCollection(
        spec: OpenAPISpec,
        selectedEndpoints: [OpenAPIEndpoint],
        serverURL: String,
        into context: ModelContext
    ) throws -> RequestCollection {
        let collection = RequestCollection(name: spec.info.title)
        context.insert(collection)
        
        var folderCache: [String: Folder] = [:]
        
        for endpoint in selectedEndpoints {
            let request = createRequest(
                from: endpoint,
                serverURL: serverURL,
                spec: spec,
                folderCache: &folderCache,
                collection: collection,
                context: context
            )
            request.sortOrder = collection.requests.count
            context.insert(request)
        }
        
        for (index, server) in spec.servers.enumerated() {
            let env = APIEnvironment(name: server.description ?? server.url)
            env.isActive = index == 0
            env.collection = collection
            context.insert(env)
            
            for variable in server.variables {
                let v = Variable(
                    key: variable.name,
                    value: variable.defaultValue,
                    isSecret: false,
                    isEnabled: true
                )
                v.environment = env
            }
        }
        
        try context.save()
        return collection
    }
    
    func updateCollection(
        _ collection: RequestCollection,
        decisions: [EndpointDecision],
        spec: OpenAPISpec,
        selectedEndpoints: [OpenAPIEndpoint],
        serverURL: String,
        context: ModelContext
    ) throws {
        var folderCache: [String: Folder] = [:]
        
        for existingFolder in collection.folders {
            folderCache[existingFolder.name] = existingFolder
        }
        
        for decision in decisions {
            switch decision {
            case .addNew(let endpoint):
                let request = createRequest(
                    from: endpoint,
                    serverURL: serverURL,
                    spec: spec,
                    folderCache: &folderCache,
                    collection: collection,
                    context: context
                )
                request.sortOrder = collection.requests.count
                context.insert(request)
                
            case .replaceExisting(let requestID, let endpoint):
                guard let request = try? context.fetch(
                    FetchDescriptor<HTTPRequest>(predicate: #Predicate { $0.id == requestID })
                ).first else { continue }
                
                let originalMethod = request.method
                let originalSortOrder = request.sortOrder
                let originalFolder = request.folder
                
                updateRequest(
                    request,
                    from: endpoint,
                    serverURL: serverURL,
                    spec: spec
                )
                
                request.methodRaw = originalMethod.rawValue
                request.sortOrder = originalSortOrder
                
                let targetFolder = endpoint.tags.first.map { getOrCreateFolder(named: $0, in: &folderCache, collection: collection, context: context) }
                if request.folder !== targetFolder {
                    request.folder = targetFolder
                }
                
            case .deleteExisting(let requestID):
                guard let request = try? context.fetch(
                    FetchDescriptor<HTTPRequest>(predicate: #Predicate { $0.id == requestID })
                ).first else { continue }
                
                AuthConfig.deleteSecrets(forRequestID: request.id.uuidString)
                context.delete(request)
                
            case .keepExisting:
                break
            }
        }
        
        for folder in collection.folders where folder.requests.isEmpty {
            context.delete(folder)
        }
        
        collection.updatedAt = Date()
        try context.save()
    }
    
    // MARK: - Private Helpers
    
    private func createRequest(
        from endpoint: OpenAPIEndpoint,
        serverURL: String,
        spec: OpenAPISpec,
        folderCache: inout [String: Folder],
        collection: RequestCollection,
        context: ModelContext
    ) -> HTTPRequest {
        let urlString = serverURL.isEmpty ? endpoint.path : serverURL + endpoint.path
        
        let request = HTTPRequest(
            name: endpoint.name,
            method: endpoint.method,
            url: urlString,
            openAPIPath: endpoint.path,
            openAPIMethod: endpoint.method.rawValue
        )
        
        let headers = endpoint.parameters
            .filter { $0.location == "header" }
            .map { KeyValuePair(key: $0.name, value: "", isEnabled: true) }
        request.headersData = headers.encode()
        
        let queryParams = endpoint.parameters
            .filter { $0.location == "query" }
            .map { KeyValuePair(key: $0.name, value: "", isEnabled: true) }
        request.queryParamsData = queryParams.encode()
        
        if let requestBody = endpoint.requestBody {
            request.bodyType = mapContentTypeToBodyType(requestBody.contentType)
        }
        
        let authConfig = createAuthConfig(
            security: endpoint.security,
            schemes: spec.securitySchemes
        )
        request.authConfig = authConfig
        
        let folder = endpoint.tags.first.map { getOrCreateFolder(named: $0, in: &folderCache, collection: collection, context: context) }
        request.folder = folder
        request.collection = collection
        
        return request
    }
    
    private func updateRequest(
        _ request: HTTPRequest,
        from endpoint: OpenAPIEndpoint,
        serverURL: String,
        spec: OpenAPISpec
    ) {
        let urlString = serverURL.isEmpty ? endpoint.path : serverURL + endpoint.path
        
        request.name = endpoint.name
        request.urlTemplate = urlString
        request.openAPIPath = endpoint.path
        request.openAPIMethod = endpoint.method.rawValue
        request.updatedAt = Date()
        
        let headers = endpoint.parameters
            .filter { $0.location == "header" }
            .map { KeyValuePair(key: $0.name, value: "", isEnabled: true) }
        request.headersData = headers.encode()
        
        let queryParams = endpoint.parameters
            .filter { $0.location == "query" }
            .map { KeyValuePair(key: $0.name, value: "", isEnabled: true) }
        request.queryParamsData = queryParams.encode()
        
        if let requestBody = endpoint.requestBody {
            request.bodyType = mapContentTypeToBodyType(requestBody.contentType)
        }
        
        let authConfig = createAuthConfig(
            security: endpoint.security,
            schemes: spec.securitySchemes
        )
        request.authConfig = authConfig
    }
    
    private func getOrCreateFolder(
        named name: String,
        in cache: inout [String: Folder],
        collection: RequestCollection,
        context: ModelContext
    ) -> Folder {
        if let existing = cache[name] {
            return existing
        }
        
        let folder = Folder(name: name)
        folder.collection = collection
        folder.sortOrder = cache.count
        context.insert(folder)
        cache[name] = folder
        return folder
    }
    
    private func mapContentTypeToBodyType(_ contentType: String?) -> BodyType {
        guard let contentType else { return .none }
        
        if contentType.contains("json") { return .json }
        if contentType.contains("xml") { return .xml }
        if contentType.contains("form-urlencoded") { return .urlEncoded }
        if contentType.contains("form-data") { return .formData }
        return .raw
    }
    
    private func createAuthConfig(
        security: [String]?,
        schemes: [OpenAPISecurityScheme]
    ) -> AuthConfig {
        guard let security, let schemeName = security.first,
              let scheme = schemes.first(where: { $0.name == schemeName }) else {
            return AuthConfig()
        }
        
        var config = AuthConfig()
        
        switch scheme.type {
        case .http(let schemeName):
            if schemeName == "bearer" {
                config.type = .bearer
            } else if schemeName == "basic" {
                config.type = .basic
            }
        case .apiKey(let name, let location):
            config.type = .apiKey
            config.apiKeyName = name
            config.apiKeyLocation = location == "query" ? .queryParam : .header
        case .unsupported:
            break
        }
        
        return config
    }
}
