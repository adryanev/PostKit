import SwiftUI

struct ResponseViewerPane: View {
    let response: HTTPResponse?
    let error: Error?
    @Binding var activeTab: RequestDetailView.ResponseTab
    let isLoading: Bool
    
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
                    activeTab: $activeTab
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
    @Binding var activeTab: RequestDetailView.ResponseTab
    
    var body: some View {
        VStack(spacing: 0) {
            ResponseStatusBar(response: response)
            Divider()
            
            ScrollView {
                switch activeTab {
                case .body:
                    ResponseBodyView(data: response.body)
                case .headers:
                    ResponseHeadersView(headers: response.headers)
                case .timing:
                    ResponseTimingView(duration: response.duration, size: response.size)
                }
            }
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
            
            Label(formatBytes(response.size), systemImage: "doc")
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
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
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ResponseBodyView: View {
    let data: Data
    @State private var showRaw = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isJSON {
                    Toggle("Raw", isOn: $showRaw)
                        .toggleStyle(.checkbox)
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bodyString, forType: .string)
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView([.horizontal, .vertical]) {
                Text(displayString)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(12)
    }
    
    private var isJSON: Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        return json is [Any] || json is [String: Any]
    }
    
    private var bodyString: String {
        String(data: data, encoding: .utf8) ?? "<binary data>"
    }
    
    private var displayString: String {
        if !showRaw && isJSON {
            if let pretty = try? JSONSerialization.jsonObject(with: data),
               let data = try? JSONSerialization.data(withJSONObject: pretty, options: .prettyPrinted),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return bodyString
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
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .fontWeight(.medium)
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            
            Text("Detailed timing metrics coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
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
                case .networkError(let underlying):
                    if (underlying as NSError).code == NSURLErrorTimedOut {
                        Text("The request timed out. Try increasing the timeout in settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        duration: 0.234,
        size: 1234
    )
    
    ResponseViewerPane(
        response: sampleResponse,
        error: nil,
        activeTab: .constant(.body),
        isLoading: false
    )
    .frame(width: 400, height: 500)
}
