import Foundation

/// Maps content-type strings to Highlightr language identifiers for syntax highlighting.
/// - Parameter contentType: The content-type header value (should be lowercase, without parameters)
/// - Returns: The Highlightr language identifier, or nil if no highlighting is available
func languageForContentType(_ contentType: String?) -> String? {
    switch contentType {
    case "application/json": return "json"
    case "application/xml", "text/xml": return "xml"
    case "text/html": return "html"
    case "text/css": return "css"
    case "application/javascript", "text/javascript": return "javascript"
    case "application/x-yaml", "text/yaml": return "yaml"
    default: return nil
    }
}

/// Computes the display string for response body data with optional JSON pretty-printing.
/// - Parameters:
///   - data: The raw response body data
///   - contentType: The normalized content type (lowercase, without parameters)
///   - showRaw: If true, skip pretty-printing and return raw string
///   - maxDisplaySize: Maximum bytes to include in output (truncates if larger)
///   - prettyPrintThreshold: Maximum size for JSON pretty-printing (skips if larger)
/// - Returns: The string to display
func computeDisplayString(
    for data: Data,
    contentType: String?,
    showRaw: Bool,
    maxDisplaySize: Int64 = 10_000_000,
    prettyPrintThreshold: Int = 524_288
) -> String {
    let actualData = data.prefix(Int(maxDisplaySize))
    let isJSON = contentType == "application/json"
    
    if !showRaw && isJSON && data.count <= prettyPrintThreshold {
        if let json = try? JSONSerialization.jsonObject(with: actualData),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
    }
    
    return String(data: actualData, encoding: .utf8) ?? "<binary data>"
}
