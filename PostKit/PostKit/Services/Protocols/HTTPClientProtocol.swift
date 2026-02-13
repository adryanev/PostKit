import Foundation

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
    
    func getBodyData() throws -> Data {
        if let body = body {
            return body
        }
        if let url = bodyFileURL {
            return try Data(contentsOf: url)
        }
        return Data()
    }
}
