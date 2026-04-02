import Testing
import Foundation
import SwiftData
@testable import PostKit

// MARK: - OpenAPI Importer Tests

@MainActor
struct OpenAPIImporterTests {

    private func createModelContainer() throws -> ModelContainer {
        let schema = Schema([
            RequestCollection.self, Folder.self, HTTPRequest.self,
            APIEnvironment.self, Variable.self, HistoryEntry.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func createSpec(
        servers: [OpenAPIServer] = [],
        endpoints: [OpenAPIEndpoint] = [],
        securitySchemes: [OpenAPISecurityScheme] = []
    ) -> OpenAPISpec {
        OpenAPISpec(
            info: OpenAPIInfo(title: "Test API", version: "1.0.0", description: nil),
            servers: servers,
            endpoints: endpoints,
            securitySchemes: securitySchemes,
            refSkipCount: 0
        )
    }

    // MARK: - importNewCollection Tests

    @Test func importCreatesOneEnvironmentPerServer() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [
                OpenAPIServer(url: "https://api.prod.example.com", description: "Production", variables: []),
                OpenAPIServer(url: "https://api.staging.example.com", description: "Staging", variables: [])
            ],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil)
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: spec.endpoints, into: context)

        #expect(collection.environments.count == 2)
        #expect(collection.environments.contains { $0.name == "Production" })
        #expect(collection.environments.contains { $0.name == "Staging" })
    }

    @Test func importSetsFirstEnvironmentActive() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [
                OpenAPIServer(url: "https://api.example.com/v1", description: nil, variables: []),
                OpenAPIServer(url: "https://api2.example.com/v1", description: nil, variables: [])
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let firstEnv = collection.environments.first { $0.openAPIServerURL == "https://api.example.com/v1" }
        let secondEnv = collection.environments.first { $0.openAPIServerURL == "https://api2.example.com/v1" }
        #expect(firstEnv?.isActive == true)
        #expect(secondEnv?.isActive == false)
    }

    @Test func importCreatesBaseUrlVariable() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [
                OpenAPIServer(url: "https://api.example.com/v1", description: "Prod", variables: [])
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let env = collection.environments.first!
        let baseUrlVar = env.variables.first { $0.key == "baseUrl" }
        #expect(baseUrlVar != nil)
        #expect(baseUrlVar?.value == "https://api.example.com/v1")
        #expect(baseUrlVar?.isSecret == false)
    }

    @Test func importStripsTrailingSlashFromBaseUrl() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [
                OpenAPIServer(url: "https://api.example.com/v1/", description: nil, variables: [])
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let baseUrlVar = collection.environments.first!.variables.first { $0.key == "baseUrl" }
        #expect(baseUrlVar?.value == "https://api.example.com/v1")
    }

    @Test func importConvertsServerURLTemplateVariables() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [
                OpenAPIServer(url: "https://{env}.api.example.com/v1", description: nil, variables: [
                    OpenAPIServerVariable(name: "env", defaultValue: "api", enumValues: nil, description: nil)
                ])
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let baseUrlVar = collection.environments.first!.variables.first { $0.key == "baseUrl" }
        #expect(baseUrlVar?.value == "https://{{env}}.api.example.com/v1")
    }

    @Test func importCreatesServerVariables() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [
                OpenAPIServer(url: "https://api.example.com:{port}/v1", description: nil, variables: [
                    OpenAPIServerVariable(name: "port", defaultValue: "443", enumValues: ["443", "8443"], description: nil)
                ])
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let env = collection.environments.first!
        let portVar = env.variables.first { $0.key == "port" }
        #expect(portVar != nil)
        #expect(portVar?.value == "443")
    }

    @Test func importCreatesBearerTokenVariable() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [OpenAPIServer(url: "https://api.example.com", description: nil, variables: [])],
            securitySchemes: [
                OpenAPISecurityScheme(name: "bearerAuth", type: .http(scheme: "bearer"))
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let bearerVar = collection.environments.first!.variables.first { $0.key == "bearerToken" }
        #expect(bearerVar != nil)
        #expect(bearerVar?.isSecret == true)
    }

