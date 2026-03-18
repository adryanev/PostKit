import Foundation
import Observation
import SwiftData
import FactoryKit

/// ViewModel for managing mock servers
@Observable
final class MockServerViewModel {
    
    // MARK: - UI State
    
    var selectedServer: MockServer?
    var selectedEndpoint: MockEndpoint?
    var selectedResponse: MockResponse?
    var isShowingImportSheet = false
    var isShowingExportSheet = false
    var exportURL: URL?
    var error: Error?
    var showingError = false
    
    // MARK: - Dependencies
    
    private let modelContext: ModelContext
    
    @ObservationIgnored @Injected(\.mockServerManager) private var mockServerManager
    @ObservationIgnored @Injected(\.openAPIParser) private var openAPIParser
    
    // MARK: - Init
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Server Management
    
    func createServer(name: String, port: Int? = nil) -> MockServer {
        let serverPort = port ?? mockServerManager.findAvailablePort()
        let server = MockServer(name: name, port: serverPort)
        modelContext.insert(server)
        
        // Add a default endpoint
        let defaultEndpoint = MockEndpoint(
            path: "/",
            method: .get,
            name: "Root Endpoint"
        )
        defaultEndpoint.server = server
        server.endpoints.append(defaultEndpoint)
        
        // Add a default response
        let defaultResponse = MockResponse.defaultJSONResponse()
        defaultResponse.endpoint = defaultEndpoint
        defaultEndpoint.responses.append(defaultResponse)
        
        return server
    }
    
    func deleteServer(_ server: MockServer) async {
        // Stop the server if running
        await mockServerManager.stopServer(server)
        
        modelContext.delete(server)
    }
    
    func duplicateServer(_ server: MockServer) -> MockServer {
        let copy = server.duplicated()
        modelContext.insert(copy)
        return copy
    }
    
    // MARK: - Server Control
    
    func startServer(_ server: MockServer) async {
        do {
            try await mockServerManager.startServer(server)
        } catch {
            self.error = error
            self.showingError = true
        }
    }
    
    func stopServer(_ server: MockServer) async {
        await mockServerManager.stopServer(server)
    }
    
    func toggleServer(_ server: MockServer) async {
        if mockServerManager.isServerRunning(server) {
            await stopServer(server)
        } else {
            await startServer(server)
        }
    }
    
    func restartServer(_ server: MockServer) async {
        do {
            try await mockServerManager.restartServer(server)
        } catch {
            self.error = error
            self.showingError = true
        }
    }
    
    // MARK: - Endpoint Management
    
    func addEndpoint(to server: MockServer, path: String = "/", method: HTTPMethod = .get) -> MockEndpoint {
        let endpoint = MockEndpoint(path: path, method: method)
        endpoint.server = server
        server.endpoints.append(endpoint)
        
        // Add a default response
        let defaultResponse = MockResponse.defaultJSONResponse()
        defaultResponse.endpoint = endpoint
        endpoint.responses.append(defaultResponse)
        
        return endpoint
    }
    
    func deleteEndpoint(_ endpoint: MockEndpoint) {
        if let server = endpoint.server {
            server.endpoints.removeAll { $0.id == endpoint.id }
        }
        modelContext.delete(endpoint)
        
        if selectedEndpoint?.id == endpoint.id {
            selectedEndpoint = nil
        }
    }
    
    func duplicateEndpoint(_ endpoint: MockEndpoint) -> MockEndpoint {
        let copy = endpoint.duplicated()
        if let server = endpoint.server {
            copy.server = server
            server.endpoints.append(copy)
        }
        return copy
    }
    
    // MARK: - Response Management
    
    func addResponse(to endpoint: MockEndpoint, name: String = "New Response") -> MockResponse {
        let response = MockResponse(name: name)
        response.endpoint = endpoint
        endpoint.responses.append(response)
        return response
    }
    
