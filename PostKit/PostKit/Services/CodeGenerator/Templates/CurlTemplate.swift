import Foundation

/// Generates cURL command
final class CurlTemplate: CodeTemplate {
    let displayName = "cURL"
    let fileExtension = "sh"

    func generateCode(for request: HTTPRequest) -> String {
        var code = "curl"

        // Method (if not GET)
        if request.method != .get {
            code += " -X \(request.method.rawValue)"
        }

        // Add headers
        let headers = getHeaders(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        for header in headers {
            code += " \\\n  -H \"\(escapeString(header.key)): \(escapeString(header.value))\""
        }

        // Add body if present
        if let body = getBody(for: request) {
            code += " \\\n  -d \"\(escapeString(body))\""
        }

        // Add URL
        code += " \\\n  \"\(escapeString(getFullURL(for: request)))\""

        return code
    }
}
