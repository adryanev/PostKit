import Foundation

struct ParsedRequest {
    var method: HTTPMethod = .get
    var url: String = ""
    var headers: [KeyValuePair] = []
    var body: String?
    var bodyType: BodyType = .none
    var authConfig: AuthConfig?
}

enum CurlParserError: LocalizedError {
    case invalidCommand
    case missingURL
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "Invalid cURL command format"
        case .missingURL:
            return "No URL found in cURL command"
        case .invalidURL:
            return "Invalid URL in cURL command"
        }
    }
}

final class CurlParser: CurlParserProtocol, Sendable {
    func parse(_ curlCommand: String) throws -> ParsedRequest {
        var result = ParsedRequest()
        
        let normalized = curlCommand
            .replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "\\\r\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard normalized.lowercased().hasPrefix("curl") else {
            throw CurlParserError.invalidCommand
        }
        
        let tokens = tokenize(normalized)
        
        var i = 1
        while i < tokens.count {
            let token = tokens[i]
            
            switch token.lowercased() {
            case "-x", "--request":
                if i + 1 < tokens.count {
                    let methodStr = tokens[i + 1].uppercased()
                    result.method = HTTPMethod(rawValue: methodStr) ?? .get
                    i += 2
                } else {
                    i += 1
                }
                
            case "-h", "--header":
                if i + 1 < tokens.count {
                    let headerValue = tokens[i + 1]
                    if let colonIndex = headerValue.firstIndex(of: ":") {
                        let key = String(headerValue[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        let value = String(headerValue[headerValue.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                        result.headers.append(KeyValuePair(key: key, value: value))
                    }
                    i += 2
                } else {
                    i += 1
                }
                
            case "-d", "--data", "--data-raw", "--data-binary":
                if i + 1 < tokens.count {
                    let data = tokens[i + 1]
                    result.body = data
                    result.bodyType = data.hasPrefix("{") ? .json : .raw
                    if result.method == .get {
                        result.method = .post
                    }
                    i += 2
                } else {
                    i += 1
                }
                
            case "-u", "--user":
                if i + 1 < tokens.count {
                    let credentials = tokens[i + 1]
                    if let colonIndex = credentials.firstIndex(of: ":") {
                        let username = String(credentials[..<colonIndex])
                        let password = String(credentials[credentials.index(after: colonIndex)...])
                        result.authConfig = AuthConfig(type: .basic)
                        result.authConfig?.username = username
                        result.authConfig?.password = password
                    }
                    i += 2
                } else {
                    i += 1
                }
                
            case "-a", "--user-agent":
                if i + 1 < tokens.count {
                    result.headers.append(KeyValuePair(key: "User-Agent", value: tokens[i + 1]))
                    i += 2
                } else {
                    i += 1
                }
                
            case "-e", "--referer":
                if i + 1 < tokens.count {
                    result.headers.append(KeyValuePair(key: "Referer", value: tokens[i + 1]))
                    i += 2
                } else {
                    i += 1
                }
                
            case "-b", "--cookie":
                if i + 1 < tokens.count {
                    result.headers.append(KeyValuePair(key: "Cookie", value: tokens[i + 1]))
                    i += 2
                } else {
                    i += 1
                }
                
            case "--compressed":
                result.headers.append(KeyValuePair(key: "Accept-Encoding", value: "gzip, deflate"))
                i += 1
                
            case "-s", "--silent", "-l", "--location", "-k", "--insecure", "-v", "--verbose":
                i += 1
                
            default:
                if !token.hasPrefix("-") && (token.hasPrefix("http://") || token.hasPrefix("https://")) {
                    if URL(string: token) != nil {
                        result.url = token
                    }
                }
                i += 1
            }
        }
        
        if result.url.isEmpty {
            throw CurlParserError.missingURL
        }
        
        return result
    }
    
    private func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escapeNext = false

        for char in command {
            if escapeNext {
                current.append(char)
                escapeNext = false
            } else if char == "\\" && (inDoubleQuote || inSingleQuote) {
                escapeNext = true
            } else if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if char == " " && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
