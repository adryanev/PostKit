import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedRequest: HTTPRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var focusedPane: Pane?

    enum Pane: Hashable {
        case sidebar, detail
    }

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
        }
    }

    private func cycleFocus() {
        switch focusedPane {
        case .sidebar: focusedPane = .detail
        case .detail, .none: focusedPane = .sidebar
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: RequestCollection.self, inMemory: true)
}
