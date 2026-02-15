import Foundation

struct EndpointSnapshot: Sendable, Identifiable {
    let id: String
    let requestID: UUID?
    let name: String
    let method: HTTPMethod
    let path: String
    let headers: [KeyValuePair]
    let queryParams: [KeyValuePair]
    let bodyType: BodyType
    let bodyContentType: String?
    let authDescription: String?
    let tags: [String]
}

struct EndpointChange: Sendable, Identifiable {
    let id: String
    let existing: EndpointSnapshot
    let incoming: EndpointSnapshot
    let incomingEndpoint: OpenAPIEndpoint
}

struct DiffResult: Sendable {
    let newEndpoints: [OpenAPIEndpoint]
    let changedEndpoints: [EndpointChange]
    let removedEndpoints: [EndpointSnapshot]
    let unchangedEndpoints: [EndpointSnapshot]
}

enum EndpointDecision: Sendable, Hashable {
    case addNew(OpenAPIEndpoint)
    case replaceExisting(requestID: UUID, with: OpenAPIEndpoint)
    case deleteExisting(requestID: UUID)
    case keepExisting(requestID: UUID)
}

final class OpenAPIDiffEngine: Sendable {
    func diff(
        spec: OpenAPISpec,
        selectedEndpoints: [OpenAPIEndpoint],
        serverURL: String,
        existingSnapshots: [EndpointSnapshot],
        securitySchemes: [OpenAPISecurityScheme]
    ) -> DiffResult {
        var newEndpoints: [OpenAPIEndpoint] = []
        var changedEndpoints: [EndpointChange] = []
        var unchangedEndpoints: [EndpointSnapshot] = []
        
        var unmatchedSnapshots = Dictionary(uniqueKeysWithValues: existingSnapshots.map { ($0.id, $0) })
        
        for endpoint in selectedEndpoints {
            let matchKey = "\(endpoint.method.rawValue) \(endpoint.path)"
            
            if let existingSnapshot = unmatchedSnapshots.removeValue(forKey: matchKey) {
                let incomingSnapshot = createSnapshotFromEndpoint(
                    endpoint,
                    serverURL: serverURL,
                    securitySchemes: securitySchemes
                )
                
                if snapshotsAreEqual(existingSnapshot, incomingSnapshot) {
                    unchangedEndpoints.append(existingSnapshot)
                } else {
                    changedEndpoints.append(EndpointChange(
                        id: matchKey,
                        existing: existingSnapshot,
                        incoming: incomingSnapshot,
                        incomingEndpoint: endpoint
                    ))
                }
            } else {
                newEndpoints.append(endpoint)
            }
        }
        
        let removedEndpoints = Array(unmatchedSnapshots.values)
        
        return DiffResult(
            newEndpoints: newEndpoints,
            changedEndpoints: changedEndpoints,
            removedEndpoints: removedEndpoints,
            unchangedEndpoints: unchangedEndpoints
        )
    }
    
    func createSnapshotFromEndpoint(
        _ endpoint: OpenAPIEndpoint,
        serverURL: String,
        securitySchemes: [OpenAPISecurityScheme]
    ) -> EndpointSnapshot {
        let headers = endpoint.parameters
            .filter { $0.location == "header" }
            .map { KeyValuePair(key: $0.name, value: "", isEnabled: true) }
        
        let queryParams = endpoint.parameters
            .filter { $0.location == "query" }
            .map { KeyValuePair(key: $0.name, value: "", isEnabled: true) }
        
        let bodyType = mapContentTypeToBodyType(endpoint.requestBody?.contentType)
        
        let authDescription = resolveAuthDescription(
            security: endpoint.security,
            schemes: securitySchemes
        )
        
        return EndpointSnapshot(
            id: "\(endpoint.method.rawValue) \(endpoint.path)",
            requestID: nil,
            name: endpoint.name,
            method: endpoint.method,
            path: endpoint.path,
            headers: headers,
            queryParams: queryParams,
            bodyType: bodyType,
            bodyContentType: endpoint.requestBody?.contentType,
            authDescription: authDescription,
            tags: endpoint.tags
        )
    }
    
    func createSnapshotFromRequest(_ request: HTTPRequest) -> EndpointSnapshot {
        let headers = [KeyValuePair].decode(from: request.headersData)
        let queryParams = [KeyValuePair].decode(from: request.queryParamsData)
        
        var authDescription: String? = nil
        let authConfig = request.authConfig
        if authConfig.type != .none {
            authDescription = authConfig.type.displayName
        }
        
        let matchPath = request.openAPIPath ?? request.urlTemplate
        let matchMethod = request.openAPIMethod ?? request.method.rawValue
        
        return EndpointSnapshot(
            id: "\(matchMethod) \(matchPath)",
            requestID: request.id,
            name: request.name,
            method: request.method,
            path: matchPath,
            headers: headers,
            queryParams: queryParams,
            bodyType: request.bodyType,
            bodyContentType: nil,
            authDescription: authDescription,
            tags: []
        )
    }
    
    private func snapshotsAreEqual(_ a: EndpointSnapshot, _ b: EndpointSnapshot) -> Bool {
        return a.name == b.name &&
               a.path == b.path &&
               a.method == b.method &&
               a.headers == b.headers &&
               a.queryParams == b.queryParams &&
               a.bodyType == b.bodyType &&
               a.authDescription == b.authDescription &&
               a.tags == b.tags
    }
    
    private func mapContentTypeToBodyType(_ contentType: String?) -> BodyType {
        guard let contentType else { return .none }
        
        if contentType.contains("json") { return .json }
        if contentType.contains("xml") { return .xml }
        if contentType.contains("form-urlencoded") { return .urlEncoded }
        if contentType.contains("form-data") { return .formData }
        return .raw
    }
    
    private func resolveAuthDescription(
        security: [String]?,
        schemes: [OpenAPISecurityScheme]
    ) -> String? {
        guard let security, !security.isEmpty else { return nil }
        
        guard let schemeName = security.first,
              let scheme = schemes.first(where: { $0.name == schemeName }) else {
            return nil
        }
        
        switch scheme.type {
        case .http(let schemeName):
            return schemeName == "bearer" ? "Bearer Token" : "Basic Auth"
        case .apiKey(let name, _):
            return "API Key (\(name))"
        case .unsupported:
            return nil
        }
    }
}
