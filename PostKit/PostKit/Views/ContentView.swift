import SwiftUI
import SwiftData
import FactoryKit
import CoreSpotlight

enum SidebarSelection: Hashable {
    case collection(RequestCollection)
    case folder(Folder)
    case request(HTTPRequest)
    case chain(RequestChain)
    case mockServer(MockServer)
    case mockServersList
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSidebarItem: SidebarSelection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var focusedPane: Pane?
    @ObservationIgnored @Injected(\.spotlightIndexer) private var spotlightIndexer
    @ObservationIgnored @Injected(\.cloudKitSync) private var cloudKitSync
    @MainActor @Injected(\.mockServerManager) private var mockServerManager
    private static var hasIndexedOnce = false

    enum Pane: Hashable {
        case sidebar, detail
    }

    @Query private var allRequests: [HTTPRequest]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CollectionsSidebar(selection: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
                .focused($focusedPane, equals: .sidebar)
        } detail: {
            detailView
                .focused($focusedPane, equals: .detail)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EnvironmentPicker()
            }
            
            ToolbarItem(placement: .automatic) {
                SyncStatusView(syncService: cloudKitSync)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sidebarSelectionChange)) { notification in
            handleSidebarSelectionChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMockServers)) { _ in
            selectedSidebarItem = .mockServersList
            NSApp.activate()
        }
        .onKeyPress(.tab) {
            if NSEvent.modifierFlags.contains(.control) {
                cycleFocus()
                return .handled
            }
            return .ignored
        }
        .onChange(of: selectedSidebarItem) { oldValue, newValue in
            if case .request(let old) = oldValue {
                old.updatedAt = Date()
            }
            if case .request(let new) = newValue {
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
                    mockServerManager.configure(with: modelContext)
                    await mockServerManager.startAutoStartServers()
                }
            }
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedSidebarItem {
        case .collection(let collection):
            CollectionDetailView(collection: collection)
        case .folder(let folder):
            FolderDetailView(folder: folder)
        case .request(let request):
            RequestDetailView(request: request)
        case .chain(let chain):
            ChainBuilderView(chain: chain, modelContext: modelContext)
        case .mockServer(let server):
            MockServerEditorView(server: server, viewModel: MockServerViewModel(modelContext: modelContext))
        case .mockServersList:
            MockServerListView()
        case .none:
            ContentUnavailableView(
                "Select an Item",
                systemImage: "arrow.right.circle",
                description: Text("Choose a collection, folder, or request from the sidebar")
            )
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
            selectedSidebarItem = .request(request)
            NSApp.activate()
        }
    }
    
    private func handleSpotlightActivity(_ userActivity: NSUserActivity) {
        guard let identifierString = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let identifier = UUID(uuidString: identifierString) else { return }

        if let request = allRequests.first(where: { $0.id == identifier }) {
            selectedSidebarItem = .request(request)
            NSApp.activate()
        }
    }

    private func handleSidebarSelectionChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let selection = userInfo["selection"] as? SidebarSelection else { return }

        selectedSidebarItem = selection

        // Activate the app to bring it to front
        NSApp.activate()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: RequestCollection.self, inMemory: true)
}
