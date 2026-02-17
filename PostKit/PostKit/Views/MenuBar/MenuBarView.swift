import SwiftUI
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

struct MenuBarView: View {
    @Query(filter: #Predicate<HTTPRequest> { $0.isPinned }, sort: \HTTPRequest.updatedAt, order: .reverse)
    private var pinnedRequests: [HTTPRequest]

    @Environment(\.modelContext) private var modelContext
    @Injected(\.httpClient) private var httpClient
    @Injected(\.requestBuilder) private var requestBuilder

    @State private var results: [UUID: MenuBarResult] = [:]
    @State private var sendingRequestIDs: Set<UUID> = []

    private let maxPinnedDisplay = 20

    var body: some View {
        if pinnedRequests.isEmpty {
            Text("No Pinned Requests")
                .foregroundStyle(.secondary)
            Divider()
        } else {
            ForEach(pinnedRequests.prefix(maxPinnedDisplay)) { request in
                MenuBarRequestRow(
                    request: request,
                    result: results[request.id],
                    isSending: sendingRequestIDs.contains(request.id)
                ) {
                    await sendRequest(request)
                }
            }
            Divider()
        }

        Button("Open PostKit") {
            NSApp.activate()
        }
        .keyboardShortcut("o")

        Divider()

        Button("Quit PostKit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func sendRequest(_ request: HTTPRequest) async {
        guard !request.urlTemplate.isEmpty else { return }

        let hasScripts = (request.preRequestScript?.isEmpty == false) || (request.postRequestScript?.isEmpty == false)
        if hasScripts {
            return
        }

        await MainActor.run {
            _ = sendingRequestIDs.insert(request.id)
        }

        do {
            let variables = requestBuilder.getActiveEnvironmentVariables(from: modelContext)
            let urlRequest = try requestBuilder.buildURLRequest(for: request, with: variables)
            let response = try await httpClient.execute(urlRequest, taskID: UUID())

            // Clean up temp file for large responses that were spilled to disk
            if let fileURL = response.bodyFileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }

            await MainActor.run {
                results[request.id] = MenuBarResult(
                    statusCode: response.statusCode,
                    duration: response.duration,
                    timestamp: Date(),
                    error: nil
                )
                sendingRequestIDs.remove(request.id)
            }

            let entry = HistoryEntry(
                method: request.method,
                url: request.urlTemplate,
                statusCode: response.statusCode,
                responseTime: response.duration,
                responseSize: response.size
            )
            entry.request = request
            modelContext.insert(entry)
            try? modelContext.save()
        } catch {
            await MainActor.run {
                results[request.id] = MenuBarResult(
                    statusCode: 0,
                    duration: 0,
                    timestamp: Date(),
                    error: error
                )
                sendingRequestIDs.remove(request.id)
            }
        }
    }
}

struct MenuBarRequestRow: View {
    let request: HTTPRequest
    let result: MenuBarResult?
    let isSending: Bool
    let onSend: () async -> Void

    private let maxDisplayTime: TimeInterval = 30

    var body: some View {
        Button {
            Task { await onSend() }
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else if let result = result, Date().timeIntervalSince(result.timestamp) < maxDisplayTime {
                    Circle()
                        .fill(result.statusColor)
                        .frame(width: 8, height: 8)
                } else {
                    methodBadge
                }

                Text(request.name)
                    .lineLimit(1)

                Spacer()

                if let result = result, Date().timeIntervalSince(result.timestamp) < maxDisplayTime {
                    if result.error != nil {
                        Text("Error")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Text("\(result.statusCode) • \(String(format: "%.0f", result.duration * 1000))ms")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if hasScripts {
                    Text("(script)")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .disabled(isSending || hasScripts)
    }

    @ViewBuilder
    private var methodBadge: some View {
        Text(request.method.rawValue.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(methodColor)
    }

    private var methodColor: Color {
        switch request.method {
        case .get: .blue
        case .post: .green
        case .put: .orange
        case .patch: .yellow
        case .delete: .red
        default: .gray
        }
    }

    private var hasScripts: Bool {
        (request.preRequestScript?.isEmpty == false) || (request.postRequestScript?.isEmpty == false)
    }
}
