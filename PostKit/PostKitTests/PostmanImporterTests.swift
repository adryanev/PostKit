import Testing
import Foundation
import SwiftData
@testable import PostKit

struct PostmanImporterTests {
    
    private func makeFormDataCollection(formData: [[String: Any]]) -> Data {
        let json: [String: Any] = [
            "info": [
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": [
                [
                    "name": "Form Data Request",
                    "request": [
                        "method": "POST",
                        "url": "https://api.example.com/upload",
                        "body": [
                            "mode": "formdata",
                            "formdata": formData
                        ]
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }
    
    @MainActor
    @Test func formDataEncodesEqualsInKey() throws {
        let formData: [[String: Any]] = [
            ["key": "field=name", "value": "test", "type": "text"]
        ]
        let data = makeFormDataCollection(formData: formData)
        
        let importer = PostmanImporter()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RequestCollection.self, HTTPRequest.self, Folder.self, Variable.self, APIEnvironment.self, HistoryEntry.self, ResponseExample.self, configurations: config)
        let context = container.mainContext
        
        let collection = try importer.importCollection(from: data, into: context)
        let request = collection.requests.first!
        
        #expect(request.bodyType == .formData)
        #expect(request.bodyContent?.contains("field%3Dname=test") == true)
    }
    
    @MainActor
    @Test func formDataEncodesEqualsInValue() throws {
        let formData: [[String: Any]] = [
            ["key": "query", "value": "a=b&c=d", "type": "text"]
        ]
        let data = makeFormDataCollection(formData: formData)
        
        let importer = PostmanImporter()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RequestCollection.self, HTTPRequest.self, Folder.self, Variable.self, APIEnvironment.self, HistoryEntry.self, ResponseExample.self, configurations: config)
        let context = container.mainContext
        
        let collection = try importer.importCollection(from: data, into: context)
        let request = collection.requests.first!
        
        #expect(request.bodyType == .formData)
        #expect(request.bodyContent?.contains("query=a%3Db%26c%3Dd") == true)
    }
    
    @MainActor
    @Test func formDataEncodesNewlineInKey() throws {
        let formData: [[String: Any]] = [
            ["key": "multi\nline", "value": "value", "type": "text"]
        ]
        let data = makeFormDataCollection(formData: formData)
        
        let importer = PostmanImporter()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RequestCollection.self, HTTPRequest.self, Folder.self, Variable.self, APIEnvironment.self, HistoryEntry.self, ResponseExample.self, configurations: config)
        let context = container.mainContext
        
        let collection = try importer.importCollection(from: data, into: context)
        let request = collection.requests.first!
        
        #expect(request.bodyType == .formData)
        #expect(request.bodyContent?.contains("multi%0Aline=value") == true)
        #expect(request.bodyContent?.contains("\n") == false || request.bodyContent?.contains("%0A") == true)
    }
    
    @MainActor
    @Test func formDataEncodesNewlineInValue() throws {
        let formData: [[String: Any]] = [
            ["key": "message", "value": "line1\nline2", "type": "text"]
        ]
        let data = makeFormDataCollection(formData: formData)
        
        let importer = PostmanImporter()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RequestCollection.self, HTTPRequest.self, Folder.self, Variable.self, APIEnvironment.self, HistoryEntry.self, ResponseExample.self, configurations: config)
        let context = container.mainContext
        
        let collection = try importer.importCollection(from: data, into: context)
        let request = collection.requests.first!
        
        #expect(request.bodyType == .formData)
        #expect(request.bodyContent?.contains("message=line1%0Aline2") == true)
    }
    
    @MainActor
    @Test func formDataMultiplePairsWithAmpersandSeparator() throws {
        let formData: [[String: Any]] = [
            ["key": "username", "value": "john", "type": "text"],
            ["key": "email", "value": "john@example.com", "type": "text"]
        ]
        let data = makeFormDataCollection(formData: formData)
        
        let importer = PostmanImporter()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RequestCollection.self, HTTPRequest.self, Folder.self, Variable.self, APIEnvironment.self, HistoryEntry.self, ResponseExample.self, configurations: config)
        let context = container.mainContext
        
        let collection = try importer.importCollection(from: data, into: context)
        let request = collection.requests.first!
        
        #expect(request.bodyType == .formData)
        let pairs = request.bodyContent?.components(separatedBy: "&") ?? []
        #expect(pairs.count == 2)
        #expect(pairs.contains("username=john"))
        #expect(pairs.contains("email=john%40example.com"))
    }
    
    @MainActor
    @Test func formDataSkipsEmptyKey() throws {
        let formData: [[String: Any]] = [
            ["key": "", "value": "ignored", "type": "text"],
            ["key": "valid", "value": "kept", "type": "text"]
        ]
        let data = makeFormDataCollection(formData: formData)
        
        let importer = PostmanImporter()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RequestCollection.self, HTTPRequest.self, Folder.self, Variable.self, APIEnvironment.self, HistoryEntry.self, ResponseExample.self, configurations: config)
        let context = container.mainContext
        
        let collection = try importer.importCollection(from: data, into: context)
        let request = collection.requests.first!
        
        #expect(request.bodyType == .formData)
        #expect(request.bodyContent == "valid=kept")
    }
    
    @MainActor
    @Test func formDataEncodesSpecialCharacters() throws {
        let formData: [[String: Any]] = [
            ["key": "data", "value": "hello world & <test>", "type": "text"]
        ]
        let data = makeFormDataCollection(formData: formData)
        
        let importer = PostmanImporter()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RequestCollection.self, HTTPRequest.self, Folder.self, Variable.self, APIEnvironment.self, HistoryEntry.self, ResponseExample.self, configurations: config)
        let context = container.mainContext
        
        let collection = try importer.importCollection(from: data, into: context)
        let request = collection.requests.first!
        
        #expect(request.bodyType == .formData)
        #expect(request.bodyContent?.contains("data=hello%20world%20%26%20%3Ctest%3E") == true)
    }
}
