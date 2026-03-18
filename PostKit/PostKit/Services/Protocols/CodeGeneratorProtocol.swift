import Foundation

/// Protocol defining the interface for generating code snippets from HTTP requests
protocol CodeGeneratorProtocol {
    var availableLanguages: [String] { get }
    func generateCode(for request: HTTPRequest, language: String) -> String?
    func fileExtension(for language: String) -> String?
}
