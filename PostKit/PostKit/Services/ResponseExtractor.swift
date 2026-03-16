import Foundation

/// Errors that can occur during response extraction
enum ExtractionError: LocalizedError, Sendable {
    case invalidPattern(String)
    case valueNotFound(String)
    case parseError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidPattern(let pattern):
            return "Invalid extraction pattern: \(pattern)"
        case .valueNotFound(let path):
            return "Value not found at path: \(path)"
        case .parseError(let message):
            return "Failed to parse response: \(message)"
        case .invalidResponse:
            return "Invalid or empty response"
        }
    }
}

/// Result of extracting values from a response
struct ExtractionResult: Sendable {
    let extractedValues: [String: String]
    let errors: [String: String] // variableName -> errorMessage
    
    var isSuccess: Bool {
        errors.isEmpty
    }
    
    static let empty = ExtractionResult(extractedValues: [:], errors: [:])
    
    func merged(with other: ExtractionResult) -> ExtractionResult {
        ExtractionResult(
            extractedValues: extractedValues.merging(other.extractedValues) { _, new in new },
            errors: errors.merging(other.errors) { _, new in new }
        )
    }
}

/// Protocol defining the interface for extracting values from HTTP responses
protocol ResponseExtractorProtocol: Sendable {
    /// Extract a value from an HTTP response using the given rule
    func extract(from response: HTTPResponse, using rule: ExtractionRule) -> Result<String, ExtractionError>
    
    /// Extract multiple values from a response using multiple rules
    func extractAll(from response: HTTPResponse, using rules: [ExtractionRule]) -> ExtractionResult
}

/// Service for extracting values from HTTP responses using various extraction types
final class ResponseExtractor: ResponseExtractorProtocol, Sendable {
    
    // MARK: - JSONPath Parsing
    
    private let jsonPathRegex: NSRegularExpression
    
    init() {
        // Regex for parsing JSONPath segments: $.store.book[0].title or $['store']['book'][0]['title']
        // swiftlint:disable:next force_try
        jsonPathRegex = try! NSRegularExpression(
            pattern: #"^(\$|@)((?:\.[^\.\[\]]+)|(?:\['[^']+'\])|(?:\[\d+\]))*"$"#
        )
    }
    
    // MARK: - Single Extraction
    
    func extract(from response: HTTPResponse, using rule: ExtractionRule) -> Result<String, ExtractionError> {
        guard rule.isEnabled else {
            return .failure(.valueNotFound("Rule is disabled"))
        }
        
        let result: Result<String, ExtractionError>
        
        switch rule.extractionType {
        case .jsonPath:
            result = extractJSONPath(from: response, pattern: rule.pattern)
        case .regex:
            result = extractRegex(from: response, pattern: rule.pattern)
        case .header:
            result = extractHeader(from: response, headerName: rule.pattern)
        case .statusCode:
            result = .success(String(response.statusCode))
        }
        
        // Apply default value if extraction failed and default is set
        switch result {
        case .success(let value):
            return .success(value)
        case .failure(let error):
            if let defaultValue = rule.defaultValue, !defaultValue.isEmpty {
                return .success(defaultValue)
            }
            return .failure(error)
        }
    }
    
    // MARK: - Multiple Extractions
    
    func extractAll(from response: HTTPResponse, using rules: [ExtractionRule]) -> ExtractionResult {
        var extractedValues: [String: String] = [:]
        var errors: [String: String] = [:]
        
        for rule in rules where rule.isEnabled && !rule.variableName.isEmpty {
            switch extract(from: response, using: rule) {
            case .success(let value):
                extractedValues[rule.variableName] = value
            case .failure(let error):
                errors[rule.variableName] = error.localizedDescription
                // Store default if available
                if let defaultValue = rule.defaultValue, !defaultValue.isEmpty {
                    extractedValues[rule.variableName] = defaultValue
                }
            }
        }
        
        return ExtractionResult(extractedValues: extractedValues, errors: errors)
    }
    
    // MARK: - JSONPath Extraction
    
