import Foundation
import JavaScriptCore

final class JavaScriptEngine: ScriptEngineProtocol, Sendable {
    private static let timeout: TimeInterval = 5.0
    
    private final class ExecutionContext {
        var consoleOutput: [String] = []
        var environmentChanges: [String: String] = [:]
    }
    
    func executePreRequest(
        script: String,
        request: ScriptRequest,
        environment: [String: String]
    ) async throws -> ScriptPreRequestResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executePreRequestSync(
                        script: script,
                        request: request,
                        environment: environment
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func executePostRequest(
        script: String,
        response: ScriptResponse,
        environment: [String: String]
    ) async throws -> ScriptPostRequestResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executePostRequestSync(
                        script: script,
                        response: response,
                        environment: environment
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func executePreRequestSync(
        script: String,
        request: ScriptRequest,
        environment: [String: String]
    ) throws -> ScriptPreRequestResult {
        let context = JSContext()!
        let executionContext = ExecutionContext()
        
        setupConsole(context: context, executionContext: executionContext)
        setupPKNamespace(
            context: context,
            environment: environment,
            executionContext: executionContext,
            request: request,
            response: nil
        )
        setupPMShim(context: context)
        
        _ = context.evaluateScript(script)
        
        if let exception = context.exception {
            context.exception = nil
            throw ScriptEngineError.runtimeError(exception.toString())
        }
        
        var modifiedHeaders: [String: String]?
        var modifiedURL: String?
        var modifiedBody: String?
        
        if let pk = context.objectForKeyedSubscript("pk"),
           let pkRequest = pk.objectForKeyedSubscript("request") {
            
            if let headersObj = pkRequest.objectForKeyedSubscript("headers"),
               headersObj.isObject {
                modifiedHeaders = extractHeaders(headersObj)
            }
            
            if let urlString = pkRequest.objectForKeyedSubscript("url").toString(),
               urlString != request.url {
                modifiedURL = urlString
            }
            
            if let bodyString = pkRequest.objectForKeyedSubscript("body").toString(),
               bodyString != (request.body ?? "") {
                modifiedBody = bodyString
            }
        }
        
        return ScriptPreRequestResult(
            modifiedHeaders: modifiedHeaders,
            modifiedURL: modifiedURL,
            modifiedBody: modifiedBody,
            environmentChanges: executionContext.environmentChanges,
            consoleOutput: executionContext.consoleOutput
        )
    }
    
    private func executePostRequestSync(
        script: String,
        response: ScriptResponse,
        environment: [String: String]
    ) throws -> ScriptPostRequestResult {
        let context = JSContext()!
        let executionContext = ExecutionContext()
        
        setupConsole(context: context, executionContext: executionContext)
        setupPKNamespace(
            context: context,
            environment: environment,
            executionContext: executionContext,
            request: nil,
            response: response
        )
        setupPMShim(context: context)
        
        _ = context.evaluateScript(script)
        
        if let exception = context.exception {
            context.exception = nil
            throw ScriptEngineError.runtimeError(exception.toString())
        }
        
        return ScriptPostRequestResult(
            environmentChanges: executionContext.environmentChanges,
            consoleOutput: executionContext.consoleOutput
        )
    }
    
    private func setupConsole(context: JSContext, executionContext: ExecutionContext) {
        let consoleLog: @convention(block) (String) -> Void = { message in
            executionContext.consoleOutput.append(message)
        }
        
        let console = JSValue(newObjectIn: context)
        console?.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }
    
    private func setupPKNamespace(
        context: JSContext,
        environment: [String: String],
        executionContext: ExecutionContext,
        request: ScriptRequest?,
        response: ScriptResponse?
    ) {
        let pk = JSValue(newObjectIn: context)
        
        let env = JSValue(newObjectIn: context)
        let envGet: @convention(block) (String) -> String? = { key in
            return environment[key]
        }
        let envSet: @convention(block) (String, String) -> Void = { key, value in
            executionContext.environmentChanges[key] = value
        }
        env?.setObject(envGet, forKeyedSubscript: "get" as NSString)
        env?.setObject(envSet, forKeyedSubscript: "set" as NSString)
        pk?.setObject(env, forKeyedSubscript: "environment" as NSString)
        
        let variables = JSValue(newObjectIn: context)
        let variablesGet: @convention(block) (String) -> String? = { key in
            return environment[key]
        }
        variables?.setObject(variablesGet, forKeyedSubscript: "get" as NSString)
        pk?.setObject(variables, forKeyedSubscript: "variables" as NSString)
        
        if let request = request {
            let pkRequest = JSValue(newObjectIn: context)
            pkRequest?.setObject(request.method, forKeyedSubscript: "method" as NSString)
            pkRequest?.setObject(request.url, forKeyedSubscript: "url" as NSString)
            pkRequest?.setObject(request.body ?? "", forKeyedSubscript: "body" as NSString)
            
            let headers = JSValue(newObjectIn: context)
            let headersGet: @convention(block) (String) -> String? = { key in
                return request.headers[key]
            }
            headers?.setObject(headersGet, forKeyedSubscript: "get" as NSString)
            pkRequest?.setObject(headers, forKeyedSubscript: "headers" as NSString)
            
            pk?.setObject(pkRequest, forKeyedSubscript: "request" as NSString)
        }
        
        if let response = response {
            let pkResponse = JSValue(newObjectIn: context)
            pkResponse?.setObject(response.statusCode, forKeyedSubscript: "code" as NSString)
            pkResponse?.setObject(response.duration * 1000, forKeyedSubscript: "responseTime" as NSString)
            
            let bodyText = response.body ?? ""
            let text: @convention(block) () -> String = { bodyText }
            pkResponse?.setObject(text, forKeyedSubscript: "text" as NSString)
            
            let json: @convention(block) () -> Any? = {
                guard let data = bodyText.data(using: .utf8),
                      let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
                    return nil
                }
                return jsonObject
            }
            pkResponse?.setObject(json, forKeyedSubscript: "json" as NSString)
            
            let headers = JSValue(newObjectIn: context)
            let headersGet: @convention(block) (String) -> String? = { key in
                return response.headers[key]
            }
            headers?.setObject(headersGet, forKeyedSubscript: "get" as NSString)
            pkResponse?.setObject(headers, forKeyedSubscript: "headers" as NSString)
            
            pk?.setObject(pkResponse, forKeyedSubscript: "response" as NSString)
        }
        
        context.setObject(pk, forKeyedSubscript: "pk" as NSString)
    }
    
    private func setupPMShim(context: JSContext) {
        context.evaluateScript("var pm = pk;")
    }
    
    private func extractHeaders(_ headersObj: JSValue) -> [String: String] {
        var headers: [String: String] = [:]
        guard let properties = headersObj.toDictionary() as? [String: Any] else {
            return headers
        }
        for (key, value) in properties {
            if let stringValue = value as? String {
                headers[key] = stringValue
            }
        }
        return headers
    }
}
