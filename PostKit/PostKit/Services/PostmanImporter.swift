import Foundation
import SwiftData
import FactoryKit

struct PostmanImportPreview {
    let collectionName: String
    let folderCount: Int
    let requestCount: Int
    let scriptCount: Int
    let variableCount: Int
}

enum PostmanImportError: LocalizedError {
    case parseError(Error)
    case importFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .parseError(let error):
            return "Failed to parse Postman collection: \(error.localizedDescription)"
        case .importFailed(let message):
            return message
        }
    }
}

@MainActor
final class PostmanImporter {
    
    private let parser: PostmanParserProtocol
    private let maxFolderDepth = 2
    
    nonisolated init(parser: PostmanParserProtocol = PostmanParser()) {
        self.parser = parser
    }
    
    nonisolated func previewCollection(from data: Data) throws -> PostmanImportPreview {
        let collection = try parser.parse(data)
        
        var folderCount = 0
        var requestCount = 0
        var scriptCount = 0
        
        for item in collection.items {
            let counts = countItems(item)
            folderCount += counts.folders
            requestCount += counts.requests
            scriptCount += counts.scripts
        }
        
        return PostmanImportPreview(
            collectionName: collection.info.name,
            folderCount: folderCount,
            requestCount: requestCount,
            scriptCount: scriptCount,
            variableCount: collection.variables.count
        )
    }
    
    func importCollection(
        from data: Data,
        into context: ModelContext
    ) throws -> RequestCollection {
        let collection = try parser.parse(data)
        
        let requestCollection = RequestCollection(name: collection.info.name)
        context.insert(requestCollection)
        
        var folderCache: [String: Folder] = [:]
        var sortOrder = 0
        
        for item in collection.items {
            importItem(
                item,
                into: context,
                collection: requestCollection,
                folderCache: &folderCache,
                parentFolder: nil,
                currentDepth: 0,
                sortOrder: &sortOrder
            )
        }
        
        if !collection.variables.isEmpty {
            let env = APIEnvironment(name: "\(collection.info.name) - Variables")
            env.isActive = false
            env.collection = requestCollection
            context.insert(env)
            
            for postmanVar in collection.variables {
                let variable = Variable(
                    key: postmanVar.key,
                    value: postmanVar.value ?? "",
                    isSecret: postmanVar.type == "secret",
                    isEnabled: true
                )
                variable.environment = env
            }
        }
        
        try context.save()
        return requestCollection
    }
    
    func importEnvironment(
        from data: Data,
        into context: ModelContext,
        collection: RequestCollection,
        secretKeys: Set<String> = []
    ) throws -> APIEnvironment {
        let postmanEnv = try parser.parseEnvironment(data)
        
        let env = APIEnvironment(name: postmanEnv.name)
        env.isActive = false
        env.collection = collection
        context.insert(env)
        
        for postmanVar in postmanEnv.values {
            let isSecret = secretKeys.contains(postmanVar.key) || postmanVar.type == "secret"
            let variable = Variable(
                key: postmanVar.key,
                value: isSecret ? "" : (postmanVar.value ?? ""),
                isSecret: isSecret,
                isEnabled: true
            )
            variable.environment = env
            
            if isSecret, let value = postmanVar.value, !value.isEmpty {
                variable.secureValue = value
            }
        }
        
        try context.save()
        return env
    }
    
    private nonisolated func countItems(_ item: PostmanItem) -> (folders: Int, requests: Int, scripts: Int) {
        var folders = 0
        var requests = 0
        var scripts = 0
        
        if item.request != nil {
            requests += 1
            if let events = item.events {
                for event in events {
                    if event.listen == "prerequest" || event.listen == "test" {
                        if let exec = event.script?.exec, !exec.isEmpty {
                            scripts += 1
                            break
                        }
                    }
                }
            }
        } else if let items = item.items, !items.isEmpty {
            folders += 1
            for child in items {
                let childCounts = countItems(child)
                folders += childCounts.folders
                requests += childCounts.requests
                scripts += childCounts.scripts
            }
        }
        
        return (folders, requests, scripts)
    }
    
