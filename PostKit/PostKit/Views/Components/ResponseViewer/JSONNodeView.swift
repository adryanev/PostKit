import SwiftUI

// MARK: - JSON Node Model

/// Represents a node in the JSON tree structure
struct JSONNode: Identifiable, Sendable {
    var id: String { path }
    let key: String?
    let value: JSONValue
    let path: String
    let depth: Int
    
    var displayKey: String {
        key ?? ""
    }
    
    var hasChildren: Bool {
        switch value {
        case .object(let entries):
            return !entries.isEmpty
        case .array(let arr):
            return !arr.isEmpty
        default:
            return false
        }
    }

    var childCount: Int {
        switch value {
        case .object(let entries):
            return entries.count
        case .array(let arr):
            return arr.count
        default:
            return 0
        }
    }
}

/// Key-value entry for a JSON object, pre-sorted by key at parse time
struct JSONObjectEntry: Sendable, Equatable {
    let key: String
    let value: JSONValue
}

/// Represents a JSON value type
indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([JSONObjectEntry])
    
    var typeIndicator: String {
        switch self {
        case .null: return "null"
        case .bool: return "bool"
        case .number: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }
    
    var icon: String {
        switch self {
        case .null: return "circle"
        case .bool: return "togglepower"
        case .number: return "number"
        case .string: return "textformat"
        case .array: return "list.bullet"
        case .object: return "curlybraces"
        }
    }
    
    /// Convert from JSONSerialization output
    static func from(_ any: Any) -> JSONValue {
        switch any {
        case is NSNull:
            return .null
        case let bool as Bool:
            return .bool(bool)
        case let number as NSNumber:
            return .number(number.doubleValue)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map { from($0) })
        case let dict as [String: Any]:
            let sortedEntries = dict.sorted(by: { $0.key < $1.key })
                .map { JSONObjectEntry(key: $0.key, value: from($0.value)) }
            return .object(sortedEntries)
        default:
            return .null
        }
    }
    
    /// Convert to JSONSerialization format
    func toAny() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            return NSNumber(value: n)
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { $0.toAny() }
        case .object(let entries):
            var dict: [String: Any] = [:]
            for entry in entries {
                dict[entry.key] = entry.value.toAny()
            }
            return dict
        }
    }
}

// MARK: - JSON Node View

/// Individual node view in the JSON tree
struct JSONNodeView: View {
    let node: JSONNode
    @Binding var expandedPaths: Set<String>
    let searchQuery: String
    let selectedPath: String?
    let onSelect: (JSONNode) -> Void
    let onToggle: (JSONNode) -> Void
    /// When `false`, children are not rendered inline (used by JSONTreeView's flattened list approach)
    var showsChildren: Bool = true
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isExpanded: Bool {
        expandedPaths.contains(node.path)
    }
    
    private var isSelected: Bool {
        selectedPath == node.path
    }
    
    private var isSearchMatch: Bool {
        guard !searchQuery.isEmpty else { return false }
        let lowercased = searchQuery.lowercased()
        if node.displayKey.lowercased().contains(lowercased) { return true }
        if case .string(let s) = node.value, s.lowercased().contains(lowercased) { return true }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Indentation
                if node.depth > 0 {
                    ForEach(0..<node.depth, id: \.self) { _ in
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            .frame(width: 1)
                            .padding(.leading, 12)
                    }
                }
                
                // Expand/collapse button for objects/arrays
                if node.hasChildren {
                    Button {
                        onToggle(node)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 16)
                }
                
                // Type icon
                Image(systemName: node.value.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(typeColor)
                    .frame(width: 14)
                
                // Key (if present)
                if !node.displayKey.isEmpty {
                    Text(node.displayKey)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    Text(":")
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 2)
                }
                
                // Value preview
                valuePreview
                
                Spacer()
                
                // Type indicator
                Text(node.value.typeIndicator)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(typeColor.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.1))
                    .cornerRadius(3)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background {
                if isSelected {
                    Color.accentColor.opacity(0.2)
                        .cornerRadius(4)
                } else if isSearchMatch {
                    Color.yellow.opacity(colorScheme == .dark ? 0.2 : 0.3)
                        .cornerRadius(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(node)
            }
            
            // Children (if expanded and inline rendering is enabled)
            if showsChildren && isExpanded {
                childrenView
            }
        }
    }
    
