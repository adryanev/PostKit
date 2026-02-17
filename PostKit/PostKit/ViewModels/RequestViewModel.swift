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
                let modifiedRequest = request
                
                // Execute pre-request script
                if let preScript = request.preRequestScript, !preScript.isEmpty {
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
                    
                    // Apply modifications
                    if let modifiedURL = preResult.modifiedURL {
                        modifiedRequest.urlTemplate = modifiedURL
                    }
                    if let modifiedBody = preResult.modifiedBody {
                        modifiedRequest.bodyContent = modifiedBody
                    }
                }
                
                let urlRequest = try self.buildURLRequest(for: modifiedRequest, with: variables)
                let httpResponse = try await self.httpClient.execute(urlRequest, taskID: taskID)

                guard taskID == self.currentTaskID else { return }
                
                // Execute post-request script
                if let postScript = request.postRequestScript, !postScript.isEmpty {
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

    // MARK: - Request Building

    func buildURLRequest(for request: HTTPRequest, with variables: [String: String]? = nil) throws -> URLRequest {
        let vars = variables ?? getActiveEnvironmentVariables()

        let interpolatedURL = try interpolator.interpolate(
            request.urlTemplate,
            with: vars
        )

        var urlComponents = URLComponents(string: interpolatedURL)

        let queryParams = [KeyValuePair].decode(from: request.queryParamsData)
        var queryItems = urlComponents?.queryItems ?? []

        for param in queryParams where param.isEnabled {
            let interpolatedKey = try interpolator.interpolate(param.key, with: vars)
            let interpolatedValue = try interpolator.interpolate(param.value, with: vars)
            queryItems.append(URLQueryItem(name: interpolatedKey, value: interpolatedValue))
        }

        let authConfig = request.authConfig
        if authConfig.type == .apiKey,
           authConfig.apiKeyLocation == .queryParam,
           let name = authConfig.apiKeyName,
           let value = authConfig.apiKeyValue {
            queryItems.append(URLQueryItem(name: name, value: value))
        }

        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw HTTPClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = 30

        let headers = [KeyValuePair].decode(from: request.headersData)
        for header in headers where header.isEnabled {
            let interpolatedKey = try interpolator.interpolate(header.key, with: vars)
            let interpolatedValue = try interpolator.interpolate(header.value, with: vars)
            urlRequest.setValue(interpolatedValue, forHTTPHeaderField: interpolatedKey)
        }

        if let bodyContent = request.bodyContent, !bodyContent.isEmpty {
            let interpolatedBody = try interpolator.interpolate(bodyContent, with: vars)
            switch request.bodyType {
            case .json, .raw, .xml:
                urlRequest.httpBody = interpolatedBody.data(using: .utf8)
            case .urlEncoded:
                urlRequest.httpBody = interpolatedBody.data(using: .utf8)
            case .formData, .none:
                break
            }

            if let contentType = request.bodyType.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        applyAuth(&urlRequest, authConfig: authConfig)

        return urlRequest
    }

    // MARK: - Environment Variables

    func getActiveEnvironmentVariables() -> [String: String] {
        var variables: [String: String] = [:]

        let descriptor = FetchDescriptor<APIEnvironment>(
            predicate: #Predicate { $0.isActive }
        )

        guard let activeEnv = try? modelContext.fetch(descriptor).first else {
            return variables
        }

        for variable in activeEnv.variables where variable.isEnabled {
            variables[variable.key] = variable.secureValue
        }

        return variables
    }
    
    private func persistEnvironmentChanges(_ changes: [String: String]) {
        let descriptor = FetchDescriptor<APIEnvironment>(
            predicate: #Predicate { $0.isActive }
        )
        
        guard let activeEnv = try? modelContext.fetch(descriptor).first else {
            return
        }
        
        for (key, value) in changes {
            if let existingVar = activeEnv.variables.first(where: { $0.key == key }) {
                existingVar.value = value
                if existingVar.isSecret {
                    existingVar.secureValue = value
                }
            } else {
                let newVar = Variable(key: key, value: value)
                newVar.environment = activeEnv
                modelContext.insert(newVar)
            }
        }
        
        try? modelContext.save()
    }

    // MARK: - Auth

    func applyAuth(_ urlRequest: inout URLRequest, authConfig: AuthConfig) {
        switch authConfig.type {
        case .bearer:
            if let token = authConfig.token {
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            if let username = authConfig.username,
               let password = authConfig.password {
                let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
                urlRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
            }
        case .apiKey:
            if let name = authConfig.apiKeyName,
               let value = authConfig.apiKeyValue {
                if authConfig.apiKeyLocation == .header {
                    urlRequest.setValue(value, forHTTPHeaderField: name)
                }
            }
        case .none:
            break
        }
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
