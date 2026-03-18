import SwiftUI

// MARK: - Response Search Bar

/// Search bar for finding text within response content
struct ResponseSearchBar: View {
    @Binding var text: String
    let matchCount: Int
    let currentMatch: Int
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onClose: () -> Void
    
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            // Search field
            TextField("Search in response", text: $text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($isFocused)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.shift) {
                        onFindPrevious()
                    } else {
                        onFindNext()
                    }
                }
            
            // Match counter
            if !text.isEmpty {
                Text(matchCount > 0 ? "\(currentMatch + 1) of \(matchCount)" : "No matches")
                    .font(.system(size: 11))
                    .foregroundStyle(matchCount > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                    .padding(.horizontal, 4)
            }
            
            // Navigation buttons
            if !text.isEmpty && matchCount > 0 {
                HStack(spacing: 2) {
                    Button {
                        onFindPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Previous match (⇧⏎)")
                    
                    Button {
                        onFindNext()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Next match (⏎)")
                }
            }
            
            Divider()
                .frame(height: 16)
            
            // Close button
            Button {
                text = ""
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (⎋)")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Search Result

/// Represents a search match in the response
struct SearchMatch: Identifiable, Equatable {
    let id = UUID()
    let range: NSRange
    let line: Int
    let column: Int
    let snippet: String
}

// MARK: - Search Manager

/// Manages search state and navigation
@MainActor
@Observable
final class ResponseSearchManager {
    var query: String = ""
    var matches: [SearchMatch] = []
    var currentMatchIndex: Int = -1
    var isSearching: Bool = false
    
    private var content: String = ""
    
    var currentMatch: SearchMatch? {
        guard currentMatchIndex >= 0 && currentMatchIndex < matches.count else { return nil }
        return matches[currentMatchIndex]
    }
    
    var matchCount: Int {
        matches.count
    }
    
    func setContent(_ newContent: String) {
        content = newContent
        if !query.isEmpty {
            performSearch()
        }
    }
    
    func updateQuery(_ newQuery: String) {
        query = newQuery
        performSearch()
    }
    
    func findNext() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }
    
    func findPrevious() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }
    
    func clear() {
        query = ""
        matches = []
        currentMatchIndex = -1
    }
    
    private func performSearch() {
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = -1
            return
        }
        
        isSearching = true
        
        let searchString = content
        let searchQuery = query
        
        Task.detached(priority: .userInitiated) { [weak self] in
            var foundMatches: [SearchMatch] = []
            let lowercasedContent = searchString.lowercased()
            let lowercasedQuery = searchQuery.lowercased()
            
            var searchStartIndex = lowercasedContent.startIndex
            var line = 1
            var lineStartIndex = lowercasedContent.startIndex
            
            while let range = lowercasedContent.range(of: lowercasedQuery, range: searchStartIndex..<lowercasedContent.endIndex) {
                let nsRange = NSRange(range, in: searchString)
                
                // Calculate line and column
                let prefix = lowercasedContent[lineStartIndex..<range.lowerBound]
                let newlines = prefix.filter { $0 == "\n" }.count
                line += newlines
                
                if newlines > 0 {
                    if let lastNewline = prefix.lastIndex(of: "\n") {
                        lineStartIndex = lowercasedContent.index(after: lastNewline)
                    }
                }
                
                let column = lowercasedContent.distance(from: lineStartIndex, to: range.lowerBound)
                
                // Extract snippet around the match
                let snippetStart = max(lowercasedContent.startIndex, lowercasedContent.index(range.lowerBound, offsetBy: -20, limitedBy: lowercasedContent.startIndex) ?? range.lowerBound)
                let snippetEnd = min(lowercasedContent.endIndex, lowercasedContent.index(range.upperBound, offsetBy: 20, limitedBy: lowercasedContent.endIndex) ?? range.upperBound)
                let snippet = String(lowercasedContent[snippetStart..<snippetEnd])
                
                foundMatches.append(SearchMatch(
                    range: nsRange,
                    line: line,
                    column: column,
                    snippet: snippet
                ))
                
                searchStartIndex = range.upperBound
                
                // Limit matches to prevent performance issues
                if foundMatches.count >= 1000 {
                    break
                }
            }
            
            Task { @MainActor in
                self?.matches = foundMatches
                self?.currentMatchIndex = foundMatches.isEmpty ? -1 : 0
                self?.isSearching = false
            }
        }
    }
}

// MARK: - Highlighted Text View

/// Text view that highlights search matches
struct HighlightedTextView: NSViewRepresentable {
    let text: String
    let matches: [SearchMatch]
    let currentMatchIndex: Int
    let language: String?
    
    @Environment(\.colorScheme) private var colorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = text
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        // Apply highlighting
        applyHighlights(to: textView)
        
        // Scroll to current match
        if currentMatchIndex >= 0 && currentMatchIndex < matches.count {
            let match = matches[currentMatchIndex]
            textView.scrollRangeToVisible(match.range)
            textView.selectedRange = match.range
        }
    }
    
    private func applyHighlights(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textStorage = textView.textStorage else { return }
        
        // Reset all highlighting
        textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))
        
        let highlightColor = colorScheme == .dark
            ? NSColor.yellow.withAlphaComponent(0.3)
            : NSColor.yellow.withAlphaComponent(0.5)
        
        let currentHighlightColor = NSColor.orange.withAlphaComponent(0.6)
        
        // Apply highlights
        for (index, match) in matches.enumerated() {
            let color: NSColor = index == currentMatchIndex ? currentHighlightColor : highlightColor
            textStorage.addAttribute(.backgroundColor, value: color, range: match.range)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        weak var textView: NSTextView?
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ResponseSearchBar(
            text: .constant("test"),
            matchCount: 5,
            currentMatch: 2,
            onFindNext: {},
            onFindPrevious: {},
            onClose: {}
        )
        .padding()
        
        Spacer()
    }
    .frame(width: 400, height: 200)
}
