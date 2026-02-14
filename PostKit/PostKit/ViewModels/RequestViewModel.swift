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
    private(set) var currentTaskID: UUID?

    // MARK: - Dependencies

    private let modelContext: ModelContext
    
    // Factory @Injected properties MUST be marked @ObservationIgnored in @Observable classes.
    // Without it, the Observation framework tracks dependency resolution as state changes,
    // causing infinite re-render loops or compilation errors.
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.variableInterpolator) private var interpolator

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
        let taskID = UUID()
        currentTaskID = taskID

        Task {
            do {
                let urlRequest = try buildURLRequest(for: request)
                let httpResponse = try await httpClient.execute(urlRequest, taskID: taskID)

                guard taskID == self.currentTaskID else { return }
                
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

    func cancelRequest() {
        if let taskID = currentTaskID {
            Task {
                await httpClient.cancel(taskID: taskID)
            }
        }
        isSending = false
    }

    // MARK: - Request Building

    func buildURLRequest(for request: HTTPRequest) throws -> URLRequest {
        let variables = getActiveEnvironmentVariables()

        let interpolatedURL = try interpolator.interpolate(
            request.urlTemplate,
            with: variables
        )

        var urlComponents = URLComponents(string: interpolatedURL)

        let queryParams = [KeyValuePair].decode(from: request.queryParamsData)
        var queryItems = urlComponents?.queryItems ?? []

        for param in queryParams where param.isEnabled {
            let interpolatedKey = try interpolator.interpolate(param.key, with: variables)
            let interpolatedValue = try interpolator.interpolate(param.value, with: variables)
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
            let interpolatedKey = try interpolator.interpolate(header.key, with: variables)
            let interpolatedValue = try interpolator.interpolate(header.value, with: variables)
            urlRequest.setValue(interpolatedValue, forHTTPHeaderField: interpolatedKey)
        }

        if let bodyContent = request.bodyContent, !bodyContent.isEmpty {
            let interpolatedBody = try interpolator.interpolate(bodyContent, with: variables)
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
}
