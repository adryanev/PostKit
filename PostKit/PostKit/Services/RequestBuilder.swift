import Foundation
import FactoryKit
import SwiftData

/// Shared request-building logic used by both RequestViewModel and MenuBarView.
/// Accepts pre-fetched environment variables so callers can supply overrides
/// (e.g. after pre-request scripts modify the variables map).
final class RequestBuilder: Sendable {

    @Injected(\.variableInterpolator) private var interpolator

    // MARK: - Build URLRequest

    /// Builds a `URLRequest` from an `HTTPRequest` model.
    ///
    /// - Parameters:
    ///   - request: The SwiftData model describing the request.
    ///   - variables: Environment variables used for `{{…}}` interpolation.
    ///   - urlOverride: Optional URL that replaces `request.urlTemplate` (used by script overrides).
    ///   - bodyOverride: Optional body that replaces `request.bodyContent` (used by script overrides).
    /// - Returns: A fully-interpolated `URLRequest`.
    func buildURLRequest(
        for request: HTTPRequest,
        with variables: [String: String],
        urlOverride: String? = nil,
        bodyOverride: String?? = nil
    ) throws -> URLRequest {
        let effectiveURL = urlOverride ?? request.urlTemplate
        let interpolatedURL = try interpolator.interpolate(effectiveURL, with: variables)

        var urlComponents = URLComponents(string: interpolatedURL)

        let queryParams = [KeyValuePair].decode(from: request.queryParamsData)
        var queryItems = urlComponents?.queryItems ?? []

        for param in queryParams where param.isEnabled {
            let interpolatedKey = try interpolator.interpolate(param.key, with: variables)
            let interpolatedValue = try interpolator.interpolate(param.value, with: variables)
            queryItems.append(URLQueryItem(name: interpolatedKey, value: interpolatedValue))
        }

        let authConfig = request.authConfig
        if authConfig.type == .apiKey,
           authConfig.apiKeyLocation == .queryParam,
           let name = authConfig.apiKeyName,
           let value = authConfig.apiKeyValue {
            queryItems.append(URLQueryItem(name: name, value: value))
        }

        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw HTTPClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = 30

        let headers = [KeyValuePair].decode(from: request.headersData)
        for header in headers where header.isEnabled {
            let interpolatedKey = try interpolator.interpolate(header.key, with: variables)
            let interpolatedValue = try interpolator.interpolate(header.value, with: variables)
            urlRequest.setValue(interpolatedValue, forHTTPHeaderField: interpolatedKey)
        }

        let effectiveBody: String? = bodyOverride ?? request.bodyContent
        if let bodyContent = effectiveBody, !bodyContent.isEmpty {
            let interpolatedBody = try interpolator.interpolate(bodyContent, with: variables)
            switch request.bodyType {
            case .json, .raw, .xml:
                urlRequest.httpBody = interpolatedBody.data(using: .utf8)
            case .urlEncoded:
                urlRequest.httpBody = interpolatedBody.data(using: .utf8)
            case .formData, .none:
                break
            }

            if let contentType = request.bodyType.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        applyAuth(&urlRequest, authConfig: authConfig)

        return urlRequest
    }

    // MARK: - Auth

    /// Applies authentication headers/query-params to the request.
    func applyAuth(_ urlRequest: inout URLRequest, authConfig: AuthConfig) {
        switch authConfig.type {
        case .bearer:
            if let token = authConfig.token {
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            if let username = authConfig.username,
               let password = authConfig.password {
                let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
                urlRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
            }
        case .apiKey:
            if let name = authConfig.apiKeyName,
               let value = authConfig.apiKeyValue {
                if authConfig.apiKeyLocation == .header {
                    urlRequest.setValue(value, forHTTPHeaderField: name)
                }
            }
        case .none:
            break
        }
    }

    // MARK: - Environment Variables

    /// Fetches active environment variables from the given `ModelContext`.
    func getActiveEnvironmentVariables(from modelContext: ModelContext) -> [String: String] {
        var variables: [String: String] = [:]

        let descriptor = FetchDescriptor<APIEnvironment>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            guard let activeEnv = try modelContext.fetch(descriptor).first else {
                return variables
            }
            for variable in activeEnv.variables where variable.isEnabled {
                variables[variable.key] = variable.secureValue
            }
        } catch {
            print("[PostKit] Failed to fetch active environment: \(error)")
        }

        return variables
    }
}
