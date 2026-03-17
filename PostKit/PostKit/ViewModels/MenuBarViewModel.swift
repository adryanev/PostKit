import Foundation
import SwiftData
import FactoryKit

struct MenuBarResult {
    let statusCode: Int
    let duration: TimeInterval
    let timestamp: Date
    let error: Error?

    var statusColor: Color {
        switch statusCode {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        case 500..<600: .red
        default: .gray
        }
    }
}

import SwiftUI

@Observable
final class MenuBarViewModel {
    var results: [UUID: MenuBarResult] = [:]
    var sendingRequestIDs: Set<UUID> = []
    
    @ObservationIgnored @Injected(\.httpClient) private var httpClient
    @ObservationIgnored @Injected(\.requestBuilder) private var requestBuilder
    
    func sendRequest(_ request: HTTPRequest, modelContext: ModelContext) async {
        guard !request.urlTemplate.isEmpty else { return }

        let hasScripts = (request.preRequestScript?.isEmpty == false) || (request.postRequestScript?.isEmpty == false)
        if hasScripts {
            return
        }

        let (urlRequest, requestID, requestMethod, requestURLTemplate) = await MainActor.run {
            sendingRequestIDs.insert(request.id)
            let variables = requestBuilder.getActiveEnvironmentVariables(from: modelContext)
            let urlRequest = try? requestBuilder.buildURLRequest(for: request, with: variables, urlOverride: nil, bodyOverride: nil)
            return (urlRequest, request.id, request.method, request.urlTemplate)
        }

        guard let urlRequest = urlRequest else {
            _ = await MainActor.run {
                sendingRequestIDs.remove(request.id)
            }
            return
        }

        do {
            let response = try await httpClient.execute(urlRequest, taskID: UUID())

            if let fileURL = response.bodyFileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }

            await MainActor.run {
                results[requestID] = MenuBarResult(
                    statusCode: response.statusCode,
                    duration: response.duration,
                    timestamp: Date(),
                    error: nil
                )
                sendingRequestIDs.remove(requestID)

                let entry = HistoryEntry(
                    method: requestMethod,
                    url: requestURLTemplate,
                    statusCode: response.statusCode,
                    responseTime: response.duration,
                    responseSize: response.size
                )
                entry.request = request
                modelContext.insert(entry)
                do {
                    try modelContext.save()
                } catch {
                    print("[MenuBar] Failed to save history: \(error)")
                }
            }
        } catch {
            await MainActor.run {
                results[requestID] = MenuBarResult(
                    statusCode: 0,
                    duration: 0,
                    timestamp: Date(),
                    error: error
                )
                sendingRequestIDs.remove(requestID)
            }
        }
    }
}
