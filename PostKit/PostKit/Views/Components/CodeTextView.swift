import SwiftUI
import AppKit

// MARK: - Highlightr Threading Model
//
// Highlightr wraps Highlight.js via JavaScriptCore's JSContext for syntax highlighting.
// The threading model is as follows:
//
// 1. JSContext Safety: CodeAttributedString dispatches highlighting work to a background
//    DispatchQueue.global() but serializes JSContext access internally. The library has been
//    widely used in production without thread safety issues.
//
// 2. @preconcurrency Import: This is the standard Swift pattern for importing non-Sendable
//    Objective-C libraries. It suppresses Sendability warnings while acknowledging that the
//    underlying library was not designed with Swift concurrency in mind.
//
// 3. Theme Changes: All theme mutations (via `applyThemeChange`) are invoked from the main
//    thread via SwiftUI's `updateNSView`, which runs on the main actor. This ensures theme
//    changes are serialized with respect to the main run loop, coordinating safely with
//    Highlightr's internal JSContext serialization.
//
// Reference: https://github.com/raspu/Highlightr
//
@preconcurrency import Highlightr

struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var language: String?
    var isEditable: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private let highlightingThreshold: Int = 262_144
    
    func makeNSView(context: Context) -> FindBarAwareScrollView {
        let scrollView = FindBarAwareScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        
        let textStorage = CodeAttributedString()
        
        let theme = colorScheme == .dark ? "xcode-dark" : "xcode"
        textStorage.highlightr.setTheme(to: theme)
        textStorage.highlightr.theme.setCodeFont(.monospacedSystemFont(ofSize: 13, weight: .regular))
        
        let byteCount = text.utf8.count
        context.coordinator.lastTextByteCount = byteCount
        
        if byteCount <= highlightingThreshold {
            textStorage.language = language
        }
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer()
        if isEditable {
            textContainer.widthTracksTextView = true
        } else {
            textContainer.widthTracksTextView = false
            textContainer.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = isEditable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = context.coordinator
        textView.string = text
        
        scrollView.documentView = textView
        scrollView.textView = textView
        
        let lineNumberRuler = LineNumberRulerView(scrollView: scrollView, clientView: textView)
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.rulersVisible = true
        
        context.coordinator.textView = textView
        context.coordinator.textStorage = textStorage
        context.coordinator.currentThemeName = theme
        context.coordinator.currentLanguage = language
        context.coordinator.lastWrittenText = text
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: FindBarAwareScrollView, context: Context) {
        context.coordinator.parent = self
        
        guard let textView = scrollView.textView else { return }
        
        if scrollView.isFindBarVisible {
            return
        }
        
        if !isEditable {
            // Fast path: compare against coordinator's cached text instead of O(n) textView.string comparison
            if text != context.coordinator.lastWrittenText {
                let selectedRanges = textView.selectedRanges
                textView.string = text
                textView.selectedRanges = selectedRanges
                context.coordinator.lastWrittenText = text
                context.coordinator.lastTextByteCount = text.utf8.count
            }
        } else {
            guard !context.coordinator.isUpdatingFromSwiftUI else { return }
            
            if text != context.coordinator.lastWrittenText {
                guard textView.string != text else { return }
                
                context.coordinator.isUpdatingFromSwiftUI = true
                let selectedRanges = textView.selectedRanges
                textView.string = text
                textView.selectedRanges = selectedRanges
                context.coordinator.isUpdatingFromSwiftUI = false
            }
        }
        
        let newTheme = colorScheme == .dark ? "xcode-dark" : "xcode"
        if context.coordinator.currentThemeName != newTheme {
            context.coordinator.applyThemeChange(to: newTheme, textStorage: context.coordinator.textStorage)
        }
        
        if context.coordinator.currentLanguage != language {
            context.coordinator.currentLanguage = language
            if context.coordinator.lastTextByteCount <= highlightingThreshold {
                context.coordinator.textStorage?.language = language
            } else {
                context.coordinator.textStorage?.language = nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        weak var textView: NSTextView?
        var textStorage: CodeAttributedString?
        var isUpdatingFromSwiftUI = false
        var lastWrittenText: String = ""
        var lastTextByteCount: Int = 0
        var currentThemeName: String = ""
        var currentLanguage: String?
        
        init(parent: CodeTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard parent.isEditable else { return }
            guard !isUpdatingFromSwiftUI else { return }
            guard let textView = notification.object as? NSTextView else { return }
            
            isUpdatingFromSwiftUI = true
            let newText = textView.string
            parent.text = newText
            lastWrittenText = newText
            lastTextByteCount = newText.utf8.count
            isUpdatingFromSwiftUI = false
        }
        
        func applyThemeChange(to theme: String, textStorage: CodeAttributedString?) {
            textStorage?.highlightr.setTheme(to: theme)
            textStorage?.highlightr.theme.setCodeFont(.monospacedSystemFont(ofSize: 13, weight: .regular))
            currentThemeName = theme
        }
    }
}

final class FindBarAwareScrollView: NSScrollView {
    weak var textView: NSTextView?
    
    override var isFindBarVisible: Bool {
        didSet {
            if oldValue && !isFindBarVisible {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    self.window?.makeFirstResponder(textView)
                }
            }
        }
    }
}
