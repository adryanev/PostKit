import SwiftUI
import SwiftData

/// Status view showing running mock servers in the menu bar or as a compact widget
struct MockServerStatusView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MockServer.name) private var servers: [MockServer]
    
    @State private var viewModel: MockServerViewModel?
    @State private var runningServers: [(server: MockServer, state: MockServerManager.ServerState)] = []
    @State private var refreshTimer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                Text("Mock Servers")
                    .font(.headline)
                Spacer()
                
                if !runningServers.isEmpty {
                    Text("\(runningServers.count) running")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            if servers.isEmpty {
                Text("No mock servers configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if runningServers.isEmpty {
                Text("No servers running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runningServers, id: \.server.id) { item in
                    MockServerStatusRow(server: item.server, state: item.state, viewModel: viewModel)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MockServerViewModel(modelContext: modelContext)
            }
            updateRunningServers()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }
    
    private func updateRunningServers() {
        guard let viewModel = viewModel else { return }
        
        runningServers = servers.compactMap { server in
            guard let state = viewModel.runningServers[server.id],
                  state.status == .running else { return nil }
            return (server, state)
        }
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                updateRunningServers()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Status Row

struct MockServerStatusRow: View {
    let server: MockServer
    let state: MockServerManager.ServerState
    let viewModel: MockServerViewModel?
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(state.status.color)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text("Port \(server.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Request count
            if state.requestCount > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(state.requestCount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("requests")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Quick actions
            Button {
                Task { await viewModel?.stopServer(server) }
            } label: {
                Image(systemName: "stop.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop server")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Compact Status Indicator

/// Compact status indicator for toolbar or menu bar
struct MockServerCompactStatus: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MockServer.name) private var servers: [MockServer]
    
    @State private var viewModel: MockServerViewModel?
    @State private var runningCount = 0
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: runningCount > 0 ? "server.rack" : "server.rack")
                .symbolVariant(runningCount > 0 ? .fill : .none)
                .foregroundStyle(runningCount > 0 ? .green : .secondary)
            
            if runningCount > 0 {
                Text("\(runningCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .help(runningCount > 0 ? "\(runningCount) mock server(s) running" : "No mock servers running")
        .onAppear {
            if viewModel == nil {
                viewModel = MockServerViewModel(modelContext: modelContext)
            }
            updateCount()
        }
        .onChange(of: viewModel?.runningServers) {
            updateCount()
        }
    }
    
    private func updateCount() {
        runningCount = viewModel?.runningServerCount ?? 0
    }
}

// MARK: - Menu Bar Status View

/// Detailed menu bar view for mock servers
struct MockServerMenuBarStatusView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MockServer.name) private var servers: [MockServer]
    
    @State private var viewModel: MockServerViewModel?
    
    var body: some View {
        Group {
            if servers.isEmpty {
                Text("No Mock Servers")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(servers) { server in
                    MockServerMenuBarRow(server: server, viewModel: viewModel)
                }
            }
            
            Divider()
            
            Button("Open Mock Servers") {
                // Post notification to open mock servers view
                NotificationCenter.default.post(name: .openMockServers, object: nil)
                NSApp.activate()
            }
            .keyboardShortcut("m")
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MockServerViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Menu Bar Row

struct MockServerMenuBarRow: View {
    let server: MockServer
    let viewModel: MockServerViewModel?
    
    @State private var status: MockServerStatus = .stopped
    @State private var isRunning = false
    
    var body: some View {
        Button {
            Task {
                await viewModel?.toggleServer(server)
                updateStatus()
            }
        } label: {
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(":\(server.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(status.displayText)
                            .font(.caption)
                            .foregroundStyle(status.color)
                    }
                }
                
                Spacer()
                
                if isRunning {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
            }
        }
        .onAppear {
            updateStatus()
        }
    }
    
    private func updateStatus() {
        status = viewModel?.serverStatus(server) ?? .stopped
        isRunning = viewModel?.isServerRunning(server) ?? false
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let openMockServers = Notification.Name("openMockServers")
}

// MARK: - Preview

#Preview("Status View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MockServer.self, configurations: config)
    
    let server1 = MockServer(name: "API Mock", port: 3000)
    let server2 = MockServer(name: "Auth Mock", port: 3001)
    
    container.mainContext.insert(server1)
    container.mainContext.insert(server2)
    
    return MockServerStatusView()
        .modelContainer(container)
        .frame(width: 250)
        .padding()
}

#Preview("Compact Status") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MockServer.self, configurations: config)
    
    return MockServerCompactStatus()
        .modelContainer(container)
        .padding()
}

#Preview("Menu Bar View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MockServer.self, configurations: config)
    
    let server1 = MockServer(name: "API Mock", port: 3000)
    container.mainContext.insert(server1)
    
    return MockServerMenuBarStatusView()
        .modelContainer(container)
        .frame(width: 250)
}
