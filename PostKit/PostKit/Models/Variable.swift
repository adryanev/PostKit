import Foundation
import SwiftData

@Model
final class Variable {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String
    var isSecret: Bool
    var isEnabled: Bool
    
    var environment: APIEnvironment?
    
    init(key: String, value: String, isSecret: Bool = false, isEnabled: Bool = true) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.isEnabled = isEnabled
    }

    // MARK: - Secure Value (Keychain-backed for secrets)

    /// Keychain key derived from the variable's unique ID.
    private var keychainKey: String {
        "variable-\(id.uuidString)"
    }

    /// Use this property instead of `value` to transparently
    /// store and retrieve secret variables from the Keychain.
    /// Non-secret variables read and write `value` directly.
    var secureValue: String {
        get {
            if isSecret {
                return (try? KeychainManager.shared.retrieve(key: keychainKey)) ?? value
            }
            return value
        }
        set {
            if isSecret {
                try? KeychainManager.shared.store(key: keychainKey, value: newValue)
                value = "" // Don't store in plaintext
            } else {
                value = newValue
            }
        }
    }

    /// Removes the Keychain entry associated with this variable.
    /// Call this when deleting a secret variable to avoid orphaned Keychain items.
    func deleteSecureValue() {
        if isSecret {
            try? KeychainManager.shared.delete(key: keychainKey)
        }
    }
}
