import Foundation
import FactoryKit
import os

private let log = OSLog(subsystem: "dev.adryanev.PostKit", category: "Container")

extension Container {
    var httpClient: Factory<HTTPClientProtocol> {
        self {
            do {
                return try CurlHTTPClient()
            } catch {
                os_log(.error, log: log, "CurlHTTPClient init failed, falling back to URLSession: %{public}@", error.localizedDescription)
                return URLSessionHTTPClient()
            }
        }.singleton
    }

    var keychainManager: Factory<KeychainManagerProtocol> {
        self { KeychainManager.shared }.singleton
    }

    @MainActor
    var fileExporter: Factory<FileExporterProtocol> {
        self { @MainActor in FileExporter() }
    }
}
