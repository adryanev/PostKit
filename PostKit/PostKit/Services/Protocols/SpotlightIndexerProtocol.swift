import Foundation

struct IndexableRequest: Sendable {
    let id: UUID
    let name: String
    let method: HTTPMethod
    let urlTemplate: String
    let collectionName: String?
    let folderName: String?
}

protocol SpotlightIndexerProtocol: Sendable {
    func indexRequest(_ request: IndexableRequest) async
    func deindexRequest(id: UUID) async
    func deindexRequests(ids: [UUID]) async
    func reindexAll(requests: [IndexableRequest]) async
}
