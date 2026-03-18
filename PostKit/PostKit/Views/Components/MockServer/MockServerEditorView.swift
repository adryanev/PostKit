import SwiftUI
import SwiftData

/// Editor view for configuring a mock server
struct MockServerEditorView: View {
    @Bindable var server: MockServer
    let viewModel: MockServerViewModel?
    
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showingExportPicker = false
    @State private var showingAddEndpoint = false
    @State private var newEndpointPath = "/"
    @State private var newEndpointMethod: HTTPMethod = .get
    @State private var status: MockServerStatus = .stopped
    @State private var isRunning = false
    
    private var endpoints: [MockEndpoint] {
        server.endpoints.sorted { $0.path < $1.path }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Server Header
                serverHeader
                    .padding()
                
                Divider()
                
                // Server Configuration
                serverConfiguration
                    .padding()
                
                Divider()
                
                // Endpoints Section
                endpointsSection
                    .padding()
            }
        }
        .navigationTitle(server.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 12) {
                    // Start/Stop Button
                    Button {
                        Task { await toggleServer() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                            Text(isRunning ? "Stop" : "Start")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? .red : .green)
                    
                    // Export Button
                    Button {
                        showingExportPicker = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export Server Configuration")
                }
            }
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: MockServerDocument(server: server),
            contentType: .json,
            defaultFilename: "\(server.name.replacingOccurrences(of: " ", with: "-")).json"
        ) { result in
            // Handle export result
        }
        .alert("Add Endpoint", isPresented: $showingAddEndpoint) {
            TextField("Path", text: $newEndpointPath)
            
            Picker("Method", selection: $newEndpointMethod) {
                ForEach(HTTPMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            
            Button("Cancel", role: .cancel) {
                newEndpointPath = "/"
                newEndpointMethod = .get
            }
            Button("Add") {
                if let viewModel = viewModel {
                    _ = viewModel.addEndpoint(to: server, path: newEndpointPath, method: newEndpointMethod)
                    newEndpointPath = "/"
                    newEndpointMethod = .get
                }
            }
        }
        .onAppear {
            updateStatus()
        }
        .onChange(of: viewModel?.runningServers) {
            updateStatus()
        }
    }
    
    // MARK: - Server Header
    
    private var serverHeader: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: status.systemImage)
                    .font(.title)
                    .foregroundStyle(status.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if isEditingName {
                    TextField("Server Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .onSubmit {
                            saveName()
                        }
                        .onExitCommand {
                            cancelNameEdit()
                        }
                } else {
                    Text(server.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .onTapGesture(count: 2) {
                            startNameEdit()
                        }
                }
                
                HStack(spacing: 8) {
                    Label(serverURL, systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contextMenu {
                            Button("Copy URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(serverURL, forType: .string)
                            }
                        }
                }
                
                if status == .running {
                    Label("Running on port \(server.port)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let error = server.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Server Configuration
    
    private var serverConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Port:")
                        .gridColumnAlignment(.trailing)
                    
                    HStack {
                        TextField("", value: $server.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        
                        if !(viewModel?.validatePort(server.port, for: server) ?? true) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("Port may be in use")
                        }
                        
                        Button("Suggest") {
                            server.port = viewModel?.suggestedPort() ?? 3000
                        }
                        .buttonStyle(.link)
                    }
                }
                
                GridRow {
                    Text("Base URL Path:")
                    
                    TextField("", text: $server.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                
                GridRow {
                    Text("Description:")
                    
                    TextField("", text: Binding(get: { server.serverDescription ?? "" }, set: { server.serverDescription = $0.isEmpty ? nil : $0 }), prompt: Text("Optional description"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: server.serverDescription) {
                            server.updatedAt = Date()
                        }
                }
                
                GridRow {
                    Text("CORS Enabled:")
                    
                    Toggle("", isOn: $server.corsEnabled)
                        .onChange(of: server.corsEnabled) {
                            server.updatedAt = Date()
                            Task {
                                await viewModel?.updateServerCORS(server)
                            }
                        }
                }
                
                GridRow {
                    Text("Auto-start:")
                    
                    Toggle("", isOn: $server.autoStart)
                        .help("Automatically start this server when PostKit launches")
                        .onChange(of: server.autoStart) {
                            server.updatedAt = Date()
                        }
                }
                
                GridRow {
                    Text("Enabled:")
                    
                    Toggle("", isOn: $server.isEnabled)
                        .onChange(of: server.isEnabled) {
                            server.updatedAt = Date()
                        }
                }
            }
        }
    }
    
    // MARK: - Endpoints Section
    
    private var endpointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Endpoints")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingAddEndpoint = true
                } label: {
                    Label("Add Endpoint", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            
            if endpoints.isEmpty {
                ContentUnavailableView {
                    Label("No Endpoints", systemImage: "arrowshape.turn.up.right")
                } description: {
                    Text("Add endpoints to define how the mock server responds to requests")
                } actions: {
                    Button("Add Endpoint") {
                        showingAddEndpoint = true
                    }
                }
            } else {
                Table(endpoints) {
                    TableColumn("Method") { endpoint in
                        Text(endpoint.method.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundStyle(endpoint.method.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(endpoint.method.color.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .width(min: 80, max: 100)
                    
                    TableColumn("Path") { endpoint in
                        Text(endpoint.path)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    TableColumn("Name") { endpoint in
                        Text(endpoint.name)
                            .lineLimit(1)
                    }
                    
                    TableColumn("Responses") { endpoint in
                        Text("\(endpoint.responses.count)")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, max: 80)
                    
                    TableColumn("Enabled") { endpoint in
                        Toggle("", isOn: Binding(
                            get: { endpoint.isEnabled },
                            set: { 
                                endpoint.isEnabled = $0
                                endpoint.updatedAt = Date()
                                Task { await viewModel?.updateServerEndpoints(server) }
                            }
                        ))
                        .labelsHidden()
                    }
                    .width(min: 50, max: 60)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 200)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var serverURL: String {
        "http://localhost:\(server.port)\(server.baseURL)"
    }
    
    private func updateStatus() {
        status = viewModel?.serverStatus(server) ?? .stopped
        isRunning = viewModel?.isServerRunning(server) ?? false
    }
    
    private func toggleServer() async {
        await viewModel?.toggleServer(server)
        updateStatus()
    }
    
    private func startNameEdit() {
        editedName = server.name
        isEditingName = true
    }
    
    private func saveName() {
        if !editedName.isEmpty {
            server.name = editedName
            server.updatedAt = Date()
        }
        isEditingName = false
    }
    
    private func cancelNameEdit() {
        isEditingName = false
        editedName = ""
    }
}

// MARK: - Mock Server Document

import UniformTypeIdentifiers

struct MockServerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let server: MockServer
    
    init(server: MockServer) {
        self.server = server
    }
    
    init(configuration: ReadConfiguration) throws {
        fatalError("Reading not supported")
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try server.exportConfiguration()
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MockServer.self, configurations: config)
    
    let server = MockServer(name: "Test Server", port: 3000)
    container.mainContext.insert(server)
    
    return MockServerEditorView(server: server, viewModel: MockServerViewModel(modelContext: container.mainContext))
        .modelContainer(container)
}
