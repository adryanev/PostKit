---
title: "SwiftUI macOS Sidebar Navigation and Layout Fixes"
date: 2026-02-14
category: ui-bugs
tags:
  - swiftui
  - macos
  - navigation-split-view
  - disclosure-group
  - context-menu
  - hsplitview
  - sidebar
  - layout
components:
  - ContentView
  - CollectionsSidebar
  - CollectionRow
  - FolderRow
  - RequestDetailView
  - EnvironmentPicker
framework: SwiftUI
platform: macOS 14+
severity: medium
symptoms:
  - Request rows in sidebar not clickable
  - Redundant middle column in NavigationSplitView
  - No selection highlight on active request
  - Detail pane not expanding to fill available width
  - Detail pane content not filling available height
  - Environment editor empty state showing split view with invisible sidebar
  - Right-clicking request shows collection-level context menu
---

# SwiftUI macOS Sidebar Navigation and Layout Fixes

## Problem Summary

PostKit's sidebar navigation had seven interrelated UI bugs stemming from SwiftUI/AppKit interop quirks on macOS. The sidebar displayed collections with expandable request rows but none of the rows were interactive, the layout wasted space, and context menus appeared on the wrong items.

## Issues and Root Causes

### 1. Request Rows Not Clickable

**Symptom:** Clicking request rows inside `DisclosureGroup` did nothing.

**Root Cause:** `DisclosureGroup` children had no interaction handlers. The sidebar `List(selection:)` was bound to `RequestCollection?`, but request rows had no `.tag()` and no tap gesture. `DisclosureGroup` items are expandable containers, not selectable rows.

**Fix:** Thread `selectedRequest: HTTPRequest?` binding through the hierarchy and use `List(selection: $selectedRequest)` with `.tag(request)` on each row:

```swift
// CollectionsSidebar
List(selection: $selectedRequest) {
    ForEach(collections) { collection in
        CollectionRow(collection: collection, selectedRequest: $selectedRequest)
    }
}

// Inside CollectionRow's DisclosureGroup content
RequestRow(request: request, compact: true)
    .tag(request)  // Enables native List selection
```

### 2. Redundant 3-Column Layout

**Symptom:** Middle column duplicated the sidebar's collection/request hierarchy.

**Root Cause:** The app used `NavigationSplitView(sidebar:content:detail:)` where the `content` column showed a `RequestListView` for the selected collection. Since the sidebar already displayed all collections expanded with their requests, the middle column was redundant.

**Fix:** Switch to 2-column `NavigationSplitView(sidebar:detail:)`, remove `selectedCollection` state, delete `RequestListView.swift`:

```swift
// Before: 3-column
NavigationSplitView(columnVisibility: $columnVisibility) {
    CollectionsSidebar(selection: $selectedCollection)
} content: {
    RequestListView(collection: selectedCollection, selection: $selectedRequest)
} detail: {
    RequestDetailView(request: selectedRequest)
}

// After: 2-column
NavigationSplitView(columnVisibility: $columnVisibility) {
    CollectionsSidebar(selectedRequest: $selectedRequest)
} detail: {
    RequestDetailView(request: selectedRequest)
}
```

### 3. No Selection Highlight

**Symptom:** Clicking a request opened it in the detail pane but the sidebar row had no visual indicator.

**Root Cause:** The `List` had no `selection:` binding, so macOS couldn't apply its native accent-color highlight.

**Fix:** `List(selection: $selectedRequest)` + `.tag(request)` gives native macOS sidebar highlighting for free. SwiftData `@Model` types conform to `Hashable` (via `PersistentModel`), so they work as tag values.

### 4. Detail Pane Not Expanding Width

**Symptom:** Detail pane only used ~50% of horizontal space.

**Root Cause:** `.navigationSplitViewStyle(.balanced)` divides space equally between columns. Designed for 3-column layouts, it's wrong for sidebar + detail.

**Fix:**

```swift
// Before
.navigationSplitViewStyle(.balanced)

// After
.navigationSplitViewStyle(.prominentDetail)
```

### 5. Detail Pane Not Expanding Height

**Symptom:** Large empty gap above URL bar; content vertically centered instead of top-aligned.

**Root Cause:** macOS `HSplitView` bridges to AppKit's `NSSplitView` and does **not** auto-expand vertically in SwiftUI's `VStack`. Without explicit height constraints, it sizes to intrinsic content height. The parent `VStack` then centers the undersized content.

