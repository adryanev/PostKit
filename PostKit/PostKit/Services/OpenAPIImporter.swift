import Foundation
import SwiftData

@MainActor
final class OpenAPIImporter {
    func importNewCollection(
        spec: OpenAPISpec,
        selectedEndpoints: [OpenAPIEndpoint],
        into context: ModelContext
    ) throws -> RequestCollection {
        let collection = RequestCollection(name: spec.info.title)
        context.insert(collection)
        
        var folderCache: [String: Folder] = [:]
        
        for endpoint in selectedEndpoints {
            let request = createRequest(
                from: endpoint,
                spec: spec,
                folderCache: &folderCache,
                collection: collection,
                context: context
            )
            request.sortOrder = collection.requests.count
            context.insert(request)
        }
        
        if spec.servers.isEmpty {
            let env = APIEnvironment(name: spec.info.title)
            env.isActive = true
            env.collection = collection
            context.insert(env)
            
            let baseUrlVar = Variable(key: "baseUrl", value: "", isSecret: false, isEnabled: true)
            baseUrlVar.environment = env
            context.insert(baseUrlVar)
            
            createAuthVariables(
                from: spec.securitySchemes,
                for: env,
                existingKeys: ["baseUrl"],
                context: context
            )
        } else {
            for (index, server) in spec.servers.enumerated() {
                let env = APIEnvironment(name: server.description ?? server.url)
                env.isActive = index == 0
                env.openAPIServerURL = server.url
                env.collection = collection
                context.insert(env)
                
                var existingKeys = Set<String>()

                // Process server-defined variables first so they take priority
                for variable in server.variables {
                    if !existingKeys.contains(variable.name) {
                        let v = Variable(
                            key: variable.name,
                            value: variable.defaultValue,
                            isSecret: false,
                            isEnabled: true
                        )
                        v.environment = env
                        context.insert(v)
                        existingKeys.insert(variable.name)
                    }
                }

                // Only create auto-generated baseUrl if the server didn't define one
                let rawURL = server.url.hasSuffix("/") ? String(server.url.dropLast()) : server.url
                let convertedURL = convertServerURLVariables(rawURL)

                if !existingKeys.contains("baseUrl") {
                    let baseUrlVar = Variable(key: "baseUrl", value: convertedURL, isSecret: false, isEnabled: true)
                    baseUrlVar.environment = env
                    context.insert(baseUrlVar)
                    existingKeys.insert("baseUrl")
                }
                
                createAuthVariables(
                    from: spec.securitySchemes,
                    for: env,
                    existingKeys: existingKeys,
                    context: context
                )
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
        
        updateEnvironments(for: collection, spec: spec, context: context)
        
        for folder in collection.folders where folder.requests.isEmpty {
            context.delete(folder)
        }
        
        collection.updatedAt = Date()
        try context.save()
    }
    
    // MARK: - Private Helpers
    
    private func createRequest(
        from endpoint: OpenAPIEndpoint,
        spec: OpenAPISpec,
        folderCache: inout [String: Folder],
        collection: RequestCollection,
        context: ModelContext
    ) -> HTTPRequest {
        let urlString = "{{baseUrl}}" + endpoint.path
        
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
        spec: OpenAPISpec
    ) {
        let urlString = "{{baseUrl}}" + endpoint.path
        
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
                config.token = "{{bearerToken}}"
            } else if schemeName == "basic" {
                config.type = .basic
                config.username = "{{basicUsername}}"
                config.password = "{{basicPassword}}"
            }
        case .apiKey(let name, let location):
            config.type = .apiKey
            config.apiKeyName = name
            config.apiKeyValue = "{{apiKeyValue}}"
            config.apiKeyLocation = location == "query" ? .queryParam : .header
        case .unsupported:
            break
        }
        
        return config
    }
    
    private func convertServerURLVariables(_ url: String) -> String {
        let pattern = "\\{(\\w+)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return url }
        let range = NSRange(url.startIndex..., in: url)
        return regex.stringByReplacingMatches(in: url, range: range, withTemplate: "{{$1}}")
    }
    
