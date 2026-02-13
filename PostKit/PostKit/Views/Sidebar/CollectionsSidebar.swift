import SwiftUI
import SwiftData

struct CollectionsSidebar: View {
    @Binding var selection: RequestCollection?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RequestCollection.sortOrder) private var collections: [RequestCollection]
    @State private var isAddingCollection = false
    @State private var newCollectionName = ""
    
    var body: some View {
        List(selection: $selection) {
            ForEach(collections) { collection in
                CollectionRow(collection: collection, selection: $selection)
            }
            .onDelete(perform: deleteCollections)
            .onMove(perform: moveCollections)
        }
        .listStyle(.sidebar)
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { isAddingCollection = true }) {
                    Label("New Collection", systemImage: "folder.badge.plus")
                }
            }
        }
        .alert("New Collection", isPresented: $isAddingCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
            Button("Create") {
                createCollection()
            }
        }
    }
    
    private func createCollection() {
        guard !newCollectionName.isEmpty else { return }
        let collection = RequestCollection(name: newCollectionName)
        modelContext.insert(collection)
        newCollectionName = ""
        selection = collection
    }
    
    private func deleteCollections(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(collections[index])
        }
    }
    
    private func moveCollections(from source: IndexSet, to destination: Int) {
        var revised = collections
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, collection) in revised.enumerated() {
            collection.sortOrder = index
        }
    }
}

#Preview {
    CollectionsSidebar(selection: .constant(nil))
        .modelContainer(for: RequestCollection.self, inMemory: true)
}
