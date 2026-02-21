import Testing
import Foundation
@testable import PostKit

struct SyntaxHighlightingTests {
    
    // MARK: - HTTPResponse.contentType Tests
    
    @Test func contentTypeExtractsSimpleContentType() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/json"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeHandlesCaseInsensitiveHeader() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["content-type": "application/json"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeStripsCharsetParameter() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeStripsMultipleParameters() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "text/html; charset=utf-8; boundary=something"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "text/html")
    }
    
    @Test func contentTypeTrimsWhitespace() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "  application/json  ; charset=utf-8"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeReturnsLowercase() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "Application/JSON"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/json")
    }
    
    @Test func contentTypeReturnsNilWhenMissing() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: [:],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == nil)
    }
    
    @Test func contentTypeHandlesXMLTypes() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/xml; charset=utf-8"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "application/xml")
    }
    
    @Test func contentTypeHandlesTextPlain() {
        let response = HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "text/plain"],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        )
        #expect(response.contentType == "text/plain")
    }
    
    // MARK: - BodyType.highlightrLanguage Tests
    
    @Test func bodyTypeNoneReturnsNilLanguage() {
        #expect(BodyType.none.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeJsonReturnsJsonLanguage() {
        #expect(BodyType.json.highlightrLanguage == "json")
    }
    
    @Test func bodyTypeXmlReturnsXmlLanguage() {
        #expect(BodyType.xml.highlightrLanguage == "xml")
    }
    
    @Test func bodyTypeRawReturnsNilLanguage() {
        #expect(BodyType.raw.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeUrlEncodedReturnsNilLanguage() {
        #expect(BodyType.urlEncoded.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeFormDataReturnsNilLanguage() {
        #expect(BodyType.formData.highlightrLanguage == nil)
    }
    
    @Test func bodyTypeAllCasesCovered() {
        for bodyType in BodyType.allCases {
            switch bodyType {
            case .none, .json, .xml, .raw, .urlEncoded, .formData:
                break
            }
        }
    }
    
    // MARK: - languageForContentType Tests
    
    @Test func languageForContentTypeJson() {
        #expect(languageForContentType("application/json") == "json")
    }
    
    @Test func languageForContentTypeApplicationXml() {
        #expect(languageForContentType("application/xml") == "xml")
    }
    
    @Test func languageForContentTypeTextXml() {
        #expect(languageForContentType("text/xml") == "xml")
    }
    
    @Test func languageForContentTypeHtml() {
        #expect(languageForContentType("text/html") == "html")
    }
    
    @Test func languageForContentTypeCss() {
        #expect(languageForContentType("text/css") == "css")
    }
    
    @Test func languageForContentTypeApplicationJavascript() {
        #expect(languageForContentType("application/javascript") == "javascript")
    }
    
    @Test func languageForContentTypeTextJavascript() {
        #expect(languageForContentType("text/javascript") == "javascript")
    }
    
    @Test func languageForContentTypeApplicationYaml() {
        #expect(languageForContentType("application/x-yaml") == "yaml")
    }
    
    @Test func languageForContentTypeTextYaml() {
        #expect(languageForContentType("text/yaml") == "yaml")
    }
    
    @Test func languageForContentTypeUnknownReturnsNil() {
        #expect(languageForContentType("application/octet-stream") == nil)
    }
    
    @Test func languageForContentTypeNilReturnsNil() {
        #expect(languageForContentType(nil) == nil)
    }
    
    @Test func languageForContentTypeTextPlainReturnsNil() {
        #expect(languageForContentType("text/plain") == nil)
    }
    
    // MARK: - computeDisplayString Tests
    
    @Test func computeDisplayStringRawMode() {
        let data = #"{"name":"test","value":123}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: true)
        #expect(result == #"{"name":"test","value":123}"#)
    }
    
    @Test func computeDisplayStringJsonPrettyPrint() {
        let data = #"{"name":"test","value":123}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result.contains("\n"))
        #expect(result.contains("\"name\""))
        #expect(result.contains("\"test\""))
    }
    
    @Test func computeDisplayStringNonJsonPassthrough() {
        let data = "Hello, World!".data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "text/plain", showRaw: false)
        #expect(result == "Hello, World!")
    }
    
    @Test func computeDisplayStringNilContentType() {
        let data = "Hello, World!".data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: nil, showRaw: false)
        #expect(result == "Hello, World!")
    }
    
    @Test func computeDisplayStringInvalidJsonReturnsRaw() {
        let data = "not valid json".data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result == "not valid json")
    }
    
    @Test func computeDisplayStringBinaryData() {
        let data = Data([0x00, 0x01, 0x02, 0xFF])
        let result = computeDisplayString(for: data, contentType: "application/octet-stream", showRaw: false)
        #expect(result == "<binary data>")
    }
    
    @Test func computeDisplayStringTruncatesToMaxDisplaySize() {
        let longString = String(repeating: "a", count: 100)
        let data = longString.data(using: .utf8)!
        let result = computeDisplayString(
            for: data,
            contentType: "text/plain",
            showRaw: false,
            maxDisplaySize: 50
        )
        #expect(result.count == 50)
    }
    
    @Test func computeDisplayStringSkipsPrettyPrintAboveThreshold() {
        let jsonObject: [String: Any] = ["data": Array(repeating: "x", count: 1000)]
        let data = try! JSONSerialization.data(withJSONObject: jsonObject)
        
        let result = computeDisplayString(
            for: data,
            contentType: "application/json",
            showRaw: false,
            maxDisplaySize: 10_000_000,
            prettyPrintThreshold: 10
        )
        #expect(!result.contains("\n  "))
    }
    
    @Test func computeDisplayStringContainsAllJsonKeys() {
        let data = #"{"z":1,"a":2,"m":3}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result.contains("z"))
        #expect(result.contains("a"))
        #expect(result.contains("m"))
    }
    
    @Test func computeDisplayStringNestedJson() {
        let data = #"{"user":{"name":"Alice","age":30}}"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result.contains("user"))
        #expect(result.contains("Alice"))
        #expect(result.contains("30"))
    }
    
    @Test func computeDisplayStringJsonArray() {
        let data = #"[1,2,3]"#.data(using: .utf8)!
        let result = computeDisplayString(for: data, contentType: "application/json", showRaw: false)
        #expect(result.contains("["))
        #expect(result.contains("1"))
        #expect(result.contains("2"))
        #expect(result.contains("3"))
    }
    
    @Test func computeDisplayStringEmptyData() {
        let data = Data()
        let result = computeDisplayString(for: data, contentType: "text/plain", showRaw: false)
        #expect(result == "")
    }
}
