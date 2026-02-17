import Foundation
import SwiftData

@Model
final class ResponseExample {
    var id: UUID
    var name: String
    var statusCode: Int
    var headersData: Data?
    var body: String?
    var contentType: String?
    var createdAt: Date
    
    var request: HTTPRequest?
    
    static let maxExampleBodySize = 10 * 1024 * 1024
    
    init(name: String, statusCode: Int, contentType: String? = nil, body: String? = nil) {
        self.id = UUID()
        self.name = name
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
        self.createdAt = Date()
    }
}
