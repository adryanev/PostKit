import Foundation

/// Generates Node.js code using axios
final class NodeAxiosTemplate: CodeTemplate {
    let displayName = "Node.js"
    let fileExtension = "js"

    func generateCode(for request: HTTPRequest) -> String {
        var code = "const axios = require('axios');\n\n"

        // Prepare headers
        let headers = getHeaders(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        if !headers.isEmpty {
            code += "const headers = {\n"
            for (index, header) in headers.enumerated() {
                let comma = index < headers.count - 1 ? "," : ""
                code += "    '\(escapeString(header.key))': '\(escapeString(header.value))'\(comma)\n"
            }
            code += "};\n\n"
        } else {
            code += "const headers = {};\n\n"
        }

        // Prepare query params
        let queryParams = getQueryParams(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        let baseURL = getBaseURL(for: request)

        // Prepare body if present
        if let body = getBody(for: request), request.bodyType != .none {
            if request.bodyType == .json {
                code += "const data = \(body);\n\n"
            } else {
                code += "const data = `\(escapeString(body))`;\n\n"
            }
        }

        // Make request
        code += "axios.\(request.method.rawValue.lowercased())('"

        code += escapeString(baseURL)
        code += "'"

        if !queryParams.isEmpty {
            code += ", {\n"
            code += "    params: {\n"
            for (index, param) in queryParams.enumerated() {
                let comma = index < queryParams.count - 1 ? "," : ""
                code += "        '\(escapeString(param.key))': '\(escapeString(param.value))'\(comma)\n"
            }
            code += "    }"

            if let _ = getBody(for: request), request.bodyType != .none {
                code += ",\n    data: data"
            }
            if !headers.isEmpty {
                code += ",\n    headers: headers"
            }

            code += "\n}"
        } else {
            code += ", {"

            let options: [String] = [
                !headers.isEmpty ? "headers" : nil,
                getBody(for: request) != nil && request.bodyType != .none ? "data" : nil
            ].compactMap { $0 }

            if !options.isEmpty {
                code += "\n"
                if !headers.isEmpty {
                    code += "    headers: headers"
                    if options.count > 1 {
                        code += ","
                    }
                    code += "\n"
                }
                if let _ = getBody(for: request), request.bodyType != .none {
                    code += "    data: data\n"
                }
            }

            code += "}"
        }

        code += ")\n"
        code += ".then(response => {\n"
        code += "    console.log(`Status Code: ${response.status}`);\n"
        code += "    console.log('Response:', response.data);\n"
        code += "})\n"
        code += ".catch(error => {\n"
        code += "    console.error('Error:', error.response?.data || error.message);\n"
        code += "});\n"

        return code
    }
}
