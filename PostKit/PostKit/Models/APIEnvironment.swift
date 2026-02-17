import Foundation
import SwiftData

@Model
final class APIEnvironment {
    var id: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Variable.environment)
    var variables: [Variable] = []

    var collection: RequestCollection?
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isActive = false
        self.createdAt = Date()
    }
}
