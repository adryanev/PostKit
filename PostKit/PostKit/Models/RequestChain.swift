import Foundation
import SwiftData

/// Represents a chain of HTTP requests that can be executed sequentially
/// with data flowing between steps via extracted values
@Model
final class RequestChain {
    var id: UUID
    var name: String
    var chainDescription: String?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    
    @Relationship(deleteRule: .cascade, inverse: \ChainStep.chain)
    var steps: [ChainStep] = []
    
    // Chain execution history
    @Relationship(deleteRule: .cascade)
    var history: [ChainExecutionHistory] = []
    
    init(name: String, chainDescription: String? = nil) {
        self.id = UUID()
        self.name = name
        self.chainDescription = chainDescription
        self.isEnabled = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = 0
    }
    
    /// Get steps sorted by their order
    var sortedSteps: [ChainStep] {
        steps.sorted { $0.stepOrder < $1.stepOrder }
    }
    
    /// Duplicate this chain with all its steps
    func duplicated() -> RequestChain {
        let copy = RequestChain(name: "\(name) (Copy)", chainDescription: chainDescription)
        copy.isEnabled = isEnabled
        
        for step in sortedSteps {
            let stepCopy = step.duplicated()
            stepCopy.chain = copy
            copy.steps.append(stepCopy)
        }
        
        return copy
    }
}

// MARK: - Chain Execution History

/// Records the result of a chain execution
@Model
final class ChainExecutionHistory {
    var id: UUID
    var startedAt: Date
    var completedAt: Date?
    var statusRaw: String
    var totalDurationMs: Int
    var errorMessage: String?
    
    // Step results encoded as JSON
    var stepResultsData: Data?
    
    var chain: RequestChain?
    
    @Transient var status: ChainExecutionStatus {
        get { ChainExecutionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
    
    @Transient var stepResults: [ChainStepResult] {
        get {
            guard let data = stepResultsData else { return [] }
            return (try? JSONDecoder().decode([ChainStepResult].self, from: data)) ?? []
        }
        set {
            stepResultsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    init() {
        self.id = UUID()
        self.startedAt = Date()
        self.statusRaw = ChainExecutionStatus.pending.rawValue
        self.totalDurationMs = 0
    }
}

// MARK: - Chain Execution Status

enum ChainExecutionStatus: String, Codable, Sendable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Chain Step Result

/// Captures the result of executing a single step in the chain
struct ChainStepResult: Codable, Sendable, Identifiable {
    let id: UUID
    let stepId: UUID
    let stepName: String
    let statusCode: Int?
    let durationMs: Int
    let success: Bool
    let errorMessage: String?
    let extractedValues: [String: String]
    let timestamp: Date
    
    init(
        stepId: UUID,
        stepName: String,
        statusCode: Int? = nil,
        durationMs: Int,
        success: Bool,
        errorMessage: String? = nil,
        extractedValues: [String: String] = [:]
    ) {
        self.id = UUID()
        self.stepId = stepId
        self.stepName = stepName
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.success = success
        self.errorMessage = errorMessage
        self.extractedValues = extractedValues
        self.timestamp = Date()
    }
}
