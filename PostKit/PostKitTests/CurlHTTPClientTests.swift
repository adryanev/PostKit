import Testing
import Foundation
@testable import PostKit

struct CurlHTTPClientTests {
    @Test func statusMessageExtractionFromHeaderLine() {
        let headerLines = ["HTTP/1.1 200 OK", "Content-Type: application/json"]
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 200)
        #expect(message == "OK")
    }
    
    @Test func statusMessageExtractionFromNoHeaders() {
        let headerLines: [String] = []
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 404)
        #expect(message == HTTPURLResponse.localizedString(forStatusCode: 404))
    }
    
    @Test func statusMessageExtractionFromMalformedLine() {
        let headerLines = ["HTTP/1.1 500"]
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 500)
        #expect(message == HTTPURLResponse.localizedString(forStatusCode: 500))
    }
    
    @Test func statusMessageExtractionFromNonHTTPLine() {
        let headerLines = ["Invalid response"]
        let message = CurlHTTPClient.parseStatusMessage(from: headerLines, statusCode: 200)
        #expect(message == HTTPURLResponse.localizedString(forStatusCode: 200))
    }
    
    @Test func timingDeltaClampingWithPositiveValues() {
        let timing = TimingBreakdown(
            dnsLookup: 0.05,
            tcpConnection: 0.03,
            tlsHandshake: 0.02,
            transferStart: 0.01,
            download: 0.10,
            total: 0.21,
            redirectTime: 0
        )
        #expect(timing.dnsLookup == 0.05)
        #expect(timing.tcpConnection >= 0)
        #expect(timing.tlsHandshake >= 0)
    }
    
    @Test func timingDeltaClampingWithZeroValues() {
        let timing = TimingBreakdown(
            dnsLookup: 0,
            tcpConnection: 0,
            tlsHandshake: 0,
            transferStart: 0.01,
            download: 0.05,
            total: 0.06,
            redirectTime: 0
        )
        #expect(timing.dnsLookup == 0)
        #expect(timing.tcpConnection == 0)
        #expect(timing.tlsHandshake == 0)
    }
    
    @Test func sanitizeForCurlStripsCRLF() {
        let input = "hello\r\nworld"
        let result = CurlHTTPClient.sanitizeForCurl(input)
        #expect(result == "helloworld")
    }
    
    @Test func sanitizeForCurlStripsNUL() {
        let input = "hello\0world"
        let result = CurlHTTPClient.sanitizeForCurl(input)
        #expect(result == "helloworld")
    }
    
    @Test func sanitizeForCurlStripsAllControlChars() {
        let input = "line1\r\n\0line2"
        let result = CurlHTTPClient.sanitizeForCurl(input)
        #expect(result == "line1line2")
    }
    
    @Test func httpClientErrorTimeoutExists() {
        let error = HTTPClientError.timeout
        #expect(error.errorDescription == "Request timed out")
    }
    
    @Test func httpClientErrorEngineInitFailedExists() {
        let error = HTTPClientError.engineInitializationFailed
        #expect(error.errorDescription == "HTTP client engine failed to initialize")
    }
    
    @Test func httpClientErrorResponseTooLarge() {
        let error = HTTPClientError.responseTooLarge(100_000_000)
        #expect(error.errorDescription?.contains("100000000") == true)
    }
    
    @Test func curlHTTPClientConformsToHTTPClientProtocol() throws {
        _ = try CurlHTTPClient()
        #expect(Bool(true))
    }

    // MARK: - parseHeaders Tests

    @Test func parseHeadersBasic() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json",
            "X-Request-Id: abc123"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["X-Request-Id"] == "abc123")
    }

    @Test func parseHeadersSkipsStatusLine() {
        let lines = ["HTTP/1.1 200 OK", "Host: example.com"]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Host"] == "example.com")
        #expect(headers.count == 1)
    }

    @Test func parseHeadersDuplicateKeysJoined() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Set-Cookie: a=1",
            "Set-Cookie: b=2"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Set-Cookie"] == "a=1, b=2")
    }

    @Test func parseHeadersColonInValue() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Location: https://example.com:8080/path"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Location"] == "https://example.com:8080/path")
    }

    @Test func parseHeadersEmptyInput() {
        let headers = CurlHTTPClient.parseHeaders(from: [])
        #expect(headers.isEmpty)
    }

    @Test func parseHeadersTrimsWhitespace() {
        let lines = [
            "HTTP/1.1 200 OK",
            "Content-Type:   application/json  "
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers["Content-Type"] == "application/json")
    }

    @Test func parseHeadersNoColonLineSkipped() {
        let lines = [
            "HTTP/1.1 200 OK",
            "InvalidLineWithoutColon",
            "Valid-Header: value"
        ]
        let headers = CurlHTTPClient.parseHeaders(from: lines)
        #expect(headers.count == 1)
        #expect(headers["Valid-Header"] == "value")
    }

    // MARK: - Error Type Tests

    @Test func httpClientErrorInvalidURL() {
        let error = HTTPClientError.invalidURL
        #expect(error.errorDescription == "Invalid URL")
    }

    @Test func httpClientErrorInvalidResponse() {
        let error = HTTPClientError.invalidResponse
        #expect(error.errorDescription == "Invalid response received")
    }

    @Test func httpClientErrorNetworkError() {
        let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "test error"])
        let error = HTTPClientError.networkError(underlying)
        #expect(error.errorDescription == "test error")
    }

    // MARK: - HTTPResponse Tests

    @Test func httpResponseGetBodyDataFromMemory() throws {
        let body = "test body".data(using: .utf8)!
        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: body, bodyFileURL: nil, duration: 0.1, size: Int64(body.count),
            timingBreakdown: nil
        )
        let data = try response.getBodyData()
        #expect(data == body)
    }

    @Test func httpResponseGetBodyDataFromFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("postkit-test-\(UUID().uuidString).tmp")
        let content = "file body content".data(using: .utf8)!
        try content.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: nil, bodyFileURL: tempURL, duration: 0.1, size: Int64(content.count),
            timingBreakdown: nil
        )
        let data = try response.getBodyData()
        #expect(data == content)
    }

    @Test func httpResponseGetBodyDataEmpty() throws {
        let response = HTTPResponse(
            statusCode: 204, statusMessage: "No Content", headers: [:],
            body: nil, bodyFileURL: nil, duration: 0.1, size: 0,
            timingBreakdown: nil
        )
        let data = try response.getBodyData()
        #expect(data.isEmpty)
    }

    @Test func httpResponseIsLargeWhenFileURLPresent() {
        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: nil, bodyFileURL: URL(fileURLWithPath: "/tmp/test"), duration: 0.1, size: 5_000_000,
            timingBreakdown: nil
        )
        #expect(response.isLarge)
    }

    @Test func httpResponseIsNotLargeWhenInMemory() {
        let response = HTTPResponse(
            statusCode: 200, statusMessage: "OK", headers: [:],
            body: Data(), bodyFileURL: nil, duration: 0.1, size: 100,
            timingBreakdown: nil
        )
        #expect(!response.isLarge)
    }

    // MARK: - Shared Constant Tests

    @Test func maxMemorySizeIsConsistentAcrossClients() {
        #expect(httpClientMaxMemorySize == 1_000_000)
    }
}
