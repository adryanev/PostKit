import Foundation
import SwiftData
import os
import Combine

/// Manages multiple mock HTTP servers
@MainActor
final class MockServerManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var runningServers: [UUID: ServerState] = [:]
    @Published private(set) var isInitialized = false
    
    // MARK: - Types
    
    struct ServerState: Sendable {
        let port: Int
        var status: MockServerStatus
        var errorMessage: String?
        var requestCount: Int
        var lastRequestTime: Date?
    }
    
    // MARK: - Private Properties
    
    private var servers: [UUID: MockHTTPServer] = [:]
    private let logger = OSLog(subsystem: "dev.adryanev.PostKit", category: "MockServerManager")
    private var modelContext: ModelContext?
    
    // MARK: - Singleton
    
    static let shared = MockServerManager()
    
    private init() {}
    
    // MARK: - Configuration
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        self.isInitialized = true
    }
    
    // MARK: - Server Lifecycle
    
    /// Starts a mock server
    func startServer(_ mockServer: MockServer) async throws {
        guard !runningServers.keys.contains(mockServer.id) else {
            throw MockServerError.invalidConfiguration
        }
        
        // Check if port is already in use
        if isPortInUse(mockServer.port) {
            throw MockServerError.portInUse(mockServer.port)
        }
        
        // Update state to starting
        runningServers[mockServer.id] = ServerState(
            port: mockServer.port,
            status: .starting,
            errorMessage: nil,
            requestCount: 0,
            lastRequestTime: nil
        )
        
        // Create and configure server
        let server = MockHTTPServer(
            port: mockServer.port,
            endpoints: mockServer.endpoints,
            corsEnabled: mockServer.corsEnabled
        )
        
        do {
            try await server.start()
            servers[mockServer.id] = server
            
            // Update state to running
            runningServers[mockServer.id] = ServerState(
                port: mockServer.port,
                status: .running,
                errorMessage: nil,
                requestCount: 0,
                lastRequestTime: nil
            )
            
            os_log(.info, log: logger, "Started mock server '%{public}@' on port %d", mockServer.name, mockServer.port)
        } catch {
            // Update state to error
            runningServers[mockServer.id] = ServerState(
                port: mockServer.port,
                status: .error,
                errorMessage: error.localizedDescription,
                requestCount: 0,
                lastRequestTime: nil
            )
            
            throw error
        }
    }
    
    /// Stops a mock server
    func stopServer(_ mockServer: MockServer) async {
        guard let server = servers[mockServer.id] else { return }
        
        // Update state to stopping
        if var state = runningServers[mockServer.id] {
            state.status = .stopping
            runningServers[mockServer.id] = state
        }
        
        await server.stop()
        servers.removeValue(forKey: mockServer.id)
        runningServers.removeValue(forKey: mockServer.id)
        
        os_log(.info, log: logger, "Stopped mock server '%{public}@'", mockServer.name)
    }
    
    /// Stops all running servers
    func stopAllServers() async {
        for (serverId, server) in servers {
            await server.stop()
            runningServers.removeValue(forKey: serverId)
        }
        servers.removeAll()
        
        os_log(.info, log: logger, "Stopped all mock servers")
    }
    
    /// Restarts a mock server
    func restartServer(_ mockServer: MockServer) async throws {
        await stopServer(mockServer)
        try await startServer(mockServer)
    }
    
    // MARK: - Server Updates
    
    /// Updates the endpoints for a running server
    func updateEndpoints(for mockServer: MockServer) async {
        guard let server = servers[mockServer.id] else { return }
        
        await server.updateEndpoints(mockServer.endpoints)
        
        os_log(.info, log: logger, "Updated endpoints for mock server '%{public}@'", mockServer.name)
    }
    
    /// Updates the CORS setting for a running server
    func updateCORS(for mockServer: MockServer) async {
        guard let server = servers[mockServer.id] else { return }
        
        await server.setCORSEnabled(mockServer.corsEnabled)
        
        os_log(.info, log: logger, "Updated CORS setting for mock server '%{public}@'", mockServer.name)
    }
    
    // MARK: - Status
    
    /// Checks if a server is running
    func isServerRunning(_ mockServer: MockServer) -> Bool {
        runningServers[mockServer.id]?.status == .running
    }
    
    /// Gets the state of a server
    func serverState(for mockServer: MockServer) -> ServerState? {
        runningServers[mockServer.id]
    }
    
    /// Gets the server URL
    func serverURL(for mockServer: MockServer) -> String {
        "http://localhost:\(mockServer.port)"
    }
    
    /// Checks if a port is in use by another server
    func isPortInUse(_ port: Int) -> Bool {
        runningServers.values.contains { $0.port == port && $0.status == .running }
    }
    
    /// Finds an available port starting from the given port
    func findAvailablePort(startingFrom startPort: Int = 3000) -> Int {
        var port = startPort
        while isPortInUse(port) {
            port += 1
        }
        return port
    }
    
    // MARK: - Auto-start
    
    /// Starts all servers marked for auto-start
    func startAutoStartServers() async {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<MockServer>(
            predicate: #Predicate { $0.autoStart && $0.isEnabled }
        )
        
        do {
            let autoStartServers = try modelContext.fetch(descriptor)
            
            for mockServer in autoStartServers {
                do {
                    try await startServer(mockServer)
                } catch {
                    os_log(.error, log: logger, "Failed to auto-start server '%{public}@': %{public}@", mockServer.name, error.localizedDescription)
                }
            }
        } catch {
            os_log(.error, log: logger, "Failed to fetch auto-start servers: %{public}@", error.localizedDescription)
        }
    }
    
    // MARK: - Import from OpenAPI
    
    /// Creates a mock server from an OpenAPI specification
    func createServerFromOpenAPI(
        spec: OpenAPISpec,
        name: String? = nil,
        port: Int? = nil
    ) -> MockServer {
        let serverName = name ?? spec.info.title
        let serverPort = port ?? findAvailablePort()
        
        let mockServer = MockServer.from(
            openAPISpec: spec,
            name: serverName,
            port: serverPort
        )
        
        return mockServer
    }
    
    // MARK: - Statistics
    
    /// Increments the request count for a server
    func recordRequest(for serverId: UUID) {
        guard var state = runningServers[serverId] else { return }
        state.requestCount += 1
        state.lastRequestTime = Date()
        runningServers[serverId] = state
    }
    
    /// Gets the total request count across all servers
    var totalRequestCount: Int {
        runningServers.values.reduce(0) { $0 + $1.requestCount }
    }
    
    /// Gets the count of running servers
    var runningServerCount: Int {
        runningServers.values.filter { $0.status == .running }.count
    }
}

// MARK: - MockServer Extension for Status

extension MockServer {
    /// Updates the transient status properties from the manager state
    func updateFromManagerState(_ state: MockServerManager.ServerState?) {
        guard let state = state else {
            self.status = .stopped
            self.errorMessage = nil
            return
        }
        
        self.status = state.status
        self.errorMessage = state.errorMessage
        self.requestCount = state.requestCount
        self.lastRequestTime = state.lastRequestTime
    }
}
