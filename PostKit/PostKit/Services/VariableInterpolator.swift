import Foundation

enum InterpolationError: LocalizedError {
    case invalidPattern(String)

    var errorDescription: String? {
        switch self {
        case .invalidPattern(let pattern):
            return "Invalid variable pattern: \(pattern)"
        }
    }
}

final class VariableInterpolator: VariableInterpolatorProtocol, Sendable {
    private let variableRegex: NSRegularExpression

    init() {
        // Safe to force-try: pattern is a compile-time constant.
        // swiftlint:disable:next force_try
        variableRegex = try! NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#)
    }

    func interpolate(
        _ template: String,
        with variables: [String: String]
    ) throws -> String {
        var result = template
        let range = NSRange(template.startIndex..., in: template)

        var replacements: [(Range<String.Index>, String)] = []

        variableRegex.enumerateMatches(in: template, range: range) { match, _, _ in
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
}
