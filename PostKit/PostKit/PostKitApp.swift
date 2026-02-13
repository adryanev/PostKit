//
//  PostKitApp.swift
//  PostKit
//
//  Created by Adryan Eka Vandra on 06/01/26.
//

import SwiftUI
import SwiftData

@main
struct PostKitApp: App {
    let httpClient: HTTPClientProtocol
    
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

    init() {
        self.httpClient = URLSessionHTTPClient()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .environment(\.httpClient, httpClient)
    }
}
