import Foundation
import Yams

struct OpenAPISpec: Sendable {
    let info: OpenAPIInfo
    let servers: [OpenAPIServer]
    let endpoints: [OpenAPIEndpoint]
    let securitySchemes: [OpenAPISecurityScheme]
    let refSkipCount: Int
}

struct OpenAPIServer: Sendable {
    let url: String
    let description: String?
    let variables: [OpenAPIServerVariable]
}

struct OpenAPIServerVariable: Sendable {
    let name: String
    let defaultValue: String
    let enumValues: [String]?
    let description: String?
}

struct OpenAPISecurityScheme: Sendable {
    let name: String
    let type: SecuritySchemeType
}

enum SecuritySchemeType: Sendable {
    case http(scheme: String)
    case apiKey(name: String, location: String)
    case unsupported(String)
}

struct OpenAPIEndpoint: Sendable, Identifiable {
    var id: String { "\(method.rawValue) \(path)" }
    var name: String
    var method: HTTPMethod
    var path: String
    var parameters: [OpenAPIParameter]
    var requestBody: OpenAPIRequestBody?
    var tags: [String]
    var operationId: String?
    var description: String?
    var security: [String]?
}

struct OpenAPIParameter: Sendable {
    var name: String
    var location: String
}

struct OpenAPIRequestBody: Sendable {
    var contentType: String
}

enum OpenAPIParserError: LocalizedError, Sendable {
    case invalidFormat
    case unsupportedVersion
    case missingInfo
    case missingTitle
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid OpenAPI format"
        case .unsupportedVersion:
            return "Unsupported OpenAPI version"
        case .missingInfo:
            return "Missing required info section"
        case .missingTitle:
            return "Missing required info.title"
        }
    }
}

final class OpenAPIParser: OpenAPIParserProtocol, Sendable {
    private let httpMethods: Set<String> = ["get", "put", "post", "delete", "options", "head", "patch"]
    
    func parse(_ data: Data) throws -> (info: OpenAPIInfo, endpoints: [OpenAPIEndpoint], servers: [String]) {
        let spec = try parseSpec(data)
        let serverURLs = spec.servers.map { $0.url }
        return (spec.info, spec.endpoints, serverURLs)
    }
    
    func parseSpec(_ data: Data) throws -> OpenAPISpec {
        let json: [String: Any]
        
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = jsonObj
        } else if let yamlString = String(data: data, encoding: .utf8),
                  let yamlObj = try? Yams.load(yaml: yamlString) as? [String: Any] {
            json = yamlObj
        } else {
            throw OpenAPIParserError.invalidFormat
        }
        
        let openapiVersion: String
        if let v = json["openapi"] as? String {
            openapiVersion = v
        } else if let v = json["openapi"] as? Double {
            openapiVersion = String(v)
        } else {
            throw OpenAPIParserError.invalidFormat
        }
        
        guard openapiVersion.hasPrefix("3.") else {
            throw OpenAPIParserError.unsupportedVersion
        }
        
        guard let infoDict = json["info"] as? [String: Any] else {
            throw OpenAPIParserError.missingInfo
        }
        
        guard let title = infoDict["title"] as? String, !title.isEmpty else {
            throw OpenAPIParserError.missingTitle
        }
        
        let info = OpenAPIInfo(
            title: title,
            version: infoDict["version"] as? String ?? "1.0",
            description: infoDict["description"] as? String
        )
        
        let servers = parseServers(json["servers"] as? [[String: Any]])
        let securitySchemes = parseSecuritySchemes(json["components"] as? [String: Any])
        let globalSecurity = json["security"] as? [[String: Any]]
        
        var totalRefSkips = 0
        var endpoints: [OpenAPIEndpoint] = []
        
        if let paths = json["paths"] as? [String: [String: Any]] {
            for (path, pathItem) in paths {
                let pathLevelParams = pathItem["parameters"] as? [[String: Any]] ?? []
                
                for (methodKey, methodValue) in pathItem {
                    guard httpMethods.contains(methodKey.lowercased()),
                          let methodValue = methodValue as? [String: Any],
                          let method = HTTPMethod(rawValue: methodKey.uppercased()) else {
                        continue
                    }
                    
                    let operationId = methodValue["operationId"] as? String
                    let summary = methodValue["summary"] as? String
                    let description = methodValue["description"] as? String
                    let name = operationId ?? summary ?? "\(method.rawValue) \(path)"
                    let tags = methodValue["tags"] as? [String] ?? []
                    
                    let operationParams = methodValue["parameters"] as? [[String: Any]] ?? []
                    let (mergedParams, refSkips) = mergeParameters(
                        pathLevel: pathLevelParams,
                        operationLevel: operationParams
                    )
                    totalRefSkips += refSkips
                    
                    let parameters = mergedParams.compactMap { param -> OpenAPIParameter? in
                        guard let name = param["name"] as? String,
                              let location = param["in"] as? String else {
                            return nil
                        }
                        return OpenAPIParameter(name: name, location: location)
                    }.sorted { ($0.location, $0.name) < ($1.location, $1.name) }
                    
                    var requestBody: OpenAPIRequestBody?
                    if let requestBodyDict = methodValue["requestBody"] as? [String: Any],
                       let content = requestBodyDict["content"] as? [String: Any] {
                        let contentType = content.keys.first ?? "application/json"
                        requestBody = OpenAPIRequestBody(contentType: contentType)
                    }
                    
                    let operationSecurity = methodValue["security"] as? [[String: Any]]
                    let effectiveSecurity = resolveEffectiveSecurity(
                        operationSecurity: operationSecurity,
                        globalSecurity: globalSecurity
                    )
                    
                    let convertedPath = convertPathParameters(path)
                    
                    endpoints.append(OpenAPIEndpoint(
                        name: name,
                        method: method,
                        path: convertedPath,
                        parameters: parameters,
                        requestBody: requestBody,
                        tags: tags,
                        operationId: operationId,
                        description: description,
                        security: effectiveSecurity
                    ))
                }
            }
        }
        
