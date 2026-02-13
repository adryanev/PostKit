import Foundation
import SwiftData

@Model
final class RequestCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var folderPath: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    
    var folders: [Folder] = []
    var requests: [HTTPRequest] = []
    var environments: [APIEnvironment] = []
    
    init(name: String, folderPath: String? = nil) {
        self.id = UUID()
        self.name = name
        self.folderPath = folderPath
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = 0
    }
}
