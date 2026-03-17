import Foundation
import FactoryKit

enum AuthType: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case bearer = "bearer"
    case basic = "basic"
    case apiKey = "api-key"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AuthType(rawValue: rawValue) ?? .none
    }

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
    /// Returns any errors encountered during storage.
    @discardableResult
    mutating func storeSecrets(forRequestID requestID: String) -> [KeychainError] {
        let keychain = Container.shared.keychainManager()
        var errors: [KeychainError] = []

        if let token = token, !token.isEmpty {
            do {
                try keychain.store(key: Self.tokenKey(for: requestID), value: token)
                self.token = ""
            } catch let error as KeychainError {
                errors.append(error)
            } catch {
                errors.append(.storeFailed(errSecNotAvailable))
            }
        }
        if let password = password, !password.isEmpty {
            do {
                try keychain.store(key: Self.passwordKey(for: requestID), value: password)
                self.password = ""
            } catch let error as KeychainError {
                errors.append(error)
            } catch {
                errors.append(.storeFailed(errSecNotAvailable))
            }
        }
        if let apiKeyValue = apiKeyValue, !apiKeyValue.isEmpty {
            do {
                try keychain.store(key: Self.apiKeyValueKey(for: requestID), value: apiKeyValue)
                self.apiKeyValue = ""
            } catch let error as KeychainError {
                errors.append(error)
            } catch {
                errors.append(.storeFailed(errSecNotAvailable))
            }
        }
        
        if !errors.isEmpty {
            print("[PostKit] Keychain storage errors for request \(requestID): \(errors)")
        }
        
        return errors
    }

    func retrieveSecrets(forRequestID requestID: String) -> AuthConfig {
        let keychain = Container.shared.keychainManager()
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

    static func deleteSecrets(forRequestID requestID: String) {
        let keychain = Container.shared.keychainManager()
        for key in [tokenKey(for: requestID), passwordKey(for: requestID), apiKeyValueKey(for: requestID)] {
            do {
                try keychain.delete(key: key)
            } catch {
                print("[PostKit] Failed to delete keychain entry \(key): \(error)")
            }
        }
    }
}
