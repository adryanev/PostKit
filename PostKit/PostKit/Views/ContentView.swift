import SwiftUI
import SwiftData
import FactoryKit
import CoreSpotlight

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedRequest: HTTPRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var focusedPane: Pane?
    @ObservationIgnored @Injected(\.spotlightIndexer) private var spotlightIndexer
    private static var hasIndexedOnce = false

    enum Pane: Hashable {
        case sidebar, detail
    }
    
    @Query private var allRequests: [HTTPRequest]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CollectionsSidebar(selectedRequest: $selectedRequest)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
                .focused($focusedPane, equals: .sidebar)
        } detail: {
            if let request = selectedRequest {
                RequestDetailView(request: request)
                    .focused($focusedPane, equals: .detail)
            } else {
                ContentUnavailableView(
                    "Select a Request",
                    systemImage: "arrow.right.circle",
                    description: Text("Choose a request from the sidebar to edit and send")
                )
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EnvironmentPicker()
            }
        }
        .focusedValue(\.selectedRequest, selectedRequest)
        .onKeyPress(.tab) {
            if NSEvent.modifierFlags.contains(.control) {
                cycleFocus()
                return .handled
            }
            return .ignored
        }
        .onChange(of: selectedRequest) { oldValue, newValue in
            if let old = oldValue {
                old.updatedAt = Date()
            }
            if let new = newValue {
                Task {
                    await spotlightIndexer.indexRequest(
                        new,
                        collectionName: new.collection?.name,
                        folderName: new.folder?.name
                    )
                }
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            handleSpotlightActivity(userActivity)
        }
        .onAppear {
            if !Self.hasIndexedOnce {
                Self.hasIndexedOnce = true
                Task {
                    await spotlightIndexer.reindexAll(requests: allRequests)
                }
            }
        }
    }

    private func cycleFocus() {
        switch focusedPane {
        case .sidebar: focusedPane = .detail
        case .detail, .none: focusedPane = .sidebar
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "postkit", url.host == "request" else { return }
        guard let requestIdString = url.path.split(separator: "/").last,
              let requestId = UUID(uuidString: String(requestIdString)) else { return }
        
        if let request = allRequests.first(where: { $0.id == requestId }) {
            selectedRequest = request
            NSApp.activate()
        }
    }
    
    private func handleSpotlightActivity(_ userActivity: NSUserActivity) {
        guard let identifierString = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let identifier = UUID(uuidString: identifierString) else { return }
        
        if let request = allRequests.first(where: { $0.id == identifier }) {
            selectedRequest = request
            NSApp.activate()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: RequestCollection.self, inMemory: true)
}
