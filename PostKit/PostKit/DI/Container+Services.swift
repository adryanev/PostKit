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

    nonisolated var requestBuilder: Factory<RequestBuilderProtocol> {
        self { RequestBuilder() }
    }

    nonisolated var codeGenerator: Factory<CodeGenerator> {
        self { CodeGenerator() }
    }

    // MARK: - Chain Services

    nonisolated var responseExtractor: Factory<ResponseExtractorProtocol> {
        self { ResponseExtractor() }
    }

    nonisolated var chainExecutor: Factory<ChainExecutorService> {
        self { ChainExecutorService() }
    }

    // MARK: - Mock Server Services

    @MainActor
    var mockServerManager: Factory<MockServerManager> {
        self { @MainActor in MockServerManager() }.scope(.singleton)
    }
}
