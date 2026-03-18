import SwiftUI
import SwiftData
import Combine
import FactoryKit

struct MenuBarView: View {
    @Query(filter: #Predicate<HTTPRequest> { $0.isPinned }, sort: \HTTPRequest.updatedAt, order: .reverse)
    private var pinnedRequests: [HTTPRequest]
    
    @Query(sort: \MockServer.name) private var mockServers: [MockServer]

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = MenuBarViewModel()

    private let maxPinnedDisplay = 20
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        // Mock Servers Section
        if !mockServers.isEmpty {
            mockServersSection
            Divider()
        }
        
        // Pinned Requests Section
        if pinnedRequests.isEmpty {
            Text("No Pinned Requests")
                .foregroundStyle(.secondary)
            Divider()
        } else {
            ForEach(pinnedRequests.prefix(maxPinnedDisplay)) { request in
                MenuBarRequestRow(
                    request: request,
                    result: viewModel.results[request.id],
                    isSending: viewModel.sendingRequestIDs.contains(request.id)
                ) {
                    await viewModel.sendRequest(request, modelContext: modelContext)
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

    @ViewBuilder
    private var mockServersSection: some View {
        ForEach(mockServers) { server in
            MenuBarMockServerRow(
                server: server,
                isRunning: viewModel.runningMockServerIDs.contains(server.id)
            ) {
                await viewModel.toggleMockServer(server)
            }
        }
    }
}

// MARK: - Mock Server Menu Bar Row

struct MenuBarMockServerRow: View {
    let server: MockServer
    let isRunning: Bool
    let onToggle: () async -> Void
    
    var body: some View {
        Button {
            Task { await onToggle() }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(server.name)
                    .lineLimit(1)
                
                Text(":\(server.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if isRunning {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
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
