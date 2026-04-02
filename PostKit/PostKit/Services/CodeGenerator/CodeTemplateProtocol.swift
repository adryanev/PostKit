import Foundation

/// Protocol for generating code snippets from HTTP requests in various programming languages
protocol CodeTemplateProtocol {
    /// The display name of the language (e.g., "Swift", "Python")
    var displayName: String { get }

    /// The file extension for the generated code (e.g., "swift", "py")
    var fileExtension: String { get }

    /// Generate a code snippet for the given HTTP request
    /// - Parameter request: The HTTP request to generate code for
    /// - Returns: A code snippet string
    func generateCode(for request: HTTPRequest) -> String
}

/// Extension providing common helper methods for templates
extension CodeTemplateProtocol {
    /// Decode headers data to key-value pairs
    func getHeaders(from request: HTTPRequest) -> [KeyValuePair] {
        [KeyValuePair].decode(from: request.headersData)
    }

    /// Decode query params data to key-value pairs
    func getQueryParams(from request: HTTPRequest) -> [KeyValuePair] {
        [KeyValuePair].decode(from: request.queryParamsData)
    }

    /// Get body content with appropriate content type
    func getBody(for request: HTTPRequest) -> String? {
        request.bodyContent?.isEmpty == false ? request.bodyContent : nil
    }

    /// Get the full URL with query parameters
    func getFullURL(for request: HTTPRequest) -> String {
        var url = request.urlTemplate
        let queryParams = getQueryParams(from: request).filter { $0.isEnabled && !$0.key.isEmpty }

        if !queryParams.isEmpty {
            let queryString = queryParams.map { pair in
                let encodedKey = pair.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pair.key
                let encodedValue = pair.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pair.value
                return "\(encodedKey)=\(encodedValue)"
            }.joined(separator: "&")
            url += (url.contains("?") ? "&" : "?") + queryString
        }

        return url
    }

    /// Get the base URL (without query parameters)
    func getBaseURL(for request: HTTPRequest) -> String {
        let queryParams = getQueryParams(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        var url = request.urlTemplate

        if !queryParams.isEmpty {
            // Remove existing query string from urlTemplate
            if let queryRange = url.range(of: "?") {
                url = String(url[..<queryRange.lowerBound])
            }
        }

        return url
    }

    /// Escape string for code generation (double-quoted contexts)
    func escapeString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Escape string for shell single-quoted arguments.
    /// Single quotes in the input are handled by ending the current single-quoted segment,
    /// inserting an escaped single quote (backslash-single-quote), and reopening.
    func escapeShellSingleQuote(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "'\\''")
    }
}
