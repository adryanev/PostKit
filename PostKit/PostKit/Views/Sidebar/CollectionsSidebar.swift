import SwiftUI
import SwiftData

struct CollectionsSidebar: View {
    @Binding var selection: SidebarSelection?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RequestCollection.sortOrder) private var collections: [RequestCollection]
    @Query(sort: \RequestChain.sortOrder) private var chains: [RequestChain]
    @State private var isAddingCollection = false
    @State private var isAddingChain = false
    @State private var newCollectionName = ""
    @State private var newChainName = ""

    var body: some View {
        List(selection: $selection) {
            // Collections Section
            Section("Collections") {
                ForEach(collections) { collection in
                    CollectionRow(collection: collection, selection: $selection)
                }
                .onDelete(perform: deleteCollections)
                .onMove(perform: moveCollections)
            }
            
            // Chains Section
            Section("Request Chains") {
                ForEach(chains) { chain in
                    ChainRow(chain: chain, selection: $selection)
                }
                .onDelete(perform: deleteChains)
                .onMove(perform: moveChains)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PostKit")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isAddingCollection = true
                    } label: {
                        Label("New Collection", systemImage: "folder.badge.plus")
                    }
                    
                    Button {
                        isAddingChain = true
                    } label: {
                        Label("New Chain", systemImage: "link.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
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
        .alert("New Chain", isPresented: $isAddingChain) {
            TextField("Name", text: $newChainName)
            Button("Cancel", role: .cancel) {
                newChainName = ""
            }
            Button("Create") {
                createChain()
            }
        }
    }

    private func createCollection() {
        guard !newCollectionName.isEmpty else { return }
        let collection = RequestCollection(name: newCollectionName)
        modelContext.insert(collection)
        newCollectionName = ""
    }
    
    private func createChain() {
        guard !newChainName.isEmpty else { return }
        let chain = RequestChain(name: newChainName)
        modelContext.insert(chain)
        newChainName = ""
    }

    private func deleteCollections(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(collections[index])
        }
    }
    
    private func deleteChains(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(chains[index])
        }
    }

    private func moveCollections(from source: IndexSet, to destination: Int) {
        var revised = collections
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, collection) in revised.enumerated() {
            collection.sortOrder = index
        }
    }
    
    private func moveChains(from source: IndexSet, to destination: Int) {
        var revised = chains
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, chain) in revised.enumerated() {
            chain.sortOrder = index
        }
    }
}

// MARK: - Chain Row

struct ChainRow: View {
    let chain: RequestChain
    @Binding var selection: SidebarSelection?
    
    var body: some View {
        Button {
            selection = .chain(chain)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.name)
                        .lineLimit(1)
                    
                    Text("\(chain.steps.count) steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "link")
                    .foregroundStyle(chain.isEnabled ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                selection = .chain(chain)
            } label: {
                Label("Open", systemImage: "arrow.right.circle")
            }
            
            Divider()
            
            Button(role: .destructive) {
                // Delete will be handled by parent
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    CollectionsSidebar(selection: .constant(nil))
        .modelContainer(for: RequestCollection.self, inMemory: true)
}