**Fix:** Add `.frame(maxHeight: .infinity)` to both the `HSplitView` and its children:

```swift
HSplitView {
    RequestEditorPane(request: request)
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
    ResponseViewerPane(...)
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

### 6. Environment Editor Empty State

**Symptom:** Empty environment editor showed a split view with an invisible empty list pane and the empty state pushed off-center.

**Root Cause:** `HSplitView` rendered unconditionally, so even with zero environments, the left list pane (150-200px) was allocated, pushing the `ContentUnavailableView` to the right.

**Fix:** Conditional layout:

```swift
Group {
    if environments.isEmpty {
        ContentUnavailableView("No Environments", ...)
    } else {
        HSplitView { /* list + detail */ }
    }
}
.frame(width: 600, height: 400)
```

### 7. Wrong Context Menus on Request Rows

**Symptom:** Right-clicking a request row showed collection-level menu (New Request, New Folder, Export, Rename, Delete).

**Root Cause:** `.contextMenu` on `DisclosureGroup` covers the **entire** group including expanded children. Child rows' own context menus were shadowed.

**Fix:** Move collection/folder context menus onto the `label:` view, add request-level menus to individual rows:

```swift
DisclosureGroup(isExpanded: $isExpanded) {
    ForEach(requests) { request in
        RequestRow(request: request)
            .contextMenu {          // Request-level menu
                Button("Rename") { ... }
                Button("Duplicate") { ... }
                Button("Delete") { ... }
            }
    }
} label: {
    HStack { /* collection name */ }
        .contextMenu {              // Collection-level menu (on label only)
            Button("New Request") { ... }
            Button("Rename") { ... }
            Button("Delete") { ... }
        }
}
```

## Prevention Checklist

### SwiftUI macOS Sidebar Development

- [ ] Every selectable row has `.tag(item)` matching the `List(selection:)` binding type
- [ ] `List(selection:)` binding type matches the intended selectable item (not the parent container)
- [ ] `.navigationSplitViewStyle(.prominentDetail)` for 2-column sidebar+detail layouts
- [ ] AppKit bridge views (`HSplitView`, `VSplitView`) have explicit `.frame(maxHeight: .infinity)`
- [ ] Split views have conditional empty states when their list can be empty
- [ ] `.contextMenu` is on the specific view it applies to, not a parent container
- [ ] `DisclosureGroup` context menus are on the `label:` view, not the group itself

### Code Review Checks

- [ ] No `.contextMenu` directly on `DisclosureGroup` — must be on `label:` or children
- [ ] No `.balanced` style on 2-column `NavigationSplitView`
- [ ] All `HSplitView`/`VSplitView` children have explicit frame constraints
- [ ] Empty states for split views with conditional data
- [ ] Selection bindings threaded through the full view hierarchy

### Visual Testing

- [ ] Click each sidebar row type (collection, folder, request) and verify correct behavior
- [ ] Right-click each row type and verify correct context menu appears
- [ ] Verify selection highlight follows clicks
- [ ] Resize window to verify detail pane fills available space (both width and height)
- [ ] Check empty states render centered without phantom dividers

## Cross-References

- **ADR-008** (`docs/adr/0001-postkit-architecture-decisions.md` lines 239-263): NavigationSplitView without Coordinator pattern. Note: ADR describes 3-column layout; this solution reduces to 2-column.
- **ADR-001** (lines 38-61): SwiftUI over AppKit — notes fewer resources for advanced macOS patterns.
- **Developer Guide** (`docs/sop/developer-guide.md` lines 101-172): File layout and view naming conventions.
- **Testing Standards** (`docs/sop/testing-standards.md`): Every change must include tests.

## Files Changed

| File | Change |
|------|--------|
| `Views/ContentView.swift` | 3-column to 2-column NavigationSplitView, `.prominentDetail` |
| `Views/Sidebar/CollectionsSidebar.swift` | Removed collection selection, added request selection |
| `Views/Sidebar/CollectionRow.swift` | Selection tags, scoped context menus, rename support |
| `Views/RequestDetail/RequestDetailView.swift` | HSplitView height expansion |
| `Views/Environment/EnvironmentPicker.swift` | Conditional empty state |
| `Views/RequestList/RequestListView.swift` | **Deleted** (dead code) |
