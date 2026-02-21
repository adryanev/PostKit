import Testing
import Foundation
import FactoryKit
import FactoryTesting
@testable import PostKit

@Suite(.container)
struct AuthConfigTests {

    // MARK: - Default Configuration

    @Test func defaultConfig() {
        let config = AuthConfig()
        #expect(config.type == .none)
        #expect(config.token == nil)
        #expect(config.username == nil)
        #expect(config.password == nil)
        #expect(config.apiKeyName == nil)
        #expect(config.apiKeyValue == nil)
        #expect(config.apiKeyLocation == nil)
    }

    // MARK: - Encode / Decode

    @Test func encodeDecodeBearer() throws {
        var config = AuthConfig(type: .bearer)
        config.token = "eyJhbGciOiJIUzI1NiJ9.test.signature"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .bearer)
        #expect(decoded.token == "eyJhbGciOiJIUzI1NiJ9.test.signature")
        #expect(decoded.username == nil)
        #expect(decoded.password == nil)
    }

    @Test func encodeDecodeBasic() throws {
        var config = AuthConfig(type: .basic)
        config.username = "admin"
        config.password = "p@ssw0rd!"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .basic)
        #expect(decoded.username == "admin")
        #expect(decoded.password == "p@ssw0rd!")
        #expect(decoded.token == nil)
    }

    @Test func encodeDecodeAPIKeyHeader() throws {
        var config = AuthConfig(type: .apiKey)
        config.apiKeyName = "X-API-Key"
        config.apiKeyValue = "sk-abc123xyz"
        config.apiKeyLocation = .header

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .apiKey)
        #expect(decoded.apiKeyName == "X-API-Key")
        #expect(decoded.apiKeyValue == "sk-abc123xyz")
        #expect(decoded.apiKeyLocation == .header)
    }

    @Test func encodeDecodeAPIKeyQueryParam() throws {
        var config = AuthConfig(type: .apiKey)
        config.apiKeyName = "api_key"
        config.apiKeyValue = "key-456"
        config.apiKeyLocation = .queryParam

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .apiKey)
        #expect(decoded.apiKeyName == "api_key")
        #expect(decoded.apiKeyValue == "key-456")
        #expect(decoded.apiKeyLocation == .queryParam)
    }

    @Test func decodeUnknownTypeFallsBackToNone() throws {
        let json = """
        {"type":"oauth2","token":"some-token"}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .none)
        #expect(decoded.token == "some-token")
    }

    @Test func roundTripWithEmptyStringCredentials() throws {
        var config = AuthConfig(type: .basic)
        config.username = ""
        config.password = ""

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuthConfig.self, from: data)

        #expect(decoded.type == .basic)
        #expect(decoded.username == "")
        #expect(decoded.password == "")
    }

    // MARK: - AuthType Metadata

    @Test func authTypeDisplayNames() {
        #expect(AuthType.none.displayName == "No Auth")
        #expect(AuthType.bearer.displayName == "Bearer Token")
        #expect(AuthType.basic.displayName == "Basic Auth")
        #expect(AuthType.apiKey.displayName == "API Key")
    }

    @Test func authTypeRawValues() {
        #expect(AuthType.none.rawValue == "none")
        #expect(AuthType.bearer.rawValue == "bearer")
        #expect(AuthType.basic.rawValue == "basic")
        #expect(AuthType.apiKey.rawValue == "api-key")
    }

    @Test func authTypeCaseIterable() {
        let allCases = AuthType.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.none))
        #expect(allCases.contains(.bearer))
        #expect(allCases.contains(.basic))
        #expect(allCases.contains(.apiKey))

        #expect(AuthType.none.rawValue == "none")
        #expect(AuthType.bearer.rawValue == "bearer")
        #expect(AuthType.basic.rawValue == "basic")
        #expect(AuthType.apiKey.rawValue == "api-key")
    }
}
