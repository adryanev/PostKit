import Foundation
import SwiftData

@Model
final class HistoryEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var methodRaw: String
    var url: String
    var statusCode: Int
    var responseTime: TimeInterval
    var responseSize: Int64

    var request: HTTPRequest?
    
    @Transient var method: HTTPMethod {
        get { HTTPMethod(rawValue: methodRaw) ?? .get }
        set { methodRaw = newValue.rawValue }
    }
    
    init(method: HTTPMethod, url: String, statusCode: Int, responseTime: TimeInterval, responseSize: Int64) {
        self.id = UUID()
        self.timestamp = Date()
        self.methodRaw = method.rawValue
        self.url = url
        self.statusCode = statusCode
        self.responseTime = responseTime
        self.responseSize = responseSize
    }
}