    private func extractJSONPath(from response: HTTPResponse, pattern: String) -> Result<String, ExtractionError> {
        guard !pattern.isEmpty else {
            return .failure(.invalidPattern("Empty JSONPath pattern"))
        }
        
        do {
            let bodyData = try response.getBodyData()
            
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) else {
                return .failure(.parseError("Response is not valid JSON"))
            }
            
            let value = navigateJSONPath(pattern: pattern, in: json)
            
            switch value {
            case .some(let result):
                return .success(result)
            case .none:
                return .failure(.valueNotFound(pattern))
            }
        } catch {
            return .failure(.parseError(error.localizedDescription))
        }
    }
    
    /// Navigate a JSON object using JSONPath-like syntax
    private func navigateJSONPath(pattern: String, in json: Any) -> String? {
        var current: Any? = json
        var path = pattern
        
        // Remove leading $ or @
        if path.hasPrefix("$") || path.hasPrefix("@") {
            path = String(path.dropFirst())
        }
        
        // Parse path segments
        while !path.isEmpty {
            if path.hasPrefix(".") {
                path = String(path.dropFirst())
            }
            
            // Handle array index: [0] or ['key']
            if path.hasPrefix("[") {
                guard let closeBracket = path.firstIndex(of: "]") else { return nil }
                let bracketContent = String(path[path.index(after: path.startIndex)..<closeBracket])
                path = String(path[path.index(after: closeBracket)...])
                
                if let index = Int(bracketContent) {
                    // Array index
                    guard let array = current as? [Any], index < array.count else { return nil }
                    current = array[index]
                } else if bracketContent.hasPrefix("'"), bracketContent.hasSuffix("'") {
                    // Object key with brackets
                    let key = String(bracketContent.dropFirst().dropLast())
                    guard let object = current as? [String: Any], let value = object[key] else { return nil }
                    current = value
                } else {
                    return nil
                }
            } else if let dotIndex = path.firstIndex(of: ".") ?? path.firstIndex(of: "[") {
                // Property name before next separator
                let key = String(path[..<dotIndex])
                path = String(path[dotIndex...])
                
                guard let object = current as? [String: Any], let value = object[key] else { return nil }
                current = value
            } else {
                // Last segment - property name
                guard let object = current as? [String: Any], let value = object[path] else { return nil }
                current = value
                path = ""
            }
        }
        
        // Convert final value to string
        return valueToString(current)
    }
    
    /// Convert a JSON value to its string representation
    private func valueToString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case let array as [Any]:
            return (try? JSONSerialization.data(withJSONObject: array))
                .flatMap { String(data: $0, encoding: .utf8) }
        case let dict as [String: Any]:
            return (try? JSONSerialization.data(withJSONObject: dict))
                .flatMap { String(data: $0, encoding: .utf8) }
        case .some(let val as Optional<Any>):
            return val.flatMap { valueToString($0) } ?? "null"
        case .none:
            return "null"
        default:
            return nil
        }
    }
    
    // MARK: - Regex Extraction
    
    private func extractRegex(from response: HTTPResponse, pattern: String) -> Result<String, ExtractionError> {
        guard !pattern.isEmpty else {
            return .failure(.invalidPattern("Empty regex pattern"))
        }
        
        do {
            let bodyData = try response.getBodyData()
            guard let bodyString = String(data: bodyData, encoding: .utf8) else {
                return .failure(.parseError("Response is not valid UTF-8"))
            }
            
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(bodyString.startIndex..., in: bodyString)
            
            guard let match = regex.firstMatch(in: bodyString, range: range) else {
                return .failure(.valueNotFound(pattern))
            }
            
            // If there's a capture group, return that; otherwise return full match
            if match.numberOfRanges > 1 {
                guard let captureRange = Range(match.range(at: 1), in: bodyString) else {
                    return .failure(.valueNotFound(pattern))
                }
                return .success(String(bodyString[captureRange]))
            } else {
                guard let fullRange = Range(match.range, in: bodyString) else {
                    return .failure(.valueNotFound(pattern))
                }
                return .success(String(bodyString[fullRange]))
            }
        } catch {
            return .failure(.invalidPattern(error.localizedDescription))
        }
    }
    
    // MARK: - Header Extraction
    
    private func extractHeader(from response: HTTPResponse, headerName: String) -> Result<String, ExtractionError> {
        guard !headerName.isEmpty else {
            return .failure(.invalidPattern("Empty header name"))
        }
        
        // Case-insensitive header lookup
        let normalizedHeaderName = headerName.lowercased()
        
        for (key, value) in response.headers {
            if key.lowercased() == normalizedHeaderName {
                return .success(value)
            }
        }
        
        return .failure(.valueNotFound("Header: \(headerName)"))
    }
}
