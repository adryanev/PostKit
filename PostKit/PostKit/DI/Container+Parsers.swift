import FactoryKit

extension Container {
    nonisolated var curlParser: Factory<CurlParserProtocol> {
        self { CurlParser() }
    }

    nonisolated var openAPIParser: Factory<OpenAPIParserProtocol> {
        self { OpenAPIParser() }
    }

    nonisolated var postmanParser: Factory<PostmanParserProtocol> {
        self { PostmanParser() }
    }

    nonisolated var variableInterpolator: Factory<VariableInterpolatorProtocol> {
        self { VariableInterpolator() }.singleton
    }
}
