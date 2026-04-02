import Foundation

/// Defines how to extract a value from an HTTP response
struct ExtractionRule: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var extractionType: ExtractionType
    var pattern: String
    var variableName: String
    var defaultValue: String?
    var isEnabled: Bool
    var sortOrder: Int

    init(
        name: String = "",
        extractionType: ExtractionType = .jsonPath,
        pattern: String = "",
        variableName: String = "",
        defaultValue: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.extractionType = extractionType
        self.pattern = pattern
        self.variableName = variableName
        self.defaultValue = defaultValue
        self.isEnabled = isEnabled
        self.sortOrder = 0
    }

    /// Create a copy of this extraction rule
    func duplicated() -> ExtractionRule {
        ExtractionRule(
            name: name,
            extractionType: extractionType,
            pattern: pattern,
            variableName: variableName,
            defaultValue: defaultValue,
            isEnabled: isEnabled
        )
    }
}

// MARK: - Data Encoding Extensions

extension Array where Element == ExtractionRule {
    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(from data: Data?) -> [ExtractionRule] {
        guard let data = data else { return [] }
        guard let rules = try? JSONDecoder().decode([ExtractionRule].self, from: data) else { return [] }
        return rules
    }
}
