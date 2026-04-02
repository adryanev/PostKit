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
    
    @Transient var sortedRequests: [HTTPRequest] {
        requests.sorted(by: { $0.sortOrder < $1.sortOrder })
    }
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.sortOrder = 0
    }
}
