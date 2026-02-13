import SwiftUI

/// The sole HTTPClient instance used throughout the app.
/// Views access it via @Environment(\.httpClient). No additional
/// instantiation is needed in PostKitApp or elsewhere.
private struct HTTPClientKey: EnvironmentKey {
    static let defaultValue: HTTPClientProtocol = URLSessionHTTPClient()
}

extension EnvironmentValues {
    var httpClient: HTTPClientProtocol {
        get { self[HTTPClientKey.self] }
        set { self[HTTPClientKey.self] = newValue }
    }
}
