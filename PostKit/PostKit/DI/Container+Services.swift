import Foundation
import FactoryKit
import os

extension Container {
    nonisolated var httpClient: Factory<HTTPClientProtocol> {
        self {
            do {
                return try CurlHTTPClient()
            } catch {
                let logger = OSLog(subsystem: "dev.adryanev.PostKit", category: "Container")
                os_log(.error, log: logger, "CurlHTTPClient init failed, falling back to URLSession: %{public}@", error.localizedDescription)
                return URLSessionHTTPClient()
            }
        }.singleton
    }

    nonisolated var keychainManager: Factory<KeychainManagerProtocol> {
        self { KeychainManager.shared }.singleton
    }

    @MainActor
    var fileExporter: Factory<FileExporterProtocol> {
        self { @MainActor in FileExporter() }
            .scope(.singleton)
    }
    
    nonisolated var scriptEngine: Factory<ScriptEngineProtocol> {
        self { JavaScriptEngine() }
    }
    
    nonisolated var spotlightIndexer: Factory<SpotlightIndexerProtocol> {
        self { SpotlightIndexer.shared }.singleton
    }
}
