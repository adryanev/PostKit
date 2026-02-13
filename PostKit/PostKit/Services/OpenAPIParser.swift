import Foundation

struct OpenAPIEndpoint {
    var name: String
    var method: HTTPMethod
    var path: String
    var parameters: [OpenAPIParameter]
    var requestBody: OpenAPIRequestBody?
}

struct OpenAPIParameter {
    var name: String
    var location: String
}

struct OpenAPIRequestBody {
    var contentType: String
}

enum OpenAPIParserError: LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case missingInfo
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid OpenAPI format"
        case .unsupportedVersion:
            return "Unsupported OpenAPI version"
        case .missingInfo:
            return "Missing required info section"
        }
    }
}

final class OpenAPIParser: Sendable {
    func parse(_ data: Data) throws -> (info: OpenAPIInfo, endpoints: [OpenAPIEndpoint], servers: [String]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAPIParserError.invalidFormat
        }
        
        guard let openapiVersion = json["openapi"] as? String else {
            throw OpenAPIParserError.invalidFormat
        }
        
        guard openapiVersion.hasPrefix("3.") else {
            throw OpenAPIParserError.unsupportedVersion
        }
        
        guard let infoDict = json["info"] as? [String: Any] else {
            throw OpenAPIParserError.missingInfo
        }
        
        let info = OpenAPIInfo(
            title: infoDict["title"] as? String ?? "Untitled",
            version: infoDict["version"] as? String ?? "1.0",
            description: infoDict["description"] as? String
        )
        
        var servers: [String] = []
        if let serversArray = json["servers"] as? [[String: Any]] {
            for server in serversArray {
                if let url = server["url"] as? String {
                    servers.append(url)
                }
            }
        }
        
        var endpoints: [OpenAPIEndpoint] = []
        
        if let paths = json["paths"] as? [String: [String: Any]] {
            for (path, methods) in paths {
                for (methodKey, methodValue) in methods {
                    guard let methodValue = methodValue as? [String: Any],
                          let method = HTTPMethod(rawValue: methodKey.uppercased()) else {
                        continue
                    }
                    
                    let operationId = methodValue["operationId"] as? String
                    let summary = methodValue["summary"] as? String

                    let name = operationId ?? summary ?? "\(method.rawValue) \(path)"
                    
                    var parameters: [OpenAPIParameter] = []
                    if let paramsArray = methodValue["parameters"] as? [[String: Any]] {
                        for param in paramsArray {
                            parameters.append(OpenAPIParameter(
                                name: param["name"] as? String ?? "",
                                location: param["in"] as? String ?? "query"
                            ))
                        }
                    }
                    
                    var requestBody: OpenAPIRequestBody?
                    if let requestBodyDict = methodValue["requestBody"] as? [String: Any],
                       let content = requestBodyDict["content"] as? [String: [String: Any]] {
                        let contentType = content.keys.first ?? "application/json"
                        requestBody = OpenAPIRequestBody(contentType: contentType)
                    }
                    
                    endpoints.append(OpenAPIEndpoint(
                        name: name,
                        method: method,
                        path: path,
                        parameters: parameters,
                        requestBody: requestBody
                    ))
                }
            }
        }
        
        return (info, endpoints, servers)
    }
}

struct OpenAPIInfo {
    let title: String
    let version: String
    let description: String?
}
