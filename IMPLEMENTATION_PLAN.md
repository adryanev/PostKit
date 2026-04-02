# PostKit Pro - Phase 1 Implementation Plan

## Overview

**Goal:** Launch Pro tier with 4 premium features
**Timeline:** 6-8 weeks
**Architecture:** SwiftUI + SwiftData + CloudKit

---

## Feature 1: Code Generation

### Goal
Export any HTTP request to 20+ programming languages/frameworks.

### Files to Create

```
PostKit/PostKit/Services/CodeGenerator/
├── CodeGenerator.swift              # Main generator coordinator
├── Templates/
│   ├── SwiftTemplate.swift          # URLSession + async/await
│   ├── SwiftUIHTTPTemplate.swift    # Unique! SwiftUI-native
│   ├── PythonRequestsTemplate.swift
│   ├── PythonAiohttpTemplate.swift
│   ├── GoTemplate.swift
│   ├── NodeFetchTemplate.swift
│   ├── NodeAxiosTemplate.swift
│   ├── CurlTemplate.swift
│   ├── KotlinOkhttpTemplate.swift
│   ├── JavaHttpClientTemplate.swift
│   ├── RustReqwestTemplate.swift
│   ├── RubyNetHttpTemplate.swift
│   ├── PHPCurlTemplate.swift
│   ├── CSharpHttpClientTemplate.swift
│   ├── SwiftAlamofireTemplate.swift
│   └── DartDioTemplate.swift
└── CodeGeneratorView.swift          # UI for language picker + copy

PostKit/PostKit/Models/
└── GeneratedCode.swift              # Model for generated output
```

### Implementation Steps

1. **Create protocol-based template system** (4h)
   ```swift
   protocol CodeTemplate {
       var language: String { get }
       var framework: String? { get }
       func generate(from request: HTTPRequest, environment: APIEnvironment?) -> String
   }
   ```

2. **Implement Swift templates first** (3h)
   - Native URLSession (highest value for macOS devs)
   - SwiftUI HTTP wrapper (unique differentiator)

3. **Add curl, Python, JavaScript** (4h)
   - Most commonly used
   - Test thoroughly

4. **Build remaining templates** (8h)
   - Copy patterns from existing templates
   - Use Stencil or simple string interpolation

5. **Create UI** (4h)
   - Language picker (sidebar or sheet)
   - Syntax highlighted preview
   - Copy to clipboard button
   - Keyboard shortcut ⌘⇧C

### Dependencies
- Highlightr (Swift) - syntax highlighting for preview
- Or: Custom SwiftUI AttributedText

### Effort Estimate
- **24-30 hours total**
- Can ship with 8-10 languages initially, add more later

### Challenges
- Handling complex auth (OAuth flows)
- Binary body encoding
- File uploads
- Edge cases in each language

---

## Feature 2: Keyboard-First Mode

### Goal
Navigate entire app without mouse. Vim-style + command palette.

### Files to Create/Modify

```
PostKit/PostKit/ViewModels/
└── KeyboardNavigationViewModel.swift

PostKit/PostKit/Views/Components/
├── CommandPalette.swift             # ⌘K command palette
├── KeyboardShortcutView.swift       # Shortcut preferences
└── VimNavigationView.swift          # Vim mode overlay

PostKit/PostKit/
├── PostKitCommands.swift            # (modify) Add new commands
└── KeyboardShortcuts.swift          # Central shortcut registry
```

### Implementation Steps

1. **Create keyboard shortcut registry** (3h)
   ```swift
   enum AppShortcut: String, CaseIterable {
       case commandPalette = "k"
       case newRequest = "n"
       case sendRequest = "return"
       case nextRequest = "j"
       case prevRequest = "k"
       // ... etc
   }
   ```

2. **Implement command palette** (6h)
   - ⌘K to open
   - Fuzzy search requests, collections, actions
   - Keyboard navigation within palette
   - Recent commands

3. **Add Vim navigation** (4h)
   - j/k for list navigation
   - enter to select
   - esc to go back
   - / to search
   - Optional: can be disabled in preferences

4. **Custom shortcut editor** (4h)
   - Preferences pane
   - Detect conflicts
   - Reset to defaults

5. **Focus management** (3h)
   - FocusScope, @FocusState
   - Tab between panels
   - Focus follows mouse (optional)

### Dependencies
- None (native SwiftUI)

### Effort Estimate
- **20-25 hours total**

### Challenges
- SwiftUI focus management is tricky
- Avoiding conflicts with system shortcuts
- Making it feel natural, not forced

---

## Feature 3: Advanced Response Viewer

### Goal
Better JSON/XML viewing with folding, search, syntax highlighting.

### Files to Create/Modify

```
PostKit/PostKit/Views/Components/
├── ResponseViewer/
│   ├── ResponseViewer.swift          # Main container
│   ├── JSONViewer.swift              # JSON tree view
│   ├── XMLViewer.swift               # XML tree view
│   ├── ResponseSearchBar.swift       # Search within response
│   └── ResponsePathBar.swift         # Show path to selected node
└── SyntaxHighlighter.swift           # Reusable highlighter

PostKit/PostKit/Views/RequestDetail/
└── ResponseView.swift                # (modify) Use new components
```

