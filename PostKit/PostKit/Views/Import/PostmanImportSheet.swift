import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PostmanImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var fileURL: URL?
    @State private var preview: PostmanImportPreview?
    @State private var parseError: String?
    @State private var isLoading = false
    
    private let importer = PostmanImporter()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Import Postman Collection")
                .font(.headline)
            
            if let url = fileURL {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Text(url.path())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") {
                        selectFile()
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button {
                    selectFile()
                } label: {
                    Label("Select Postman Collection File", systemImage: "doc.text")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            if isLoading {
                ProgressView("Parsing...")
            }
            
            if let error = parseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            if let preview = preview {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(preview.collectionName)
                            .font(.headline)
                    }
                    
                    Divider()
                    
                    HStack(spacing: 24) {
                        Label("\(preview.requestCount) requests", systemImage: "network")
                            .foregroundStyle(.secondary)
                        Label("\(preview.folderCount) folders", systemImage: "folder")
                            .foregroundStyle(.secondary)
                        Label("\(preview.variableCount) variables", systemImage: "variable")
                            .foregroundStyle(.secondary)
                    }
                    
                    if preview.scriptCount > 0 {
                        Label("\(preview.scriptCount) requests have scripts (will be runnable after scripting feature ships)", systemImage: "applescript")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Import") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            loadFile(at: url)
        }
    }
    
    private func loadFile(at url: URL) {
        fileURL = url
        isLoading = true
        parseError = nil
        preview = nil
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                let previewResult = try await Task.detached(priority: .userInitiated) {
                    try self.importer.previewCollection(from: data)
                }.value
                
                await MainActor.run {
                    self.preview = previewResult
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.parseError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performImport() {
        guard let url = fileURL else { return }
        
        isLoading = true
        parseError = nil
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                let _ = try importer.importCollection(from: data, into: modelContext)
                
                await MainActor.run {
                    self.isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.parseError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

struct PostmanEnvironmentImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let collection: RequestCollection
    
    @State private var fileURL: URL?
    @State private var environmentName: String?
    @State private var variables: [PostmanVariable] = []
    @State private var secretKeys: Set<String> = []
    @State private var parseError: String?
    @State private var isLoading = false
    
    private let importer = PostmanImporter()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Import Postman Environment")
                .font(.headline)
            
            if let url = fileURL {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Text(url.path())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") {
                        selectFile()
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button {
                    selectFile()
                } label: {
                    Label("Select Postman Environment File", systemImage: "doc.text")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            if isLoading {
                ProgressView("Parsing...")
            }
            
            if let error = parseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            
            if !variables.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Secret Variables")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("Secret variables will be stored in macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(variables, id: \.key) { variable in
                                HStack {
                                    Toggle("", isOn: Binding(
                                        get: { secretKeys.contains(variable.key) },
                                        set: { isSecret in
                                            if isSecret {
                                                secretKeys.insert(variable.key)
                                            } else {
                                                secretKeys.remove(variable.key)
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    
                                    Text(variable.key)
                                        .fontWeight(.medium)
                                    
                                    Spacer()
                                    
                                    if variable.type == "secret" {
                                        Text("(marked as secret)")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Import") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(variables.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            loadFile(at: url)
        }
    }
    
    private func loadFile(at url: URL) {
        fileURL = url
        isLoading = true
        parseError = nil
        variables = []
        secretKeys = []
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                let parser = PostmanParser()
                let env = try parser.parseEnvironment(data)
                
                await MainActor.run {
                    self.environmentName = env.name
                    self.variables = env.values
                    self.secretKeys = Set(env.values.filter { $0.type == "secret" }.map { $0.key })
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.parseError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performImport() {
        guard let url = fileURL else { return }
        
        isLoading = true
        parseError = nil
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                let _ = try importer.importEnvironment(
                    from: data,
                    into: modelContext,
                    collection: collection,
                    secretKeys: secretKeys
                )
                
                await MainActor.run {
                    self.isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.parseError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    PostmanImportSheet()
        .modelContainer(for: RequestCollection.self, inMemory: true)
}
