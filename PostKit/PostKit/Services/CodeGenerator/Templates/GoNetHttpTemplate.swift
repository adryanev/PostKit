import Foundation

/// Generates Go code using net/http
final class GoNetHttpTemplate: CodeTemplate {
    let displayName = "Go"
    let fileExtension = "go"

    func generateCode(for request: HTTPRequest) -> String {
        var code = "package main\n\n"
        code += "import (\n"
        code += "    \"fmt\"\n"
        code += "    \"io\"\n"
        code += "    \"net/http\"\n"
        code += "    \"strings\"\n"

        // Check if body is present for bytes import
        if let _ = getBody(for: request), request.bodyType != .none {
            code += ")\n\n"
        } else {
            code += ")\n\n"
        }

        // Main function
        code += "func main() {\n"

        // Build URL with query parameters
        let fullURL = getFullURL(for: request)
        code += "    url := \"\(escapeString(fullURL))\"\n\n"

        // Create request body if present
        if let body = getBody(for: request), request.bodyType != .none {
            code += "    payload := strings.NewReader(\"\(escapeString(body))\")\n\n"
            code += "    req, err := http.NewRequest(\"\(request.method.rawValue)\", url, payload)\n"
        } else {
            code += "    req, err := http.NewRequest(\"\(request.method.rawValue)\", url, nil)\n"
        }

        code += "    if err != nil {\n"
        code += "        fmt.Println(\"Error creating request:\", err)\n"
        code += "        return\n"
        code += "    }\n\n"

        // Add headers
        let headers = getHeaders(from: request).filter { $0.isEnabled && !$0.key.isEmpty }
        if !headers.isEmpty {
            for header in headers {
                code += "    req.Header.Set(\"\(escapeString(header.key))\", \"\(escapeString(header.value))\")\n"
            }
            code += "\n"
        }

        // Execute request
        code += "    client := &http.Client{}\n"
        code += "    resp, err := client.Do(req)\n"
        code += "    if err != nil {\n"
        code += "        fmt.Println(\"Error sending request:\", err)\n"
        code += "        return\n"
        code += "    }\n"
        code += "    defer resp.Body.Close()\n\n"

        // Print response
        code += "    fmt.Printf(\"Status Code: %d\\n\", resp.StatusCode)\n"
        code += "    body, err := io.ReadAll(resp.Body)\n"
        code += "    if err != nil {\n"
        code += "        fmt.Println(\"Error reading response:\", err)\n"
        code += "        return\n"
        code += "    }\n"
        code += "    fmt.Printf(\"Response: %s\\n\", body)\n"
        code += "}\n"

        return code
    }
}
