import SwiftUI
import SwiftData

struct CollectionRow: View {
    let collection: RequestCollection
    @Binding var selection: RequestCollection?
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = true
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var exportError: String?
    
    private let fileExporter = FileExporter()
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(collection.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                FolderRow(folder: folder)
            }
            ForEach(collection.requests.filter { $0.folder == nil }.sorted(by: { $0.sortOrder < $1.sortOrder })) { request in
                RequestRow(request: request, compact: true)
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(collection.name)
                    .lineLimit(1)
                Spacer()
            }
        }
        .contextMenu {
            Button("New Request") {
                createRequest()
            }
            Button("New Folder") {
                createFolder()
            }
            Divider()
            Button("Export Collection...") {
                exportCollection()
            }
            Divider()
            Button("Rename") {
                newName = collection.name
                isRenaming = true
            }
            Button("Delete", role: .destructive) {
                modelContext.delete(collection)
            }
        }
        .alert("Rename Collection", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                collection.name = newName
                collection.updatedAt = Date()
            }
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            if let error = exportError {
                Text(error)
            }
        }
    }
    
    private func exportCollection() {
        do {
            _ = try fileExporter.exportCollection(collection)
        } catch {
            exportError = error.localizedDescription
        }
    }
    
    private func createRequest() {
        let request = HTTPRequest(name: "New Request")
        request.collection = collection
        modelContext.insert(request)
    }
    
    private func createFolder() {
        let folder = Folder(name: "New Folder")
        folder.collection = collection
        modelContext.insert(folder)
    }
}

struct FolderRow: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = true
    @State private var isRenaming = false
    @State private var newName = ""
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(folder.requests.sorted(by: { $0.sortOrder < $1.sortOrder })) { request in
                RequestRow(request: request, compact: true)
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                    .lineLimit(1)
                Spacer()
            }
        }
        .contextMenu {
            Button("New Request") {
                let request = HTTPRequest(name: "New Request")
                request.folder = folder
                request.collection = folder.collection
                modelContext.insert(request)
            }
            Divider()
            Button("Rename") {
                newName = folder.name
                isRenaming = true
            }
            Button("Delete", role: .destructive) {
                modelContext.delete(folder)
            }
        }
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                folder.name = newName
            }
        }
    }
}

#Preview {
    List {
        CollectionRow(
            collection: {
                let c = RequestCollection(name: "My API")
                c.requests.append(HTTPRequest(name: "Get Users"))
                return c
            }(),
            selection: .constant(nil)
        )
    }
    .modelContainer(for: RequestCollection.self, inMemory: true)
}
