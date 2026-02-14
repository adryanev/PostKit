import Foundation

protocol CurlParserProtocol: Sendable {
    func parse(_ curlCommand: String) throws -> ParsedRequest
}
