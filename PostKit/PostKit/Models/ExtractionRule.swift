import Foundation
import SwiftData

/// Defines how to extract a value from an HTTP response
@Model
final class ExtractionRule {
    var id: UUID
    var name: String
    var extractionTypeRaw: String
    var pattern: String
    var variableName: String
    var defaultValue: String?
    var isEnabled: Bool
    var sortOrder: Int
    
    var chainStep: ChainStep?
    
    @Transient var extractionType: ExtractionType {
        get { ExtractionType(rawValue: extractionTypeRaw) ?? .jsonPath }
        set { extractionTypeRaw = newValue.rawValue }
    }
    
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
        self.extractionTypeRaw = extractionType.rawValue
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

// MARK: - Codable Support (for Data encoding)

struct ExtractionRuleData: Codable, Sendable {
    let id: UUID
    let name: String
    let extractionType: ExtractionType
    let pattern: String
    let variableName: String
    let defaultValue: String?
    let isEnabled: Bool
    let sortOrder: Int
    
    init(from rule: ExtractionRule) {
        self.id = rule.id
        self.name = rule.name
        self.extractionType = rule.extractionType
        self.pattern = rule.pattern
        self.variableName = rule.variableName
        self.defaultValue = rule.defaultValue
        self.isEnabled = rule.isEnabled
        self.sortOrder = rule.sortOrder
    }
    
    func toExtractionRule() -> ExtractionRule {
        let rule = ExtractionRule(
            name: name,
            extractionType: extractionType,
            pattern: pattern,
            variableName: variableName,
            defaultValue: defaultValue,
            isEnabled: isEnabled
        )
        rule.sortOrder = sortOrder
        return rule
    }
}

extension Array where Element == ExtractionRule {
    func encode() -> Data? {
        let dataObjects = self.map { ExtractionRuleData(from: $0) }
        return try? JSONEncoder().encode(dataObjects)
    }
    
    static func decode(from data: Data?) -> [ExtractionRule] {
        guard let data = data else { return [] }
        guard let dataObjects = try? JSONDecoder().decode([ExtractionRuleData].self, from: data) else { return [] }
        return dataObjects.map { $0.toExtractionRule() }
    }
}