        endpoints.sort { ($0.path, $0.method.rawValue) < ($1.path, $1.method.rawValue) }
        
        return OpenAPISpec(
            info: info,
            servers: servers,
            endpoints: endpoints,
            securitySchemes: securitySchemes,
            refSkipCount: totalRefSkips
        )
    }
    
    private func parseServers(_ serversArray: [[String: Any]]?) -> [OpenAPIServer] {
        guard let serversArray else { return [] }
        
        return serversArray.compactMap { server -> OpenAPIServer? in
            guard let url = server["url"] as? String else { return nil }
            
            let description = server["description"] as? String
            var variables: [OpenAPIServerVariable] = []
            
            if let varsDict = server["variables"] as? [String: [String: Any]] {
                for (name, varInfo) in varsDict {
                    let defaultValue = varInfo["default"] as? String ?? ""
                    let enumValues = varInfo["enum"] as? [String]
                    let varDescription = varInfo["description"] as? String
                    
                    variables.append(OpenAPIServerVariable(
                        name: name,
                        defaultValue: defaultValue,
                        enumValues: enumValues,
                        description: varDescription
                    ))
                }
            }
            
            return OpenAPIServer(url: url, description: description, variables: variables)
        }
    }
    
    private func parseSecuritySchemes(_ components: [String: Any]?) -> [OpenAPISecurityScheme] {
        guard let schemes = components?["securitySchemes"] as? [String: [String: Any]] else {
            return []
        }
        
        return schemes.compactMap { (name, scheme) -> OpenAPISecurityScheme? in
            guard let type = scheme["type"] as? String else { return nil }
            
            let schemeType: SecuritySchemeType
            switch type {
            case "http":
                let schemeName = scheme["scheme"] as? String ?? "bearer"
                schemeType = .http(scheme: schemeName)
            case "apiKey":
                let keyName = scheme["name"] as? String ?? ""
                let location = scheme["in"] as? String ?? "header"
                schemeType = .apiKey(name: keyName, location: location)
            default:
                schemeType = .unsupported(type)
            }
            
            return OpenAPISecurityScheme(name: name, type: schemeType)
        }
    }
    
    private func mergeParameters(
        pathLevel: [[String: Any]],
        operationLevel: [[String: Any]]
    ) -> (merged: [[String: Any]], refSkips: Int) {
        var merged: [String: [String: Any]] = [:]
        var skips = 0
        
        for param in pathLevel {
            if param["$ref"] != nil {
                skips += 1
                continue
            }
            guard let name = param["name"] as? String,
                  let location = param["in"] as? String else { continue }
            merged["\(name)|\(location)"] = param
        }
        
        for param in operationLevel {
            if param["$ref"] != nil {
                skips += 1
                continue
            }
            guard let name = param["name"] as? String,
                  let location = param["in"] as? String else { continue }
            merged["\(name)|\(location)"] = param
        }
        
        return (Array(merged.values), skips)
    }
    
    private func convertPathParameters(_ path: String) -> String {
        let pattern = "\\{(\\w+)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return path }
        
        let range = NSRange(path.startIndex..., in: path)
        let result = regex.stringByReplacingMatches(
            in: path,
            options: [],
            range: range,
            withTemplate: "{{$1}}"
        )
        
        return result
    }
    
    private func resolveEffectiveSecurity(
        operationSecurity: [[String: Any]]?,
        globalSecurity: [[String: Any]]?
    ) -> [String]? {
        let securityToUse = operationSecurity ?? globalSecurity
        
        guard let security = securityToUse, !security.isEmpty else {
            if operationSecurity != nil {
                return []
            }
            return nil
        }
        
        for secItem in security {
            if let secName = secItem.keys.first {
                return [secName]
            }
        }
        
        return nil
    }
}

struct OpenAPIInfo: Sendable {
    let title: String
    let version: String
    let description: String?
}