    private func importItem(
        _ item: PostmanItem,
        into context: ModelContext,
        collection: RequestCollection,
        folderCache: inout [String: Folder],
        parentFolder: Folder?,
        currentDepth: Int,
        sortOrder: inout Int
    ) {
        if let request = item.request {
            let httpRequest = createHTTPRequest(
                from: item,
                request: request,
                sortOrder: sortOrder
            )
            sortOrder += 1
            
            if let folder = parentFolder {
                httpRequest.folder = folder
            } else {
                httpRequest.collection = collection
            }
            
            context.insert(httpRequest)
        } else if let items = item.items, !items.isEmpty {
            let folder: Folder
            if currentDepth >= maxFolderDepth {
                if let existingFolder = parentFolder {
                    folder = existingFolder
                } else {
                    folder = getOrCreateFolder(
                        named: item.name,
                        in: &folderCache,
                        collection: collection,
                        context: context
                    )
                }
            } else {
                folder = getOrCreateFolder(
                    named: item.name,
                    in: &folderCache,
                    collection: collection,
                    context: context
                )
            }
            
            for child in items {
                importItem(
                    child,
                    into: context,
                    collection: collection,
                    folderCache: &folderCache,
                    parentFolder: folder,
                    currentDepth: currentDepth + 1,
                    sortOrder: &sortOrder
                )
            }
        }
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
    
    private func createHTTPRequest(
        from item: PostmanItem,
        request: PostmanRequest,
        sortOrder: Int
    ) -> HTTPRequest {
        let method = HTTPMethod(rawValue: request.method.lowercased()) ?? .get
        let url = request.url.rawValue
        
        let httpRequest = HTTPRequest(
            name: item.name,
            method: method,
            url: url
        )
        httpRequest.sortOrder = sortOrder
        
        let headers = request.headers.compactMap { kv -> KeyValuePair? in
            guard !kv.key.isEmpty, kv.enabled != false else { return nil }
            return KeyValuePair(key: kv.key, value: kv.value ?? "", isEnabled: true)
        }
        httpRequest.headersData = headers.encode()
        
        if case .structured(let urlObj) = request.url,
           let query = urlObj.query {
            let queryParams = query.compactMap { kv -> KeyValuePair? in
                guard !kv.key.isEmpty, kv.enabled != false else { return nil }
                return KeyValuePair(key: kv.key, value: kv.value ?? "", isEnabled: true)
            }
            httpRequest.queryParamsData = queryParams.encode()
        }
        
        if let body = request.body {
            switch body.mode {
            case "raw":
                httpRequest.bodyType = .raw
                httpRequest.bodyContent = body.raw
                if let raw = body.raw, raw.hasPrefix("{") || raw.hasPrefix("[") {
                    httpRequest.bodyType = .json
                } else if let raw = body.raw, raw.hasPrefix("<") {
                    httpRequest.bodyType = .xml
                }
            case "urlencoded":
                httpRequest.bodyType = .urlEncoded
                if let encoded = body.urlencoded {
                    let pairs = encoded.compactMap { kv -> String? in
                        guard !kv.key.isEmpty else { return nil }
                        let value = kv.value ?? ""
                        return "\(kv.key)=\(value)"
                    }
                    httpRequest.bodyContent = pairs.joined(separator: "&")
                }
            case "formdata":
                httpRequest.bodyType = .formData
                if let formData = body.formData {
                    let pairs = formData.compactMap { item -> String? in
                        guard !item.key.isEmpty else { return nil }
                        return "\(item.key)=\(item.value ?? "")"
                    }
                    httpRequest.bodyContent = pairs.joined(separator: "\n")
                }
            case "graphql":
                httpRequest.bodyType = .json
                if let graphql = body.graphql {
                    var gqlDict: [String: Any] = [:]
                    if let query = graphql.query {
                        gqlDict["query"] = query
                    }
                    if let variables = graphql.variables {
                        gqlDict["variables"] = variables
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: gqlDict),
                       let json = String(data: data, encoding: .utf8) {
                        httpRequest.bodyContent = json
                    }
                }
            case "file":
                if let file = body.file {
                    httpRequest.bodyContent = "[File reference: \(file)]"
                }
            default:
                break
            }
        }
        
        if let auth = request.auth {
            httpRequest.authConfig = createAuthConfig(from: auth)
        }
        
        if let events = item.events {
            for event in events {
                guard let exec = event.script?.exec, !exec.isEmpty else { continue }
                let script = exec.joined(separator: "\n")
                
                if event.listen == "prerequest" {
                    httpRequest.preRequestScript = script
                } else if event.listen == "test" {
                    httpRequest.postRequestScript = script
                }
            }
        }
        
        return httpRequest
    }
    
    private func createAuthConfig(from auth: PostmanAuth) -> AuthConfig {
        var config = AuthConfig()
        
        switch auth.type.lowercased() {
        case "bearer":
            config.type = .bearer
            if let bearer = auth.bearer {
                for kv in bearer {
                    if kv.key == "token" {
                        config.token = kv.value
                    }
                }
            }
        case "basic":
            config.type = .basic
            if let basic = auth.basic {
                for kv in basic {
                    switch kv.key {
                    case "username":
                        config.username = kv.value
                    case "password":
                        config.password = kv.value
                    default:
                        break
                    }
                }
            }
        case "apikey":
            config.type = .apiKey
            if let apiKey = auth.apiKey {
                for kv in apiKey {
                    switch kv.key {
                    case "key":
                        config.apiKeyName = kv.value
                    case "value":
                        config.apiKeyValue = kv.value
                    case "in":
                        if kv.value == "header" {
                            config.apiKeyLocation = .header
                        } else if kv.value == "query" {
                            config.apiKeyLocation = .queryParam
                        }
                    default:
                        break
                    }
                }
            }
        default:
            break
        }
        
        return config
    }
}
