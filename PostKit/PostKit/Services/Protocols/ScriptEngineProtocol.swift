import Foundation

protocol ScriptEngineProtocol: Sendable {
    func executePreRequest(
        script: String,
        request: ScriptRequest,
        environment: [String: String]
    ) async throws -> ScriptPreRequestResult
    
    func executePostRequest(
        script: String,
        response: ScriptResponse,
        environment: [String: String]
    ) async throws -> ScriptPostRequestResult
}

struct ScriptRequest: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: String?
}

struct ScriptResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: String?
    let duration: TimeInterval
}

struct ScriptPreRequestResult: Sendable {
    let modifiedHeaders: [String: String]?
    let modifiedURL: String?
    let modifiedBody: String?
    let environmentChanges: [String: String]
    let consoleOutput: [String]
}

struct ScriptPostRequestResult: Sendable {
    let environmentChanges: [String: String]
    let consoleOutput: [String]
}

enum ScriptEngineError: LocalizedError {
    case timeout
    case syntaxError(String)
    case runtimeError(String)
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Script execution timed out (5 second limit)"
        case .syntaxError(let message):
            return "Script syntax error: \(message)"
        case .runtimeError(let message):
            return "Script runtime error: \(message)"
        }
    }
}
