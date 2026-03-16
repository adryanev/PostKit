import Foundation

/// Generates Python code using requests library
final class PythonRequestsTemplate: CodeTemplate {
    let displayName = "Python"
    let fileExtension = "py"

    func generateCode(for request: HTTPRequest) -> String {
        var code = "import requests\n\n"

        // Prepare headers
        let headers = getHeaders(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        if !headers.isEmpty {
            code += "headers = {\n"
            for (index, header) in headers.enumerated() {
                let comma = index < headers.count - 1 ? "," : ""
                code += "    \"\(escapeString(header.key))\": \"\(escapeString(header.value))\"\(comma)\n"
            }
            code += "}\n\n"
        } else {
            code += "headers = {}\n\n"
        }

        // Prepare query params
        let queryParams = getQueryParams(from: request).filter { $0.isEnabled && !$0.key.isEmpty }

        // Prepare body if present
        if let body = getBody(for: request), request.bodyType != .none {
            if request.bodyType == .json {
                code += "data = \"\"\"\(escapeString(body))\n\"\"\"\n\n"
            } else {
                code += "data = \"\"\"\(escapeString(body))\n\"\"\"\n\n"
            }
        }

        // Build URL and make request
        code += "url = \"\(escapeString(getBaseURL(for: request)))\""

        if !queryParams.isEmpty {
            code += "\nparams = {\n"
            for (index, param) in queryParams.enumerated() {
                let comma = index < queryParams.count - 1 ? "," : ""
                code += "    \"\(escapeString(param.key))\": \"\(escapeString(param.value))\"\(comma)\n"
            }
            code += "}\n\n"
            code += "response = requests.\(request.method.rawValue.lowercased())(url, headers=headers, params=params"

            if let _ = getBody(for: request), request.bodyType != .none {
                code += ", data=data"
            }
            code += ")\n"
        } else {
            code += "\n\nresponse = requests.\(request.method.rawValue.lowercased())(url, headers=headers"

            if let _ = getBody(for: request), request.bodyType != .none {
                code += ", data=data"
            }
            code += ")\n"
        }

        // Print response
        code += "\nprint(f\"Status Code: {response.status_code}\")\n"
        code += "print(f\"Response: {response.text}\")\n"

        return code
    }
}
