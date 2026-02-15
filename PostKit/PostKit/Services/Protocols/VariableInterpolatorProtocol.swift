import Foundation

protocol VariableInterpolatorProtocol: Sendable {
    func interpolate(_ template: String, with variables: [String: String]) throws -> String
}
