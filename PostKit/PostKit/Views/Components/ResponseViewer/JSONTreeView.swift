import SwiftUI

// MARK: - JSON Tree View

/// Recursive, virtualized JSON tree viewer with lazy loading for performance
struct JSONTreeView: View {
    let data: Data
    let searchQuery: String
    @Binding var selectedPath: String?
    @Binding var expandedPaths: Set<String>
    let onPathChange: (String) -> Void
    
    @State private var rootValue: JSONValue?
    @State private var cachedNodes: [JSONNode] = []
    @State private var parseError: String?
    @State private var isLoading = true
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let maxInitialDepth = 3
    private let chunkSize = 100
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Parsing JSON...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = parseError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text("Failed to parse JSON")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let root = rootValue {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        let rootNode = JSONNode(
                            key: nil,
                            value: root,
                            path: "",
                            depth: 0
                        )

                        // Root node (children handled by flattened list below)
                        JSONNodeView(
                            node: rootNode,
                            expandedPaths: $expandedPaths,
                            searchQuery: searchQuery,
                            selectedPath: selectedPath,
                            onSelect: handleSelect,
                            onToggle: handleToggle,
                            showsChildren: false
                        )

                        // Render children via cached flattened list
                        ForEach(cachedNodes) { node in
                            JSONNodeView(
                                node: node,
                                expandedPaths: $expandedPaths,
                                searchQuery: searchQuery,
                                selectedPath: selectedPath,
                                onSelect: handleSelect,
                                onToggle: handleToggle,
                                showsChildren: false
                            )
                        }
                    }
                    .padding(8)
                }
                .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.98))
            } else {
                ContentUnavailableView(
                    "No JSON Data",
                    systemImage: "doc.text"
                )
            }
        }
        .task {
            await parseJSON()
        }
        .onChange(of: data) { _, _ in
            Task {
                await parseJSON()
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            handleSearch(newValue)
        }
        .onChange(of: expandedPaths) { _, _ in
            recomputeCachedNodes()
        }
    }
    
    // MARK: - JSON Parsing
    
    private func parseJSON() async {
        isLoading = true
        parseError = nil
        
        let result: (JSONValue?, String?) = await Task.detached(priority: .userInitiated) {
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                return (JSONValue.from(jsonObject), nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        }.value
        
        rootValue = result.0
        parseError = result.1
        isLoading = false
        
        // Auto-expand first level
        if let root = rootValue {
            var initialExpanded = Set<String>()
            collectInitialExpandedPaths(from: root, path: "", depth: 0, expanded: &initialExpanded)
            expandedPaths = initialExpanded
            cachedNodes = flattenedNodes(from: root, parentPath: "", depth: 0)
        }
    }

    private func recomputeCachedNodes() {
        if let root = rootValue {
            cachedNodes = flattenedNodes(from: root, parentPath: "", depth: 0)
        }
    }
    
    private func collectInitialExpandedPaths(from value: JSONValue, path: String, depth: Int, expanded: inout Set<String>) {
        guard depth < maxInitialDepth else { return }

        switch value {
        case .object(let entries):
            if depth < maxInitialDepth - 1 {
                expanded.insert(path)
                for entry in entries {
                    let childPath = path.isEmpty ? entry.key : "\(path).\(entry.key)"
                    collectInitialExpandedPaths(from: entry.value, path: childPath, depth: depth + 1, expanded: &expanded)
                }
            }
        case .array(let arr):
            if depth < maxInitialDepth - 1 {
                expanded.insert(path)
                for (index, childValue) in arr.enumerated() {
                    let childPath = "\(path)[\(index)]"
                    collectInitialExpandedPaths(from: childValue, path: childPath, depth: depth + 1, expanded: &expanded)
                }
            }
        default:
            break
        }
    }
    
    // MARK: - Flattened Nodes for Virtualization
    
    private func flattenedNodes(from value: JSONValue, parentPath: String, depth: Int) -> [JSONNode] {
        var nodes: [JSONNode] = []

        switch value {
        case .object(let entries):
            guard expandedPaths.contains(parentPath) else { return nodes }

            // Entries are already pre-sorted by key at parse time
            for entry in entries {
                let childPath = parentPath.isEmpty ? entry.key : "\(parentPath).\(entry.key)"
                let node = JSONNode(key: entry.key, value: entry.value, path: childPath, depth: depth + 1)
                nodes.append(node)

                // Recursively add children if expanded
                nodes.append(contentsOf: flattenedNodes(from: entry.value, parentPath: childPath, depth: depth + 1))
            }

        case .array(let arr):
            guard expandedPaths.contains(parentPath) else { return nodes }

            for (index, childValue) in arr.enumerated() {
                let childPath = "\(parentPath)[\(index)]"
                let node = JSONNode(key: "\(index)", value: childValue, path: childPath, depth: depth + 1)
                nodes.append(node)

                // Recursively add children if expanded
                nodes.append(contentsOf: flattenedNodes(from: childValue, parentPath: childPath, depth: depth + 1))
            }

        default:
            break
        }

        return nodes
    }
    
    // MARK: - Actions
    
    private func handleSelect(_ node: JSONNode) {
        selectedPath = node.path
        onPathChange(node.path)
    }
    
    private func handleToggle(_ node: JSONNode) {
        if expandedPaths.contains(node.path) {
            expandedPaths.remove(node.path)
        } else {
            expandedPaths.insert(node.path)
        }
    }
    
    private func handleSearch(_ query: String) {
        guard !query.isEmpty, let root = rootValue else { return }
        
        // Find and expand paths that match the search
        var matchingPaths = Set<String>()
        findMatchingPaths(from: root, path: "", query: query, matchingPaths: &matchingPaths)
        
        // Expand parent paths
        for path in matchingPaths {
            expandParentPaths(of: path)
        }
        
        // If there are matches, select the first one
        if let firstMatch = matchingPaths.sorted().first {
            selectedPath = firstMatch
            onPathChange(firstMatch)
        }
    }
    
    private func findMatchingPaths(from value: JSONValue, path: String, query: String, matchingPaths: inout Set<String>) {
        let lowercased = query.lowercased()

        switch value {
        case .object(let entries):
            for entry in entries {
                let childPath = path.isEmpty ? entry.key : "\(path).\(entry.key)"

                // Check key match
                if entry.key.lowercased().contains(lowercased) {
                    matchingPaths.insert(childPath)
                }

                // Check value match
                if case .string(let s) = entry.value, s.lowercased().contains(lowercased) {
                    matchingPaths.insert(childPath)
                }

                // Recurse
                findMatchingPaths(from: entry.value, path: childPath, query: query, matchingPaths: &matchingPaths)
            }

        case .array(let arr):
            for (index, childValue) in arr.enumerated() {
                let childPath = "\(path)[\(index)]"

                // Check value match
                if case .string(let s) = childValue, s.lowercased().contains(lowercased) {
                    matchingPaths.insert(childPath)
                }

                // Recurse
                findMatchingPaths(from: childValue, path: childPath, query: query, matchingPaths: &matchingPaths)
            }

        default:
            break
        }
    }
    
    private func expandParentPaths(of path: String) {
        var components = path.components(separatedBy: ".")
        var currentPath = ""
        
        while !components.isEmpty {
            let component = components.removeFirst()
            
            // Handle array index notation
            if component.contains("[") {
                let parts = component.components(separatedBy: "[")
                if let first = parts.first, !first.isEmpty {
                    currentPath = currentPath.isEmpty ? first : "\(currentPath).\(first)"
                    expandedPaths.insert(currentPath)
                }
                for part in parts.dropFirst() {
                    if let index = part.components(separatedBy: "]").first {
                        currentPath = "\(currentPath)[\(index)]"
                        expandedPaths.insert(currentPath)
                    }
                }
            } else {
                currentPath = currentPath.isEmpty ? component : "\(currentPath).\(component)"
                expandedPaths.insert(currentPath)
            }
        }
    }
}

