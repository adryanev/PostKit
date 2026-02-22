import Foundation
import os

private let log = OSLog(subsystem: "dev.adryanev.PostKit", category: "CurlHTTPClient")

private let maxMemorySize: Int64 = httpClientMaxMemorySize
// nonisolated(unsafe) needed to prevent MainActor isolation inference in Swift 6
nonisolated(unsafe) private let maxResponseSize: Int = 100 * 1024 * 1024

// Thread Safety Contract:
// - All mutable state is protected by OSAllocatedUnfairLock
// - The context is passed to libcurl callbacks which execute on performQueue
// - isCancelled is the cross-thread synchronization point: set from Swift concurrency
//   (onCancel handler), read from performQueue (progress callback).
// - didResume guards against double continuation resumption.
private final class CurlTransferContext: Sendable {
    let responseData: OSAllocatedUnfairLock<Data>
    let headerLines: OSAllocatedUnfairLock<[String]>
    let isCancelled: OSAllocatedUnfairLock<Bool>
    let didResume: OSAllocatedUnfairLock<Bool>
    let tempFileHandle: OSAllocatedUnfairLock<FileHandle?>
    let tempFileURL: OSAllocatedUnfairLock<URL?>
    let bytesReceived: OSAllocatedUnfairLock<Int64>

    nonisolated init() {
        responseData = OSAllocatedUnfairLock(initialState: Data(capacity: 65_536))
        headerLines = OSAllocatedUnfairLock(initialState: [])
        isCancelled = OSAllocatedUnfairLock(initialState: false)
        didResume = OSAllocatedUnfairLock(initialState: false)
        tempFileHandle = OSAllocatedUnfairLock(initialState: nil)
        tempFileURL = OSAllocatedUnfairLock(initialState: nil)
        bytesReceived = OSAllocatedUnfairLock(initialState: 0)
    }
}


nonisolated(unsafe) let curlWriteCallback: @convention(c) (UnsafeMutablePointer<Int8>?, Int, Int, UnsafeMutableRawPointer?) -> Int = { ptr, size, nmemb, userdata in
    guard let ptr = ptr, let userdata = userdata else { return 0 }
    guard size > 0, nmemb > 0, size <= Int.max / nmemb else { return 0 }

    let byteCount = size * nmemb
    let context = Unmanaged<CurlTransferContext>.fromOpaque(userdata).takeUnretainedValue()

    if context.isCancelled.withLock({ $0 }) {
        return 0
    }

    let currentBytes = context.bytesReceived.withLock { $0 }
    let newBytesReceived = currentBytes + Int64(byteCount)

    if newBytesReceived > maxMemorySize {
        let needsSpill = context.tempFileHandle.withLock { $0 == nil }
        if needsSpill {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("postkit-response-\(UUID().uuidString).tmp")

            do {
                let existingData = context.responseData.withLock { $0 }
                FileManager.default.createFile(atPath: tempURL.path, contents: existingData, attributes: [.posixPermissions: 0o600])
                let handle = try FileHandle(forWritingTo: tempURL)
                handle.seekToEndOfFile()
                context.tempFileHandle.withLock { $0 = handle }
                context.tempFileURL.withLock { $0 = tempURL }
                context.responseData.withLock { $0 = Data() }
            } catch {
                return 0
            }
        }
    }

    let fileHandle = context.tempFileHandle.withLock { $0 }
    if let fileHandle = fileHandle {
        let bytes = Data(bytes: ptr, count: byteCount)
        fileHandle.write(bytes)
    } else {
        let bytes = Data(bytes: ptr, count: byteCount)
        context.responseData.withLock { $0.append(bytes) }
    }

    context.bytesReceived.withLock { $0 = newBytesReceived }

    return byteCount
}

