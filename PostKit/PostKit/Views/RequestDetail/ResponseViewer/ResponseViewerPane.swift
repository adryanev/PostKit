import SwiftUI
import SwiftData

private extension Int64 {
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

struct ResponseViewerPane: View {
    let response: HTTPResponse?
    let error: Error?
    @Binding var activeTab: ResponseTab
    let isLoading: Bool
    let request: HTTPRequest?
    let consoleOutput: [String]
    var onClearConsole: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Sending request...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                ErrorView(error: error)
            } else if let response = response {
                ResponseContentView(
                    response: response,
                    activeTab: $activeTab,
                    request: request,
                    consoleOutput: consoleOutput,
                    onClearConsole: onClearConsole
                )
            } else {
                EmptyResponseView()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ResponseContentView: View {
    let response: HTTPResponse
    @Binding var activeTab: ResponseTab
    let request: HTTPRequest?
    let consoleOutput: [String]
    var onClearConsole: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @State private var showingSaveExample = false
    @State private var exampleName = ""
    @State private var saveError: String?
    @State private var showingSaveError = false
    
    var body: some View {
        VStack(spacing: 0) {
            ResponseStatusBar(response: response)
            Divider()
            
            ZStack {
                ResponseBodyView(response: response, onSaveAsExample: {
                    showingSaveExample = true
                    exampleName = "\(response.statusCode) \(defaultExampleName)"
                })
                .opacity(activeTab == .body ? 1 : 0)
                .allowsHitTesting(activeTab == .body)
                
                ScrollView {
                    ResponseHeadersView(headers: response.headers)
                }
                .opacity(activeTab == .headers ? 1 : 0)
                .allowsHitTesting(activeTab == .headers)
                
                ScrollView {
                    ResponseTimingView(duration: response.duration, size: response.size, timingBreakdown: response.timingBreakdown)
                }
                .opacity(activeTab == .timing ? 1 : 0)
                .allowsHitTesting(activeTab == .timing)
                
                ScrollView {
                    ConsoleTabView(output: consoleOutput, onClear: onClearConsole)
                }
                .opacity(activeTab == .console ? 1 : 0)
                .allowsHitTesting(activeTab == .console)
                
                ScrollView {
                    ExamplesTabView(request: request)
                }
                .opacity(activeTab == .examples ? 1 : 0)
                .allowsHitTesting(activeTab == .examples)
            }
        }
        .alert("Save as Example", isPresented: $showingSaveExample) {
            TextField("Name", text: $exampleName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                saveExample()
            }
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = saveError {
                Text(error)
            }
        }
    }
    
    private var defaultExampleName: String {
        guard let req = request else { return "Request" }
        let method = req.method.rawValue.uppercased()
        let path = URL(string: req.urlTemplate)?.path ?? req.urlTemplate
        return "\(method) \(path)"
    }
    
    private func saveExample() {
        guard let request = request else { return }

        do {
            let bodyData = try response.getBodyData()

            if bodyData.count > ResponseExample.maxExampleBodySize {
                saveError = "Response too large to save as example (max 10MB)"
                showingSaveError = true
                return
            }

            let bodyString = String(data: bodyData, encoding: .utf8)

            let example = ResponseExample(
                name: exampleName,
                statusCode: response.statusCode,
                contentType: response.contentType,
                body: bodyString
            )

            let headers = response.headers.map { KeyValuePair(key: $0.key, value: $0.value, isEnabled: true) }
            example.headersData = headers.encode()
            example.request = request

            modelContext.insert(example)
            try modelContext.save()

            saveError = nil
        } catch {
            saveError = error.localizedDescription
            showingSaveError = true
        }
    }
}

struct ResponseBodyView: View {
    let response: HTTPResponse
    let onSaveAsExample: (() -> Void)?
    @State private var showRaw = false
    @State private var bodyData: Data?
    @State private var loadError: String?
    @State private var cachedDisplayString: String = ""
    @State private var detectedLanguage: String?
    
    private let maxDisplaySize: Int64 = 10_000_000
    private let prettyPrintThreshold: Int = 524_288
    
    private var isJSON: Bool {
        response.contentType == "application/json"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if response.size > maxDisplaySize {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Response is too large to display (\(response.size.formattedBytes)).")
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            
            HStack {
                if isJSON {
                    Toggle("Raw", isOn: $showRaw)
                        .toggleStyle(.checkbox)
                }
                Spacer()
                if let onSaveAsExample = onSaveAsExample {
                    Button("Save as Example") {
                        onSaveAsExample()
                    }
                    .buttonStyle(.bordered)
                }
                Button("Copy") {
                    if let data = bodyData {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(String(data: data, encoding: .utf8) ?? "", forType: .string)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(bodyData == nil)
            }
            
            if bodyData != nil {
                CodeTextView(
                    text: .constant(cachedDisplayString),
                    language: showRaw ? nil : detectedLanguage,
                    isEditable: false
                )
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .id("\(response.statusCode)-\(response.size)-\(response.duration)")
            } else if let error = loadError {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                ProgressView("Loading body...")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .task {
                        await loadBodyData()
                    }
            }
        }
        .padding(12)
        .onChange(of: showRaw) { _, _ in
            updateDisplayString()
        }
    }
    
    private func loadBodyData() async {
        do {
            let data = try response.getBodyData()
            let language = languageForContentType(response.contentType)
            let raw = showRaw
            let json = isJSON
            let threshold = prettyPrintThreshold
            let maxSize = maxDisplaySize

            let displayString = await Task.detached(priority: .userInitiated) {
                let actualData = data.prefix(Int(maxSize))
                if !raw && json && data.count <= threshold {
                    if let jsonObject = try? JSONSerialization.jsonObject(with: actualData),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        return prettyString
                    }
                }
                return String(data: actualData, encoding: .utf8) ?? "<binary data>"
            }.value

            bodyData = data
            detectedLanguage = language
            cachedDisplayString = displayString
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func updateDisplayString() {
        guard let data = bodyData else { return }
        let raw = showRaw
        let json = isJSON
        let threshold = prettyPrintThreshold
        let maxSize = maxDisplaySize

        Task { @MainActor in
            let displayString = await Task.detached(priority: .userInitiated) {
                let actualData = data.prefix(Int(maxSize))
                if !raw && json && data.count <= threshold {
                    if let jsonObject = try? JSONSerialization.jsonObject(with: actualData),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        return prettyString
                    }
                }
                return String(data: actualData, encoding: .utf8) ?? "<binary data>"
            }.value
            cachedDisplayString = displayString
        }
    }
}

struct ResponseStatusBar: View {
    let response: HTTPResponse
    
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text("\(response.statusCode)")
                    .fontWeight(.medium)
                Text(response.statusMessage)
                    .foregroundStyle(.secondary)
            }
            
            Label("\(String(format: "%.0f", response.duration * 1000)) ms", systemImage: "clock")
                .foregroundStyle(.secondary)
            
            Label(response.size.formattedBytes, systemImage: "doc")
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Response: \(response.statusCode) \(response.statusMessage), \(String(format: "%.0f", response.duration * 1000)) milliseconds, \(response.size.formattedBytes)")
    }
    
    private var statusColor: Color {
        switch response.statusCode {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        case 500..<600: .red
        default: .gray
        }
    }
}

struct ResponseHeadersView: View {
    let headers: [String: String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response Headers")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(alignment: .top) {
                        Text(key)
                            .fontWeight(.medium)
                            .frame(width: 180, alignment: .leading)
                        Text(value)
                            .textSelection(.enabled)
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(12)
    }
}

struct ResponseTimingView: View {
    let duration: TimeInterval
    let size: Int64
    let timingBreakdown: TimingBreakdown?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timing")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Total Time")
                    Spacer()
                    Text("\(String(format: "%.0f", duration * 1000)) ms")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Response Size")
                    Spacer()
                    Text(size.formattedBytes)
                        .fontWeight(.medium)
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            
            if let breakdown = timingBreakdown {
                TimingWaterfallView(timing: breakdown)
            } else {
                Text("Detailed timing metrics coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

struct TimingWaterfallView: View {
    let timing: TimingBreakdown
    
    private var phases: [(String, TimeInterval, Color)] {
        [
            ("DNS", timing.dnsLookup, .blue),
            ("TCP", timing.tcpConnection, .green),
            ("TLS", timing.tlsHandshake, .orange),
            ("TTFB", timing.transferStart, .purple),
            ("Download", timing.download, .teal),
        ]
    }
    
    private var connectionReused: Bool {
        timing.dnsLookup < 0.001 && timing.tcpConnection < 0.001 && timing.tlsHandshake < 0.001
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if connectionReused {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.green)
                    Text("Connection likely reused (fast handshake)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }
            
            ForEach(phases, id: \.0) { name, duration, color in
                HStack(spacing: 8) {
                    Text(name)
                        .font(.caption)
                        .frame(width: 60, alignment: .trailing)
                    
                    if timing.total > 0 {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(width: max(2, geo.size.width * (duration / timing.total)))
                        }
                        .frame(height: 12)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 12)
                    }
                    
                    Text(String(format: "%.1f ms", duration * 1000))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
            
            if timing.redirectTime > 0 {
                HStack(spacing: 8) {
                    Text("Redirect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Spacer()
                    Text(String(format: "%.1f ms", timing.redirectTime * 1000))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
    }
}

struct ErrorView: View {
    let error: Error
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text("Request Failed")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if let clientError = error as? HTTPClientError {
                switch clientError {
                case .timeout:
                    Text("The request timed out. Try a simpler request or check the server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EmptyResponseView: View {
    var body: some View {
        ContentUnavailableView(
            "No Response",
            systemImage: "arrow.down.circle",
            description: Text("Send a request to see the response here")
        )
    }
}

struct ExamplesTabView: View {
    let request: HTTPRequest?
    @Query(sort: \ResponseExample.createdAt, order: .reverse) private var allExamples: [ResponseExample]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedExample: ResponseExample?
    @State private var showingDeleteAlert = false
    @State private var exampleToDelete: ResponseExample?
    
    private var examples: [ResponseExample] {
        guard let requestId = request?.id else { return [] }
        return allExamples.filter { $0.request?.id == requestId }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if examples.isEmpty {
                ContentUnavailableView(
                    "No Examples",
                    systemImage: "doc.text",
                    description: Text("Save a response as an example to view it here")
                )
                .frame(maxHeight: .infinity)
            } else {
                Text("Saved Examples")
                    .font(.headline)
                
                List(examples, selection: $selectedExample) { example in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.name)
                                .fontWeight(.medium)
                            HStack {
                                Text("\(example.statusCode)")
                                    .foregroundStyle(statusColor(example.statusCode))
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(example.createdAt, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            exampleToDelete = example
                            showingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .tag(example)
                }
                .listStyle(.inset)
                
                if let selected = selectedExample {
                    Divider()
                    ExampleDetailView(example: selected)
                }
            }
        }
        .padding(12)
        .alert("Delete Example?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let example = exampleToDelete {
                    modelContext.delete(example)
                    try? modelContext.save()
                }
            }
        }
    }
    
    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        case 500..<600: .red
        default: .gray
        }
    }
}

struct ExampleDetailView: View {
    let example: ResponseExample
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Viewing Example")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .cornerRadius(4)
                Spacer()
            }
            
            if let body = example.body {
                ScrollView {
                    Text(body)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
}

struct ConsoleTabView: View {
    let output: [String]
    var onClear: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Console Output")
                    .font(.headline)
                Spacer()
                if !output.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        let text = output.joined(separator: "\n")
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    Button("Clear") {
                        onClear?()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if output.isEmpty {
                ContentUnavailableView(
                    "No Console Output",
                    systemImage: "terminal",
                    description: Text("Console output from pre/post-request scripts will appear here")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(output.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .foregroundStyle(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 24, alignment: .trailing)
                                Text(line)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(12)
    }
}

#Preview("With Response") {
    let sampleResponse = HTTPResponse(
        statusCode: 200,
        statusMessage: "OK",
        headers: ["Content-Type": "application/json"],
        body: """
        {
          "users": [
            { "id": 1, "name": "John" },
            { "id": 2, "name": "Jane" }
          ]
        }
        """.data(using: .utf8)!,
        bodyFileURL: nil,
        duration: 0.234,
        size: 1234,
        timingBreakdown: nil
    )
    
    ResponseViewerPane(
        response: sampleResponse,
        error: nil,
        activeTab: .constant(.body),
        isLoading: false,
        request: nil,
        consoleOutput: ["Script executed successfully", "Response time: 234ms"]
    )
    .frame(width: 400, height: 500)
}
