import SwiftUI
import SwiftData
import FactoryKit

struct CollectionRow: View {
    let collection: RequestCollection
    @Binding var selectedRequest: HTTPRequest?
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = true
    @State private var isRenamingCollection = false
    @State private var isRenamingRequest = false
    @State private var renamingRequest: HTTPRequest?
    @State private var newName = ""
    @State private var exportError: String?

    @Injected(\.fileExporter) private var fileExporter

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(collection.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                FolderRow(folder: folder, selectedRequest: $selectedRequest)
            }
            ForEach(collection.requests.filter { $0.folder == nil }.sorted(by: { $0.sortOrder < $1.sortOrder })) { request in
                requestRow(for: request)
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(collection.name)
                    .lineLimit(1)
                Spacer()
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
                    isRenamingCollection = true
                }
                Button("Delete", role: .destructive) {
                    deleteCollection(collection)
                }
            }
        }
        .alert("Rename Collection", isPresented: $isRenamingCollection) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                collection.name = newName
                collection.updatedAt = Date()
            }
        }
        .alert("Rename Request", isPresented: $isRenamingRequest) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                renamingRequest?.name = newName
                renamingRequest?.updatedAt = Date()
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

    @ViewBuilder
    private func requestRow(for request: HTTPRequest) -> some View {
        RequestRow(request: request, compact: true)
            .tag(request)
            .contextMenu {
                Button("Rename") {
                    renamingRequest = request
                    newName = request.name
                    isRenamingRequest = true
                }
                Button("Duplicate") {
                    duplicateRequest(request)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    deleteRequest(request)
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

    private func duplicateRequest(_ request: HTTPRequest) {
        let duplicate = request.duplicated()

        // Copy secrets from original request to duplicated request's Keychain entry
        let originalAuthConfig = request.authConfig.retrieveSecrets(forRequestID: request.id.uuidString)
        var duplicatedAuthConfig = originalAuthConfig
        duplicatedAuthConfig.storeSecrets(forRequestID: duplicate.id.uuidString)
        duplicate.authConfig = duplicatedAuthConfig

        duplicate.collection = collection
        duplicate.folder = request.folder
        duplicate.sortOrder = collection.requests.count
        modelContext.insert(duplicate)
        selectedRequest = duplicate
    }

    private func deleteRequest(_ request: HTTPRequest) {
        AuthConfig.deleteSecrets(forRequestID: request.id.uuidString)
        if selectedRequest?.id == request.id {
            selectedRequest = nil
        }
        modelContext.delete(request)
    }

    private func deleteCollection(_ collection: RequestCollection) {
        for request in collection.requests {
            AuthConfig.deleteSecrets(forRequestID: request.id.uuidString)
        }
        for env in collection.environments {
            for variable in env.variables {
                variable.deleteSecureValue()
            }
        }
        modelContext.delete(collection)
    }
}

struct FolderRow: View {
    let folder: Folder
    @Binding var selectedRequest: HTTPRequest?
    @Environment(\.modelContext) private var modelContext
    @State private var isRenamingFolder = false
    @State private var isRenamingRequest = false
    @State private var renamingRequest: HTTPRequest?
    @State private var isExpanded = true
    @State private var newName = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(folder.requests.sorted(by: { $0.sortOrder < $1.sortOrder })) { request in
                RequestRow(request: request, compact: true)
                    .tag(request)
                    .contextMenu {
                        Button("Rename") {
                            renamingRequest = request
                            newName = request.name
                            isRenamingRequest = true
                        }
                        Button("Duplicate") {
                            duplicateRequest(request)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            deleteRequest(request)
                        }
                    }
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                    .lineLimit(1)
                Spacer()
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
                    isRenamingFolder = true
                }
                Button("Delete", role: .destructive) {
                    deleteFolder(folder)
                }
            }
        }
        .alert("Rename Folder", isPresented: $isRenamingFolder) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                folder.name = newName
            }
        }
        .alert("Rename Request", isPresented: $isRenamingRequest) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                renamingRequest?.name = newName
                renamingRequest?.updatedAt = Date()
            }
        }
    }

    private func duplicateRequest(_ request: HTTPRequest) {
        guard let collection = folder.collection else { return }
        let duplicate = request.duplicated()

        // Copy secrets from original request to duplicated request's Keychain entry
        let originalAuthConfig = request.authConfig.retrieveSecrets(forRequestID: request.id.uuidString)
        var duplicatedAuthConfig = originalAuthConfig
        duplicatedAuthConfig.storeSecrets(forRequestID: duplicate.id.uuidString)
        duplicate.authConfig = duplicatedAuthConfig

        duplicate.collection = collection
        duplicate.folder = folder
        duplicate.sortOrder = folder.requests.count
        modelContext.insert(duplicate)
        selectedRequest = duplicate
    }

    private func deleteRequest(_ request: HTTPRequest) {
        AuthConfig.deleteSecrets(forRequestID: request.id.uuidString)
        if selectedRequest?.id == request.id {
            selectedRequest = nil
        }
        modelContext.delete(request)
    }

    private func deleteFolder(_ folder: Folder) {
        for request in folder.requests {
            AuthConfig.deleteSecrets(forRequestID: request.id.uuidString)
        }
        modelContext.delete(folder)
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
            selectedRequest: .constant(nil)
        )
    }
    .modelContainer(for: RequestCollection.self, inMemory: true)
}
