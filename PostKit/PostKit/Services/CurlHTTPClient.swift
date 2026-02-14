import Foundation
import os

private let log = OSLog(subsystem: "dev.adryanev.PostKit", category: "CurlHTTPClient")

private let maxMemorySize: Int64 = httpClientMaxMemorySize
private let maxResponseSize: Int = 100 * 1024 * 1024

// Thread Safety Contract:
// - responseData, headerLines, tempFileHandle, tempFileURL, bytesReceived are ONLY
//   mutated from libcurl callbacks, which execute sequentially on performQueue for
//   a single easy handle (curl_easy_perform is blocking and single-threaded).
// - isCancelled is the cross-thread synchronization point: set from Swift concurrency
//   (onCancel handler), read from performQueue (progress callback).
// - didResume guards against double continuation resumption.
// - After curl_easy_perform returns on performQueue, reading context fields in
//   buildResponse is safe because the write→read happens on the same thread.
private final class CurlTransferContext: @unchecked Sendable {
    var responseData: Data
    var headerLines: [String]
    let isCancelled: OSAllocatedUnfairLock<Bool>
    let didResume: OSAllocatedUnfairLock<Bool>
    var tempFileHandle: FileHandle?
    var tempFileURL: URL?
    var bytesReceived: Int64

    init() {
        responseData = Data(capacity: 65_536)
        headerLines = []
        isCancelled = OSAllocatedUnfairLock(initialState: false)
        didResume = OSAllocatedUnfairLock(initialState: false)
        tempFileHandle = nil
        tempFileURL = nil
        bytesReceived = 0
    }
}

nonisolated func sanitizeForCurl(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\0", with: "")
}

nonisolated func parseStatusMessage(from headerLines: [String], statusCode: Int) -> String {
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

nonisolated func parseHeaders(from headerLines: [String]) -> [String: String] {
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

let curlWriteCallback: @convention(c) (UnsafeMutablePointer<Int8>?, Int, Int, UnsafeMutableRawPointer?) -> Int = { ptr, size, nmemb, userdata in
    guard let ptr = ptr, let userdata = userdata else { return 0 }
    guard size > 0, nmemb > 0, size <= Int.max / nmemb else { return 0 }

    let byteCount = size * nmemb
    let context = Unmanaged<CurlTransferContext>.fromOpaque(userdata).takeUnretainedValue()

    if context.isCancelled.withLock({ $0 }) {
        return 0
    }

    let newBytesReceived = context.bytesReceived + Int64(byteCount)

    if newBytesReceived > maxMemorySize && context.tempFileHandle == nil {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("postkit-response-\(UUID().uuidString).tmp")

        do {
            FileManager.default.createFile(atPath: tempURL.path, contents: context.responseData, attributes: [.posixPermissions: 0o600])
            context.tempFileHandle = try FileHandle(forWritingTo: tempURL)
            context.tempFileHandle?.seekToEndOfFile()
            context.tempFileURL = tempURL
            context.responseData = Data()
        } catch {
            return 0
        }
    }

    if let fileHandle = context.tempFileHandle {
        let bytes = Data(bytes: ptr, count: byteCount)
        fileHandle.write(bytes)
    } else {
        ptr.withMemoryRebound(to: UInt8.self, capacity: byteCount) { uintPtr in
            context.responseData.append(uintPtr, count: byteCount)
        }
    }

    context.bytesReceived = newBytesReceived

    return byteCount
}

let curlHeaderCallback: @convention(c) (UnsafeMutablePointer<Int8>?, Int, Int, UnsafeMutableRawPointer?) -> Int = { ptr, size, nmemb, userdata in
    guard let ptr = ptr, let userdata = userdata else { return 0 }
    guard size > 0, nmemb > 0, size <= Int.max / nmemb else { return 0 }

    let byteCount = size * nmemb
    let context = Unmanaged<CurlTransferContext>.fromOpaque(userdata).takeUnretainedValue()

    let line = ptr.withMemoryRebound(to: UInt8.self, capacity: byteCount) { uintPtr in
        String(bytes: UnsafeBufferPointer(start: uintPtr, count: byteCount), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    if !line.isEmpty {
        context.headerLines.append(line)
    }

    return byteCount
}

let curlProgressCallback: @convention(c) (UnsafeMutableRawPointer?, Int, Int, Int, Int) -> Int32 = { userdata, _, _, _, _ in
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

        let sanitizedURL = sanitizeForCurl(url.absoluteString)

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
                            context.tempFileHandle?.closeFile()
                            if let tempURL = context.tempFileURL {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        if code == CURLE_ABORTED_BY_CALLBACK {
                            context.tempFileHandle?.closeFile()
                            if let tempURL = context.tempFileURL {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        if code != CURLE_OK {
                            context.tempFileHandle?.closeFile()
                            if let tempURL = context.tempFileURL {
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
                let sanitizedKey = sanitizeForCurl(key)
                let sanitizedValue = sanitizeForCurl(value)
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

        let statusMessage = parseStatusMessage(from: context.headerLines, statusCode: statusCode)

        let headers = parseHeaders(from: context.headerLines)

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

        let size = context.bytesReceived
        let duration = totalTime

        var body: Data? = nil
        var bodyFileURL: URL? = nil

        if let fileHandle = context.tempFileHandle {
            try fileHandle.close()
            bodyFileURL = context.tempFileURL
        } else {
            body = context.responseData
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
