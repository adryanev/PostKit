import FactoryKit

extension Container {
    var curlParser: Factory<CurlParserProtocol> {
        self { CurlParser() }
    }

    var openAPIParser: Factory<OpenAPIParserProtocol> {
        self { OpenAPIParser() }
    }

    var variableInterpolator: Factory<VariableInterpolatorProtocol> {
        self { VariableInterpolator() }.singleton
    }
}