### Implementation Steps

1. **JSON tree viewer** (8h)
   - Recursive view for nested structures
   - Collapsible nodes (click to fold)
   - Type indicators (string, number, bool, null)
   - Array index display

2. **Search within response** (4h)
   - ⌘F to focus search
   - Highlight matches
   - Navigate with Enter/Shift+Enter
   - Match count display

3. **Path bar** (2h)
   - Show JSONPath to selected node
   - Click to copy path
   - e.g., `data.users[0].name`

4. **Syntax highlighting** (4h)
   - Integrate Highlightr or custom
   - Color scheme matches Xcode

5. **Performance optimization** (4h)
   - Lazy loading for large responses
   - Virtualization if needed

### Dependencies
- Highlightr (Swift) - or build custom

### Effort Estimate
- **22-28 hours total**

### Challenges
- Performance with large JSON (10MB+)
- Deeply nested structures
- Memory management

---

## Feature 4: iCloud Sync

### Goal
Sync collections and environments across Macs via iCloud.

### Files to Create/Modify

```
PostKit/PostKit/Services/
├── CloudKitSync.swift               # Sync coordinator
├── CloudKitContainer.swift          # CKContainer setup
└── ConflictResolver.swift           # Handle sync conflicts

PostKit/PostKit/Models/
└── (modify all models)              # Add CKRecord conversion

PostKit/PostKit/
└── PostKitApp.swift                 # (modify) Enable CloudKit
```

### Implementation Steps

1. **Enable CloudKit in Xcode** (1h)
   - Add iCloud capability
   - Create CloudKit container
   - Configure schema

2. **Model extensions** (6h)
   ```swift
   extension RequestCollection {
       init(from record: CKRecord) throws
       func toRecord() -> CKRecord
   }
   // Repeat for HTTPRequest, Folder, APIEnvironment, Variable
   ```

3. **Sync coordinator** (8h)
   - Subscribe to remote changes
   - Handle local changes → push to CloudKit
   - Merge conflicts (last-write-wins or user choice)

4. **Sync status UI** (3h)
   - Sync indicator in toolbar
   - Last sync timestamp
   - Manual sync button
   - Conflict resolution UI

5. **Testing** (6h)
   - Multiple devices
   - Offline mode
   - Conflict scenarios

### Dependencies
- CloudKit framework (built-in)

### Effort Estimate
- **24-30 hours total**

### Challenges
- Conflict resolution logic
- Large collection sync performance
- Offline handling
- User switching iCloud accounts

---

## Implementation Order

### Week 1-2: Code Generation
- Highest ROI, standalone feature
- No dependencies on other features
- Easy to market

### Week 2-3: Keyboard-First Mode
- Enhances all existing features
- Quick wins with shortcuts

### Week 3-4: Advanced Response Viewer
- Visual appeal for marketing
- Improves daily usage

### Week 4-6: iCloud Sync
- Most complex
- Requires thorough testing
- Save for last when app is stable

---

## Total Effort

| Feature | Hours | Weeks (40h/week) |
|---------|-------|------------------|
| Code Generation | 24-30 | 0.6-0.75 |
| Keyboard-First | 20-25 | 0.5-0.6 |
| Response Viewer | 22-28 | 0.55-0.7 |
| iCloud Sync | 24-30 | 0.6-0.75 |
| **Total** | **90-113** | **2.3-2.8 weeks** |

**With buffer for testing, polish, edge cases:** 6-8 weeks realistic timeline

---

## Testing Strategy

### Unit Tests
- Code generation templates (all languages)
- JSON parsing for viewer
- CloudKit record conversion

### Integration Tests
- Sync across two simulators
- Keyboard navigation flow

### Manual QA
- Large files (100MB+ responses)
- Network conditions (slow, offline)
- Multiple Macs with iCloud

---

## Launch Checklist

- [ ] All 4 features implemented
- [ ] Unit tests pass
- [ ] Manual testing on 2+ Macs
- [ ] iCloud sync verified
- [ ] App Store screenshots updated
- [ ] Landing page ready
- [ ] Gumroad/Lemon Squeezy set up
- [ ] Product Hunt scheduled

---

## Dependencies to Add

### Package.swift
```swift
dependencies: [
    // For syntax highlighting
    .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
]
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| iCloud sync bugs | Ship as beta feature first, add toggle to disable |
| Performance issues | Lazy loading, pagination, virtualization |
| Code gen edge cases | Start with common patterns, document limitations |
| App Store rejection | Review guidelines early, sandbox properly |

---

## Post-Launch (Phase 2)

After Phase 1 ships and stabilizes:
1. Request Chaining
2. Mock Servers
3. AI Request Builder (with BYOK)
4. Siri Shortcuts integration
