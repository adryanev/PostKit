import Foundation

/// Service for generating code snippets from HTTP requests in various languages
final class CodeGenerator {
    /// All available code templates
    private let templates: [CodeTemplate] = [
        SwiftURLSessionTemplate(),
        CurlTemplate(),
        PythonRequestsTemplate(),
        JavaScriptFetchTemplate(),
        NodeAxiosTemplate(),
        GoNetHttpTemplate()
    ]

    /// Get all available languages
    var availableLanguages: [String] {
        templates.map { $0.displayName }
    }

    /// Generate code for a request in the specified language
    /// - Parameters:
    ///   - request: The HTTP request to generate code for
    ///   - language: The display name of the language
    /// - Returns: Generated code string, or nil if language not found
    func generateCode(for request: HTTPRequest, language: String) -> String? {
        guard let template = templates.first(where: { $0.displayName == language }) else {
            return nil
        }
        return template.generateCode(for: request)
    }

    /// Get the file extension for a language
    /// - Parameter language: The display name of the language
    /// - Returns: File extension string, or nil if language not found
    func fileExtension(for language: String) -> String? {
        guard let template = templates.first(where: { $0.displayName == language }) else {
            return nil
        }
        return template.fileExtension
    }
}