    @ViewBuilder
    private var valuePreview: some View {
        switch node.value {
        case .null:
            Text("null")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .italic()
            
        case .bool(let b):
            Text(b ? "true" : "false")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color(red: 0.72, green: 0.18, blue: 0.35))
            
        case .number(let n):
            Text(formatNumber(n))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color(red: 0.74, green: 0.33, blue: 0.17))
            
        case .string(let s):
            if s.isEmpty {
                Text("\"\"")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.34))
            } else {
                Text("\"\(truncatedString(s))\"")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.34))
                    .lineLimit(1)
            }
            
        case .array(let arr):
            Text(isExpanded ? "[" : "[\(arr.count) items]")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            
        case .object(let entries):
            Text(isExpanded ? "{" : "{\(entries.count) keys}")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var childrenView: some View {
        switch node.value {
        case .array(let arr):
            ForEach(Array(arr.enumerated()), id: \.offset) { index, value in
                let childNode = JSONNode(
                    key: "\(index)",
                    value: value,
                    path: "\(node.path)[\(index)]",
                    depth: node.depth + 1
                )
                JSONNodeView(
                    node: childNode,
                    expandedPaths: $expandedPaths,
                    searchQuery: searchQuery,
                    selectedPath: selectedPath,
                    onSelect: onSelect,
                    onToggle: onToggle
                )
            }
            
        case .object(let entries):
            ForEach(entries, id: \.key) { entry in
                let childNode = JSONNode(
                    key: entry.key,
                    value: entry.value,
                    path: node.path.isEmpty ? entry.key : "\(node.path).\(entry.key)",
                    depth: node.depth + 1
                )
                JSONNodeView(
                    node: childNode,
                    expandedPaths: $expandedPaths,
                    searchQuery: searchQuery,
                    selectedPath: selectedPath,
                    onSelect: onSelect,
                    onToggle: onToggle
                )
            }
            
        default:
            EmptyView()
        }
    }
    
    private var typeColor: Color {
        switch node.value {
        case .null: return .secondary
        case .bool: return Color(red: 0.72, green: 0.18, blue: 0.35)
        case .number: return Color(red: 0.74, green: 0.33, blue: 0.17)
        case .string: return Color(red: 0.22, green: 0.52, blue: 0.34)
        case .array: return Color(red: 0.4, green: 0.44, blue: 0.53)
        case .object: return Color(red: 0.4, green: 0.44, blue: 0.53)
        }
    }
    
    private func formatNumber(_ n: Double) -> String {
        if n == floor(n) && abs(n) < Double(Int.max) {
            return String(Int(n))
        }
        return String(n)
    }
    
    private func truncatedString(_ s: String) -> String {
        if s.count > 60 {
            return String(s.prefix(60)) + "…"
        }
        return s
    }
}

// MARK: - Preview

#Preview {
    let sampleJSON: [String: Any] = [
        "users": [
            ["id": 1, "name": "John Doe", "email": "john@example.com", "active": true],
            ["id": 2, "name": "Jane Smith", "email": "jane@example.com", "active": false]
        ],
        "total": 2,
        "page": 1,
        "hasMore": false,
        "metadata": [
            "timestamp": "2024-01-15T10:30:00Z",
            "version": "1.0"
        ]
    ]
    
    let rootNode = JSONNode(
        key: nil,
        value: JSONValue.from(sampleJSON),
        path: "",
        depth: 0
    )
    
    JSONNodeView(
        node: rootNode,
        expandedPaths: .constant([""]),
        searchQuery: "",
        selectedPath: nil,
        onSelect: { _ in },
        onToggle: { _ in }
    )
    .padding()
    .frame(width: 400, height: 300)
}
