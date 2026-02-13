import Foundation

protocol HTTPClientProtocol: Sendable {
    func execute(_ request: URLRequest) async throws -> HTTPResponse
    func cancel(taskID: UUID)
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let statusMessage: String
    let headers: [String: String]
    let body: Data
    let duration: TimeInterval
    let size: Int64
}
