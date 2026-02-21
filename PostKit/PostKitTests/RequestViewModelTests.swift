import Testing
import Foundation
import FactoryKit
import FactoryTesting
import SwiftData
@testable import PostKit

@Suite(.serialized)
@MainActor
struct RequestViewModelTests {
    
    // MARK: - Positive Cases
    
    @Test func executeRequestReturnsResponse() async throws {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(response: HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": "application/json"],
            body: "{\"message\": \"success\"}".data(using: .utf8),
            bodyFileURL: nil,
            duration: 0.1,
            size: 27,
            timingBreakdown: nil
        ))

        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/test")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        #expect(viewModel.response != nil)
        #expect(viewModel.response?.statusCode == 200)
        #expect(viewModel.error == nil)
        #expect(viewModel.isSending == false)
    }
    
    @Test func viewModelInitializesWithModelContext() {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        #expect(container != nil)
        
        let viewModel = RequestViewModel(modelContext: container!.mainContext)
        #expect(viewModel.response == nil)
        #expect(viewModel.isSending == false)
        #expect(viewModel.error == nil)
    }
    
    @Test func activeTabDefaultsToBody() {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container!.mainContext)
        #expect(viewModel.activeTab == .body)
    }
    
    // MARK: - Negative Cases
    
    @Test func executeRequestHandlesNetworkError() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        struct TestError: Error {}
        let mockClient = MockHTTPClient(error: TestError())

        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/test")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        #expect(viewModel.error != nil)
        #expect(viewModel.response == nil)
        #expect(viewModel.isSending == false)
    }
    
    @Test func executeRequestHandlesHTTPError() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(response: HTTPResponse(
            statusCode: 404,
            statusMessage: "Not Found",
            headers: [:],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        ))

        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/notfound")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        #expect(viewModel.response?.statusCode == 404)
        #expect(viewModel.error == nil)
    }
    
    @Test func executeRequestSkipsEmptyURL() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient()
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Empty URL", method: .get, url: "")

        viewModel.sendRequest(for: request)
        #expect(viewModel.currentTask == nil)

        let callCount = await mockClient.executeCallCount
        #expect(callCount == 0)
        #expect(viewModel.response == nil)
    }
    
    // MARK: - Edge Cases
    
    @Test func cancelRequestStopsSending() async {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(delay: 5.0)
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Slow Request", method: .get, url: "https://api.example.com/slow")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        viewModel.cancelRequest()
        await viewModel.currentTask?.value

        #expect(viewModel.isSending == false)
    }
    
    @Test func newRequestCancelsPrevious() async throws {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(delay: 2.0)
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request1 = HTTPRequest(name: "Request 1", method: .get, url: "https://api.example.com/1")
        let request2 = HTTPRequest(name: "Request 2", method: .get, url: "https://api.example.com/2")
        container.mainContext.insert(request1)
        container.mainContext.insert(request2)

        viewModel.sendRequest(for: request1)
        let firstTaskID = viewModel.currentTaskID

        viewModel.sendRequest(for: request2)
        let secondTaskID = viewModel.currentTaskID

        await viewModel.currentTask?.value

        #expect(firstTaskID != secondTaskID)
        #expect(viewModel.currentTaskID == secondTaskID)

        let cancelledIDs = await mockClient.cancelledTaskIDs
        let callCount = await mockClient.executeCallCount
        #expect(callCount >= 1)
        if !cancelledIDs.isEmpty {
            #expect(cancelledIDs.contains(firstTaskID!))
        }
    }
    
    @Test func buildURLRequestWithQueryParams() throws {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)
        
        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/search")
        request.queryParamsData = [
            KeyValuePair(key: "q", value: "swift", isEnabled: true),
            KeyValuePair(key: "page", value: "1", isEnabled: true)
        ].encode()
        
        let urlRequest = try viewModel.buildURLRequest(for: request)
        
        #expect(urlRequest.url?.absoluteString.contains("q=swift") == true)
        #expect(urlRequest.url?.absoluteString.contains("page=1") == true)
    }
    
    @Test func buildURLRequestWithHeaders() throws {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)
        
        let request = HTTPRequest(name: "Test", method: .post, url: "https://api.example.com/data")
        request.headersData = [
            KeyValuePair(key: "Content-Type", value: "application/json", isEnabled: true),
            KeyValuePair(key: "Authorization", value: "Bearer token123", isEnabled: true)
        ].encode()
        
        let urlRequest = try viewModel.buildURLRequest(for: request)
        
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    }
    
    @Test func buildURLRequestWithJSONBody() throws {
        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)
        
        let request = HTTPRequest(name: "Test", method: .post, url: "https://api.example.com/users")
        request.bodyType = .json
        request.bodyContent = "{\"name\": \"Test\"}"
        
        let urlRequest = try viewModel.buildURLRequest(for: request)
        
        #expect(urlRequest.httpBody != nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
    
    @Test func historyCreatedAfterSend() async throws {
        Container.shared.manager.push()
        defer { Container.shared.manager.pop() }

        let mockClient = MockHTTPClient(response: HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: [:],
            body: nil,
            bodyFileURL: nil,
            duration: 0.1,
            size: 0,
            timingBreakdown: nil
        ))
        Container.shared.httpClient.register { mockClient }

        let schema = Schema([RequestCollection.self, Folder.self, HTTPRequest.self, APIEnvironment.self, Variable.self, HistoryEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let viewModel = RequestViewModel(modelContext: container.mainContext)

        let request = HTTPRequest(name: "Test", method: .get, url: "https://api.example.com/test")
        container.mainContext.insert(request)

        viewModel.sendRequest(for: request)
        await viewModel.currentTask?.value

        let callCount = await mockClient.executeCallCount
        #expect(callCount == 1)

        let descriptor = FetchDescriptor<HistoryEntry>()
        let entries = try container.mainContext.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.statusCode == 200)
    }
}
