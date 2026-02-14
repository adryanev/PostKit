import Foundation
import SwiftData
import FactoryKit

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
                return (try? Container.shared.keychainManager().retrieve(key: keychainKey)) ?? value
            }
            return value
        }
        set {
            if isSecret {
                do {
                    try Container.shared.keychainManager().store(key: keychainKey, value: newValue)
                    value = ""
                } catch {
                    // Keep plaintext if Keychain store fails - at least we don't lose data
                }
            } else {
                value = newValue
            }
        }
    }

    func deleteSecureValue() {
        if isSecret {
            try? Container.shared.keychainManager().delete(key: keychainKey)
        }
    }
}
