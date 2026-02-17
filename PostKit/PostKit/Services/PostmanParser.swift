import Foundation

enum PostmanParserError: LocalizedError, Equatable {
    case unsupportedVersion
    case invalidFormat
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "Only Postman Collection v2.1 format is supported."
        case .invalidFormat:
            return "The file is not a valid Postman collection."
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}

struct PostmanCollection: Sendable {
    let info: PostmanInfo
    let items: [PostmanItem]
    let variables: [PostmanVariable]
}

struct PostmanInfo: Sendable {
    let name: String
    let schema: String
    let description: String?
}

struct PostmanItem: Sendable {
    let name: String
    let request: PostmanRequest?
    let items: [PostmanItem]?
    let events: [PostmanEvent]?
    let description: String?
}

struct PostmanRequest: Sendable {
    let method: String
    let url: PostmanURL
    let headers: [PostmanKeyValue]
    let body: PostmanBody?
    let auth: PostmanAuth?
    let description: String?
}

enum PostmanURL: Sendable {
    case raw(String)
    case structured(PostmanURLObject)
    
    var rawValue: String {
        switch self {
        case .raw(let string):
            return string
        case .structured(let obj):
            return obj.raw ?? ""
        }
    }
}

struct PostmanURLObject: Sendable {
    let raw: String?
    let host: [String]?
    let path: [String]?
    let query: [PostmanKeyValue]?
}

struct PostmanBody: Sendable {
    let mode: String
    let raw: String?
    let formData: [PostmanFormData]?
    let urlencoded: [PostmanKeyValue]?
    let file: String?
    let graphql: PostmanGraphQL?
}

struct PostmanFormData: Sendable {
    let key: String
    let value: String?
    let type: String?
    let src: String?
}

struct PostmanGraphQL: Sendable {
    let query: String?
    let variables: String?
}

struct PostmanAuth: Sendable {
    let type: String
    let bearer: [PostmanKeyValue]?
    let basic: [PostmanKeyValue]?
    let apiKey: [PostmanKeyValue]?
}

struct PostmanKeyValue: Sendable {
    let key: String
    let value: String?
    let type: String?
    let enabled: Bool?
}

struct PostmanEvent: Sendable {
    let listen: String
    let script: PostmanScript?
}

struct PostmanScript: Sendable {
    let exec: [String]?
    let type: String?
}

struct PostmanVariable: Sendable {
    let key: String
    let value: String?
    let type: String?
    let description: String?
}

struct PostmanEnvironment: Sendable {
    let name: String
    let values: [PostmanVariable]
}

final class PostmanParser: PostmanParserProtocol, Sendable {
    
    func parse(_ data: Data) throws -> PostmanCollection {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PostmanParserError.invalidFormat
        }
        
        guard let infoDict = json["info"] as? [String: Any],
              let schema = infoDict["schema"] as? String,
              schema.contains("v2.1") else {
            throw PostmanParserError.unsupportedVersion
        }
        
        guard let name = infoDict["name"] as? String else {
            throw PostmanParserError.missingRequiredField("info.name")
        }
        
        let info = PostmanInfo(
            name: name,
            schema: schema,
            description: infoDict["description"] as? String
        )
        
        let itemsArray = json["item"] as? [[String: Any]] ?? []
        let items = try itemsArray.map { try parseItem($0) }
        
        let variablesArray = json["variable"] as? [[String: Any]] ?? []
        let variables = variablesArray.map { parseVariable($0) }
        