    func deleteResponse(_ response: MockResponse) {
        if let endpoint = response.endpoint {
            endpoint.responses.removeAll { $0.id == response.id }
        }
        modelContext.delete(response)
        
        if selectedResponse?.id == response.id {
            selectedResponse = nil
        }
    }
    
    func duplicateResponse(_ response: MockResponse) -> MockResponse {
        let copy = response.duplicated()
        if let endpoint = response.endpoint {
            copy.endpoint = endpoint
            endpoint.responses.append(copy)
        }
        return copy
    }
    
    func setDefaultResponse(_ response: MockResponse) {
        guard let endpoint = response.endpoint else { return }
        
        // Remove default from all other responses
        for otherResponse in endpoint.responses {
            otherResponse.isDefault = otherResponse.id == response.id
        }
    }
    
    // MARK: - Import/Export
    
    func importFromOpenAPI(url: URL) async throws -> MockServer {
        let data = try Data(contentsOf: url)
        let spec = try openAPIParser.parseSpec(data)
        
        let server = mockServerManager.createServerFromOpenAPI(spec: spec)
        modelContext.insert(server)
        
        return server
    }
    
    func importFromFile(url: URL) throws -> MockServer {
        let data = try Data(contentsOf: url)
        let server = try MockServer.importConfiguration(from: data)
        modelContext.insert(server)
        return server
    }
    
    func exportServer(_ server: MockServer, to url: URL) throws {
        let data = try server.exportConfiguration()
        try data.write(to: url)
    }
    
    // MARK: - Server Status
    
    func serverStatus(_ server: MockServer) -> MockServerStatus {
        mockServerManager.serverState(for: server)?.status ?? .stopped
    }
    
    func isServerRunning(_ server: MockServer) -> Bool {
        mockServerManager.isServerRunning(server)
    }
    
    func serverURL(_ server: MockServer) -> String {
        mockServerManager.serverURL(for: server)
    }
    
    var runningServerCount: Int {
        mockServerManager.runningServerCount
    }
    
    var runningServers: [UUID: MockServerManager.ServerState] {
        mockServerManager.runningServers
    }
    
    // MARK: - Updates
    
    func updateServerEndpoints(_ server: MockServer) async {
        await mockServerManager.updateEndpoints(for: server)
    }
    
    func updateServerCORS(_ server: MockServer) async {
        await mockServerManager.updateCORS(for: server)
    }
    
    // MARK: - Validation
    
    func validatePort(_ port: Int, for server: MockServer?) -> Bool {
        // Port must be in valid range (1024+ to avoid privileged ports)
        guard port >= 1024 && port <= 65535 else { return false }
        
        // Check if port is used by another server
        if let existingState = mockServerManager.runningServers.values.first(where: { $0.port == port }) {
            // Allow if it's the same server
            if let server = server,
               let state = mockServerManager.serverState(for: server),
               state.port == port {
                return true
            }
            return false
        }
        
        return true
    }
    
    func suggestedPort() -> Int {
        mockServerManager.findAvailablePort()
    }
    
    // MARK: - Quick Actions
    
    func createQuickServer(name: String = "Quick Mock") -> MockServer {
        let server = createServer(name: name)
        
        // Add common endpoints
        let usersEndpoint = addEndpoint(to: server, path: "/users", method: .get)
        usersEndpoint.name = "Get Users"
        
        let userEndpoint = addEndpoint(to: server, path: "/users/{id}", method: .get)
        userEndpoint.name = "Get User by ID"
        
        let createUserEndpoint = addEndpoint(to: server, path: "/users", method: .post)
        createUserEndpoint.name = "Create User"
        
        return server
    }
    
    func copyCurlCommand(for endpoint: MockEndpoint, server: MockServer) -> String {
        let url = "\(server.serverURL)\(endpoint.path)"
        return "curl -X \(endpoint.method.rawValue) '\(url)'"
    }
}

// MARK: - MockServerStatus Extension

extension MockServerStatus {
    var displayText: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .stopping: return "Stopping..."
        case .error: return "Error"
        }
    }
}
