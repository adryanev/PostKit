import Foundation
import Security

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case itemNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Keychain store failed: \(status)"
        case .retrieveFailed(let status):
            return "Keychain retrieve failed: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed: \(status)"
        case .itemNotFound:
            return "Keychain item not found"
        case .invalidData:
            return "Invalid keychain data"
        }
    }
}

final class KeychainManager: KeychainManagerProtocol, Sendable {
    static let shared = KeychainManager()
    
    private let service = "com.postkit.secrets"
    
    private init() {}
    
    func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }
    
    func retrieve(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.retrieveFailed(status)
        }
        
        return value
    }
    
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    func storeSecrets(_ secrets: [String: String]) throws {
        for (key, value) in secrets {
            try store(key: key, value: value)
        }
    }
    
    func retrieveSecrets(keys: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for key in keys {
            if let value = try retrieve(key: key) {
                result[key] = value
            }
        }
        return result
    }
}