        return PostmanCollection(info: info, items: items, variables: variables)
    }
    
    func parseEnvironment(_ data: Data) throws -> PostmanEnvironment {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PostmanParserError.invalidFormat
        }
        
        let name = json["name"] as? String ?? "Imported Environment"
        let valuesArray = json["values"] as? [[String: Any]] ?? []
        let values = valuesArray.map { parseVariable($0) }
        
        return PostmanEnvironment(name: name, values: values)
    }
    
    private func parseItem(_ dict: [String: Any]) throws -> PostmanItem {
        let name = dict["name"] as? String ?? "Unnamed"
        let description = dict["description"] as? String
        
        let request: PostmanRequest?
        if let requestDict = dict["request"] {
            request = try parseRequest(requestDict)
        } else {
            request = nil
        }
        
        let itemsArray = dict["item"] as? [[String: Any]]
        let items = try itemsArray?.map { try parseItem($0) }
        
        let eventsArray = dict["event"] as? [[String: Any]]
        let events = eventsArray?.map { parseEvent($0) }
        
        return PostmanItem(
            name: name,
            request: request,
            items: items,
            events: events,
            description: description
        )
    }
    
    private func parseRequest(_ request: Any) throws -> PostmanRequest {
        var method = "GET"
        var url: PostmanURL = .raw("")
        var headers: [PostmanKeyValue] = []
        var body: PostmanBody?
        var auth: PostmanAuth?
        var description: String?
        
        if let urlString = request as? String {
            url = .raw(urlString)
        } else if let dict = request as? [String: Any] {
            method = (dict["method"] as? String ?? "GET").uppercased()
            description = dict["description"] as? String
            
            if let urlString = dict["url"] as? String {
                url = .raw(urlString)
            } else if let urlDict = dict["url"] as? [String: Any] {
                url = .structured(parseURLObject(urlDict))
            }
            
            if let headerArray = dict["header"] as? [[String: Any]] {
                headers = headerArray.map { parseKeyValue($0) }
            }
            
            if let bodyDict = dict["body"] as? [String: Any] {
                body = parseBody(bodyDict)
            }
            
            if let authDict = dict["auth"] as? [String: Any] {
                auth = parseAuth(authDict)
            }
        }
        
        return PostmanRequest(
            method: method,
            url: url,
            headers: headers,
            body: body,
            auth: auth,
            description: description
        )
    }
    
    private func parseURLObject(_ dict: [String: Any]) -> PostmanURLObject {
        let raw = dict["raw"] as? String
        let host = dict["host"] as? [String]
        let path = dict["path"] as? [String]
        let queryArray = dict["query"] as? [[String: Any]]
        let query = queryArray?.map { parseKeyValue($0) }
        
        return PostmanURLObject(raw: raw, host: host, path: path, query: query)
    }
    
    private func parseBody(_ dict: [String: Any]) -> PostmanBody {
        let mode = dict["mode"] as? String ?? "raw"
        let raw = dict["raw"] as? String
        
        let formDataArray = dict["formdata"] as? [[String: Any]]
        let formData = formDataArray?.map { dict in
            PostmanFormData(
                key: dict["key"] as? String ?? "",
                value: dict["value"] as? String,
                type: dict["type"] as? String,
                src: dict["src"] as? String
            )
        }
        
        let urlencodedArray = dict["urlencoded"] as? [[String: Any]]
        let urlencoded = urlencodedArray?.map { parseKeyValue($0) }
        
        let file: String?
        if let fileDict = dict["file"] as? [String: Any] {
            file = fileDict["src"] as? String
        } else {
            file = dict["file"] as? String
        }
        
        var graphql: PostmanGraphQL?
        if let graphqlDict = dict["graphql"] as? [String: Any] {
            graphql = PostmanGraphQL(
                query: graphqlDict["query"] as? String,
                variables: graphqlDict["variables"] as? String
            )
        }
        
        return PostmanBody(
            mode: mode,
            raw: raw,
            formData: formData,
            urlencoded: urlencoded,
            file: file,
            graphql: graphql
        )
    }
    
    private func parseAuth(_ dict: [String: Any]) -> PostmanAuth {
        let type = dict["type"] as? String ?? "noauth"
        
        let bearerArray = dict["bearer"] as? [[String: Any]]
        let bearer = bearerArray?.map { parseKeyValue($0) }
        
        let basicArray = dict["basic"] as? [[String: Any]]
        let basic = basicArray?.map { parseKeyValue($0) }
        
        let apiKeyArray = dict["apikey"] as? [[String: Any]]
        let apiKey = apiKeyArray?.map { parseKeyValue($0) }
        
        return PostmanAuth(
            type: type,
            bearer: bearer,
            basic: basic,
            apiKey: apiKey
        )
    }
    
    private func parseKeyValue(_ dict: [String: Any]) -> PostmanKeyValue {
        PostmanKeyValue(
            key: dict["key"] as? String ?? "",
            value: dict["value"] as? String,
            type: dict["type"] as? String,
            enabled: dict["enabled"] as? Bool ?? true
        )
    }
    
    private func parseEvent(_ dict: [String: Any]) -> PostmanEvent {
        let listen = dict["listen"] as? String ?? ""
        var script: PostmanScript?
        if let scriptDict = dict["script"] as? [String: Any] {
            script = PostmanScript(
                exec: scriptDict["exec"] as? [String],
                type: scriptDict["type"] as? String
            )
        }
        return PostmanEvent(listen: listen, script: script)
    }
    
    private func parseVariable(_ dict: [String: Any]) -> PostmanVariable {
        PostmanVariable(
            key: dict["key"] as? String ?? "",
            value: dict["value"] as? String,
            type: dict["type"] as? String,
            description: dict["description"] as? String
        )
    }
}
