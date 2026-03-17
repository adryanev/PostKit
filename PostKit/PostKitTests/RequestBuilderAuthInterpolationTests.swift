import Testing
import Foundation
@testable import PostKit

// MARK: - RequestBuilder Auth Interpolation Tests

struct RequestBuilderAuthInterpolationTests {
    let builder = RequestBuilder()

    @Test func applyAuthInterpolatesBearerToken() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/test")!)
        var authConfig = AuthConfig(type: .bearer)
        authConfig.token = "{{bearerToken}}"

        builder.applyAuth(&request, authConfig: authConfig, variables: ["bearerToken": "my-secret-token"])

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-secret-token")
    }

    @Test func applyAuthInterpolatesBasicCredentials() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/test")!)
        var authConfig = AuthConfig(type: .basic)
        authConfig.username = "{{basicUsername}}"
        authConfig.password = "{{basicPassword}}"

        builder.applyAuth(&request, authConfig: authConfig, variables: ["basicUsername": "admin", "basicPassword": "secret123"])

        let expectedCredentials = Data("admin:secret123".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(expectedCredentials)")
    }

    @Test func applyAuthInterpolatesApiKeyValue() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/test")!)
        var authConfig = AuthConfig(type: .apiKey)
        authConfig.apiKeyName = "X-API-Key"
        authConfig.apiKeyValue = "{{apiKeyValue}}"
        authConfig.apiKeyLocation = .header

        builder.applyAuth(&request, authConfig: authConfig, variables: ["apiKeyValue": "sk-abc123"])

        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "sk-abc123")
    }

    @Test func applyAuthFallsBackToLiteralIfNoVariable() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/test")!)
        var authConfig = AuthConfig(type: .bearer)
        authConfig.token = "literal-token-value"

        builder.applyAuth(&request, authConfig: authConfig, variables: [:])

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer literal-token-value")
    }

    @Test func applyAuthWithEmptyVariablesUsesTemplate() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/test")!)
        var authConfig = AuthConfig(type: .bearer)
        authConfig.token = "{{bearerToken}}"

        builder.applyAuth(&request, authConfig: authConfig, variables: [:])

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer {{bearerToken}}")
    }
}
