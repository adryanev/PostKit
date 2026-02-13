import SwiftUI

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
    @Binding var activeTab: ResponseTab
    
    var body: some View {
        VStack(spacing: 0) {
            ResponseStatusBar(response: response)
            Divider()
            
            ScrollView {
                switch activeTab {
                case .body:
                    ResponseBodyView(response: response)
                case .headers:
                    ResponseHeadersView(headers: response.headers)
                case .timing:
                    ResponseTimingView(duration: response.duration, size: response.size, timingBreakdown: response.timingBreakdown)
                }
            }
        }
    }
}

struct ResponseBodyView: View {
    let response: HTTPResponse
    @State private var showRaw = false
    @State private var bodyData: Data?
    @State private var loadError: String?
    
    private let maxDisplaySize: Int64 = 10_000_000 // 10MB
    
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
                Button("Copy") {
                    if let data = bodyData {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(String(data: data, encoding: .utf8) ?? "", forType: .string)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(bodyData == nil)
            }
            
            if let data = bodyData {
                ScrollView([.horizontal, .vertical]) {
                    Text(displayString(for: data))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            } else if let error = loadError {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                ProgressView("Loading body...")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .task {
                        do {
                            bodyData = try response.getBodyData()
                        } catch {
                            loadError = error.localizedDescription
                        }
                    }
            }
        }
        .padding(12)
    }
    
    private var isJSON: Bool {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        return json is [Any] || json is [String: Any]
    }
    
    private func displayString(for data: Data) -> String {
        let actualData = data.prefix(Int(maxDisplaySize))
        let bodyString = String(data: actualData, encoding: .utf8) ?? "<binary data>"
        
        if !showRaw && isJSON {
            if let pretty = try? JSONSerialization.jsonObject(with: actualData),
               let data = try? JSONSerialization.data(withJSONObject: pretty, options: .prettyPrinted),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return bodyString
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
                    Text("Connection reused")
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
                case .networkError(let underlying):
                    if (underlying as NSError).code == NSURLErrorTimedOut {
                        Text("The request timed out. Try a simpler request or check the server.")
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
        bodyFileURL: nil,
        duration: 0.234,
        size: 1234,
        timingBreakdown: nil
    )
    
    ResponseViewerPane(
        response: sampleResponse,
        error: nil,
        activeTab: .constant(.body),
        isLoading: false
    )
    .frame(width: 400, height: 500)
}
