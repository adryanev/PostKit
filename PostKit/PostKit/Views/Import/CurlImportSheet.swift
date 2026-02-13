import SwiftUI
import SwiftData

struct CurlImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let collection: RequestCollection?
    
    @State private var curlCommand = ""
    @State private var parseError: String?
    @State private var parsedPreview: ParsedRequest?
    
    private let parser = CurlParser()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Import cURL Command")
                .font(.headline)
            
            TextEditor(text: $curlCommand)
                .font(.system(.body, design: .monospaced))
                .frame(height: 150)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: curlCommand) { _, _ in
                    parseCurlCommand()
                }
            
            if let error = parseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            
            if let preview = parsedPreview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(preview.method.rawValue)
                            .fontWeight(.semibold)
                            .foregroundStyle(methodColor(for: preview.method))
                        Text(preview.url)
                            .lineLimit(1)
                    }
                    
                    if !preview.headers.isEmpty {
                        Text("\(preview.headers.count) headers")
                            .foregroundStyle(.secondary)
                    }
                    
                    if let body = preview.body {
                        Text("Body: \(body.count) characters")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Paste from Clipboard") {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        curlCommand = clipboard
                    }
                }
                
                Button("Import") {
                    importRequest()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedPreview == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500)
    }
    
    private func parseCurlCommand() {
        parseError = nil
        parsedPreview = nil
        
        guard !curlCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        do {
            parsedPreview = try parser.parse(curlCommand)
        } catch {
            parseError = error.localizedDescription
        }
    }
    
    private func importRequest() {
        guard let parsed = parsedPreview else { return }
        
        let request = HTTPRequest(name: "Imported Request", method: parsed.method, url: parsed.url)
        request.headersData = parsed.headers.encode()
        request.bodyContent = parsed.body
        request.bodyType = parsed.bodyType
        
        if let auth = parsed.authConfig {
            request.authConfig = auth
        }
        
        if let collection = collection {
            request.collection = collection
            request.sortOrder = collection.requests.count
        }
        
        modelContext.insert(request)
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
    CurlImportSheet(collection: nil)
}
