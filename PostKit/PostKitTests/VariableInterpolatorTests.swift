import Testing
import Foundation
@testable import PostKit

struct VariableInterpolatorTests {
    let interpolator = VariableInterpolator()

    @Test func interpolateSimpleVariable() throws {
        let result = try interpolator.interpolate(
            "Hello, {{name}}!",
            with: ["name": "World"]
        )
        #expect(result == "Hello, World!")
    }

    @Test func interpolateMultipleVariables() throws {
        let result = try interpolator.interpolate(
            "{{greeting}}, {{name}}! Welcome to {{place}}.",
            with: ["greeting": "Hi", "name": "Alice", "place": "PostKit"]
        )
        #expect(result == "Hi, Alice! Welcome to PostKit.")
    }

    @Test func interpolateMissingVariableLeavesTemplate() throws {
        let result = try interpolator.interpolate(
            "Token: {{auth_token}}",
            with: [:]
        )
        #expect(result == "Token: {{auth_token}}")
    }

    @Test func interpolateNoVariablesPassthrough() throws {
        let template = "This is plain text without any variables."
        let result = try interpolator.interpolate(template, with: ["unused": "value"])
        #expect(result == template)
    }

    @Test func interpolateEmptyTemplate() throws {
        let result = try interpolator.interpolate("", with: ["key": "value"])
        #expect(result == "")
    }

    @Test func interpolateBuiltInTimestamp() throws {
        let before = Int(Date().timeIntervalSince1970 * 1000)
        let result = try interpolator.interpolate("ts={{$timestamp}}", with: [:])
        let after = Int(Date().timeIntervalSince1970 * 1000)

        let timestampString = String(result.dropFirst(3))
        let timestamp = Int(timestampString)
        #expect(timestamp != nil)
        #expect(timestamp! >= before)
        #expect(timestamp! <= after)
    }

    @Test func interpolateBuiltInUUID() throws {
        let result = try interpolator.interpolate("id={{$uuid}}", with: [:])
        let uuidString = String(result.dropFirst(3))
        #expect(UUID(uuidString: uuidString) != nil)
    }

    @Test func interpolateBuiltInGuid() throws {
        let result = try interpolator.interpolate("id={{$guid}}", with: [:])
        let uuidString = String(result.dropFirst(3))
        #expect(UUID(uuidString: uuidString) != nil)
    }

    @Test func interpolateBuiltInRandomInt() throws {
        let result = try interpolator.interpolate("num={{$randomInt}}", with: [:])
        let numString = String(result.dropFirst(4))
        let num = Int(numString)
        #expect(num != nil)
        #expect(num! >= 0)
        #expect(num! <= 999999)
    }

    @Test func interpolateBuiltInIsoTimestamp() throws {
        let result = try interpolator.interpolate("time={{$isoTimestamp}}", with: [:])
        let isoString = String(result.dropFirst(5))
        let formatter = ISO8601DateFormatter()
        #expect(formatter.date(from: isoString) != nil)
    }

    @Test func interpolateBuiltInRandomString() throws {
        let result = try interpolator.interpolate("rand={{$randomString}}", with: [:])
        let randomStr = String(result.dropFirst(5))
        #expect(randomStr.count == 16)
        #expect(randomStr.allSatisfy { $0.isLowercase && $0.isLetter })
    }

    @Test func interpolateVariableWithSpaces() throws {
        let result = try interpolator.interpolate(
            "Value: {{ name }}",
            with: ["name": "trimmed"]
        )
        #expect(result == "Value: trimmed")
    }

    @Test func interpolateMixedUserAndBuiltIn() throws {
        let result = try interpolator.interpolate(
            "{{baseUrl}}/items?ts={{$timestamp}}",
            with: ["baseUrl": "https://api.test.com"]
        )
        #expect(result.hasPrefix("https://api.test.com/items?ts="))
        let tsString = String(result.split(separator: "=").last!)
        #expect(Int(tsString) != nil)
    }

    @Test func interpolateSameVariableMultipleTimes() throws {
        let result = try interpolator.interpolate(
            "{{sep}}A{{sep}}B{{sep}}",
            with: ["sep": "-"]
        )
        #expect(result == "-A-B-")
    }
}
