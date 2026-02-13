import Foundation

struct KeyValuePair: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true
    
    init(key: String = "", value: String = "", isEnabled: Bool = true) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}

extension Array where Element == KeyValuePair {
    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }
    
    static func decode(from data: Data?) -> [KeyValuePair] {
        guard let data = data else { return [] }
        return (try? JSONDecoder().decode([KeyValuePair].self, from: data)) ?? []
    }
}
