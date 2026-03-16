import SwiftUI

// MARK: - Response Viewer Mode

enum ResponseViewerMode: String, CaseIterable {
    case raw = "Raw"
    case tree = "Tree"
    
    var icon: String {
        switch self {
        case .raw: return "text.alignleft"
        case .tree: return "sidebar.right"
        }
    }
}

// MARK: - Response Viewer

/// Advanced response viewer with JSON tree view, search, and path navigation
struct ResponseViewer: View {
    let data: Data?
    let contentType: String?
    let statusCode: Int
    
    @State private var viewerMode: ResponseViewerMode = .raw
    @State private var isSearchVisible = false
    @State private var searchQuery = ""
    @State private var selectedPath: String?
    @State private var expandedPaths: Set<String> = []
    @State private var rawText: String = ""
    @State private var searchManager = ResponseSearchManager()
    @State private var isLoading = true
    @State private var parseError: String?
    
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool
    
    private var isJSON: Bool {
        contentType?.contains("application/json") ?? false
    }
    
    private var hasData: Bool {
        guard let data = data, !data.isEmpty else { return false }
        return true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            Divider()
            
            // Path bar (tree mode only)
            if viewerMode == .tree && isJSON && hasData {
                JSONPathBar(path: selectedPath ?? "")
                    .padding(8)
                Divider()
            }
            
            // Search bar
            if isSearchVisible {
                ResponseSearchBar(
                    text: $searchQuery,
                    matchCount: searchManager.matchCount,
                    currentMatch: searchManager.currentMatchIndex,
                    onFindNext: { searchManager.findNext() },
                    onFindPrevious: { searchManager.findPrevious() },
                    onClose: {
                        isSearchVisible = false
                        searchManager.clear()
                    }
                )
                .padding(8)
                Divider()
            }
            
            // Content
            mainContent
        }
        .task {
            await loadContent()
        }
        .onChange(of: data) { _, _ in
            Task {
                await loadContent()
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            if viewerMode == .raw {
                searchManager.updateQuery(newValue)
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ViewBuilder
    private var toolbarView: some View {
        HStack(spacing: 12) {
            // View mode picker
            if isJSON && hasData {
                Picker("View Mode", selection: $viewerMode) {
                    ForEach(ResponseViewerMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Search button
                Button {
                    isSearchVisible.toggle()
                    if isSearchVisible {
                        isSearchFieldFocused = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Search (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
                
                // Copy button
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                .disabled(!hasData)
                
                // Expand all (tree mode)
                if viewerMode == .tree && isJSON {
                    Menu {
                        Button("Expand All") {
                            expandAllNodes()
                        }
                        Button("Collapse All") {
                            collapseAllNodes()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("More options")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            ProgressView("Loading response...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = parseError {
            errorView(error)
        } else if !hasData {
            emptyView
        } else {
            switch viewerMode {
            case .raw:
                rawView
                
            case .tree:
                if isJSON {
                    treeView
                } else {
                    rawView
                }
            }
        }
    }
    
    @ViewBuilder
    private var rawView: some View {
        if isSearchVisible && !searchQuery.isEmpty {
            HighlightedTextView(
                text: rawText,
                matches: searchManager.matches,
                currentMatchIndex: searchManager.currentMatchIndex,
                language: isJSON ? "json" : nil
            )
        } else {
            CodeTextView(
                text: .constant(rawText),
                language: isJSON ? "json" : languageForContentType(contentType),
                isEditable: false
            )
        }
    }
    
    @ViewBuilder
    private var treeView: some View {
        if let data = data {
            JSONTreeView(
                data: data,
                searchQuery: searchQuery,
                selectedPath: $selectedPath,
                expandedPaths: $expandedPaths,
                onPathChange: { path in
                    // Update search manager with value at path
                    if let value = JSONPathBuilder.extractValue(at: path, from: data) {
                        // Could display value preview or copy to clipboard
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private var emptyView: some View {
        ContentUnavailableView(
            "No Response Body",
            systemImage: "doc.text",
            description: Text("The response has no body content")
        )
    }
    
    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Unable to display response")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadContent() async {
        isLoading = true
        parseError = nil
        
        guard let data = data, !data.isEmpty else {
            rawText = ""
            isLoading = false
            return
        }
        
        // Load raw text
        if let text = String(data: data, encoding: .utf8) {
            // Pretty print JSON
            if isJSON {
                let result = await Task.detached(priority: .userInitiated) {
                    do {
                        let json = try JSONSerialization.jsonObject(with: data)
                        let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
                        return String(data: prettyData, encoding: .utf8)
                    } catch {
                        return text
                    }
                }.value
                rawText = result ?? text
            } else {
                rawText = text
            }
            
            // Update search manager
            searchManager.setContent(rawText)
        } else {
            parseError = "Response contains binary data"
        }
        
        isLoading = false
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawText, forType: .string)
    }
    
    private func expandAllNodes() {
        guard let data = data else { return }
        var allPaths = Set<String>()
        collectAllPaths(from: data, path: "", allPaths: &allPaths)
        expandedPaths = allPaths
    }
    
    private func collapseAllNodes() {
        expandedPaths.removeAll()
    }
    
    private func collectAllPaths(from data: Data, path: String, allPaths: inout Set<String>) {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return }
        collectAllPathsFromJSON(json, path: path, allPaths: &allPaths)
    }
    
    private func collectAllPathsFromJSON(_ json: Any, path: String, allPaths: inout Set<String>) {
        switch json {
        case let dict as [String: Any]:
            if !dict.isEmpty {
                allPaths.insert(path)
                for (key, value) in dict {
                    let childPath = path.isEmpty ? key : "\(path).\(key)"
                    collectAllPathsFromJSON(value, path: childPath, allPaths: &allPaths)
                }
            }
        case let array as [Any]:
            if !array.isEmpty {
                allPaths.insert(path)
                for (index, value) in array.enumerated() {
                    let childPath = "\(path)[\(index)]"
                    collectAllPathsFromJSON(value, path: childPath, allPaths: &allPaths)
                }
            }
        default:
            break
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleJSON = """
    {
        "users": [
            {
                "id": 1,
                "name": "John Doe",
                "email": "john@example.com",
                "active": true
            },
            {
                "id": 2,
                "name": "Jane Smith",
                "email": "jane@example.com",
                "active": false
            }
        ],
        "total": 2,
        "page": 1
    }
    """.data(using: .utf8)!
    
    ResponseViewer(
        data: sampleJSON,
        contentType: "application/json",
        statusCode: 200
    )
    .frame(width: 600, height: 400)
}
