import Foundation

protocol HTTPClientProtocol: Sendable {
    func execute(_ request: URLRequest) async throws -> HTTPResponse
    func cancel(taskID: UUID)
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let statusMessage: String
    let headers: [String: String]
    let body: Data?
    let bodyFileURL: URL?
    let duration: TimeInterval
    let size: Int64
    
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
