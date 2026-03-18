import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// List view displaying all mock servers
struct MockServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MockServer.createdAt, order: .reverse) private var servers: [MockServer]
    
    @State private var viewModel: MockServerViewModel?
    @State private var selectedServerId: UUID?
    @State private var isAddingServer = false
    @State private var newServerName = ""
    @State private var showingImportPicker = false
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedServerId) {
                if servers.isEmpty {
                    ContentUnavailableView {
                        Label("No Mock Servers", systemImage: "server.rack")
                    } description: {
                        Text("Create a mock server to simulate API responses")
                    } actions: {
                        Button("Create Server") {
                            isAddingServer = true
                        }
                    }
                } else {
                    ForEach(servers) { server in
                        MockServerRow(server: server, viewModel: viewModel)
                            .tag(server.id)
                            .contextMenu {
                                MockServerContextMenu(server: server, viewModel: viewModel)
                            }
                    }
                    .onDelete(perform: deleteServers)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Mock Servers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isAddingServer = true
                        } label: {
                            Label("New Server", systemImage: "plus")
                        }
                        
                        Button {
                            if let viewModel = viewModel {
                                let server = viewModel.createQuickServer()
                                selectedServerId = server.id
                            }
                        } label: {
                            Label("Quick Server", systemImage: "bolt")
                        }
                        
                        Divider()
                        
                        Button {
                            showingImportPicker = true
                        } label: {
                            Label("Import from File", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Mock Server", isPresented: $isAddingServer) {
                TextField("Name", text: $newServerName)
                Button("Cancel", role: .cancel) {
                    newServerName = ""
                }
                Button("Create") {
                    if let viewModel = viewModel, !newServerName.isEmpty {
                        let server = viewModel.createServer(name: newServerName)
                        selectedServerId = server.id
                        newServerName = ""
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json, .yaml],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        } detail: {
            if let serverId = selectedServerId,
               let server = servers.first(where: { $0.id == serverId }) {
                MockServerEditorView(server: server, viewModel: viewModel)
            } else {
                ContentUnavailableView(
                    "Select a Server",
                    systemImage: "server.rack",
                    description: Text("Choose a mock server from the list or create a new one")
                )
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MockServerViewModel(modelContext: modelContext)
            }
        }
    }
    
    private func deleteServers(at offsets: IndexSet) {
        guard let viewModel = viewModel else { return }
        
        for index in offsets {
            Task {
                await viewModel.deleteServer(servers[index])
            }
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        guard let viewModel = viewModel,
              case .success(let urls) = result,
              let url = urls.first else { return }
        
        Task {
            do {
                // Try OpenAPI first
                if url.pathExtension == "yaml" || url.pathExtension == "yml" {
                    _ = try await viewModel.importFromOpenAPI(url: url)
                } else {
                    // Try as PostKit export, then OpenAPI
                    do {
                        _ = try viewModel.importFromFile(url: url)
                    } catch {
                        _ = try await viewModel.importFromOpenAPI(url: url)
                    }
                }
            } catch {
                // Handle error
                print("Import failed: \(error)")
            }
        }
    }
}

// MARK: - Server Row

struct MockServerRow: View {
    let server: MockServer
    let viewModel: MockServerViewModel?
    
    @State private var status: MockServerStatus = .stopped
    
    var body: some View {
        Button {
            // Selection handled by parent
        } label: {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(status.color)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 4) {
                        Text("Port \(server.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if server.corsEnabled {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("CORS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !server.endpoints.isEmpty {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("\(server.endpoints.count) endpoints")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Running indicator
                if status == .running {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            updateStatus()
        }
        .onChange(of: viewModel?.runningServers) {
            updateStatus()
        }
    }
    
    private func updateStatus() {
        status = viewModel?.serverStatus(server) ?? .stopped
    }
}

// MARK: - Context Menu

struct MockServerContextMenu: View {
    let server: MockServer
    let viewModel: MockServerViewModel?
    
    var body: some View {
        Group {
            if viewModel?.isServerRunning(server) == true {
                Button {
                    Task { await viewModel?.stopServer(server) }
                } label: {
                    Label("Stop Server", systemImage: "stop.circle")
                }
            } else {
                Button {
                    Task { await viewModel?.startServer(server) }
                } label: {
                    Label("Start Server", systemImage: "play.circle")
                }
            }
            
            Button {
                Task { await viewModel?.restartServer(server) }
            } label: {
                Label("Restart Server", systemImage: "arrow.clockwise")
            }
            
            Divider()
            
            Button {
                Pasteboard.general.setString(viewModel?.serverURL(server) ?? "", forType: .string)
            } label: {
                Label("Copy Server URL", systemImage: "link")
            }
            
            Button {
                if let viewModel = viewModel {
                    _ = viewModel.duplicateServer(server)
                }
            } label: {
                Label("Duplicate Server", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                Task { await viewModel?.deleteServer(server) }
            } label: {
                Label("Delete Server", systemImage: "trash")
            }
        }
    }
}

// MARK: - Pasteboard Helper

private enum Pasteboard {
    static var general: NSPasteboard { .general }
}

#Preview {
    MockServerListView()
        .modelContainer(for: MockServer.self, inMemory: true)
}
