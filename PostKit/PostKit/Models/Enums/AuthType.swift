import Foundation

enum AuthType: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case bearer = "bearer"
    case basic = "basic"
    case apiKey = "api-key"
    
    var displayName: String {
        switch self {
        case .none: return "No Auth"
        case .bearer: return "Bearer Token"
        case .basic: return "Basic Auth"
        case .apiKey: return "API Key"
        }
    }
}

struct AuthConfig: Codable, Sendable {
    var type: AuthType
    var token: String?
    var username: String?
    var password: String?
    var apiKeyName: String?
    var apiKeyValue: String?
    var apiKeyLocation: APIKeyLocation?

    enum APIKeyLocation: String, Codable, Sendable {
        case header
        case queryParam
    }

    init(type: AuthType = .none) {
        self.type = type
    }
}

// MARK: - Keychain-backed secret storage for AuthConfig

extension AuthConfig {

    // MARK: Keychain key helpers

    private static func tokenKey(for requestID: String) -> String {
        "auth-token-\(requestID)"
    }

    private static func passwordKey(for requestID: String) -> String {
        "auth-password-\(requestID)"
    }

    private static func apiKeyValueKey(for requestID: String) -> String {
        "auth-apikey-\(requestID)"
    }

    // MARK: Store & clear plaintext

    /// Moves sensitive fields (token, password, apiKeyValue) into the
    /// Keychain and clears their plaintext representations.
    mutating func storeSecrets(forRequestID requestID: String) {
        let keychain = KeychainManager.shared

        if let token = token, !token.isEmpty {
            try? keychain.store(key: Self.tokenKey(for: requestID), value: token)
            self.token = ""
        }
        if let password = password, !password.isEmpty {
            try? keychain.store(key: Self.passwordKey(for: requestID), value: password)
            self.password = ""
        }
        if let apiKeyValue = apiKeyValue, !apiKeyValue.isEmpty {
            try? keychain.store(key: Self.apiKeyValueKey(for: requestID), value: apiKeyValue)
            self.apiKeyValue = ""
        }
    }

    // MARK: Retrieve from Keychain

    /// Returns a copy of this config with sensitive fields populated
    /// from the Keychain. Non-secret fields are passed through unchanged.
    func retrieveSecrets(forRequestID requestID: String) -> AuthConfig {
        let keychain = KeychainManager.shared
        var config = self

        if config.token?.isEmpty != false {
            config.token = try? keychain.retrieve(key: Self.tokenKey(for: requestID))
        }
        if config.password?.isEmpty != false {
            config.password = try? keychain.retrieve(key: Self.passwordKey(for: requestID))
        }
        if config.apiKeyValue?.isEmpty != false {
            config.apiKeyValue = try? keychain.retrieve(key: Self.apiKeyValueKey(for: requestID))
        }
        return config
    }

    // MARK: Delete secrets

    /// Removes all Keychain entries associated with the given request ID.
    /// Call this when deleting a request to avoid orphaned Keychain items.
    static func deleteSecrets(forRequestID requestID: String) {
        let keychain = KeychainManager.shared
        try? keychain.delete(key: tokenKey(for: requestID))
        try? keychain.delete(key: passwordKey(for: requestID))
        try? keychain.delete(key: apiKeyValueKey(for: requestID))
    }
}
