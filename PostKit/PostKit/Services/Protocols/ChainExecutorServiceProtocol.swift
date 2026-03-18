import Foundation
import SwiftData

/// Protocol defining the interface for the chain execution service wrapper
protocol ChainExecutorServiceProtocol: Sendable {
    func execute(
        chain: RequestChain,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> [ChainStepResult]

    func executeStep(
        step: ChainStep,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> ChainStepResult
}
