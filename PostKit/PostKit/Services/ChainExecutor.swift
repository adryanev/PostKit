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

// MARK: - Sendable DTOs for Actor Boundary Crossing

/// Sendable snapshot of a chain step's data for crossing actor boundaries
struct ChainStepSnapshot: Sendable {
    let id: UUID
    let name: String
    let requestID: UUID?
    let stepOrder: Int
    let isEnabled: Bool
    let continueOnError: Bool
    let delayMs: Int
    let extractionRules: [ExtractionRuleSnapshot]

    init(from step: ChainStep) {
        self.id = step.id
        self.name = step.name
        self.requestID = step.requestID
        self.stepOrder = step.stepOrder
        self.isEnabled = step.isEnabled
        self.continueOnError = step.continueOnError
        self.delayMs = step.delayMs
        self.extractionRules = step.extractionRules.map { ExtractionRuleSnapshot(from: $0) }
    }
}

/// Sendable snapshot of an extraction rule for crossing actor boundaries
struct ExtractionRuleSnapshot: Sendable {
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

    /// Convert back to an ExtractionRule for use with ResponseExtractor
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

/// Sendable intermediate result returned by the actor containing the raw HTTP response
struct StepHTTPResult: Sendable {
    let stepId: UUID
    let stepName: String
    let response: HTTPResponse?
    let durationMs: Int
    let success: Bool
    let errorMessage: String?
}

/// Protocol for chain execution service
protocol ChainExecutorProtocol: Sendable {
    /// Execute HTTP requests for a chain and return raw results (no @Model access)
    func execute(
        steps: [ChainStepSnapshot],
        urlRequests: [UUID: URLRequest],
        requestNames: [UUID: String]
    ) async throws -> [StepHTTPResult]

