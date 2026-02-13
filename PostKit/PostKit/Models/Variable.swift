import Foundation
import SwiftData

@Model
final class Variable {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String
    var isSecret: Bool
    var isEnabled: Bool
    
    var environment: APIEnvironment?
    
    init(key: String, value: String, isSecret: Bool = false, isEnabled: Bool = true) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.isEnabled = isEnabled
    }
}