// MARK: - Expand All / Collapse All

extension JSONTreeView {
    /// Expands all nodes in the tree
    func expandAll() {
        guard let root = rootValue else { return }
        var allPaths = Set<String>()
        collectAllPaths(from: root, path: "", allPaths: &allPaths)
        expandedPaths = allPaths
    }

    /// Collapses all nodes in the tree
    func collapseAll() {
        expandedPaths.removeAll()
    }

    private func collectAllPaths(from value: JSONValue, path: String, allPaths: inout Set<String>) {
        switch value {
        case .object(let entries):
            if !entries.isEmpty {
                allPaths.insert(path)
                for entry in entries {
                    let childPath = path.isEmpty ? entry.key : "\(path).\(entry.key)"
                    collectAllPaths(from: entry.value, path: childPath, allPaths: &allPaths)
                }
            }
        case .array(let arr):
            if !arr.isEmpty {
                allPaths.insert(path)
                for (index, childValue) in arr.enumerated() {
                    let childPath = "\(path)[\(index)]"
                    collectAllPaths(from: childValue, path: childPath, allPaths: &allPaths)
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
                "active": true,
                "roles": ["admin", "user"]
            },
            {
                "id": 2,
                "name": "Jane Smith",
                "email": "jane@example.com",
                "active": false,
                "roles": ["user"]
            }
        ],
        "total": 2,
        "page": 1,
        "hasMore": false,
        "metadata": {
            "timestamp": "2024-01-15T10:30:00Z",
            "version": "1.0",
            "nested": {
                "deep": {
                    "value": 42
                }
            }
        }
    }
    """.data(using: .utf8)!
    
    JSONTreeView(
        data: sampleJSON,
        searchQuery: "",
        selectedPath: .constant(nil),
        expandedPaths: .constant([""]),
        onPathChange: { _ in }
    )
    .frame(width: 500, height: 400)
}
