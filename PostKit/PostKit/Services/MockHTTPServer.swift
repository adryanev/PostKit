import Foundation
import Network
import os

/// A lightweight HTTP server implementation using Network.framework
/// This avoids external dependencies while providing full HTTP mock server functionality
actor MockHTTPServer: MockHTTPServerProtocol {
    
    // MARK: - Properties
    
    private let logger = OSLog(subsystem: "dev.adryanev.PostKit", category: "MockHTTPServer")
    
    let port: Int
    private(set) var isRunning = false
    
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]
    private var endpoints: [MockEndpoint] = []
    private var corsEnabled = true
    
    private let requestHandler: (@Sendable (MockServerRequest) async -> MockServerResponse)?
    
    nonisolated var baseURL: String {
        "http://localhost:\(port)"
    }
    
    // MARK: - Initialization
    
    init(
        port: Int,
        endpoints: [MockEndpoint] = [],
        corsEnabled: Bool = true,
        requestHandler: (@Sendable (MockServerRequest) async -> MockServerResponse)? = nil
    ) {
        self.port = port
        self.endpoints = endpoints
        self.corsEnabled = corsEnabled
        self.requestHandler = requestHandler
    }
    
    // MARK: - Public Methods
    
    func start() async throws {
        guard !isRunning else { return }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw MockServerError.invalidConfiguration
        }
        
        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw MockServerError.portInUse(port)
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleListenerState(state)
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection)
            }
        }
        
        listener?.start(queue: .global())
        isRunning = true
        
        os_log(.info, log: logger, "Mock server started on port %d", port)
    }
    
    func stop() async {
        guard isRunning else { return }
        
        // Close all active connections
        for (_, connection) in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        
        // Stop the listener
        listener?.cancel()
        listener = nil
        isRunning = false
        
        os_log(.info, log: logger, "Mock server stopped on port %d", port)
    }
    
    func updateEndpoints(_ endpoints: [MockEndpoint]) {
        self.endpoints = endpoints
    }
    
    func setCORSEnabled(_ enabled: Bool) {
        self.corsEnabled = enabled
    }
    
    // MARK: - Private Methods
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            os_log(.info, log: logger, "Listener ready on port %d", port)
        case .failed(let error):
            os_log(.error, log: logger, "Listener failed: %{public}@", error.localizedDescription)
            isRunning = false
        case .waiting(let error):
            os_log(.warning, log: logger, "Listener waiting: %{public}@", error.localizedDescription)
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = UUID()
        activeConnections[connectionId] = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                switch state {
                case .ready:
                    await self?.receiveRequest(connection: connection, connectionId: connectionId)
                case .failed, .cancelled:
                    await self?.removeConnection(connectionId)
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .global())
    }
    
    private func removeConnection(_ connectionId: UUID) {
        activeConnections.removeValue(forKey: connectionId)
    }
    
    private func receiveRequest(connection: NWConnection, connectionId: UUID) async {
        // Read the HTTP request
        var requestData = Data()
        var headersComplete = false
        var contentLength = 0
        var bodyRead = 0
        
        while !headersComplete || bodyRead < contentLength {
            let chunk = await readFromConnection(connection, maxLength: 8192)
            guard !chunk.isEmpty else { break }
            
            requestData.append(chunk)
            
            // Check if headers are complete
            if let headerEnd = requestData.range(of: "\r\n\r\n".data(using: .utf8)!) {
                headersComplete = true
                
                // Parse content-length from headers
                let headerData = requestData[0..<headerEnd.lowerBound]
                if let headerString = String(data: headerData, encoding: .utf8),
                   let match = headerString.range(of: "Content-Length: (\\d+)", options: .regularExpression) {
                    let lengthString = String(headerString[match].dropFirst("Content-Length: ".count))
                    contentLength = Int(lengthString) ?? 0
                    bodyRead = requestData.count - headerEnd.upperBound
                } else {
                    bodyRead = 0
                }
            }
        }
        
        // Parse and handle the request
        guard let request = parseHTTPRequest(requestData) else {
            await sendResponse(connection: connection, response: MockServerResponse.internalServerError())
            connection.cancel()
            await removeConnection(connectionId)
            return
        }
        
        // Handle the request
        let response = await handleRequest(request)
        
        // Send response
        await sendResponse(connection: connection, response: response)
        
        // Close connection
        connection.cancel()
        await removeConnection(connectionId)
    }
    
    private func readFromConnection(_ connection: NWConnection, maxLength: Int) async -> Data {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, _, error in
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
    
    private func parseHTTPRequest(_ data: Data) -> MockServerRequest? {
        guard let requestString = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2,
              let method = HTTPMethod(rawValue: String(requestParts[0]).uppercased()) else {
            return nil
        }
        
        let fullPath = String(requestParts[1])
        
        // Parse path and query parameters
        var path = fullPath
        var queryParameters: [String: String] = [:]
        
        if let queryIndex = fullPath.firstIndex(of: "?") {
            path = String(fullPath[fullPath.startIndex..<queryIndex])
            let queryString = String(fullPath[fullPath.index(after: queryIndex)...])
            
            for pair in queryString.components(separatedBy: "&") {
                let keyValue = pair.components(separatedBy: "=")
                if keyValue.count == 2 {
                    queryParameters[keyValue[0]] = keyValue[1].removingPercentEncoding ?? keyValue[1]
                }
            }
        }
        
        // Parse headers
        var headers: [String: String] = [:]
        var bodyStartIndex = 0
        
        for (index, line) in lines.enumerated().dropFirst() {
            if line.isEmpty {
                bodyStartIndex = index + 1
                break
            }
            
            let headerParts = line.components(separatedBy: ": ")
            if headerParts.count >= 2 {
                headers[headerParts[0]] = headerParts.dropFirst().joined(separator: ": ")
            }
        }
        
        // Parse body
        var body: Data? = nil
        if bodyStartIndex > 0 && bodyStartIndex < lines.count {
            let bodyString = lines[bodyStartIndex...].joined(separator: "\r\n")
            if !bodyString.isEmpty {
                body = bodyString.data(using: .utf8)
            }
        }
        
        return MockServerRequest(
            method: method,
            path: path,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            pathParameters: [:]
        )
    }
    
    private func handleRequest(_ request: MockServerRequest) async -> MockServerResponse {
        // Use custom handler if provided
        if let handler = requestHandler {
            return await handler(request)
        }
        
        // Find matching endpoint
        var matchedEndpoint: MockEndpoint?
        var pathParameters: [String: String] = [:]
        
        for endpoint in endpoints where endpoint.isEnabled {
            if endpoint.matches(requestPath: request.path, requestMethod: request.method) {
                matchedEndpoint = endpoint
                pathParameters = endpoint.extractPathParameters(from: request.path)
                break
            }
        }
        
        guard let endpoint = matchedEndpoint else {
            os_log(.info, log: logger, "No endpoint found for %{public}@ %{public}@", request.method.rawValue, request.path)
            return MockServerResponse.notFound()
        }
        
        // Get the response from the endpoint
        guard let mockResponse = endpoint.defaultResponse else {
            return MockServerResponse.notFound()
        }
        
        // Build response
        var headers = mockResponse.headers.reduce(into: [String: String]()) { result, pair in
            if pair.isEnabled {
                result[pair.key] = pair.value
            }
        }
        
        // Add CORS headers if enabled
        if corsEnabled {
            headers["Access-Control-Allow-Origin"] = "*"
            headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD"
            headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-Requested-With"
        }
        
        // Add X-Mock-Server header
        headers["X-Mock-Server"] = "PostKit"
        
        let body = mockResponse.bodyContent?.data(using: .utf8)
        let delayMs = mockResponse.delayMs
        
        os_log(.info, log: logger, "Serving response for %{public}@ %{public}@ -> %d", request.method.rawValue, request.path, mockResponse.statusCode)
        
        return MockServerResponse(
            statusCode: mockResponse.statusCode,
            headers: headers,
            body: body,
            delayMs: delayMs
        )
    }
    
    private func sendResponse(connection: NWConnection, response: MockServerResponse) async {
        // Apply delay if specified
        if response.delayMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(response.delayMs) * 1_000_000)
        }
        
        var httpResponse = "HTTP/1.1 \(response.statusCode) \(statusMessage(for: response.statusCode))\r\n"
        
        for (key, value) in response.headers {
            httpResponse += "\(key): \(value)\r\n"
        }
        
        if let body = response.body {
            httpResponse += "Content-Length: \(body.count)\r\n"
        }
        
        httpResponse += "\r\n"
        
        var responseData = httpResponse.data(using: .utf8) ?? Data()
        
        if let body = response.body {
            responseData.append(body)
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(responseData, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
    
    private nonisolated func statusMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}
