import Foundation
import Observation
import SwiftData
import FactoryKit

/// ViewModel for managing and executing request chains
@Observable
final class RequestChainViewModel {
    
    // MARK: - UI State
    
    var selectedChain: RequestChain?
    var selectedStep: ChainStep?
    var isExecuting = false
    var executionState: ChainExecutionState = .idle
    var currentExecutionHistory: ChainExecutionHistory?
    var error: Error?
    
    // Execution results for display
    var stepResults: [UUID: ChainStepResult] = [:]
    var currentStepIndex: Int = 0
    
    // Drag and drop state
    var draggedStep: ChainStep?
    var dropTargetStep: ChainStep?
    
    // MARK: - Dependencies
    
    private let modelContext: ModelContext
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.requestBuilder) private var requestBuilder
    
    private let executor = ChainExecutorService()
    private var executionTask: Task<Void, Never>?
    
    // MARK: - Init
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Chain Management
    
    func createChain(name: String, description: String? = nil) -> RequestChain {
        let chain = RequestChain(name: name, description: description)
        modelContext.insert(chain)
        try? modelContext.save()
        return chain
    }
    
    func deleteChain(_ chain: RequestChain) {
        // Clean up execution history
        for history in chain.history {
            modelContext.delete(history)
        }
        modelContext.delete(chain)
        try? modelContext.save()
        
        if selectedChain == chain {
            selectedChain = nil
            selectedStep = nil
        }
    }
    
    func duplicateChain(_ chain: RequestChain) -> RequestChain {
        let copy = chain.duplicated()
        modelContext.insert(copy)
        try? modelContext.save()
        return copy
    }
    
    // MARK: - Step Management
    
    func addStep(to chain: RequestChain, request: HTTPRequest, name: String? = nil) -> ChainStep {
        let step = ChainStep(
            name: name ?? request.name,
            requestID: request.id,
            stepOrder: chain.steps.count
        )
        step.chain = chain
        chain.steps.append(step)
        try? modelContext.save()
        return step
    }
    
    func removeStep(_ step: ChainStep) {
        guard let chain = step.chain else { return }
        chain.steps.removeAll { $0.id == step.id }
        reorderSteps(in: chain)
        try? modelContext.save()
        
        if selectedStep == step {
            selectedStep = nil
        }
    }
    
    func duplicateStep(_ step: ChainStep) -> ChainStep? {
        guard let chain = step.chain else { return nil }
        let copy = step.duplicated()
        copy.stepOrder = step.stepOrder + 1
        copy.chain = chain
        
        // Shift subsequent steps
        for existingStep in chain.steps where existingStep.stepOrder > step.stepOrder {
            existingStep.stepOrder += 1
        }
        
        chain.steps.append(copy)
        try? modelContext.save()
        return copy
    }
    
    func reorderSteps(in chain: RequestChain) {
        let sorted = chain.sortedSteps
        for (index, step) in sorted.enumerated() {
            step.stepOrder = index
        }
    }
    
    func moveStep(_ step: ChainStep, to newIndex: Int) {
        guard let chain = step.chain else { return }
        let steps = chain.sortedSteps
        let currentIndex = steps.firstIndex(where: { $0.id == step.id }) ?? 0
        
        guard newIndex >= 0, newIndex < steps.count, currentIndex != newIndex else { return }
        
        // Update step orders
        if newIndex > currentIndex {
            // Moving down: shift intermediate steps up
            for i in currentIndex..<newIndex {
                steps[i + 1].stepOrder = i
            }
        } else {
            // Moving up: shift intermediate steps down
            for i in (newIndex..<currentIndex).reversed() {
                steps[i].stepOrder = i + 1
            }
        }
        
        step.stepOrder = newIndex
        try? modelContext.save()
    }
    
    // MARK: - Extraction Rule Management
    
    func addExtractionRule(to step: ChainStep, type: ExtractionType = .jsonPath) -> ExtractionRule {
        let rule = ExtractionRule(
            name: "New Extraction",
            extractionType: type,
            variableName: ""
        )
        rule.sortOrder = step.extractionRules.count
        rule.chainStep = step
        
        var rules = step.extractionRules
        rules.append(rule)
        step.extractionRules = rules
        
        try? modelContext.save()
        return rule
    }
    
    func removeExtractionRule(_ rule: ExtractionRule) {
        guard let step = rule.chainStep else { return }
        var rules = step.extractionRules
        rules.removeAll { $0.id == rule.id }
        step.extractionRules = rules
        try? modelContext.save()
    }
    
    func updateExtractionRule(_ rule: ExtractionRule) {
        guard let step = rule.chainStep else { return }
        var rules = step.extractionRules
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        }
        step.extractionRules = rules
        try? modelContext.save()
    }
    
    // MARK: - Chain Execution
    
    func executeChain(_ chain: RequestChain) {
        guard !isExecuting else { return }
        
        isExecuting = true
        executionState = .running(currentStep: 0, totalSteps: chain.sortedSteps.count)
        stepResults = [:]
        currentStepIndex = 0
        error = nil
        
        // Create execution history entry
        let history = ChainExecutionHistory()
        history.chain = chain
        history.status = .running
        modelContext.insert(history)
        currentExecutionHistory = history
        
        let variables = getActiveEnvironmentVariables()
        
        executionTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let results = try await self.executor.execute(
                    chain: chain,
                    modelContext: self.modelContext,
                    variables: variables
                )
                
                await MainActor.run {
                    // Store results
                    for result in results {
                        self.stepResults[result.stepId] = result
                    }
                    
                    // Update history
                    history.status = .completed
                    history.completedAt = Date()
                    history.stepResults = results
                    history.totalDurationMs = results.reduce(0) { $0 + $1.durationMs }
                    
                    self.executionState = .completed
                    self.isExecuting = false
                    try? self.modelContext.save()
                }
                
            } catch is CancellationError {
                await MainActor.run {
                    history.status = .cancelled
                    history.completedAt = Date()
                    self.executionState = .cancelled
                    self.isExecuting = false
                }
                
            } catch {
                await MainActor.run {
                    history.status = .failed
                    history.completedAt = Date()
                    history.errorMessage = error.localizedDescription
                    self.executionState = .failed(error: error.localizedDescription)
                    self.error = error
                    self.isExecuting = false
                }
            }
        }
    }
    
    func executeSingleStep(_ step: ChainStep) {
        guard !isExecuting else { return }
        
        isExecuting = true
        executionState = .running(currentStep: 0, totalSteps: 1)
        error = nil
        
        let variables = getActiveEnvironmentVariables()
        
        executionTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let result = try await self.executor.executeStep(
                    step: step,
                    modelContext: self.modelContext,
                    variables: variables
                )
                
                await MainActor.run {
                    self.stepResults[step.id] = result
                    step.extractedValues = result.extractedValues
                    
                    if result.success {
                        self.executionState = .completed
                    } else {
                        self.executionState = .failed(error: result.errorMessage ?? "Unknown error")
                    }
                    
                    self.isExecuting = false
                }
                
            } catch {
                await MainActor.run {
                    self.executionState = .failed(error: error.localizedDescription)
                    self.error = error
                    self.isExecuting = false
                }
            }
        }
    }
    
    func cancelExecution() {
        executionTask?.cancel()
        executionTask = nil
        isExecuting = false
        executionState = .cancelled
    }
    
    // MARK: - Environment Variables
    
    func getActiveEnvironmentVariables() -> [String: String] {
        requestBuilder.getActiveEnvironmentVariables(from: modelContext)
    }
    
    // MARK: - History Management
    
    func clearHistory(for chain: RequestChain) {
        for history in chain.history {
            modelContext.delete(history)
        }
        try? modelContext.save()
    }
    
    func loadHistory(_ history: ChainExecutionHistory) {
        stepResults = [:]
        for result in history.stepResults {
            stepResults[result.stepId] = result
        }
        currentExecutionHistory = history
    }
    
    // MARK: - Request Lookup
    
    func fetchRequest(id: UUID) -> HTTPRequest? {
        let descriptor = FetchDescriptor<HTTPRequest>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}
