import SwiftUI

// MARK: - JSON Path Bar

/// Shows the JSONPath to the currently selected node with copy functionality
struct JSONPathBar: View {
    let path: String
    @State private var showCopiedFeedback = false
    @State private var isHovering = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayPath: String {
        if path.isEmpty {
            return "$"
        }
        return "$.\(path)"
    }
    
    private var pathSegments: [(type: PathSegmentType, value: String)] {
        if path.isEmpty {
            return []
        }
        
        var segments: [(type: PathSegmentType, value: String)] = []
        var currentSegment = ""
        var inBracket = false
        
        for char in path {
            if char == "[" {
                if !currentSegment.isEmpty {
                    segments.append((.key, currentSegment))
                    currentSegment = ""
                }
                inBracket = true
            } else if char == "]" {
                if !currentSegment.isEmpty {
                    segments.append((.index, currentSegment))
                    currentSegment = ""
                }
                inBracket = false
            } else if char == "." && !inBracket {
                if !currentSegment.isEmpty {
                    segments.append((.key, currentSegment))
                    currentSegment = ""
                }
            } else {
                currentSegment.append(char)
            }
        }
        
        if !currentSegment.isEmpty {
            segments.append((inBracket ? .index : .key, currentSegment))
        }
        
        return segments
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Root indicator
            Text("$")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            
            if !path.isEmpty {
                ForEach(Array(pathSegments.enumerated()), id: \.offset) { _, segment in
                    switch segment.type {
                    case .key:
                        Text(".")
                            .foregroundStyle(.secondary)
                        Text(segment.value)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    
                    case .index:
                        Text("[\(segment.value)]")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color(red: 0.4, green: 0.44, blue: 0.53))
                    }
                }
            }
            
            Spacer()
            
            // Copy button
            Button {
                copyPath()
            } label: {
                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(showCopiedFeedback ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy JSONPath")
            .animation(.easeInOut(duration: 0.2), value: showCopiedFeedback)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovering ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            copyPath()
        }
    }
    
    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayPath, forType: .string)
        
        withAnimation {
            showCopiedFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
}

// MARK: - Path Segment Type

enum PathSegmentType {
    case key
    case index
}

// MARK: - JSON Path Builder

/// Utility for building and manipulating JSONPath strings
enum JSONPathBuilder {
    /// Formats a path for display
    static func formatDisplayPath(_ path: String) -> String {
        if path.isEmpty {
            return "$ (root)"
        }
        return "$.\(path)"
    }
    
    /// Parses a JSONPath string into components
    static func parsePath(_ path: String) -> [PathComponent] {
        var components: [PathComponent] = []
        var currentSegment = ""
        var inBracket = false
        
        for char in path {
            if char == "[" {
                if !currentSegment.isEmpty {
                    components.append(.key(currentSegment))
                    currentSegment = ""
                }
                inBracket = true
            } else if char == "]" {
                if !currentSegment.isEmpty {
                    if let index = Int(currentSegment) {
                        components.append(.index(index))
                    } else {
                        components.append(.key(currentSegment))
                    }
                    currentSegment = ""
                }
                inBracket = false
            } else if char == "." && !inBracket {
                if !currentSegment.isEmpty {
                    components.append(.key(currentSegment))
                    currentSegment = ""
                }
            } else {
                currentSegment.append(char)
            }
        }
        
        if !currentSegment.isEmpty {
            if inBracket {
                if let index = Int(currentSegment) {
                    components.append(.index(index))
                } else {
                    components.append(.key(currentSegment))
                }
            } else {
                components.append(.key(currentSegment))
            }
        }
        
        return components
    }
    
    /// Extracts a value at the given path from JSON data
    static func extractValue(at path: String, from data: Data) -> Any? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return extractValue(at: parsePath(path), from: json)
    }
    
    private static func extractValue(at path: [PathComponent], from json: Any) -> Any? {
        var current: Any? = json
        
        for component in path {
            switch component {
            case .key(let key):
                if let dict = current as? [String: Any] {
                    current = dict[key]
                } else {
                    return nil
                }
                
            case .index(let index):
                if let array = current as? [Any], index >= 0, index < array.count {
                    current = array[index]
                } else {
                    return nil
                }
            }
        }
        
        return current
    }
}

// MARK: - Path Component

enum PathComponent: Equatable {
    case key(String)
    case index(Int)
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        JSONPathBar(path: "")
        JSONPathBar(path: "data")
        JSONPathBar(path: "data.users[0]")
        JSONPathBar(path: "data.users[0].name")
        JSONPathBar(path: "items[2].properties.nested.value")
    }
    .padding()
    .frame(width: 400)
}
