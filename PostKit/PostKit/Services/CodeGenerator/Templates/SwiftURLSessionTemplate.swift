import Foundation

/// Generates Swift code using URLSession with async/await
final class SwiftURLSessionTemplate: CodeTemplate {
    let displayName = "Swift"
    let fileExtension = "swift"

    func generateCode(for request: HTTPRequest) -> String {
        var code = ""

        // Import statement
        code += "import Foundation\n\n"

        // Function definition
        code += "func sendRequest() async throws {\n"

        // Create URL
        let fullURL = getFullURL(for: request)
        code += "    guard let url = URL(string: \"\(escapeString(fullURL))\") else {\n"
        code += "        throw URLError(.badURL)\n"
        code += "    }\n\n"

        // Create request
        code += "    var request = URLRequest(url: url)\n"
        code += "    request.httpMethod = \"\(request.method.rawValue)\"\n"

        // Add headers
        let headers = getHeaders(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        if !headers.isEmpty {
            code += "\n"
            for header in headers {
                code += "    request.setValue(\"\(escapeString(header.value))\", forHTTPHeaderField: \"\(escapeString(header.key))\")\n"
            }
        }

        // Add body if present
        if let body = getBody(for: request) {
            code += "\n"
            code += "    request.httpBody = \"\(escapeString(body))\".data(using: .utf8)\n"
        }

        // Execute request
        code += "\n"
        code += "    let (data, response) = try await URLSession.shared.data(for: request)\n\n"
        code += "    guard let httpResponse = response as? HTTPURLResponse else {\n"
        code += "        throw URLError(.badServerResponse)\n"
        code += "    }\n\n"
        code += "    print(\"Status Code: \\(httpResponse.statusCode)\")\n"
        code += "    if let responseString = String(data: data, encoding: .utf8) {\n"
        code += "        print(\"Response: \\(responseString)\")\n"
        code += "    }\n"
        code += "}\n"

        return code
    }
}
