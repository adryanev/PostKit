import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct PostKitApp: App {
    @State private var curlImportCollection: RequestCollection?
    @State private var showingOpenAPIImport = false
    @State private var showingImportCollection = false
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RequestCollection.self,
            Folder.self,
            HTTPRequest.self,
            APIEnvironment.self,
            Variable.self,
            HistoryEntry.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(item: $curlImportCollection) { collection in
                    CurlImportSheet(collection: collection)
                }
                .sheet(isPresented: $showingOpenAPIImport) {
                    OpenAPIImportSheet()
                }
                .fileImporter(
                    isPresented: $showingImportCollection,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        try? importCollection(from: url)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            PostKitCommands()
            CommandGroup(after: .newItem) {
                Button("Import cURL Command...") {
                    curlImportCollection = fetchOrCreateImportCollection()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("Import OpenAPI Specification...") {
                    showingOpenAPIImport = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Import Collection...") {
                    showingImportCollection = true
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
    
    private func fetchOrCreateImportCollection() -> RequestCollection {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<RequestCollection>(
            predicate: #Predicate { $0.name == "Imported" }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let collection = RequestCollection(name: "Imported")
        context.insert(collection)
        try? context.save()
        return collection
    }

    private func importCollection(from url: URL) throws {
        let exporter = FileExporter()
        let context = sharedModelContainer.mainContext
        _ = try exporter.importCollection(from: url, into: context)
    }
}
