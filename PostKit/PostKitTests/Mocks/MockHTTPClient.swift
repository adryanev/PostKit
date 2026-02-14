import Foundation
@testable import PostKit

actor MockHTTPClient: HTTPClientProtocol {
    var responseToReturn: HTTPResponse?
    var errorToThrow: Error?
    var executeCallCount = 0
    var lastRequest: URLRequest?
    var lastTaskID: UUID?
    var delay: TimeInterval = 0

    init(response: HTTPResponse? = nil, error: Error? = nil, delay: TimeInterval = 0) {
        self.responseToReturn = response
        self.errorToThrow = error
        self.delay = delay
    }

    func execute(_ request: URLRequest, taskID: UUID) async throws -> HTTPResponse {
        executeCallCount += 1
        lastRequest = request
        lastTaskID = taskID
        
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        
        if let error = errorToThrow {
            throw error
        }
        
        return responseToReturn ?? HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: [:],
            body: Data(),
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
    }

    var cancelledTaskIDs: [UUID] = []
    
    func cancel(taskID: UUID) async {
        cancelledTaskIDs.append(taskID)
    }
    
    func reset() {
        executeCallCount = 0
        lastRequest = nil
        lastTaskID = nil
        cancelledTaskIDs.removeAll()
        responseToReturn = nil
        errorToThrow = nil
        delay = 0
    }
}
