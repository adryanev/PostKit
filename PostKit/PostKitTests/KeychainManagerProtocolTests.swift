import Testing
import FactoryKit
import FactoryTesting
@testable import PostKit

@Suite(.container)
struct KeychainManagerProtocolTests {

    // MARK: - Single Operations

    @Test func mockKeychainStoreAndRetrieve() throws {
        let mock = MockKeychainManager()
        
        try mock.store(key: "test-key", value: "test-value")
        #expect(mock.storeCallCount == 1)
        
        let retrieved = try mock.retrieve(key: "test-key")
        #expect(retrieved == "test-value")
        #expect(mock.retrieveCallCount == 1)
    }
    
    @Test func mockKeychainDelete() throws {
        let mock = MockKeychainManager()
        
        try mock.store(key: "test-key", value: "test-value")
        try mock.delete(key: "test-key")
        
        let retrieved = try mock.retrieve(key: "test-key")
        #expect(retrieved == nil)
        #expect(mock.deleteCallCount == 1)
    }

    // MARK: - Batch Operations

    @Test func mockKeychainStoreSecretsBatch() throws {
        let mock = MockKeychainManager()
        
        try mock.storeSecrets(["key1": "value1", "key2": "value2"])
        
        #expect(try mock.retrieve(key: "key1") == "value1")
        #expect(try mock.retrieve(key: "key2") == "value2")
    }
    
    @Test func mockKeychainRetrieveSecretsBatch() throws {
        let mock = MockKeychainManager()
        
        try mock.store(key: "key1", value: "value1")
        try mock.store(key: "key2", value: "value2")
        
        let secrets = try mock.retrieveSecrets(keys: ["key1", "key2", "nonexistent"])
        
        #expect(secrets["key1"] == "value1")
        #expect(secrets["key2"] == "value2")
        #expect(secrets["nonexistent"] == nil)
    }

    // MARK: - Error Handling

    @Test func mockKeychainThrowsWhenConfigured() {
        let mock = MockKeychainManager(shouldThrow: true)
        
        #expect(throws: KeychainError.self) {
            try mock.store(key: "test", value: "test")
        }
    }
}
