import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os
import FactoryKit
import CloudKit

private let log = OSLog(subsystem: "dev.adryanev.PostKit", category: "PostKitApp")

private func cleanupStaleTempFiles() {
    let tempDir = FileManager.default.temporaryDirectory
    let fileManager = FileManager.default
    
    guard let enumerator = fileManager.enumerator(
        at: tempDir,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return }
    
    let staleThreshold: TimeInterval = 24 * 60 * 60
    let now = Date()
    
    for case let fileURL as URL in enumerator {
        guard fileURL.lastPathComponent.hasPrefix("postkit-response-"),
              fileURL.pathExtension == "tmp" else { continue }
        
        do {
            let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
            guard let modDate = attrs[.modificationDate] as? Date else { continue }
            
            if now.timeIntervalSince(modDate) > staleThreshold {
                try fileManager.removeItem(at: fileURL)
                os_log(.info, log: log, "Cleaned up stale temp file: %{public}@", fileURL.lastPathComponent)
            }
        } catch {
            os_log(.error, log: log, "Failed to check/remove temp file: %{public}@", error.localizedDescription)
        }
    }
}

@main
struct PostKitApp: App {
    @State private var curlImportCollection: RequestCollection?
    @State private var showingOpenAPIImport = false
    @State private var showingImportCollection = false
    @State private var showingPostmanImport = false
    @State private var postmanEnvironmentCollection: RequestCollection?
    @State private var showingCommandPalette = false
    @State private var commandPaletteViewModel: CommandPaletteViewModel?

    init() {
        Task.detached(priority: .background) {
            cleanupStaleTempFiles()
        }

        // Force-resolve singletons so the real implementations are cached
        // before any other code can register overrides.
        _ = Container.shared.httpClient()
        _ = Container.shared.keychainManager()

        #if !DEBUG
        // Runtime verification that the Keychain manager has not been tampered with
        precondition(Container.shared.keychainManager() is KeychainManager,
                     "KeychainManager has been replaced with an unexpected implementation")
        #endif
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RequestCollection.self,
            Folder.self,
            HTTPRequest.self,
            APIEnvironment.self,
            Variable.self,
            HistoryEntry.self,
            ResponseExample.self,
            RequestChain.self,
            ChainStep.self,
            ExtractionRule.self,
            ChainExecutionHistory.self,
            MockServer.self,
            MockEndpoint.self,
            MockResponse.self
        ])
        
        // Check if iCloud sync is enabled
        let iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "CloudKitSyncEnabled")
        
        let modelConfiguration: ModelConfiguration
        if iCloudSyncEnabled {
            // Use CloudKit for sync when enabled
            modelConfiguration = ModelConfiguration(
                "PostKit",
                schema: schema,
                cloudKitDatabase: .private("iCloud.dev.adryanev.PostKit")
            )
            os_log(.info, log: log, "SwiftData configured with CloudKit sync enabled")
        } else {
            // Local-only storage
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .sheet(item: $curlImportCollection) { collection in
                        CurlImportSheet(collection: collection)
                    }
                    .sheet(isPresented: $showingOpenAPIImport) {
                        OpenAPIImportSheet()
                    }
                    .sheet(isPresented: $showingPostmanImport) {
                        PostmanImportSheet()
                    }
                    .sheet(item: $postmanEnvironmentCollection) { collection in
                        PostmanEnvironmentImportSheet(collection: collection)
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

                // Command Palette Overlay
                if showingCommandPalette, let viewModel = commandPaletteViewModel {
                    CommandPalette(
                        viewModel: viewModel,
                        onDismiss: {
                            showingCommandPalette = false
                        }
                    )
                    .zIndex(1000)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteSelection)) { notification in
                handleCommandPaletteSelection(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteAction)) { notification in
                handleCommandPaletteAction(notification)
            }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            PostKitCommands()

            CommandGroup(replacing: .appInfo) {
                Button("Command Palette") {
                    showCommandPalette()
                }
                .keyboardShortcut(KeyboardShortcuts.commandPalette, modifiers: KeyboardShortcuts.commandModifiers)
                
                Divider()
                
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Import cURL Command...") {
                    curlImportCollection = fetchOrCreateImportCollection()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("Import OpenAPI Specification...") {
                    showingOpenAPIImport = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Import Postman Collection...") {
                    showingPostmanImport = true
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Import Collection...") {
                    showingImportCollection = true
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        
        MenuBarExtra("PostKit", systemImage: "network") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(sharedModelContainer)
        
        // Settings window
        Settings {
            SettingsView()
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
        let exporter = Container.shared.fileExporter()
        let context = sharedModelContainer.mainContext
        _ = try exporter.importCollection(from: url, into: context)
    }

    // MARK: - Command Palette

    private func showCommandPalette() {
        let context = sharedModelContainer.mainContext
        commandPaletteViewModel = CommandPaletteViewModel(modelContext: context)
        commandPaletteViewModel?.show()
        showingCommandPalette = true
    }

    private func handleCommandPaletteSelection(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let selection = userInfo["selection"] as? SidebarSelection else { return }

        // Post to the main window to handle selection
        NotificationCenter.default.post(
            name: .sidebarSelectionChange,
            object: nil,
            userInfo: ["selection": selection]
        )
    }

    private func handleCommandPaletteAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let action = userInfo["action"] as? CommandPaletteAction else { return }

        switch action {
        case .newRequest:
            curlImportCollection = fetchOrCreateImportCollection()
        case .newCollection:
            // Create a new collection - this would need UI handling
            // For now, just close the palette
            showingCommandPalette = false
        case .importCurl:
            curlImportCollection = fetchOrCreateImportCollection()
        case .importOpenAPI:
            showingOpenAPIImport = true
        case .importPostman:
            showingPostmanImport = true
        }
    }
}

// MARK: - Sidebar Selection Notification

extension Notification.Name {
    static let sidebarSelectionChange = Notification.Name("sidebarSelectionChange")
}
