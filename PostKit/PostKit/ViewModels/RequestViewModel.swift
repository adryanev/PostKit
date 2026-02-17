import Foundation
import Observation
import SwiftData
import FactoryKit

/// Encapsulates the business logic previously embedded in `RequestDetailView`.
/// Manages HTTP request execution, response state, history recording, and
/// variable interpolation so the view remains a thin rendering layer.
@Observable
final class RequestViewModel {

    // MARK: - UI State

    var response: HTTPResponse?
    var isSending = false
    var error: Error?
    var activeTab: ResponseTab = .body
    var consoleOutput: [String] = []
    private(set) var currentTaskID: UUID?
    @ObservationIgnored private(set) var currentTask: Task<Void, Never>?
    private var pendingEnvironmentChanges: [String: String] = [:]

    // MARK: - Dependencies

    private let modelContext: ModelContext
    
    // Factory @Injected properties MUST be marked @ObservationIgnored in @Observable classes.
    // Without it, the Observation framework tracks dependency resolution as state changes,
    // causing infinite re-render loops or compilation errors.
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.variableInterpolator) private var interpolator
    @ObservationIgnored @Injected(\.scriptEngine) private var scriptEngine
    @ObservationIgnored @Injected(\.requestBuilder) private var requestBuilder

    // MARK: - History Cleanup

    private static let maxHistoryEntries = 1000
    private static var requestCount = 0
    private static let cleanupInterval = 10

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    func sendRequest(for request: HTTPRequest) {
        guard !request.urlTemplate.isEmpty else { return }

        // Clean up previous response's temp file before starting a new request
        if let oldURL = response?.bodyFileURL {
            try? FileManager.default.removeItem(at: oldURL)
        }

        isSending = true
        error = nil
        response = nil
        consoleOutput = []
        let taskID = UUID()
        currentTaskID = taskID

        currentTask = Task { @MainActor in
            do {
                var variables = self.getActiveEnvironmentVariables()
                var effectiveURL = request.urlTemplate
                var effectiveBody = request.bodyContent

                // Execute pre-request script
                if let preScript = request.preRequestScript, !preScript.isEmpty {
                    self.consoleOutput.append("[PostKit] Executing pre-request script...")
                    let scriptRequest = ScriptRequest(
                        method: request.method.rawValue,
                        url: request.urlTemplate,
                        headers: self.headersDict(for: request),
                        body: request.bodyContent
                    )
                    let preResult = try await self.scriptEngine.executePreRequest(
                        script: preScript,
                        request: scriptRequest,
                        environment: variables
                    )
                    self.consoleOutput.append(contentsOf: preResult.consoleOutput)
                    variables.merge(preResult.environmentChanges) { _, new in new }
                    self.pendingEnvironmentChanges.merge(preResult.environmentChanges) { _, new in new }

                    // Apply modifications to local variables, not the persisted model
                    if let modifiedURL = preResult.modifiedURL {
                        effectiveURL = modifiedURL
                    }
                    if let modifiedBody = preResult.modifiedBody {
                        effectiveBody = modifiedBody
                    }
                }

                let urlRequest = try self.requestBuilder.buildURLRequest(
                    for: request,
                    with: variables,
                    urlOverride: effectiveURL,
                    bodyOverride: effectiveBody
                )
                let httpResponse = try await self.httpClient.execute(urlRequest, taskID: taskID)

                guard taskID == self.currentTaskID else { return }
                
                // Execute post-request script
                if let postScript = request.postRequestScript, !postScript.isEmpty {
                    self.consoleOutput.append("[PostKit] Executing post-request script...")
                    let bodyString: String? = {
                        guard let body = httpResponse.body else { return nil }
                        return String(data: body, encoding: .utf8)
                    }()
                    let scriptResponse = ScriptResponse(
                        statusCode: httpResponse.statusCode,
                        headers: httpResponse.headers,
                        body: bodyString,
                        duration: httpResponse.duration
                    )
                    let postResult = try await self.scriptEngine.executePostRequest(
                        script: postScript,
                        response: scriptResponse,
                        environment: variables
                    )
                    self.consoleOutput.append(contentsOf: postResult.consoleOutput)
                    self.pendingEnvironmentChanges.merge(postResult.environmentChanges) { _, new in new }
                }
                
                // Persist environment changes to SwiftData
                if !self.pendingEnvironmentChanges.isEmpty {
                    self.persistEnvironmentChanges(self.pendingEnvironmentChanges)
                    self.pendingEnvironmentChanges = [:]
                }

                self.response = httpResponse
                self.isSending = false
                self.saveHistory(httpResponse, for: request)
            } catch {
                guard taskID == self.currentTaskID else { return }

                self.error = error
                self.isSending = false
            }
        }
    }
    
    private func headersDict(for request: HTTPRequest) -> [String: String] {
        let headers = [KeyValuePair].decode(from: request.headersData)
        var dict: [String: String] = [:]
        for header in headers where header.isEnabled {
            dict[header.key] = header.value
        }
        return dict
    }

    func cancelRequest() {
        if let taskID = currentTaskID {
            Task { @MainActor in
                await httpClient.cancel(taskID: taskID)
            }
        }
        isSending = false
    }

    // MARK: - Request Building (delegates to RequestBuilder)

    func buildURLRequest(
        for request: HTTPRequest,
        with variables: [String: String]? = nil,
        urlOverride: String? = nil,
        bodyOverride: String?? = nil
    ) throws -> URLRequest {
        let vars = variables ?? getActiveEnvironmentVariables()
        return try requestBuilder.buildURLRequest(
            for: request,
            with: vars,
            urlOverride: urlOverride,
            bodyOverride: bodyOverride
        )
    }

    // MARK: - Environment Variables (delegates to RequestBuilder)

    func getActiveEnvironmentVariables() -> [String: String] {
        requestBuilder.getActiveEnvironmentVariables(from: modelContext)
    }
    
    private func persistEnvironmentChanges(_ changes: [String: String]) {
        let descriptor = FetchDescriptor<APIEnvironment>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            guard let activeEnv = try modelContext.fetch(descriptor).first else {
                return
            }

            for (key, value) in changes {
                if let existingVar = activeEnv.variables.first(where: { $0.key == key }) {
                    if existingVar.isSecret {
                        existingVar.secureValue = value
                    } else {
                        existingVar.value = value
                    }
                } else {
                    let newVar = Variable(key: key, value: value)
                    newVar.environment = activeEnv
                    modelContext.insert(newVar)
                }
            }

            try modelContext.save()
        } catch {
            print("[PostKit] Failed to save environment changes: \(error)")
        }
    }

    // MARK: - Auth (delegates to RequestBuilder)

    func applyAuth(_ urlRequest: inout URLRequest, authConfig: AuthConfig) {
        requestBuilder.applyAuth(&urlRequest, authConfig: authConfig)
    }

    // MARK: - History

    func saveHistory(_ httpResponse: HTTPResponse, for request: HTTPRequest) {
        let entry = HistoryEntry(
            method: request.method,
            url: request.urlTemplate,
            statusCode: httpResponse.statusCode,
            responseTime: httpResponse.duration,
            responseSize: httpResponse.size
        )
        entry.request = request
        modelContext.insert(entry)

        Self.requestCount += 1
        if Self.requestCount % Self.cleanupInterval == 0 {
            cleanupOldHistory()
        }
    }

    func cleanupOldHistory() {
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchOffset = Self.maxHistoryEntries

        guard let oldEntries = try? modelContext.fetch(descriptor), !oldEntries.isEmpty else {
            return
        }
        for entry in oldEntries {
            modelContext.delete(entry)
        }
    }
}

// MARK: - ResponseTab

/// Tab selection for the response viewer. Defined at file scope so both
/// `RequestViewModel` and `ResponseViewerPane` can reference it without
/// coupling to `RequestDetailView`.
enum ResponseTab: String, CaseIterable {
    case body = "Body"
    case headers = "Headers"
    case timing = "Timing"
    case console = "Console"
    case examples = "Examples"
}