    /// Execute a single HTTP request and return the raw result
    func executeStep(
        step: ChainStepSnapshot,
        urlRequest: URLRequest,
        requestName: String
    ) async throws -> StepHTTPResult
}

/// Actor for executing HTTP requests in request chains.
/// Only handles HTTP execution; extraction and @Model interactions stay on the caller side.
actor ChainExecutor: ChainExecutorProtocol {

    @discardableResult
    func execute(
        steps: [ChainStepSnapshot],
        urlRequests: [UUID: URLRequest],
        requestNames: [UUID: String]
    ) async throws -> [StepHTTPResult] {
        let enabledSteps = steps.filter { $0.isEnabled }
        var results: [StepHTTPResult] = []

        for step in enabledSteps {
            // Check for cancellation
            try Task.checkCancellation()

            // Apply delay if specified
            if step.delayMs > 0 {
                try await Task.sleep(nanoseconds: UInt64(step.delayMs) * 1_000_000)
            }

            guard let urlRequest = urlRequests[step.id] else {
                let failResult = StepHTTPResult(
                    stepId: step.id,
                    stepName: step.name,
                    response: nil,
                    durationMs: 0,
                    success: false,
                    errorMessage: "No URL request available for step"
                )
                results.append(failResult)

                if !step.continueOnError {
                    throw ChainExecutorError.stepFailed("No URL request available for step")
                }
                continue
            }

            let requestName = requestNames[step.id] ?? step.name

            do {
                let result = try await executeStep(
                    step: step,
                    urlRequest: urlRequest,
                    requestName: requestName
                )
                results.append(result)
            } catch {
                let result = StepHTTPResult(
                    stepId: step.id,
                    stepName: step.name,
                    response: nil,
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
        step: ChainStepSnapshot,
        urlRequest: URLRequest,
        requestName: String
    ) async throws -> StepHTTPResult {
        let startTime = Date()

        do {
            let httpClient = Container.shared.httpClient()

            // Execute the request
            let taskID = UUID()
            let response = try await httpClient.execute(urlRequest, taskID: taskID)

            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

            return StepHTTPResult(
                stepId: step.id,
                stepName: step.name.isEmpty ? requestName : step.name,
                response: response,
                durationMs: durationMs,
                success: true,
                errorMessage: nil
            )

        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

            return StepHTTPResult(
                stepId: step.id,
                stepName: step.name.isEmpty ? requestName : step.name,
                response: nil,
                durationMs: durationMs,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }
}

// MARK: - Sync Wrapper for Non-Actor Contexts

/// Non-actor wrapper for ChainExecutor that can be used from @Observable contexts.
/// Handles ModelContext interactions and response extraction on the caller side,
/// passing only Sendable types across the actor boundary.
final class ChainExecutorService: Sendable {
    private let executor = ChainExecutor()

    /// Executes a chain by resolving all ModelContext-dependent data on the caller side,
    /// then delegating network execution to the actor with only Sendable types.
    func execute(
        chain: RequestChain,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> [ChainStepResult] {
        guard chain.isEnabled else {
            throw ChainExecutorError.chainDisabled
        }

        let sortedSteps = chain.sortedSteps.filter { $0.isEnabled }
        let stepSnapshots = sortedSteps.map { ChainStepSnapshot(from: $0) }

        // Pre-resolve URLRequests and request names from ModelContext (non-Sendable)
        let requestBuilder = Container.shared.requestBuilder()
        var urlRequests: [UUID: URLRequest] = [:]
        var requestNames: [UUID: String] = [:]

        for snapshot in stepSnapshots {
            guard let requestID = snapshot.requestID else { continue }

            let descriptor = FetchDescriptor<HTTPRequest>(predicate: #Predicate { $0.id == requestID })
            guard let request = try? modelContext.fetch(descriptor).first else {
                throw ChainExecutorError.requestNotFound(requestID)
            }

            requestNames[snapshot.id] = request.name
            urlRequests[snapshot.id] = try requestBuilder.buildURLRequest(
                for: request,
                with: variables,
                urlOverride: nil,
                bodyOverride: nil
            )
        }

        // Execute HTTP requests on actor with only Sendable types
        let httpResults = try await executor.execute(
            steps: stepSnapshots,
            urlRequests: urlRequests,
            requestNames: requestNames
        )

        // Perform extraction on the caller side (where @Model types are accessible)
        let responseExtractor = ResponseExtractor()
        var finalResults: [ChainStepResult] = []

        for (index, httpResult) in httpResults.enumerated() {
            let snapshot = stepSnapshots[index]
            var extractedValues: [String: String] = [:]

            if httpResult.success, let response = httpResult.response {
                let extractionRules = snapshot.extractionRules.map { $0.toExtractionRule() }
                let extractionResult = responseExtractor.extractAll(
                    from: response,
                    using: extractionRules
                )
                extractedValues = extractionResult.extractedValues
            }

            let result = ChainStepResult(
                stepId: httpResult.stepId,
                stepName: httpResult.stepName,
                statusCode: httpResult.response?.statusCode,
                durationMs: httpResult.durationMs,
                success: httpResult.success,
                errorMessage: httpResult.errorMessage,
                extractedValues: extractedValues
            )
            finalResults.append(result)
        }

        // Update non-Sendable model objects back on the caller side
        for (step, result) in zip(sortedSteps, finalResults) {
            step.extractedValues = result.extractedValues
        }

        return finalResults
    }

    /// Executes a single step by resolving ModelContext-dependent data on the caller side.
    func executeStep(
        step: ChainStep,
        modelContext: ModelContext,
        variables: [String: String]
    ) async throws -> ChainStepResult {
        guard let requestID = step.requestID else {
            throw ChainExecutorError.requestNotFound(UUID())
        }

        let descriptor = FetchDescriptor<HTTPRequest>(predicate: #Predicate { $0.id == requestID })
        guard let request = try? modelContext.fetch(descriptor).first else {
            throw ChainExecutorError.requestNotFound(requestID)
        }

        let requestBuilder = Container.shared.requestBuilder()
        let urlRequest = try requestBuilder.buildURLRequest(
            for: request,
            with: variables,
            urlOverride: nil,
            bodyOverride: nil
        )

        let snapshot = ChainStepSnapshot(from: step)

        let httpResult = try await executor.executeStep(
            step: snapshot,
            urlRequest: urlRequest,
            requestName: request.name
        )

        // Perform extraction on the caller side
        var extractedValues: [String: String] = [:]
        if httpResult.success, let response = httpResult.response {
            let responseExtractor = ResponseExtractor()
            let extractionRules = step.extractionRules
            let extractionResult = responseExtractor.extractAll(
                from: response,
                using: extractionRules
            )
            extractedValues = extractionResult.extractedValues
        }

        return ChainStepResult(
            stepId: httpResult.stepId,
            stepName: httpResult.stepName,
            statusCode: httpResult.response?.statusCode,
            durationMs: httpResult.durationMs,
            success: httpResult.success,
            errorMessage: httpResult.errorMessage,
            extractedValues: extractedValues
        )
    }
}
