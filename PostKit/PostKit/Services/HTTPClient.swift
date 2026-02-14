import Foundation

actor URLSessionHTTPClient: HTTPClientProtocol {
    private let session: URLSession
    private var activeTasks: [UUID: URLSessionTask] = [:]

    private let maxMemorySize: Int64 = httpClientMaxMemorySize

    init(configuration: URLSessionConfiguration = .default) {
        let config = configuration
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func execute(_ request: URLRequest, taskID: UUID) async throws -> HTTPResponse {
        let start = CFAbsoluteTimeGetCurrent()

        // Use download(for:) which streams the response to a temporary file on disk,
        // avoiding loading the entire response body into memory at once.
        let (tempDownloadURL, response): (URL, URLResponse) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request) { url, response, error in
                    Task { await self.removeTask(taskID) }

                    if let error = error {
                        if (error as NSError).code == NSURLErrorCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else if (error as NSError).code == NSURLErrorTimedOut {
                            continuation.resume(throwing: HTTPClientError.timeout)
                        } else {
                            continuation.resume(throwing: HTTPClientError.networkError(error))
                        }
                        return
                    }

                    guard let url = url, let response = response else {
                        continuation.resume(throwing: HTTPClientError.invalidResponse)
                        return
                    }

                    // Move the file to a stable location before the callback returns,
                    // because the system deletes the temporary download file immediately after.
                    let stableURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("postkit-response-\(UUID().uuidString).tmp")
                    do {
                        try FileManager.default.moveItem(at: url, to: stableURL)
                        continuation.resume(returning: (stableURL, response))
                    } catch {
                        continuation.resume(throwing: HTTPClientError.networkError(error))
                    }
                }

                Task { await self.storeTask(task, id: taskID) }
                task.resume()
            }
        } onCancel: {
            Task { await self.cancel(taskID: taskID) }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: tempDownloadURL)
            throw HTTPClientError.invalidResponse
        }

        let duration = CFAbsoluteTimeGetCurrent() - start
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: tempDownloadURL.path)
        let size = (fileAttributes[.size] as? Int64) ?? 0

        if size > maxMemorySize {
            return HTTPResponse(
                statusCode: httpResponse.statusCode,
                statusMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                headers: headers,
                body: nil,
                bodyFileURL: tempDownloadURL,
                duration: duration,
                size: size,
                timingBreakdown: nil
            )
        } else {
            let data = try Data(contentsOf: tempDownloadURL)
            try? FileManager.default.removeItem(at: tempDownloadURL)
            return HTTPResponse(
                statusCode: httpResponse.statusCode,
                statusMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                headers: headers,
                body: data,
                bodyFileURL: nil,
                duration: duration,
                size: size,
                timingBreakdown: nil
            )
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
    case timeout
    case engineInitializationFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response received"
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return error.localizedDescription
        case .responseTooLarge(let size): return "Response too large: \(size) bytes"
        case .timeout: return "Request timed out"
        case .engineInitializationFailed: return "HTTP client engine failed to initialize"
        }
    }
}
