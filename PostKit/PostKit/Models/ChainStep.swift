import Foundation
import SwiftData

/// Represents a single step in a request chain
@Model
final class ChainStep {
    var id: UUID
    var name: String
    var stepOrder: Int
    var isEnabled: Bool
    var continueOnError: Bool
    var delayMs: Int
    var createdAt: Date
    var updatedAt: Date
    
    // Reference to the request this step executes
    var requestID: UUID?
    
    // Extraction rules encoded as Data
    var extractionRulesData: Data?
    
    // Parent chain
    var chain: RequestChain?
    
    // Execution state (transient, not persisted)
    @Transient var extractedValues: [String: String] = [:]
    
    @Transient var extractionRules: [ExtractionRule] {
        get { [ExtractionRule].decode(from: extractionRulesData) }
        set { extractionRulesData = newValue.encode() }
    }
    
    init(
        name: String = "",
        requestID: UUID? = nil,
        stepOrder: Int = 0,
        isEnabled: Bool = true,
        continueOnError: Bool = false,
        delayMs: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.requestID = requestID
        self.stepOrder = stepOrder
        self.isEnabled = isEnabled
        self.continueOnError = continueOnError
        self.delayMs = delayMs
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func duplicated() -> ChainStep {
        let copy = ChainStep(
            name: name,
            requestID: requestID,
            stepOrder: stepOrder,
            isEnabled: isEnabled,
            continueOnError: continueOnError,
            delayMs: delayMs
        )
        copy.extractionRulesData = extractionRulesData
        return copy
    }
}