    @Test func importCreatesBasicAuthVariables() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [OpenAPIServer(url: "https://api.example.com", description: nil, variables: [])],
            securitySchemes: [
                OpenAPISecurityScheme(name: "basicAuth", type: .http(scheme: "basic"))
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let env = collection.environments.first!
        let usernameVar = env.variables.first { $0.key == "basicUsername" }
        let passwordVar = env.variables.first { $0.key == "basicPassword" }

        #expect(usernameVar != nil)
        #expect(usernameVar?.isSecret == false)
        #expect(passwordVar != nil)
        #expect(passwordVar?.isSecret == true)
    }

    @Test func importCreatesApiKeyVariable() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [OpenAPIServer(url: "https://api.example.com", description: nil, variables: [])],
            securitySchemes: [
                OpenAPISecurityScheme(name: "apiKey", type: .apiKey(name: "X-API-Key", location: "header"))
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let apiKeyVar = collection.environments.first!.variables.first { $0.key == "apiKeyValue" }
        #expect(apiKeyVar != nil)
        #expect(apiKeyVar?.isSecret == true)
    }

    @Test func importSetsAuthConfigTemplates() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [OpenAPIServer(url: "https://api.example.com", description: nil, variables: [])],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: ["bearerAuth"])
            ],
            securitySchemes: [
                OpenAPISecurityScheme(name: "bearerAuth", type: .http(scheme: "bearer"))
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: spec.endpoints, into: context)

        let request = collection.requests.first!
        #expect(request.authConfig.type == .bearer)
        #expect(request.authConfig.token == "{{bearerToken}}")
    }

    @Test func importRequestsUseBaseUrlVariable() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [OpenAPIServer(url: "https://api.example.com/v1", description: nil, variables: [])],
            endpoints: [
                OpenAPIEndpoint(name: "Get Users", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil)
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: spec.endpoints, into: context)

        let request = collection.requests.first!
        #expect(request.urlTemplate == "{{baseUrl}}/users")
    }

    @Test func importZeroServersCreatesFallbackEnvironment() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(servers: [], endpoints: [
            OpenAPIEndpoint(name: "Get Users", method: .get, path: "/users", parameters: [], requestBody: nil, tags: [], operationId: nil, description: nil, security: nil)
        ])

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: spec.endpoints, into: context)

        #expect(collection.environments.count == 1)
        #expect(collection.environments.first?.isActive == true)

        let baseUrlVar = collection.environments.first?.variables.first { $0.key == "baseUrl" }
        #expect(baseUrlVar?.value == "")
    }

    @Test func importMultipleSecuritySchemes() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [OpenAPIServer(url: "https://api.example.com", description: nil, variables: [])],
            securitySchemes: [
                OpenAPISecurityScheme(name: "bearerAuth", type: .http(scheme: "bearer")),
                OpenAPISecurityScheme(name: "apiKey", type: .apiKey(name: "X-API-Key", location: "header"))
            ]
        )

        let importer = OpenAPIImporter()
        let collection = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let env = collection.environments.first!
        #expect(env.variables.contains { $0.key == "bearerToken" })
        #expect(env.variables.contains { $0.key == "apiKeyValue" })
    }

    @Test func contextInsertIsCalledForAllVariables() throws {
        let container = try createModelContainer()
        let context = container.mainContext

        let spec = createSpec(
            servers: [
                OpenAPIServer(url: "https://api.example.com:{port}", description: nil, variables: [
                    OpenAPIServerVariable(name: "port", defaultValue: "443", enumValues: nil, description: nil)
                ])
            ],
            securitySchemes: [
                OpenAPISecurityScheme(name: "bearerAuth", type: .http(scheme: "bearer"))
            ]
        )

        let importer = OpenAPIImporter()
        _ = try importer.importNewCollection(spec: spec, selectedEndpoints: [], into: context)

        let descriptor = FetchDescriptor<Variable>()
        let variables = try context.fetch(descriptor)

        #expect(variables.count == 3)
        #expect(variables.contains { $0.key == "baseUrl" })
        #expect(variables.contains { $0.key == "port" })
        #expect(variables.contains { $0.key == "bearerToken" })
    }
}
