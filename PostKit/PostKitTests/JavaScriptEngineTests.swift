import Testing
import Foundation
import FactoryKit
import FactoryTesting
@testable import PostKit

@Suite(.container)
struct JavaScriptEngineTests {
    let engine = JavaScriptEngine()
    
    // MARK: - Pre-request Script Tests
    
    @Test func preRequestConsoleLog() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "console.log('test message');", request: request, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput[0] == "test message")
    }
    
    @Test func preRequestEnvironmentGet() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "console.log(pk.environment.get('token'));", request: request, environment: ["token": "abc123"])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "abc123")
    }
    
    @Test func preRequestEnvironmentSet() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "pk.environment.set('newVar', 'newValue');", request: request, environment: [:])
        #expect(result.environmentChanges["newVar"] == "newValue")
    }
    
    @Test func preRequestVariablesAlias() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "console.log(pk.variables.get('myVar'));", request: request, environment: ["myVar": "test"])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "test")
    }
    
    @Test func preRequestAccessRequestData() async throws {
        let request = ScriptRequest(method: "POST", url: "https://api.example.com/users", headers: ["Content-Type": "application/json"], body: "{\"name\":\"test\"}")
        let result = try await engine.executePreRequest(script: "console.log(pk.request.method + ' ' + pk.request.url);", request: request, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "POST https://api.example.com/users")
    }
    
    @Test func preRequestAccessHeaders() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: ["Authorization": "Bearer token"], body: nil)
        let result = try await engine.executePreRequest(script: "console.log(pk.request.headers.get('Authorization'));", request: request, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "Bearer token")
    }
    
    @Test func preRequestModifyURL() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com/v1", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "pk.request.url = 'https://api.example.com/v2';", request: request, environment: [:])
        #expect(result.modifiedURL == "https://api.example.com/v2")
    }
    
    @Test func preRequestModifyBody() async throws {
        let request = ScriptRequest(method: "POST", url: "https://api.example.com", headers: [:], body: "original")
        let result = try await engine.executePreRequest(script: "pk.request.body = JSON.stringify({modified: true});", request: request, environment: [:])
        #expect(result.modifiedBody == "{\"modified\":true}")
    }
    
    @Test func preRequestPMShim() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "console.log(pm.environment.get('key'));", request: request, environment: ["key": "shim-value"])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "shim-value")
    }
    
    @Test func preRequestScriptError() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        await #expect(throws: ScriptEngineError.self) {
            _ = try await engine.executePreRequest(script: "undefinedFunction();", request: request, environment: [:])
        }
    }
    
    // MARK: - Post-request Script Tests
    
    @Test func postRequestConsoleLog() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: nil, duration: 0.5)
        let result = try await engine.executePostRequest(script: "console.log('response received');", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput[0] == "response received")
    }
    
    @Test func postRequestAccessResponseCode() async throws {
        let response = ScriptResponse(statusCode: 201, headers: [:], body: nil, duration: 0.5)
        let result = try await engine.executePostRequest(script: "console.log(pk.response.code);", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "201")
    }
    
    // responseTime contract: the engine multiplies duration (seconds) by 1000 and
    // truncates to Int, so 0.234s becomes "234" ms.
    @Test func postRequestAccessResponseTime() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: nil, duration: 0.234)
        let result = try await engine.executePostRequest(script: "console.log(pk.response.responseTime);", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "234")
    }
    
    @Test func postRequestAccessResponseBodyText() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: "{\"name\":\"John\"}", duration: 0.5)
        let result = try await engine.executePostRequest(script: "console.log(pk.response.text());", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "{\"name\":\"John\"}")
    }
    
    @Test func postRequestAccessResponseBodyJSON() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: "{\"name\":\"Jane\",\"age\":30}", duration: 0.5)
        let result = try await engine.executePostRequest(script: "console.log(pk.response.json().name);", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "Jane")
    }
    
    @Test func postRequestAccessResponseHeaders() async throws {
        let response = ScriptResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: nil, duration: 0.5)
        let result = try await engine.executePostRequest(script: "console.log(pk.response.headers.get('Content-Type'));", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "application/json")
    }
    
    @Test func postRequestEnvironmentSet() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: "{\"token\":\"newToken123\"}", duration: 0.5)
        let result = try await engine.executePostRequest(script: "pk.environment.set('authToken', pk.response.json().token);", response: response, environment: [:])
        #expect(result.environmentChanges["authToken"] == "newToken123")
    }
    
    @Test func postRequestPMShim() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: nil, duration: 0.5)
        let result = try await engine.executePostRequest(script: "console.log(pm.response.code);", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "200")
    }
    
    @Test func postRequestScriptError() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: nil, duration: 0.5)
        await #expect(throws: ScriptEngineError.self) {
            _ = try await engine.executePostRequest(script: "throw new Error('test error');", response: response, environment: [:])
        }
    }
    
    // MARK: - Edge Cases
    
    @Test func emptyScriptSucceeds() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "", request: request, environment: [:])
        #expect(result.consoleOutput.isEmpty)
        #expect(result.environmentChanges.isEmpty)
    }
    
    @Test func nullJSONResponse() async throws {
        let response = ScriptResponse(statusCode: 200, headers: [:], body: nil, duration: 0.5)
        let result = try await engine.executePostRequest(script: "console.log(pk.response.json());", response: response, environment: [:])
        #expect(result.consoleOutput.count == 1)
        #expect(result.consoleOutput.first == "undefined")
    }
    
    @Test func multipleConsoleLogs() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(script: "console.log('a'); console.log('b'); console.log('c');", request: request, environment: [:])
        #expect(result.consoleOutput == ["a", "b", "c"])
    }
    
    @Test func environmentMergePreservesOriginal() async throws {
        let request = ScriptRequest(method: "GET", url: "https://api.example.com", headers: [:], body: nil)
        let result = try await engine.executePreRequest(
            script: "pk.environment.set('newKey', 'newValue'); console.log(pk.environment.get('existingKey'));",
            request: request,
            environment: ["existingKey": "existingValue"]
        )
        #expect(result.consoleOutput.count >= 1)
        #expect(result.consoleOutput.first == "existingValue")
        #expect(result.environmentChanges["newKey"] == "newValue")
    }
}
