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
        let allVariables = variables

        // Build path variable lookup from request's pathVariablesData
        let pathVariables = [KeyValuePair].decode(from: request.pathVariablesData)
        var pathVarLookup: [String: String] = [:]
        for pathVar in pathVariables where pathVar.isEnabled && !pathVar.key.isEmpty {
            pathVarLookup[pathVar.key] = pathVar.value
        }

        let effectiveURL = urlOverride ?? request.urlTemplate
        // First replace :varName path variables, then {{varName}} environment variables
        let pathInterpolated = interpolatePathVariables(effectiveURL, with: pathVarLookup)
        let interpolatedURL = try interpolator.interpolate(pathInterpolated, with: allVariables)

        var urlComponents = URLComponents(string: interpolatedURL)

        let queryParams = [KeyValuePair].decode(from: request.queryParamsData)
        var queryItems = urlComponents?.queryItems ?? []

        for param in queryParams where param.isEnabled {
            let interpolatedKey = try interpolator.interpolate(param.key, with: allVariables)
            let interpolatedValue = try interpolator.interpolate(param.value, with: allVariables)
            queryItems.append(URLQueryItem(name: interpolatedKey, value: interpolatedValue))
        }

        let authConfig = request.authConfig
        if authConfig.type == .apiKey,
           authConfig.apiKeyLocation == .queryParam,
           let name = authConfig.apiKeyName,
           let value = authConfig.apiKeyValue {
            let resolved = (try? interpolator.interpolate(value, with: allVariables)) ?? value
            queryItems.append(URLQueryItem(name: name, value: resolved))
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
            let interpolatedKey = try interpolator.interpolate(header.key, with: allVariables)
            let interpolatedValue = try interpolator.interpolate(header.value, with: allVariables)
            urlRequest.setValue(interpolatedValue, forHTTPHeaderField: interpolatedKey)
        }

        let effectiveBody: String? = bodyOverride ?? request.bodyContent
        if let bodyContent = effectiveBody, !bodyContent.isEmpty {
            let interpolatedBody = try interpolator.interpolate(bodyContent, with: allVariables)
            switch request.bodyType {
            case .json, .raw, .xml:
                urlRequest.httpBody = interpolatedBody.data(using: .utf8)
            case .urlEncoded, .formData:
                urlRequest.httpBody = interpolatedBody.data(using: .utf8)
            case .none:
                break
            }

            if let contentType = request.bodyType.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        applyAuth(&urlRequest, authConfig: authConfig, variables: allVariables)

        return urlRequest
    }

    // MARK: - Auth

    func applyAuth(_ urlRequest: inout URLRequest, authConfig: AuthConfig, variables: [String: String] = [:]) {
        switch authConfig.type {
        case .bearer:
            if let token = authConfig.token {
                let resolved = (try? interpolator.interpolate(token, with: variables)) ?? token
                urlRequest.setValue("Bearer \(resolved)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            if let username = authConfig.username,
               let password = authConfig.password {
                let resolvedUser = (try? interpolator.interpolate(username, with: variables)) ?? username
                let resolvedPass = (try? interpolator.interpolate(password, with: variables)) ?? password
                let credentials = Data("\(resolvedUser):\(resolvedPass)".utf8).base64EncodedString()
                urlRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
            }
        case .apiKey:
            if let name = authConfig.apiKeyName,
               let value = authConfig.apiKeyValue {
                let resolved = (try? interpolator.interpolate(value, with: variables)) ?? value
                if authConfig.apiKeyLocation == .header {
                    urlRequest.setValue(resolved, forHTTPHeaderField: name)
                }
            }
        case .none:
            break
        }
    }

    // MARK: - Path Variable Interpolation

    /// Replaces `:varName` path variable tokens in a URL with their values.
    /// Only matches `:varName` after a `/` to avoid false positives (e.g. port numbers in `http://host:8080`).
    private func interpolatePathVariables(_ template: String, with pathVars: [String: String]) -> String {
        guard !pathVars.isEmpty else { return template }

        var result = template
        for (key, value) in pathVars {
            // Match /:key followed by end-of-string, /, or ?
            let pattern = "/:\(NSRegularExpression.escapedPattern(for: key))(?=[/?]|$)"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "/\(NSRegularExpression.escapedTemplate(for: value))")
            }
        }
        return result
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
