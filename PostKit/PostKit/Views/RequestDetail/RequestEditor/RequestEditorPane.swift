import SwiftUI

struct RequestEditorPane: View {
    @Bindable var request: HTTPRequest
    @State private var selectedTab: EditorTab = .params
    
    enum EditorTab: String, CaseIterable {
        case params = "Params"
        case headers = "Headers"
        case body = "Body"
        case auth = "Auth"
        case preRequest = "Pre-req"
        case postRequest = "Post-req"
    }
    
    private var detectedPathVariables: [String] {
        let pattern = #"\{\{([^}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(request.urlTemplate.startIndex..., in: request.urlTemplate)
        let matches = regex.matches(in: request.urlTemplate, range: range)
        return matches.compactMap { match in
            if match.numberOfRanges > 1,
               let varRange = Range(match.range(at: 1), in: request.urlTemplate) {
                return String(request.urlTemplate[varRange])
            }
            return nil
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Editor Tab", selection: $selectedTab) {
                ForEach(EditorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
            
            Divider()

            switch selectedTab {
            case .params:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !detectedPathVariables.isEmpty {
                            PathVariablesEditor(
                                pathVariables: Binding(
                                    get: { [KeyValuePair].decode(from: request.pathVariablesData) },
                                    set: { request.pathVariablesData = $0.encode() }
                                ),
                                detectedVariables: detectedPathVariables
                            )
                            
                            Divider()
                        }
                        
                        QueryParamsEditor(
                            params: Binding(
                                get: { [KeyValuePair].decode(from: request.queryParamsData) },
                                set: { request.queryParamsData = $0.encode() }
                            )
                        )
                    }
                    .padding(12)
                }
            case .headers:
                ScrollView {
                    HeadersEditor(
                        headers: Binding(
                            get: { [KeyValuePair].decode(from: request.headersData) },
                            set: { request.headersData = $0.encode() }
                        )
                    )
                }
            case .body:
                BodyEditor(
                    bodyType: $request.bodyType,
                    bodyContent: $request.bodyContent
                )
            case .auth:
                ScrollView {
                    AuthEditor(authConfig: $request.authConfig)
                }
            case .preRequest:
                ScriptEditor(
                    title: "Pre-request Script",
                    description: "This script runs before the request is sent. Use pk.environment.get/set, pk.request.headers/method/url/body.",
                    script: Binding(
                        get: { request.preRequestScript ?? "" },
                        set: { request.preRequestScript = $0.isEmpty ? nil : $0 }
                    )
                )
            case .postRequest:
                ScriptEditor(
                    title: "Post-request Script",
                    description: "This script runs after the response is received. Use pk.response.code/headers/body/time, pk.environment.get/set.",
                    script: Binding(
                        get: { request.postRequestScript ?? "" },
                        set: { request.postRequestScript = $0.isEmpty ? nil : $0 }
                    )
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct QueryParamsEditor: View {
    @Binding var params: [KeyValuePair]
    
    var body: some View {
        KeyValueEditor(
            items: $params,
            placeholder: "Query parameter"
        )
    }
}

struct PathVariablesEditor: View {
    @Binding var pathVariables: [KeyValuePair]
    let detectedVariables: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Path Variables", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                Spacer()
            }
            
            Text("Variables detected in URL. Set values here to override environment variables.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 4) {
                HStack {
                    Text("Key")
                        .frame(width: 150, alignment: .leading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Value")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("")
                        .frame(width: 60)
                }
                .padding(.horizontal, 8)
                
                ForEach(detectedVariables, id: \.self) { varName in
                    PathVariableRow(
                        varName: varName,
                        pathVariables: $pathVariables
                    )
                }
            }
        }
    }
}

struct PathVariableRow: View {
    let varName: String
    @Binding var pathVariables: [KeyValuePair]
    
    private var binding: Binding<String> {
        Binding(
            get: {
                pathVariables.first { $0.key == varName }?.value ?? ""
            },
            set: { newValue in
                if let index = pathVariables.firstIndex(where: { $0.key == varName }) {
                    pathVariables[index].value = newValue
                } else {
                    let newVar = KeyValuePair(key: varName, value: newValue, isEnabled: true)
                    pathVariables.append(newVar)
                }
            }
        )
    }
    
    var body: some View {
        HStack {
            Text("{{\(varName)}}")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 150, alignment: .leading)
                .padding(.horizontal, 8)
            
            TextField("Value", text: binding)
                .textFieldStyle(.roundedBorder)
            
            Spacer()
                .frame(width: 30)
        }
    }
}

struct HeadersEditor: View {
    @Binding var headers: [KeyValuePair]
    
