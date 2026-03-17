import Foundation
@testable import PostKit

final class MockKeychainManager: KeychainManagerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _store: [String: String] = [:]
    private var _storeCallCount = 0
    private var _retrieveCallCount = 0
    private var _deleteCallCount = 0
    var shouldThrow = false
    
    var storeCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _storeCallCount
    }
    
    var retrieveCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _retrieveCallCount
    }
    
    var deleteCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _deleteCallCount
    }
    
    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func store(key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        _storeCallCount += 1
        if shouldThrow { throw KeychainError.storeFailed(errSecNotAvailable) }
        _store[key] = value
    }

    func retrieve(key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        _retrieveCallCount += 1
        if shouldThrow { throw KeychainError.retrieveFailed(errSecNotAvailable) }
        return _store[key]
    }

    func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        _deleteCallCount += 1
        if shouldThrow { throw KeychainError.deleteFailed(errSecNotAvailable) }
        _store.removeValue(forKey: key)
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _store.removeAll()
        _storeCallCount = 0
        _retrieveCallCount = 0
        _deleteCallCount = 0
    }
}
