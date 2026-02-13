import Foundation

enum InterpolationContext {
    case url
    case header
    case body
    case general
}

enum InterpolationError: LocalizedError {
    case blockedHost(String)
    case invalidPattern(String)
    
    var errorDescription: String? {
        switch self {
        case .blockedHost(let host):
            return "Blocked host: \(host). Internal network addresses are not allowed."
        case .invalidPattern(let pattern):
            return "Invalid variable pattern: \(pattern)"
        }
    }
}

final class VariableInterpolator: Sendable {
    private let variablePattern = #"\{\{([^}]+)\}\}"#
    
    func interpolate(
        _ template: String,
        with variables: [String: String],
        context: InterpolationContext = .general
    ) throws -> String {
        var result = template
        let regex = try NSRegularExpression(pattern: variablePattern)
        let range = NSRange(template.startIndex..., in: template)
        
        var replacements: [(Range<String.Index>, String)] = []
        
        regex.enumerateMatches(in: template, range: range) { match, _, _ in
            guard let match = match,
                  let keyRange = Range(match.range(at: 1), in: template),
                  let fullRange = Range(match.range, in: template) else { return }
            
            let key = String(template[keyRange]).trimmingCharacters(in: .whitespaces)
            let value = resolveVariable(key, variables: variables)
            replacements.append((fullRange, value))
        }
        
        for (range, value) in replacements.reversed() {
            result.replaceSubrange(range, with: value)
        }
        
        try validateResult(result, context: context)
        
        return result
    }
    
    private func resolveVariable(_ key: String, variables: [String: String]) -> String {
        switch key {
        case "$timestamp":
            return String(Int(Date().timeIntervalSince1970 * 1000))
        case "$randomInt":
            return String(Int.random(in: 0...999999))
        case "$guid", "$uuid":
            return UUID().uuidString
        case "$isoTimestamp":
            return ISO8601DateFormatter().string(from: Date())
        case "$randomString":
            return String((0..<16).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        default:
            return variables[key] ?? "{{\(key)}}"
        }
    }
    
    private func validateResult(_ result: String, context: InterpolationContext) throws {
        switch context {
        case .url:
            guard let url = URL(string: result) else { return }
            
            let host = url.host?.lowercased() ?? ""
            let blockedHosts = ["localhost", "127.0.0.1", "0.0.0.0", "[::1]"]
            let blockedPrefixes = [
                "10.", "172.16.", "172.17.", "172.18.", "172.19.",
                "172.20.", "172.21.", "172.22.", "172.23.",
                "172.24.", "172.25.", "172.26.", "172.27.",
                "172.28.", "172.29.", "172.30.", "172.31.",
                "192.168."
            ]
            
            if blockedHosts.contains(host) {
                throw InterpolationError.blockedHost(host)
            }
            
            for prefix in blockedPrefixes {
                if host.hasPrefix(prefix) {
                    throw InterpolationError.blockedHost(host)
                }
            }
            
        case .header, .body, .general:
            break
        }
    }
    
    func extractVariables(from template: String) -> [String] {
        var variables: [String] = []
        let regex = try? NSRegularExpression(pattern: variablePattern)
        let range = NSRange(template.startIndex..., in: template)
        
        regex?.enumerateMatches(in: template, range: range) { match, _, _ in
            guard let match = match,
                  let keyRange = Range(match.range(at: 1), in: template) else { return }
            
            let key = String(template[keyRange]).trimmingCharacters(in: .whitespaces)
            if !variables.contains(key) {
                variables.append(key)
            }
        }
        
        return variables
    }
}