nonisolated(unsafe) let curlHeaderCallback: @convention(c) (UnsafeMutablePointer<Int8>?, Int, Int, UnsafeMutableRawPointer?) -> Int = { ptr, size, nmemb, userdata in
    guard let ptr = ptr, let userdata = userdata else { return 0 }
    guard size > 0, nmemb > 0, size <= Int.max / nmemb else { return 0 }

    let byteCount = size * nmemb
    let context = Unmanaged<CurlTransferContext>.fromOpaque(userdata).takeUnretainedValue()

    let line = ptr.withMemoryRebound(to: UInt8.self, capacity: byteCount) { uintPtr in
        String(bytes: UnsafeBufferPointer(start: uintPtr, count: byteCount), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    if !line.isEmpty {
        context.headerLines.withLock { $0.append(line) }
    }

    return byteCount
}

nonisolated(unsafe) let curlProgressCallback: @convention(c) (UnsafeMutableRawPointer?, Int, Int, Int, Int) -> Int32 = { userdata, _, _, _, _ in
    guard let userdata = userdata else { return 0 }

    let context = Unmanaged<CurlTransferContext>.fromOpaque(userdata).takeUnretainedValue()

    if context.isCancelled.withLock({ $0 }) {
        return 1
    }

    return 0
}

actor CurlHTTPClient: HTTPClientProtocol {
    private let performQueue = DispatchQueue(label: "com.postkit.curl-perform", qos: .userInitiated, attributes: .concurrent)
    private var activeContexts: [UUID: CurlTransferContext] = [:]

    private static let globalInitResult: CURLcode = curl_global_init(Int(CURL_GLOBAL_ALL))

    init() throws {
        _ = Self.globalInitResult
        guard Self.globalInitResult == CURLE_OK else {
            throw HTTPClientError.engineInitializationFailed
        }
    }

    func execute(_ request: URLRequest, taskID: UUID) async throws -> HTTPResponse {
        guard let url = request.url else {
            throw HTTPClientError.invalidURL
        }

        let sanitizedURL = Self.sanitizeForCurl(url.absoluteString)

        let context = CurlTransferContext()
        activeContexts[taskID] = context
        defer { activeContexts.removeValue(forKey: taskID) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                performQueue.async {
                    let handle = curl_easy_init()
                    guard let handle = handle else {
                        context.didResume.withLock { didResume in
                            guard !didResume else { return }
                            didResume = true
                            continuation.resume(throwing: HTTPClientError.networkError(NSError(domain: "CurlHTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create curl handle"])))
                        }
                        return
                    }
                    defer { curl_easy_cleanup(handle) }

                    var headerList: UnsafeMutablePointer<curl_slist>?
                    defer { curl_slist_free_all(headerList) }

                    let contextPtr = Unmanaged.passRetained(context).toOpaque()
                    defer { Unmanaged<CurlTransferContext>.fromOpaque(contextPtr).release() }

                    do {
                        try self.setupHandle(handle, request: request, sanitizedURL: sanitizedURL, context: context, contextPtr: contextPtr, headerList: &headerList)
                    } catch {
                        context.didResume.withLock { didResume in
                            guard !didResume else { return }
                            didResume = true
                            continuation.resume(throwing: error)
                        }
                        return
                    }

                    let code = curl_easy_perform(handle)

                    context.didResume.withLock { didResume in
                        guard !didResume else { return }
                        didResume = true

                        if context.isCancelled.withLock({ $0 }) {
                            context.tempFileHandle.withLock { $0?.closeFile() }
                            if let tempURL = context.tempFileURL.withLock({ $0 }) {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        if code == CURLE_ABORTED_BY_CALLBACK {
                            context.tempFileHandle.withLock { $0?.closeFile() }
                            if let tempURL = context.tempFileURL.withLock({ $0 }) {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        if code != CURLE_OK {
                            context.tempFileHandle.withLock { $0?.closeFile() }
                            if let tempURL = context.tempFileURL.withLock({ $0 }) {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            let error = self.mapCurlError(code)
                            continuation.resume(throwing: error)
                            return
                        }

                        do {
                            let response = try self.buildResponse(handle: handle, context: context, url: url)
                            continuation.resume(returning: response)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            Task {
                await self.cancel(taskID: taskID)
            }
        }
    }

    func cancel(taskID: UUID) async {
        if let context = activeContexts[taskID] {
            context.isCancelled.withLock { $0 = true }
        }
        activeContexts.removeValue(forKey: taskID)
    }

    private nonisolated func setupHandle(
        _ handle: UnsafeMutableRawPointer,
        request: URLRequest,
        sanitizedURL: String,
        context: CurlTransferContext,
        contextPtr: UnsafeMutableRawPointer,
        headerList: inout UnsafeMutablePointer<curl_slist>?
    ) throws {
        let caCertPath = Bundle.main.path(forResource: "cacert", ofType: "pem")

        curl_easy_setopt_string(handle, CURLOPT_URL, sanitizedURL)
        curl_easy_setopt_long(handle, CURLOPT_NOSIGNAL, 1)

        if let caCertPath = caCertPath {
            curl_easy_setopt_string(handle, CURLOPT_CAINFO, caCertPath)
        }

        curl_easy_setopt_string(handle, CURLOPT_PROTOCOLS_STR, "http,https")
        curl_easy_setopt_string(handle, CURLOPT_REDIR_PROTOCOLS_STR, "http,https")
        curl_easy_setopt_long(handle, CURLOPT_SSL_VERIFYPEER, 1)
        curl_easy_setopt_long(handle, CURLOPT_SSL_VERIFYHOST, 2)
        curl_easy_setopt_long(handle, CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2)

        curl_easy_setopt_long(handle, CURLOPT_FOLLOWLOCATION, 1)
        curl_easy_setopt_long(handle, CURLOPT_MAXREDIRS, 10)

        curl_easy_setopt_long(handle, CURLOPT_TIMEOUT, 300)
        curl_easy_setopt_long(handle, CURLOPT_CONNECTTIMEOUT, 10)
        curl_easy_setopt_long(handle, CURLOPT_LOW_SPEED_LIMIT, 1)
        let lowSpeedTime = Int(request.timeoutInterval > 0 ? request.timeoutInterval : 30)
        curl_easy_setopt_long(handle, CURLOPT_LOW_SPEED_TIME, lowSpeedTime)

        curl_easy_setopt_int64(handle, CURLOPT_MAXFILESIZE_LARGE, maxResponseSize)
        curl_easy_setopt_long(handle, CURLOPT_BUFFERSIZE, 256 * 1024)
        curl_easy_setopt_long(handle, CURLOPT_MAXCONNECTS, 20)

        curl_easy_setopt_string(handle, CURLOPT_ACCEPT_ENCODING, "")

        let method = request.httpMethod?.uppercased() ?? "GET"
        if method != "GET" {
            curl_easy_setopt_string(handle, CURLOPT_CUSTOMREQUEST, method)
        }

        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers {
                let sanitizedKey = Self.sanitizeForCurl(key)
                let sanitizedValue = Self.sanitizeForCurl(value)
                let headerString = "\(sanitizedKey): \(sanitizedValue)"
                headerString.withCString { cString in
                    headerList = curl_slist_append(headerList, cString)
                }
            }
        }
        if headerList != nil {
            curl_easy_setopt_pointer(handle, CURLOPT_HTTPHEADER, headerList)
        }

        if let body = request.httpBody, !body.isEmpty {
            curl_easy_setopt_int64(handle, CURLOPT_POSTFIELDSIZE_LARGE, Int(body.count))
            body.withUnsafeBytes { ptr in
                if let baseAddress = ptr.baseAddress {
                    curl_easy_setopt_pointer(handle, CURLOPT_COPYPOSTFIELDS, UnsafeMutableRawPointer(mutating: baseAddress))
                }
            }
        }

        curl_easy_setopt_pointer(handle, CURLOPT_WRITEDATA, contextPtr)
        curl_easy_setopt_write_callback(handle, CURLOPT_WRITEFUNCTION, curlWriteCallback)

        curl_easy_setopt_pointer(handle, CURLOPT_HEADERDATA, contextPtr)
        curl_easy_setopt_header_callback(handle, CURLOPT_HEADERFUNCTION, curlHeaderCallback)

        curl_easy_setopt_long(handle, CURLOPT_NOPROGRESS, 0)
        curl_easy_setopt_pointer(handle, CURLOPT_XFERINFODATA, contextPtr)
        curl_easy_setopt_progress_callback(handle, CURLOPT_XFERINFOFUNCTION, curlProgressCallback)
    }

    private nonisolated func buildResponse(handle: UnsafeMutableRawPointer, context: CurlTransferContext, url: URL) throws -> HTTPResponse {
        var statusCodeLong: Int = 0
        curl_easy_getinfo_long(handle, CURLINFO_RESPONSE_CODE, &statusCodeLong)
        let statusCode = statusCodeLong

        let headerLinesCopy = context.headerLines.withLock { $0 }
        let statusMessage = Self.parseStatusMessage(from: headerLinesCopy, statusCode: statusCode)

        let headers = Self.parseHeaders(from: headerLinesCopy)

        var totalTime: Double = 0
        var nameLookupTime: Double = 0
        var connectTime: Double = 0
        var appConnectTime: Double = 0
        var startTransferTime: Double = 0
        var redirectTime: Double = 0

        curl_easy_getinfo_double(handle, CURLINFO_TOTAL_TIME, &totalTime)
        curl_easy_getinfo_double(handle, CURLINFO_NAMELOOKUP_TIME, &nameLookupTime)
        curl_easy_getinfo_double(handle, CURLINFO_CONNECT_TIME, &connectTime)
        curl_easy_getinfo_double(handle, CURLINFO_APPCONNECT_TIME, &appConnectTime)
        curl_easy_getinfo_double(handle, CURLINFO_STARTTRANSFER_TIME, &startTransferTime)
        curl_easy_getinfo_double(handle, CURLINFO_REDIRECT_TIME, &redirectTime)

        let timingBreakdown = TimingBreakdown(
            dnsLookup: max(0, nameLookupTime),
            tcpConnection: max(0, connectTime - nameLookupTime),
            tlsHandshake: max(0, appConnectTime - connectTime),
            transferStart: max(0, startTransferTime - appConnectTime),
            download: max(0, totalTime - startTransferTime),
            total: totalTime,
            redirectTime: redirectTime
        )

        let size = context.bytesReceived.withLock { $0 }
        let duration = totalTime

        var body: Data? = nil
        var bodyFileURL: URL? = nil

        let fileHandle = context.tempFileHandle.withLock { $0 }
        if let fileHandle = fileHandle {
            try fileHandle.close()
            bodyFileURL = context.tempFileURL.withLock { $0 }
        } else {
            body = context.responseData.withLock { $0 }
        }

        return HTTPResponse(
            statusCode: statusCode,
            statusMessage: statusMessage,
            headers: headers,
            body: body,
            bodyFileURL: bodyFileURL,
            duration: duration,
            size: size,
            timingBreakdown: timingBreakdown
        )
    }

    private nonisolated func mapCurlError(_ code: CURLcode) -> HTTPClientError {
        switch code {
        case CURLE_OPERATION_TIMEDOUT:
            return .timeout
        case CURLE_FILESIZE_EXCEEDED:
            return .responseTooLarge(Int64(maxResponseSize))
        case CURLE_URL_MALFORMAT:
            return .invalidURL
        default:
            let message = String(cString: curl_easy_strerror(code))
            return .networkError(NSError(domain: "CurlHTTPClient", code: Int(code.rawValue), userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}

// MARK: - Testable Helpers
// These helper functions are internal for testability

extension CurlHTTPClient {
    nonisolated static func sanitizeForCurl(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\0", with: "")
    }

    nonisolated static func parseStatusMessage(from headerLines: [String], statusCode: Int) -> String {
        guard let firstLine = headerLines.first else {
            return HTTPURLResponse.localizedString(forStatusCode: statusCode)
        }

        guard firstLine.hasPrefix("HTTP/") else {
            return HTTPURLResponse.localizedString(forStatusCode: statusCode)
        }

        let parts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 3 {
            return String(parts[2]).trimmingCharacters(in: .whitespaces)
        }

        return HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }

    nonisolated static func parseHeaders(from headerLines: [String]) -> [String: String] {
        var headers: [String: String] = [:]

        for line in headerLines {
            guard !line.hasPrefix("HTTP/") else { continue }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }

            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if headers[key] != nil {
                headers[key] = "\(headers[key]!), \(value)"
            } else {
                headers[key] = value
            }
        }

        return headers
    }
}
