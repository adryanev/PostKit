import Foundation

protocol OpenAPIParserProtocol: Sendable {
    func parse(_ data: Data) throws -> (info: OpenAPIInfo, endpoints: [OpenAPIEndpoint], servers: [String])
}
