import SwiftUI

struct CodeGeneratorView: View {
    let request: HTTPRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage = "cURL"
    @State private var generatedCode: String = ""

    private let codeGenerator = CodeGenerator()
    private let availableLanguages = ["cURL", "Swift", "Python", "JavaScript", "Node.js", "Go"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate Code")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Language selector
            HStack {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(availableLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .frame(width: 150)

                Spacer()

                // Copy button
                Button(action: copyCode) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(generatedCode.isEmpty)

                // Save button
                Button(action: saveCode) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(generatedCode.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Code display
            ScrollView([.horizontal, .vertical]) {
                Text(generatedCode)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 800, height: 500)
        .onChange(of: selectedLanguage) { _, _ in
            generateCode()
        }
        .onAppear {
            generateCode()
        }
    }

    private func generateCode() {
        generatedCode = codeGenerator.generateCode(for: request, language: selectedLanguage) ?? ""
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedCode, forType: .string)
    }

    private func saveCode() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "request.\(codeGenerator.fileExtension(for: selectedLanguage) ?? "txt")"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? generatedCode.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

#Preview {
    CodeGeneratorView(request: HTTPRequest(name: "Get Users", method: .get, url: "https://api.example.com/users"))
}
