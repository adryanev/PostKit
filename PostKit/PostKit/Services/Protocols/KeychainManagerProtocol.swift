import Foundation

protocol KeychainManagerProtocol: Sendable {
    func store(key: String, value: String) throws
    func retrieve(key: String) throws -> String?
    func delete(key: String) throws
}

extension KeychainManagerProtocol {
    func storeSecrets(_ secrets: [String: String]) throws {
        for (key, value) in secrets {
            try store(key: key, value: value)
        }
    }

    func retrieveSecrets(keys: [String]) throws -> [String: String] {
        var results: [String: String] = [:]
        for key in keys {
            if let value = try retrieve(key: key) {
                results[key] = value
            }
        }
        return results
    }
}
