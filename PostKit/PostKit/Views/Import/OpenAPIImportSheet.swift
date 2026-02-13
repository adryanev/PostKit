import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct OpenAPIImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var fileURL: URL?
    @State private var parseError: String?
    @State private var openAPIInfo: OpenAPIInfo?
    @State private var endpoints: [OpenAPIEndpoint] = []
    @State private var servers: [String] = []
    @State private var selectedServer: String?
    @State private var selectedEndpoints: Set<String> = []
    @State private var isImporting = false
    
    private let parser = OpenAPIParser()
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Import OpenAPI Specification")
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                if let url = fileURL {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Change") {
                        selectFile()
                    }
                } else {
                    Button("Select File (JSON)") {
                        selectFile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            if let error = parseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            
            if let info = openAPIInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.title)
                        .font(.headline)
                    Text("Version: \(info.version)")
                        .foregroundStyle(.secondary)
                    if let description = info.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            if !servers.isEmpty {
                Picker("Server", selection: $selectedServer) {
                    ForEach(servers, id: \.self) { server in
                        Text(server).tag(Optional(server))
                    }
                }
                .frame(width: 300)
            }
            
            if !endpoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Endpoints (\(selectedEndpoints.count)/\(endpoints.count) selected)")
                        Spacer()
                        Button(selectedEndpoints.count == endpoints.count ? "Deselect All" : "Select All") {
                            if selectedEndpoints.count == endpoints.count {
                                selectedEndpoints.removeAll()
                            } else {
                                selectedEndpoints = Set(endpoints.map { $0.name + $0.path + $0.method.rawValue })
                            }
                        }
                    }
                    
                    List {
                        ForEach(endpoints, id: \.name) { endpoint in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { selectedEndpoints.contains(endpoint.name + endpoint.path + endpoint.method.rawValue) },
                                    set: { isSelected in
                                        let key = endpoint.name + endpoint.path + endpoint.method.rawValue
                                        if isSelected {
                                            selectedEndpoints.insert(key)
                                        } else {
                                            selectedEndpoints.remove(key)
                                        }
                                    }
                                ))
                                
                                Text(endpoint.method.rawValue)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(methodColor(for: endpoint.method))
                                    .frame(width: 60)
                                
                                Text(endpoint.path)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(endpoint.name)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .tag(endpoint.name + endpoint.path + endpoint.method.rawValue)
                        }
                    }
                }
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Import") {
                    importEndpoints()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedEndpoints.isEmpty || isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            self.fileURL = url
            parseFile()
        }
    }
    
    private func parseFile() {
        parseError = nil
        openAPIInfo = nil
        endpoints = []
        servers = []
        
        guard let url = fileURL else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let result = try parser.parse(data)
            openAPIInfo = result.info
            endpoints = result.endpoints
            servers = result.servers
            selectedServer = result.servers.first
            
            selectedEndpoints = Set(endpoints.map { $0.name + $0.path + $0.method.rawValue })
        } catch {
            parseError = error.localizedDescription
        }
    }
    
    private func importEndpoints() {
        isImporting = true
        
        let collection = RequestCollection(name: openAPIInfo?.title ?? "Imported API")
        modelContext.insert(collection)
        
        for endpoint in endpoints where selectedEndpoints.contains(endpoint.name + endpoint.path + endpoint.method.rawValue) {
            var urlString = endpoint.path
            if let server = selectedServer {
                urlString = server + endpoint.path
            }
            
            let request = HTTPRequest(name: endpoint.name, method: endpoint.method, url: urlString)
            
            var headers: [KeyValuePair] = []
            for param in endpoint.parameters where param.location == "header" {
                headers.append(KeyValuePair(key: param.name, value: ""))
            }
            request.headersData = headers.encode()
            
            if let body = endpoint.requestBody {
                request.bodyType = body.contentType.contains("json") ? .json : .raw
            }
            
            request.collection = collection
            request.sortOrder = collection.requests.count
            modelContext.insert(request)
        }
        
        dismiss()
    }
    
    private func methodColor(for method: HTTPMethod) -> Color {
        switch method {
        case .get: .green
        case .post: .orange
        case .put: .blue
        case .patch: .purple
        case .delete: .red
        case .head, .options: .gray
        }
    }
}

#Preview {
    OpenAPIImportSheet()
}
