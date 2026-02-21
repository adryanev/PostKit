import Testing
import Foundation
@testable import PostKit

struct CurlParserTests {
    let parser = CurlParser()

    @Test func parseSimpleGet() throws {
        let result = try parser.parse("curl https://api.example.com/users")
        #expect(result.method == .get)
        #expect(result.url == "https://api.example.com/users")
        #expect(result.headers.isEmpty)
        #expect(result.body == nil)
        #expect(result.bodyType == .none)
    }

    @Test func parseExplicitGetMethod() throws {
        let result = try parser.parse("curl -X GET https://api.example.com/items")
        #expect(result.method == .get)
        #expect(result.url == "https://api.example.com/items")
    }

    @Test func parsePostWithJsonBody() throws {
        let result = try parser.parse(
            #"curl -X POST https://api.example.com/users -d '{"name":"Alice","email":"alice@example.com"}'"#
        )
        #expect(result.method == .post)
        #expect(result.url == "https://api.example.com/users")
        #expect(result.body == #"{"name":"Alice","email":"alice@example.com"}"#)
        #expect(result.bodyType == .json)
    }

    @Test func parsePostWithRawBody() throws {
        let result = try parser.parse(
            "curl -X POST https://api.example.com/data -d 'key=value&foo=bar'"
        )
        #expect(result.method == .post)
        #expect(result.body == "key=value&foo=bar")
        #expect(result.bodyType == .raw)
    }

    @Test func parseDataImpliesPostMethod() throws {
        let result = try parser.parse(
            #"curl https://api.example.com/submit -d '{"action":"create"}'"#
        )
        #expect(result.method == .post)
        #expect(result.body == #"{"action":"create"}"#)
        #expect(result.bodyType == .json)
    }

    @Test func parseSingleHeader() throws {
        let result = try parser.parse(
            "curl -H 'Content-Type: application/json' https://api.example.com/data"
        )
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Content-Type")
        #expect(result.headers[0].value == "application/json")
    }

    @Test func parseMultipleHeaders() throws {
        let result = try parser.parse(
            "curl -H 'Content-Type: application/json' -H 'Authorization: Bearer tok123' https://api.example.com/data"
        )
        #expect(result.headers.count == 2)
        #expect(result.headers[0].key == "Content-Type")
        #expect(result.headers[0].value == "application/json")
        #expect(result.headers[1].key == "Authorization")
        #expect(result.headers[1].value == "Bearer tok123")
    }

    @Test func parseLongFormFlags() throws {
        let result = try parser.parse(
            "curl --request PUT --header 'Accept: text/html' https://api.example.com/resource"
        )
        #expect(result.method == .put)
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Accept")
        #expect(result.headers[0].value == "text/html")
    }

    @Test func parseBasicAuth() throws {
        let result = try parser.parse(
            "curl -u admin:secret123 https://api.example.com/secure"
        )
        #expect(result.authConfig?.type == .basic)
        #expect(result.authConfig?.username == "admin")
        #expect(result.authConfig?.password == "secret123")
    }

    @Test func parseCompressedFlag() throws {
        let result = try parser.parse(
            "curl --compressed https://api.example.com/data"
        )
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Accept-Encoding")
        #expect(result.headers[0].value == "gzip, deflate")
    }

    @Test func parseSilentAndLocationFlags() throws {
        let result = try parser.parse(
            "curl -s -L https://api.example.com/redirect"
        )
        #expect(result.url == "https://api.example.com/redirect")
        #expect(result.headers.isEmpty)
    }

    @Test func parseMultilineCommand() throws {
        let command = """
        curl \
          -X DELETE \
          -H 'Authorization: Bearer token' \
          https://api.example.com/items/42
        """
        let result = try parser.parse(command)
        #expect(result.method == .delete)
        #expect(result.url == "https://api.example.com/items/42")
        #expect(result.headers.count == 1)
        #expect(result.headers[0].key == "Authorization")
    }

    @Test func parseInvalidCommandThrows() throws {
        #expect(throws: CurlParserError.invalidCommand) {
            try parser.parse("wget https://example.com")
        }
    }

    @Test func parseEmptyStringThrows() throws {
        #expect(throws: CurlParserError.invalidCommand) {
            try parser.parse("")
        }
    }

    @Test func parseMissingURLThrows() throws {
        #expect(throws: CurlParserError.missingURL) {
            try parser.parse("curl -X GET -H 'Accept: text/html'")
        }
    }

    @Test func parseWithQueryParams() throws {
        let result = try parser.parse(
            "curl https://api.example.com/search?q=swift&page=1&limit=20"
        )
        #expect(result.method == .get)
        #expect(result.url == "https://api.example.com/search?q=swift&page=1&limit=20")
    }

    @Test func parseHTTPUrl() throws {
        let result = try parser.parse("curl http://localhost:3000/api/health")
        #expect(result.url == "http://localhost:3000/api/health")
    }

    @Test func parseDataRaw() throws {
        let result = try parser.parse(
            #"curl --data-raw '{"id": 1}' https://api.example.com/create"#
        )
        #expect(result.method == .post)
        #expect(result.body == #"{"id": 1}"#)
        #expect(result.bodyType == .json)
    }
}
