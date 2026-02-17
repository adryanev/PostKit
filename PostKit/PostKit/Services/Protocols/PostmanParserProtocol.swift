import Foundation

protocol PostmanParserProtocol: Sendable {
    func parse(_ data: Data) throws -> PostmanCollection
    func parseEnvironment(_ data: Data) throws -> PostmanEnvironment
}
