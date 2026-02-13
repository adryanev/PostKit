import Foundation
import SwiftData

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    
    var collection: RequestCollection?
    var requests: [HTTPRequest] = []
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.sortOrder = 0
    }
}
