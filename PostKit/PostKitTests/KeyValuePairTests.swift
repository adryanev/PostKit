import Testing
import Foundation
@testable import PostKit

struct KeyValuePairTests {
    @Test func encodeDecodeRoundTrip() throws {
        let pairs = [
            KeyValuePair(key: "Content-Type", value: "application/json", isEnabled: true),
            KeyValuePair(key: "Authorization", value: "Bearer abc123", isEnabled: false),
        ]

        let data = pairs.encode()
        #expect(data != nil)

        let decoded = [KeyValuePair].decode(from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].key == "Content-Type")
        #expect(decoded[0].value == "application/json")
        #expect(decoded[0].isEnabled == true)
        #expect(decoded[1].key == "Authorization")
        #expect(decoded[1].value == "Bearer abc123")
        #expect(decoded[1].isEnabled == false)
    }

    @Test func encodeEmptyArray() throws {
        let pairs: [KeyValuePair] = []
        let data = pairs.encode()
        #expect(data != nil)

        let decoded = [KeyValuePair].decode(from: data)
        #expect(decoded.isEmpty)
    }

    @Test func decodeNilDataReturnsEmpty() {
        let decoded = [KeyValuePair].decode(from: nil)
        #expect(decoded.isEmpty)
    }

    @Test func decodeInvalidDataReturnsEmpty() {
        let invalidData = "not json".data(using: .utf8)!
        let decoded = [KeyValuePair].decode(from: invalidData)
        #expect(decoded.isEmpty)
    }

    @Test func defaultValues() {
        let pair = KeyValuePair()
        #expect(pair.key == "")
        #expect(pair.value == "")
        #expect(pair.isEnabled == true)
    }

    @Test func identifiableUniqueness() {
        let a = KeyValuePair(key: "same", value: "same")
        let b = KeyValuePair(key: "same", value: "same")
        #expect(a.id != b.id)
    }

    @Test func hashable() {
        let pair = KeyValuePair(key: "X", value: "Y")
        var set: Set<KeyValuePair> = []
        set.insert(pair)
        #expect(set.contains(pair))
    }
}