    var body: some View {
        KeyValueEditor(
            items: $headers,
            placeholder: "Header"
        )
        .padding(12)
    }
}

struct KeyValueEditor: View {
    @Binding var items: [KeyValuePair]
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(placeholder)
                    .font(.headline)
                Spacer()
                Button("Add") {
                    items.append(KeyValuePair())
                }
                .buttonStyle(.bordered)
            }
            
            if items.isEmpty {
                ContentUnavailableView(
                    "No \(placeholder)s",
                    systemImage: "list.bullet",
                    description: Text("Click Add to create a new \(placeholder.lowercased())")
                )
                .frame(height: 200)
            } else {
                VStack(spacing: 4) {
                    HStack {
                        Text("Key")
                            .frame(width: 150, alignment: .leading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Value")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("")
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 8)
                    
                    ForEach($items) { $item in
                        HStack {
                            Toggle("", isOn: $item.isEnabled)
                                .toggleStyle(.checkbox)
                                .frame(width: 20)
                            
                            TextField("Key", text: $item.key)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            
                            TextField("Value", text: $item.value)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: {
                                items.removeAll { $0.id == item.id }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 30)
                        }
                    }
                }
            }
        }
    }
}

struct BodyEditor: View {
    @Binding var bodyType: BodyType
    @Binding var bodyContent: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Body Type", selection: $bodyType) {
                ForEach(BodyType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            
            if bodyType != .none {
                CodeTextView(
                    text: Binding(
                        get: { bodyContent ?? "" },
                        set: { bodyContent = $0.isEmpty ? nil : $0 }
                    ),
                    language: bodyType.highlightrLanguage,
                    isEditable: true
                )
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            } else {
                ContentUnavailableView(
                    "No Body",
                    systemImage: "doc",
                    description: Text("Select a body type to add request content")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .padding(12)
    }
}

struct AuthEditor: View {
    @Binding var authConfig: AuthConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Auth Type", selection: $authConfig.type) {
                ForEach(AuthType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            
            Divider()
            
            switch authConfig.type {
            case .bearer:
                SecureField("Token", text: Binding(
                    get: { authConfig.token ?? "" },
                    set: { authConfig.token = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
            case .basic:
                TextField("Username", text: Binding(
                    get: { authConfig.username ?? "" },
                    set: { authConfig.username = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                SecureField("Password", text: Binding(
                    get: { authConfig.password ?? "" },
                    set: { authConfig.password = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
            case .apiKey:
                TextField("Key Name", text: Binding(
                    get: { authConfig.apiKeyName ?? "" },
                    set: { authConfig.apiKeyName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                SecureField("Key Value", text: Binding(
                    get: { authConfig.apiKeyValue ?? "" },
                    set: { authConfig.apiKeyValue = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                Picker("Add to", selection: Binding(
                    get: { authConfig.apiKeyLocation ?? .header },
                    set: { authConfig.apiKeyLocation = $0 }
                )) {
                    Text("Header").tag(AuthConfig.APIKeyLocation.header)
                    Text("Query Param").tag(AuthConfig.APIKeyLocation.queryParam)
                }
                .pickerStyle(.radioGroup)
                
            case .none:
                Text("No authentication will be sent with this request")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
    }
}

struct ScriptEditor: View {
    let title: String
    let description: String
    @Binding var script: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            CodeTextView(
                text: $script,
                language: "javascript",
                isEditable: true
            )
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(12)
    }
}

#Preview {
    RequestEditorPane(request: HTTPRequest(name: "Test", method: .post))
        .frame(width: 400, height: 500)
}
