import SwiftUI
import SwiftData

struct RequestListView: View {
    let collection: RequestCollection
    @Binding var selection: HTTPRequest?
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    
    var body: some View {
        List(selection: $selection) {
            Section("Requests") {
                ForEach(filteredRequests) { request in
                    RequestRow(request: request)
                        .tag(request)
                        .contextMenu {
                            Button("Duplicate") {
                                duplicateRequest(request)
                            }
                            Button("Delete", role: .destructive) {
                                modelContext.delete(request)
                                if selection?.id == request.id {
                                    selection = nil
                                }
                            }
                        }
                }
                .onDelete(perform: deleteRequests)
                .onMove(perform: moveRequests)
            }
        }
        .listStyle(.inset)
        .navigationTitle(collection.name)
        .searchable(text: $searchText, prompt: "Search requests")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createRequest) {
                    Label("New Request", systemImage: "plus")
                }
            }
        }
    }
    
    private var filteredRequests: [HTTPRequest] {
        let rootRequests = collection.requests
            .filter { $0.folder == nil }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
        
        if searchText.isEmpty {
            return rootRequests
        }
        return rootRequests.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func createRequest() {
        let request = HTTPRequest(name: "New Request")
        request.collection = collection
        request.sortOrder = collection.requests.count
        modelContext.insert(request)
        selection = request
    }
    
    private func duplicateRequest(_ request: HTTPRequest) {
        let duplicate = request.duplicated()
        duplicate.collection = collection
        duplicate.sortOrder = collection.requests.count
        modelContext.insert(duplicate)
        selection = duplicate
    }
    
    private func deleteRequests(at offsets: IndexSet) {
        for index in offsets {
            let request = filteredRequests[index]
            modelContext.delete(request)
        }
    }
    
    private func moveRequests(from source: IndexSet, to destination: Int) {
        var revised = filteredRequests
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, request) in revised.enumerated() {
            request.sortOrder = index
        }
    }
}

#Preview {
    NavigationStack {
        RequestListView(
            collection: {
                let c = RequestCollection(name: "My API")
                c.requests.append(HTTPRequest(name: "Get Users", method: .get))
                c.requests.append(HTTPRequest(name: "Create User", method: .post))
                return c
            }(),
            selection: .constant(nil)
        )
    }
    .modelContainer(for: RequestCollection.self, inMemory: true)
}
