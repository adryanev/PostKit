import Foundation

/// Protocol defining the interface for a mock HTTP server
protocol MockHTTPServerProtocol: Sendable {
    /// The port the server is running on
    var port: Int { get }
    
    /// Whether the server is currently running
    var isRunning: Bool { get }
    
    /// Starts the server
    func start() async throws
    
    /// Stops the server
    func stop() async
    
    /// Updates the endpoints the server responds to
    func updateEndpoints(_ endpoints: [MockEndpoint])
    
    /// Sets the CORS enabled state
    func setCORSEnabled(_ enabled: Bool)
    
    /// Gets the base URL for the server
    var baseURL: String { get }
}

/// Errors that can occur when running a mock server
enum MockServerError: LocalizedError, Sendable {
    case portInUse(Int)
    case failedToStart(Error)
    case failedToStop(Error)
    case invalidConfiguration
    case endpointNotFound(String, String)
    
    var errorDescription: String? {
        switch self {
        case .portInUse(let port):
            return "Port \(port) is already in use"
        case .failedToStart(let error):
            return "Failed to start server: \(error.localizedDescription)"
        case .failedToStop(let error):
            return "Failed to stop server: \(error.localizedDescription)"
        case .invalidConfiguration:
            return "Invalid server configuration"
        case .endpointNotFound(let method, let path):
            return "No endpoint found for \(method) \(path)"
        }
    }
}

/// Represents an incoming request to the mock server
struct MockServerRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let headers: [String: String]
    let queryParameters: [String: String]
    let body: Data?
    let pathParameters: [String: String]
}

/// Represents a response from the mock server
struct MockServerResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data?
    let delayMs: Int
    
    init(statusCode: Int = 200, headers: [String: String] = [:], body: Data? = nil, delayMs: Int = 0) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.delayMs = delayMs
    }
    
    static func notFound() -> MockServerResponse {
        MockServerResponse(
            statusCode: 404,
            headers: ["Content-Type": "application/json"],
            body: #"{"error":"Not Found","message":"No mock endpoint matches this request"}"#.data(using: .utf8)
        )
    }
    
    static func internalServerError() -> MockServerResponse {
        MockServerResponse(
            statusCode: 500,
            headers: ["Content-Type": "application/json"],
            body: #"{"error":"Internal Server Error","message":"Mock server encountered an error"}"#.data(using: .utf8)
        )
    }
}