    private func createAuthVariables(
        from schemes: [OpenAPISecurityScheme],
        for environment: APIEnvironment,
        existingKeys: Set<String>,
        context: ModelContext
    ) {
        var createdKeys = Set<String>()
        
        for scheme in schemes {
            switch scheme.type {
            case .http(let schemeName):
                if schemeName == "bearer" && !existingKeys.contains("bearerToken") && !createdKeys.contains("bearerToken") {
                    let v = Variable(key: "bearerToken", value: "", isSecret: true, isEnabled: true)
                    v.environment = environment
                    context.insert(v)
                    createdKeys.insert("bearerToken")
                } else if schemeName == "basic" {
                    if !existingKeys.contains("basicUsername") && !createdKeys.contains("basicUsername") {
                        let u = Variable(key: "basicUsername", value: "", isSecret: false, isEnabled: true)
                        u.environment = environment
                        context.insert(u)
                        createdKeys.insert("basicUsername")
                    }
                    if !existingKeys.contains("basicPassword") && !createdKeys.contains("basicPassword") {
                        let p = Variable(key: "basicPassword", value: "", isSecret: true, isEnabled: true)
                        p.environment = environment
                        context.insert(p)
                        createdKeys.insert("basicPassword")
                    }
                }
            case .apiKey:
                if !existingKeys.contains("apiKeyValue") && !createdKeys.contains("apiKeyValue") {
                    let v = Variable(key: "apiKeyValue", value: "", isSecret: true, isEnabled: true)
                    v.environment = environment
                    context.insert(v)
                    createdKeys.insert("apiKeyValue")
                }
            case .unsupported:
                break
            }
        }
    }
    
    private func updateEnvironments(
        for collection: RequestCollection,
        spec: OpenAPISpec,
        context: ModelContext
    ) {
        let existingEnvs = collection.environments
        
        for server in spec.servers {
            let matchingEnv = existingEnvs.first { $0.openAPIServerURL == server.url }
                ?? existingEnvs.first { $0.name == (server.description ?? server.url) }
            
            if let env = matchingEnv {
                let existingKeys = Set(env.variables.map { $0.key })
                addMissingVariables(
                    to: env,
                    server: server,
                    schemes: spec.securitySchemes,
                    existingKeys: existingKeys,
                    context: context
                )
            } else {
                let env = APIEnvironment(name: server.description ?? server.url)
                env.isActive = false
                env.openAPIServerURL = server.url
                env.collection = collection
                context.insert(env)
                
                var existingKeys = Set<String>()

                // Process server-defined variables first so they take priority
                for variable in server.variables {
                    if !existingKeys.contains(variable.name) {
                        let v = Variable(key: variable.name, value: variable.defaultValue, isSecret: false, isEnabled: true)
                        v.environment = env
                        context.insert(v)
                        existingKeys.insert(variable.name)
                    }
                }

                // Only create auto-generated baseUrl if the server didn't define one
                let rawURL = server.url.hasSuffix("/") ? String(server.url.dropLast()) : server.url
                let convertedURL = convertServerURLVariables(rawURL)

                if !existingKeys.contains("baseUrl") {
                    let baseUrlVar = Variable(key: "baseUrl", value: convertedURL, isSecret: false, isEnabled: true)
                    baseUrlVar.environment = env
                    context.insert(baseUrlVar)
                    existingKeys.insert("baseUrl")
                }
                
                createAuthVariables(
                    from: spec.securitySchemes,
                    for: env,
                    existingKeys: existingKeys,
                    context: context
                )
            }
        }
    }
    
    private func addMissingVariables(
        to environment: APIEnvironment,
        server: OpenAPIServer,
        schemes: [OpenAPISecurityScheme],
        existingKeys: Set<String>,
        context: ModelContext
    ) {
        var newKeys = existingKeys
        
        for variable in server.variables {
            if !newKeys.contains(variable.name) {
                let v = Variable(key: variable.name, value: variable.defaultValue, isSecret: false, isEnabled: true)
                v.environment = environment
                context.insert(v)
                newKeys.insert(variable.name)
            }
        }
        
        createAuthVariables(
            from: schemes,
            for: environment,
            existingKeys: newKeys,
            context: context
        )
    }
}
