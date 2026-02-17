import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var sortOrder: Int
    
    var collection: RequestCollection?

    @Relationship(deleteRule: .cascade, inverse: \HTTPRequest.folder)
    var requests: [HTTPRequest] = []
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.sortOrder = 0
    }
}
