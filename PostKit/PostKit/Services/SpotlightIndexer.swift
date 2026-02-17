import Foundation
import CoreSpotlight
import CoreServices
import AppKit

final class SpotlightIndexer: SpotlightIndexerProtocol, Sendable {
    
    static let shared = SpotlightIndexer()
    private nonisolated init() {}
    
    @MainActor
    func indexRequest(_ request: HTTPRequest, collectionName: String?, folderName: String?) async {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        attributeSet.title = request.name
        attributeSet.contentDescription = "\(request.method.rawValue) \(request.urlTemplate)"
        attributeSet.keywords = [
            request.method.rawValue,
            collectionName,
            folderName
        ].compactMap { $0 }
        
        attributeSet.thumbnailData = renderMethodBadge(for: request.method)
        
        let item = CSSearchableItem(
            uniqueIdentifier: request.id.uuidString,
            domainIdentifier: "dev.adryanev.PostKit.requests",
            attributeSet: attributeSet
        )
        
        try? await CSSearchableIndex.default().indexSearchableItems([item])
    }
    
    func deindexRequest(id: UUID) async {
        try? await CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [id.uuidString]
        )
    }
    
    func deindexRequests(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        try? await CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ids.map(\.uuidString)
        )
    }
    
    @MainActor
    func reindexAll(requests: [HTTPRequest]) async {
        try? await CSSearchableIndex.default().deleteAllSearchableItems()
        for request in requests {
            await indexRequest(request, collectionName: request.collection?.name, folderName: request.folder?.name)
        }
    }
    
    private func renderMethodBadge(for method: HTTPMethod) -> Data? {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let color: NSColor
        switch method {
        case .get: color = .systemBlue
        case .post: color = .systemGreen
        case .put: color = .systemOrange
        case .patch: color = .systemYellow
        case .delete: color = .systemRed
        default: color = .systemGray
        }
        
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        color.setFill()
        path.fill()
        
        let text = method.rawValue.uppercased() as NSString
        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        let textSize = text.size(withAttributes: [.font: font])
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ])
        
        image.unlockFocus()
        
        return image.tiffRepresentation
    }
}
