import Foundation

actor URLSessionHTTPClient: HTTPClientProtocol {
    private let session: URLSession
    private var activeTasks: [UUID: URLSessionTask] = [:]
    
    private let maxMemorySize: Int64 = 1_000_000 // 1MB

    init(configuration: URLSessionConfiguration = .default) {
        let config = configuration
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func execute(_ request: URLRequest) async throws -> HTTPResponse {
        let taskID = UUID()
        let start = CFAbsoluteTimeGetCurrent()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    Task { await self.removeTask(taskID) }

                    if let error = error {
                        if (error as NSError).code == NSURLErrorCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: HTTPClientError.networkError(error))
                        }
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse,
                          let data = data else {
                        continuation.resume(throwing: HTTPClientError.invalidResponse)
                        return
                    }

                    let duration = CFAbsoluteTimeGetCurrent() - start
                    let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            result[key] = value
                        }
                    }
                    
                    let size = Int64(data.count)
                    
                    if size > self.maxMemorySize {
                        // Stream to disk
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                        
                        do {
                            try data.write(to: tempURL)
                            continuation.resume(returning: HTTPResponse(
                                statusCode: httpResponse.statusCode,
                                statusMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                                headers: headers,
                                body: nil,
                                bodyFileURL: tempURL,
                                duration: duration,
                                size: size
                            ))
                        } catch {
                            continuation.resume(throwing: HTTPClientError.networkError(error))
                        }
                    } else {
                        continuation.resume(returning: HTTPResponse(
                            statusCode: httpResponse.statusCode,
                            statusMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                            headers: headers,
                            body: data,
                            bodyFileURL: nil,
                            duration: duration,
                            size: size
                        ))
                    }
                }

                Task { await self.storeTask(task, id: taskID) }
                task.resume()
            }
        } onCancel: {
            Task { await self.cancel(taskID: taskID) }
        }
    }

    func cancel(taskID: UUID) {
        activeTasks[taskID]?.cancel()
        activeTasks.removeValue(forKey: taskID)
    }

    private func storeTask(_ task: URLSessionTask, id: UUID) {
        activeTasks[id] = task
    }

    private func removeTask(_ id: UUID) {
        activeTasks.removeValue(forKey: id)
    }
}

enum HTTPClientError: LocalizedError {
    case invalidResponse
    case invalidURL
    case networkError(Error)
    case responseTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response received"
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return error.localizedDescription
        case .responseTooLarge(let size): return "Response too large: \(size) bytes"
        }
    }
}
