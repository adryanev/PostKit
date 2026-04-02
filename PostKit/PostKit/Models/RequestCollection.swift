import Foundation
import SwiftData

@Model
final class RequestCollection {
    var id: UUID
    var name: String
    var folderPath: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    
    @Relationship(deleteRule: .cascade, inverse: \Folder.collection)
    var folders: [Folder] = []

    @Relationship(deleteRule: .cascade, inverse: \HTTPRequest.collection)
    var requests: [HTTPRequest] = []

    @Relationship(deleteRule: .cascade, inverse: \APIEnvironment.collection)
    var environments: [APIEnvironment] = []
    
    @Transient var sortedFolders: [Folder] {
        folders.sorted(by: { $0.sortOrder < $1.sortOrder })
    }
    
    @Transient var rootRequests: [HTTPRequest] {
        requests.filter { $0.folder == nil }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }
    
    init(name: String, folderPath: String? = nil) {
        self.id = UUID()
        self.name = name
        self.folderPath = folderPath
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = 0
    }
}
