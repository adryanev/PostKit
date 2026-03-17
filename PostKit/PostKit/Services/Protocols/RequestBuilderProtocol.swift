import Foundation
import SwiftData

protocol RequestBuilderProtocol: Sendable {
    func buildURLRequest(
        for request: HTTPRequest,
        with variables: [String: String],
        urlOverride: String?,
        bodyOverride: String??
    ) throws -> URLRequest
    
    func applyAuth(_ urlRequest: inout URLRequest, authConfig: AuthConfig, variables: [String: String])
    
    func getActiveEnvironmentVariables(from modelContext: ModelContext) -> [String: String]
}
