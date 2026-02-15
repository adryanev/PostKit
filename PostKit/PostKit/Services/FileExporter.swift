import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ExportedCollection: Codable {
    let name: String
    let exportedAt: Date
    var requests: [ExportedRequest]
    var environments: [ExportedEnvironment]
}

struct ExportedRequest: Codable {
    let name: String
    let method: String
    let url: String
    let headers: [ExportedKeyValuePair]
    let queryParams: [ExportedKeyValuePair]
    let bodyType: String
    let bodyContent: String?
    let openAPIPath: String?
    let openAPIMethod: String?
}

struct ExportedEnvironment: Codable {
    let name: String
    let variables: [ExportedVariable]
}

struct ExportedVariable: Codable {
    let key: String
    let value: String
    let isSecret: Bool
    let isEnabled: Bool
}

struct ExportedKeyValuePair: Codable {
    let key: String
    let value: String
    let isEnabled: Bool
}

@MainActor
final class FileExporter: FileExporterProtocol {
    // Header keys whose values are stripped on export to prevent credential leaks.
    // Comparison is case-insensitive.
    private static let sensitiveHeaderKeys: Set<String> = [
        "authorization",
        "x-api-key",
        "x-auth-token",
        "proxy-authorization",
        "cookie",
    ]

    func exportCollection(_ collection: RequestCollection) throws -> URL {
        var exported = ExportedCollection(
            name: collection.name,
            exportedAt: Date(),
            requests: [],
            environments: []
        )

        for request in collection.requests {
            // Auth headers are stripped for security — sensitive header values
            // are replaced with "[REDACTED]" so exported files never contain
            // credentials by default.
            let headers = [KeyValuePair].decode(from: request.headersData).map {
                let isSensitive = Self.sensitiveHeaderKeys.contains($0.key.lowercased())
                return ExportedKeyValuePair(
                    key: $0.key,
                    value: isSensitive ? "[REDACTED]" : $0.value,
                    isEnabled: $0.isEnabled
                )
            }
            
            let queryParams = [KeyValuePair].decode(from: request.queryParamsData).map {
                ExportedKeyValuePair(key: $0.key, value: $0.value, isEnabled: $0.isEnabled)
            }
            
            exported.requests.append(ExportedRequest(
                name: request.name,
                method: request.method.rawValue,
                url: request.urlTemplate,
                headers: headers,
                queryParams: queryParams,
                bodyType: request.bodyType.rawValue,
                bodyContent: request.bodyContent,
                openAPIPath: request.openAPIPath,
                openAPIMethod: request.openAPIMethod
            ))
        }
        
        for env in collection.environments {
            let variables = env.variables.map {
                ExportedVariable(key: $0.key, value: $0.isSecret ? "" : $0.value, isSecret: $0.isSecret, isEnabled: $0.isEnabled)
            }
            exported.environments.append(ExportedEnvironment(name: env.name, variables: variables))
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(exported)
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Collection"
        savePanel.nameFieldStringValue = "\(collection.name.replacingOccurrences(of: " ", with: "-")).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        
        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            throw FileExporterError.cancelled
        }
        
        try data.write(to: url)
        return url
    }
    
    func importCollection(from url: URL, into context: ModelContext) throws -> RequestCollection {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let exported = try decoder.decode(ExportedCollection.self, from: data)
        
        let collection = RequestCollection(name: exported.name)
        context.insert(collection)
        
        for exportedRequest in exported.requests {
            guard let method = HTTPMethod(rawValue: exportedRequest.method) else { continue }
            
            let request = HTTPRequest(
                name: exportedRequest.name,
                method: method,
                url: exportedRequest.url,
                openAPIPath: exportedRequest.openAPIPath,
                openAPIMethod: exportedRequest.openAPIMethod
            )
            
            let headers = exportedRequest.headers.map {
                KeyValuePair(key: $0.key, value: $0.value, isEnabled: $0.isEnabled)
            }
            request.headersData = headers.encode()
            
            let queryParams = exportedRequest.queryParams.map {
                KeyValuePair(key: $0.key, value: $0.value, isEnabled: $0.isEnabled)
            }
            request.queryParamsData = queryParams.encode()
            
            request.bodyType = BodyType(rawValue: exportedRequest.bodyType) ?? .none
            request.bodyContent = exportedRequest.bodyContent
            
            request.collection = collection
            request.sortOrder = collection.requests.count
            context.insert(request)
        }
        
        for exportedEnv in exported.environments {
            let env = APIEnvironment(name: exportedEnv.name)
            
            for exportedVar in exportedEnv.variables {
                let variable = Variable(
                    key: exportedVar.key,
                    value: exportedVar.value,
                    isSecret: exportedVar.isSecret,
                    isEnabled: exportedVar.isEnabled
                )
                variable.environment = env
            }
            
            env.collection = collection
            context.insert(env)
        }
        
        return collection
    }
}

enum FileExporterError: LocalizedError {
    case cancelled
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Export cancelled"
        case .invalidFormat:
            return "Invalid file format"
        }
    }
}
