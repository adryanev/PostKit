import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCollection: RequestCollection?
    @State private var selectedRequest: HTTPRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var focusedPane: Pane?
    
    enum Pane: Hashable {
        case sidebar, list, detail
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CollectionsSidebar(selection: $selectedCollection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                .focused($focusedPane, equals: .sidebar)
        } content: {
            if let collection = selectedCollection {
                RequestListView(
                    collection: collection,
                    selection: $selectedRequest
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
                .focused($focusedPane, equals: .list)
            } else {
                ContentUnavailableView(
                    "Select a Collection",
                    systemImage: "folder",
                    description: Text("Choose a collection from the sidebar to view its requests")
                )
            }
        } detail: {
            if let request = selectedRequest {
                RequestDetailView(request: request)
                    .focused($focusedPane, equals: .detail)
            } else {
                ContentUnavailableView(
                    "Select a Request",
                    systemImage: "arrow.right.circle",
                    description: Text("Choose a request to edit and send")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EnvironmentPicker()
            }
        }
        .onChange(of: selectedRequest) { oldValue, newValue in
            if let old = oldValue {
                old.updatedAt = Date()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: RequestCollection.self, inMemory: true)
}
