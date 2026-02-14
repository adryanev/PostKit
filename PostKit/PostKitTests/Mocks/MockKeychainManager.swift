import Foundation
@testable import PostKit

final class MockKeychainManager: KeychainManagerProtocol, @unchecked Sendable {
    private var store: [String: String] = [:]
    var storeCallCount = 0
    var retrieveCallCount = 0
    var deleteCallCount = 0
    var shouldThrow = false
    
    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func store(key: String, value: String) throws {
        storeCallCount += 1
        if shouldThrow { throw KeychainError.storeFailed(errSecNotAvailable) }
        store[key] = value
    }

    func retrieve(key: String) throws -> String? {
        retrieveCallCount += 1
        if shouldThrow { throw KeychainError.retrieveFailed(errSecNotAvailable) }
        return store[key]
    }

    func delete(key: String) throws {
        deleteCallCount += 1
        if shouldThrow { throw KeychainError.deleteFailed(errSecNotAvailable) }
        store.removeValue(forKey: key)
    }
    
    func reset() {
        store.removeAll()
        storeCallCount = 0
        retrieveCallCount = 0
        deleteCallCount = 0
    }
}
