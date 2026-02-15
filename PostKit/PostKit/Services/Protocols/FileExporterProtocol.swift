import Foundation
import SwiftData

@MainActor
protocol FileExporterProtocol: Sendable {
    func exportCollection(_ collection: RequestCollection) throws -> URL
    func importCollection(from url: URL, into context: ModelContext) throws -> RequestCollection
}
