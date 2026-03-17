import Foundation

/// Generates JavaScript code using Fetch API
final class JavaScriptFetchTemplate: CodeTemplate {
    let displayName = "JavaScript"
    let fileExtension = "js"

    func generateCode(for request: HTTPRequest) -> String {
        var code = "fetch(\""

        // URL
        code += escapeString(getFullURL(for: request))
        code += "\", {\n"

        // Method
        code += "    method: \"\(request.method.rawValue)\""

        // Add headers
        let headers = getHeaders(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        if !headers.isEmpty {
            code += ",\n    headers: {\n"
            for (index, header) in headers.enumerated() {
                let comma = index < headers.count - 1 ? "," : ""
                code += "        \"\(escapeString(header.key))\": \"\(escapeString(header.value))\"\(comma)\n"
            }
            code += "    }"
        }

        // Add body if present
        if let body = getBody(for: request), request.bodyType != .none {
            code += ","
            code += "\n    body: "

            if request.bodyType == .json {
                code += escapeString(body)
            } else {
                code += "\"\(escapeString(body))\""
            }
        }

        code += "\n})\n"
        code += ".then(response => {\n"
        code += "    console.log(`Status Code: ${response.status}`);\n"
        code += "    return response.text();\n"
        code += "})\n"
        code += ".then(data => {\n"
        code += "    console.log(`Response: ${data}`);\n"
        code += "})\n"
        code += ".catch(error => {\n"
        code += "    console.error('Error:', error);\n"
        code += "});\n"

        return code
    }
}
