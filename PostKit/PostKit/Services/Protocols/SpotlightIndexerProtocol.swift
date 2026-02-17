import Foundation

protocol SpotlightIndexerProtocol: Sendable {
    func indexRequest(_ request: HTTPRequest, collectionName: String?, folderName: String?) async
    func deindexRequest(id: UUID) async
    func deindexRequests(ids: [UUID]) async
    func reindexAll(requests: [HTTPRequest]) async
}
