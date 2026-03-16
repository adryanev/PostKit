import Foundation
import SwiftData
import FactoryKit

/// Errors that can occur during chain execution
enum ChainExecutorError: LocalizedError, Sendable {
    case chainNotFound
    case stepNotFound(UUID)
    case requestNotFound(UUID)
    case stepFailed(String)
    case interpolationFailed(String)
    case chainDisabled
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .chainNotFound:
            return "Chain not found"
        case .stepNotFound(let id):
            return "Step not found: \(id)"
        case .requestNotFound(let id):
            return "Request not found: \(id)"
        case .stepFailed(let message):
            return "Step failed: \(message)"
        case .interpolationFailed(let message):
            return "Variable interpolation failed: \(message)"
        case .chainDisabled:
            return "Chain is disabled"
        case .cancelled:
            return "Chain execution was cancelled"
        }
    }
}

/// Represents the current state of chain execution
enum ChainExecutionState: Sendable {
    case idle
    case running(currentStep: Int, totalSteps: Int)
    case completed
    case failed(error: String)
    case cancelled
    
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Protocol for chain execution service
protocol ChainExecutorProtocol: Sendable {
    /// Execute a chain and return the results
    func execute(
        chain: RequestChain,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> [ChainStepResult]
    
    /// Execute a single step in the chain
    func executeStep(
        step: ChainStep,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> ChainStepResult
}

/// Service for executing request chains
actor ChainExecutor: ChainExecutorProtocol {
    
    @discardableResult
    func execute(
        chain: RequestChain,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> [ChainStepResult] {
        guard chain.isEnabled else {
            throw ChainExecutorError.chainDisabled
        }
        
        let steps = chain.sortedSteps.filter { $0.isEnabled }
        var results: [ChainStepResult] = []
        var accumulatedVariables = variables
        
        for (index, step) in steps.enumerated() {
            // Check for cancellation
            try Task.checkCancellation()
            
            // Apply delay if specified
            if step.delayMs > 0 {
                try await Task.sleep(nanoseconds: UInt64(step.delayMs) * 1_000_000)
            }
            
            do {
                let result = try await executeStep(
                    step: step,
                    modelContext: modelContext,
                    variables: accumulatedVariables
                )
                results.append(result)
                
                // Merge extracted values into variables for next step
                accumulatedVariables.merge(result.extractedValues) { _, new in new }
                
                // Store extracted values on step for UI display
                step.extractedValues = result.extractedValues
                
            } catch {
                let result = ChainStepResult(
                    stepId: step.id,
                    stepName: step.name,
                    durationMs: 0,
                    success: false,
                    errorMessage: error.localizedDescription
                )
                results.append(result)
                
                if !step.continueOnError {
                    throw ChainExecutorError.stepFailed(error.localizedDescription)
                }
            }
        }
        
        return results
    }
    
    func executeStep(
        step: ChainStep,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> ChainStepResult {
        guard let requestID = step.requestID else {
            throw ChainExecutorError.requestNotFound(UUID())
        }
        
        // Fetch the request
        let descriptor = FetchDescriptor<HTTPRequest>(predicate: #Predicate { $0.id == requestID })
        guard let request = try? modelContext.fetch(descriptor).first else {
            throw ChainExecutorError.requestNotFound(requestID)
        }
        
        let startTime = Date()
        
        do {
            // Build the URL request with interpolated variables
            let httpClient = Container.shared.httpClient()
            let requestBuilder = Container.shared.requestBuilder()
            let responseExtractor = ResponseExtractor()
            
            let urlRequest = try requestBuilder.buildURLRequest(
                for: request,
                with: variables
            )
            
            // Execute the request
            let taskID = UUID()
            let response = try await httpClient.execute(urlRequest, taskID: taskID)
            
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            
            // Extract values from response
            let extractionResult = responseExtractor.extractAll(
                from: response,
                using: step.extractionRules
            )
            
            let result = ChainStepResult(
                stepId: step.id,
                stepName: step.name.isEmpty ? request.name : step.name,
                statusCode: response.statusCode,
                durationMs: durationMs,
                success: true,
                extractedValues: extractionResult.extractedValues
            )
            
            return result
            
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            
            return ChainStepResult(
                stepId: step.id,
                stepName: step.name.isEmpty ? request.name : step.name,
                durationMs: durationMs,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }
}

// MARK: - Sync Wrapper for Non-Actor Contexts

/// Non-actor wrapper for ChainExecutor that can be used from @Observable contexts
final class ChainExecutorService: Sendable {
    private let executor = ChainExecutor()
    
    func execute(
        chain: RequestChain,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> [ChainStepResult] {
        try await executor.execute(chain: chain, modelContext: modelContext, variables: variables)
    }
    
    func executeStep(
        step: ChainStep,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> ChainStepResult {
        try await executor.executeStep(step: step, modelContext: modelContext, variables: variables)
    }
}
