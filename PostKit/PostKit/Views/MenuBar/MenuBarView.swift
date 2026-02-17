import SwiftUI
import SwiftData
import FactoryKit

struct MenuBarResult {
    let statusCode: Int
    let duration: TimeInterval
    let timestamp: Date
    let error: Error?
    
    var statusColor: Color {
        switch statusCode {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        case 500..<600: .red
        default: .gray
        }
    }
}

struct MenuBarView: View {
    @Query(filter: #Predicate<HTTPRequest> { $0.isPinned }, sort: \HTTPRequest.updatedAt, order: .reverse)
    private var pinnedRequests: [HTTPRequest]
    
    @Environment(\.modelContext) private var modelContext
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.variableInterpolator) private var interpolator
    
    @State private var results: [UUID: MenuBarResult] = [:]
    @State private var sendingRequestIDs: Set<UUID> = []
    
    private let maxPinnedDisplay = 20
    
    var body: some View {
        if pinnedRequests.isEmpty {
            Text("No Pinned Requests")
                .foregroundStyle(.secondary)
            Divider()
        } else {
            ForEach(pinnedRequests.prefix(maxPinnedDisplay)) { request in
                MenuBarRequestRow(
                    request: request,
                    result: results[request.id],
                    isSending: sendingRequestIDs.contains(request.id)
                ) {
                    await sendRequest(request)
                }
            }
            Divider()
        }
        
        Button("Open PostKit") {
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")
        
        Divider()
        
        Button("Quit PostKit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
    
    private func sendRequest(_ request: HTTPRequest) async {
        guard !request.urlTemplate.isEmpty else { return }
        
        let hasScripts = (request.preRequestScript?.isEmpty == false) || (request.postRequestScript?.isEmpty == false)
        if hasScripts {
            return
        }
        
        await MainActor.run {
            _ = sendingRequestIDs.insert(request.id)
        }
        
        do {
            let urlRequest = try buildURLRequest(for: request)
            let response = try await httpClient.execute(urlRequest, taskID: UUID())
            
            await MainActor.run {
                results[request.id] = MenuBarResult(
                    statusCode: response.statusCode,
                    duration: response.duration,
                    timestamp: Date(),
                    error: nil
                )
                sendingRequestIDs.remove(request.id)
            }
            
            let entry = HistoryEntry(
                method: request.method,
                url: request.urlTemplate,
                statusCode: response.statusCode,
                responseTime: response.duration,
                responseSize: response.size
            )
            entry.request = request
            modelContext.insert(entry)
            try? modelContext.save()
        } catch {
            await MainActor.run {
                results[request.id] = MenuBarResult(
                    statusCode: 0,
                    duration: 0,
                    timestamp: Date(),
                    error: error
                )
                sendingRequestIDs.remove(request.id)
            }
        }
    }
    
    private func buildURLRequest(for request: HTTPRequest) throws -> URLRequest {
        let variables = getActiveEnvironmentVariables()
        
        let interpolatedURL = try interpolator.interpolate(request.urlTemplate, with: variables)
        
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
    
    private func getActiveEnvironmentVariables() -> [String: String] {
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
    
    private func applyAuth(_ urlRequest: inout URLRequest, authConfig: AuthConfig) {
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
}

struct MenuBarRequestRow: View {
    let request: HTTPRequest
    let result: MenuBarResult?
    let isSending: Bool
    let onSend: () async -> Void
    
    private let maxDisplayTime: TimeInterval = 30
    
    var body: some View {
        Button {
            Task { await onSend() }
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else if let result = result, Date().timeIntervalSince(result.timestamp) < maxDisplayTime {
                    Circle()
                        .fill(result.statusColor)
                        .frame(width: 8, height: 8)
                } else {
                    methodBadge
                }
                
                Text(request.name)
                    .lineLimit(1)
                
                Spacer()
                
                if let result = result, Date().timeIntervalSince(result.timestamp) < maxDisplayTime {
                    if result.error != nil {
                        Text("Error")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Text("\(result.statusCode) • \(String(format: "%.0f", result.duration * 1000))ms")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                
                if hasScripts {
                    Text("(script)")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .disabled(isSending || hasScripts)
    }
    
    @ViewBuilder
    private var methodBadge: some View {
        Text(request.method.rawValue.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(methodColor)
    }
    
    private var methodColor: Color {
        switch request.method {
        case .get: .blue
        case .post: .green
        case .put: .orange
        case .patch: .yellow
        case .delete: .red
        default: .gray
        }
    }
    
    private var hasScripts: Bool {
        (request.preRequestScript?.isEmpty == false) || (request.postRequestScript?.isEmpty == false)
    }
}
