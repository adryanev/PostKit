import SwiftUI
import SwiftData

/// Editor view for configuring a mock endpoint
struct MockEndpointEditorView: View {
    @Bindable var endpoint: MockEndpoint
    let server: MockServer
    let viewModel: MockServerViewModel?
    
    @State private var showingAddResponse = false
    @State private var newResponseName = "New Response"
    @State private var selectedResponseId: UUID?
    
    private var responses: [MockResponse] {
        endpoint.responses.sorted { $0.isDefault && !$1.isDefault }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Endpoint Configuration
                endpointConfiguration
                    .padding()
                
                Divider()
                
                // Responses Section
                responsesSection
                    .padding()
            }
        }
        .navigationTitle(endpoint.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    copyCurlCommand()
                } label: {
                    Label("Copy cURL", systemImage: "terminal")
                }
                .help("Copy cURL command")
            }
        }
        .alert("Add Response", isPresented: $showingAddResponse) {
            TextField("Name", text: $newResponseName)
            Button("Cancel", role: .cancel) {
                newResponseName = "New Response"
            }
            Button("Add") {
                if let viewModel = viewModel {
                    _ = viewModel.addResponse(to: endpoint, name: newResponseName)
                    newResponseName = "New Response"
                }
            }
        }
    }
    
    // MARK: - Endpoint Configuration
    
    private var endpointConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Endpoint Configuration")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Path:")
                        .gridColumnAlignment(.trailing)
                    
                    TextField("", text: $endpoint.path, prompt: Text("/api/path"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: endpoint.path) {
                            endpoint.updatedAt = Date()
                            Task { await updateEndpoints() }
                        }
                }
                
                GridRow {
                    Text("Method:")
                    
                    Picker("", selection: $endpoint.method) {
                        ForEach(HTTPMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .frame(width: 120)
                    .onChange(of: endpoint.methodRaw) {
                        endpoint.updatedAt = Date()
                        Task { await updateEndpoints() }
                    }
                }
                
                GridRow {
                    Text("Name:")
                    
                    TextField("", text: $endpoint.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: endpoint.name) {
                            endpoint.updatedAt = Date()
                        }
                }
                
                GridRow {
                    Text("Description:")
                    
                    TextField("", text: Binding(get: { endpoint.endpointDescription ?? "" }, set: { endpoint.endpointDescription = $0.isEmpty ? nil : $0 }), prompt: Text("Optional description"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: endpoint.endpointDescription) {
                            endpoint.updatedAt = Date()
                        }
                }
                
                GridRow {
                    Text("Enabled:")
                    
                    Toggle("", isOn: $endpoint.isEnabled)
                        .onChange(of: endpoint.isEnabled) {
                            endpoint.updatedAt = Date()
                            Task { await updateEndpoints() }
                        }
                }
            }
            
            // Path Parameters Info
            if hasPathParameters {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    
                    Text("Path parameters: \(pathParameterNames)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Responses Section
    
    private var responsesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Responses")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingAddResponse = true
                } label: {
                    Label("Add Response", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            
            if responses.isEmpty {
                ContentUnavailableView {
                    Label("No Responses", systemImage: "doc.text")
                } description: {
                    Text("Add at least one response for this endpoint")
                } actions: {
                    Button("Add Response") {
                        showingAddResponse = true
                    }
                }
            } else {
                ForEach(responses) { response in
                    MockResponseRow(
                        response: response,
                        isSelected: selectedResponseId == response.id,
                        isDefault: response.isDefault
                    ) {
                        selectedResponseId = response.id
                    } onSetDefault: {
                        viewModel?.setDefaultResponse(response)
                    } onDuplicate: {
                        _ = viewModel?.duplicateResponse(response)
                    } onDelete: {
                        viewModel?.deleteResponse(response)
                    }
                }
                
                // Response Editor
                if let responseId = selectedResponseId,
                   let response = responses.first(where: { $0.id == responseId }) {
                    Divider()
                    
                    MockResponseEditor(response: response, viewModel: viewModel)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var hasPathParameters: Bool {
        endpoint.path.contains("{")
    }
    
    private var pathParameterNames: String {
        let pattern = "\\{(\\w+)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        
        let range = NSRange(endpoint.path.startIndex..., in: endpoint.path)
        let matches = regex.matches(in: endpoint.path, range: range)
        
        let params = matches.compactMap { match in
            if let paramRange = Range(match.range(at: 1), in: endpoint.path) {
                return String(endpoint.path[paramRange])
            }
            return nil
        }
        
        return params.joined(separator: ", ")
    }
    
    private func updateEndpoints() async {
        await viewModel?.updateServerEndpoints(server)
    }
    
    private func copyCurlCommand() {
        let curl = viewModel?.copyCurlCommand(for: endpoint, server: server) ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curl, forType: .string)
    }
}

// MARK: - Response Row

struct MockResponseRow: View {
    @Bindable var response: MockResponse
    
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    let onSetDefault: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                // Status Code Badge
                Text("\(response.statusCode)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(statusCodeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusCodeColor.opacity(0.15))
                    .cornerRadius(4)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(response.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        
                        if isDefault {
                            Text("DEFAULT")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(response.bodyType.contentType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if response.delayMs > 0 {
                            Text("• \(response.delayMs)ms delay")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSetDefault()
            } label: {
                Label("Set as Default", systemImage: "star")
            }
            .disabled(isDefault)
            
            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var statusCodeColor: Color {
        switch response.statusCode {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        case 500..<600: .red
        default: .gray
        }
    }
}

// MARK: - Response Editor

struct MockResponseEditor: View {
    @Bindable var response: MockResponse
    let viewModel: MockServerViewModel?
    
    @State private var headers: [KeyValuePair] = []
    @State private var bodyText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Response Details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Name:")
                        .gridColumnAlignment(.trailing)
                    
                    TextField("", text: $response.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: response.name) {
                            response.updatedAt = Date()
                        }
                }
                
                GridRow {
                    Text("Status Code:")
                    
                    HStack {
                        TextField("", value: $response.statusCode, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        
                        Picker("", selection: $response.statusCode) {
                            Text("200 OK").tag(200)
                            Text("201 Created").tag(201)
                            Text("204 No Content").tag(204)
                            Text("400 Bad Request").tag(400)
                            Text("401 Unauthorized").tag(401)
                            Text("403 Forbidden").tag(403)
                            Text("404 Not Found").tag(404)
                            Text("500 Server Error").tag(500)
                        }
                        .frame(width: 160)
                    }
                    .onChange(of: response.statusCode) {
                        response.updatedAt = Date()
                    }
                }
                
                GridRow {
                    Text("Content Type:")
                    
                    Picker("", selection: $response.bodyType) {
                        ForEach(MockResponseBodyType.allCases, id: \.self) { type in
                            Text(type.contentType).tag(type)
                        }
                    }
                    .frame(width: 200)
                    .onChange(of: response.bodyTypeRaw) {
                        response.updatedAt = Date()
                    }
                }
                
                GridRow {
                    Text("Delay (ms):")
                    
                    HStack {
                        TextField("", value: $response.delayMs, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        
                        Text("Simulate network latency")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: response.delayMs) {
                        response.updatedAt = Date()
                    }
                }
            }
            
            Divider()
            
            // Headers
            VStack(alignment: .leading, spacing: 8) {
                Text("Headers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                KeyValuePairEditor(pairs: $headers)
                    .onChange(of: headers) {
                        response.headers = headers
                        response.updatedAt = Date()
                    }
            }
            
            Divider()
            
            // Body
            VStack(alignment: .leading, spacing: 8) {
                Text("Response Body")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $bodyText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200, maxHeight: 400)
                    .border(Color.secondary.opacity(0.2))
                    .onChange(of: bodyText) {
                        response.bodyContent = bodyText
                        response.updatedAt = Date()
                    }
            }
        }
        .onAppear {
            headers = response.headers
            bodyText = response.bodyContent ?? ""
        }
    }
}

// MARK: - Key Value Pair Editor

struct KeyValuePairEditor: View {
    @Binding var pairs: [KeyValuePair]
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(pairs.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Toggle("", isOn: $pairs[index].isEnabled)
                        .labelsHidden()
                        .frame(width: 20)
                    
                    TextField("Key", text: $pairs[index].key)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Value", text: $pairs[index].value)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        pairs.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button {
                pairs.append(KeyValuePair(key: "", value: ""))
            } label: {
                Label("Add Header", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MockServer.self, configurations: config)
    
    let server = MockServer(name: "Test Server", port: 3000)
    let endpoint = MockEndpoint(path: "/users/{id}", method: .get, name: "Get User")
    
    container.mainContext.insert(server)
    container.mainContext.insert(endpoint)
    
    endpoint.server = server
    
    return MockEndpointEditorView(
        endpoint: endpoint,
        server: server,
        viewModel: MockServerViewModel(modelContext: container.mainContext)
    )
    .modelContainer(container)
}
