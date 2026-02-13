import SwiftUI
import SwiftData

struct RequestDetailView: View {
    @Bindable var request: HTTPRequest
    @Environment(\.httpClient) private var httpClient
    @Environment(\.modelContext) private var modelContext
    @State private var response: HTTPResponse?
    @State private var isSending = false
    @State private var error: Error?
    @State private var activeTab: ResponseTab = .body
    @State private var currentTaskID: UUID?
    
    enum ResponseTab: String, CaseIterable {
        case body = "Body"
        case headers = "Headers"
        case timing = "Timing"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            URLBar(
                method: $request.method,
                url: $request.urlTemplate,
                isSending: isSending,
                onSend: sendRequest,
                onCancel: cancelRequest
            )
            
            Divider()
            
            HSplitView {
                RequestEditorPane(request: request)
                    .frame(minWidth: 300, maxWidth: .infinity)
                
                ResponseViewerPane(
                    response: response,
                    error: error,
                    activeTab: $activeTab,
                    isLoading: isSending
                )
                .frame(minWidth: 300, maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Response Tab", selection: $activeTab) {
                    ForEach(ResponseTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(response == nil && error == nil)
            }
        }
    }
    
    private func sendRequest() {
        guard !request.urlTemplate.isEmpty else { return }
        
        isSending = true
        error = nil
        response = nil
        currentTaskID = UUID()
        
        Task {
            do {
                var urlRequest = try buildURLRequest()
                let httpResponse = try await httpClient.execute(urlRequest)
                
                await MainActor.run {
                    self.response = httpResponse
                    self.isSending = false
                    self.saveHistory(httpResponse)
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isSending = false
                }
            }
        }
    }
    
    private func cancelRequest() {
        if let taskID = currentTaskID {
            Task {
                await httpClient.cancel(taskID: taskID)
            }
        }
        isSending = false
    }
    
    private func buildURLRequest() throws -> URLRequest {
        var urlComponents = URLComponents(string: request.urlTemplate)
        
        let queryParams = [KeyValuePair].decode(from: request.queryParamsData)
        var queryItems = urlComponents?.queryItems ?? []
        
        for param in queryParams where param.isEnabled {
            queryItems.append(URLQueryItem(name: param.key, value: param.value))
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
            urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }
        
        if let bodyContent = request.bodyContent, !bodyContent.isEmpty {
            switch request.bodyType {
            case .json, .raw, .xml:
                urlRequest.httpBody = bodyContent.data(using: .utf8)
            case .urlEncoded:
                urlRequest.httpBody = bodyContent.data(using: .utf8)
            case .formData, .none:
                break
            }
            
            if let contentType = request.bodyType.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        
        applyAuth(&urlRequest)
        
        return urlRequest
    }
    
    private func applyAuth(_ urlRequest: inout URLRequest) {
        let authConfig = request.authConfig
        
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
    
    private func saveHistory(_ httpResponse: HTTPResponse) {
        let entry = HistoryEntry(
            method: request.method,
            url: request.urlTemplate,
            statusCode: httpResponse.statusCode,
            responseTime: httpResponse.duration,
            responseSize: httpResponse.size
        )
        entry.request = request
        modelContext.insert(entry)
    }
}

#Preview {
    RequestDetailView(request: HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users"))
        .frame(width: 900, height: 600)
        .modelContainer(for: HTTPRequest.self, inMemory: true)
}
