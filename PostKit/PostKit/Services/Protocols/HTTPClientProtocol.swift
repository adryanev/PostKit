import Foundation

/// Threshold (in bytes) above which response bodies are spilled to disk.
let httpClientMaxMemorySize: Int64 = 1_000_000 // 1MB

protocol HTTPClientProtocol: Sendable {
    func execute(_ request: URLRequest, taskID: UUID) async throws -> HTTPResponse
    func cancel(taskID: UUID) async
}

struct TimingBreakdown: Sendable, Codable {
    let dnsLookup: TimeInterval
    let tcpConnection: TimeInterval
    let tlsHandshake: TimeInterval
    let transferStart: TimeInterval
    let download: TimeInterval
    let total: TimeInterval
    let redirectTime: TimeInterval

    init(
        dnsLookup: TimeInterval,
        tcpConnection: TimeInterval,
        tlsHandshake: TimeInterval,
        transferStart: TimeInterval,
        download: TimeInterval,
        total: TimeInterval,
        redirectTime: TimeInterval
    ) {
        self.dnsLookup = max(0, dnsLookup)
        self.tcpConnection = max(0, tcpConnection)
        self.tlsHandshake = max(0, tlsHandshake)
        self.transferStart = max(0, transferStart)
        self.download = max(0, download)
        self.total = max(0, total)
        self.redirectTime = max(0, redirectTime)
    }
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let statusMessage: String
    let headers: [String: String]
    let body: Data?
    let bodyFileURL: URL?
    let duration: TimeInterval
    let size: Int64
    let timingBreakdown: TimingBreakdown?
    
    var isLarge: Bool {
        bodyFileURL != nil
    }
    
    var contentType: String? {
        let value = headers.first(where: { $0.key.lowercased() == "content-type" })?.value
        return value?.components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased()
    }
    
    func getBodyData() throws -> Data {
        if let body = body {
            return body
        }
        if let url = bodyFileURL {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
        return Data()
    }
}
