import SwiftUI
import AppKit
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
        
        let highlightr = Highlightr()
        let textStorage: CodeAttributedString
        if let highlightr = highlightr {
            textStorage = CodeAttributedString(highlightr: highlightr)
        } else {
            textStorage = CodeAttributedString()
        }
        
        let theme = colorScheme == .dark ? "xcode-dark" : "xcode"
        textStorage.highlightr.setTheme(to: theme)
        textStorage.highlightr.theme.setCodeFont(.monospacedSystemFont(ofSize: 13, weight: .regular))
        
        if text.utf8.count <= highlightingThreshold {
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
            if textView.string != text {
                let selectedRanges = textView.selectedRanges
                textView.string = text
                textView.selectedRanges = selectedRanges
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
            context.coordinator.scheduleThemeChange(to: newTheme, textStorage: context.coordinator.textStorage)
        }
        
        if context.coordinator.currentLanguage != language {
            context.coordinator.currentLanguage = language
            if text.utf8.count <= highlightingThreshold {
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
        unowned var textView: NSTextView!
        var textStorage: CodeAttributedString?
        var isUpdatingFromSwiftUI = false
        var lastWrittenText: String = ""
        var currentThemeName: String = ""
        var currentLanguage: String?
        var themeDebounceWorkItem: DispatchWorkItem?
        
        init(parent: CodeTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard parent.isEditable else { return }
            guard !isUpdatingFromSwiftUI else { return }
            guard let textView = notification.object as? NSTextView else { return }
            
            isUpdatingFromSwiftUI = true
            parent.text = textView.string
            lastWrittenText = textView.string
            isUpdatingFromSwiftUI = false
        }
        
        func scheduleThemeChange(to theme: String, textStorage: CodeAttributedString?) {
            themeDebounceWorkItem?.cancel()
            
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                textStorage?.highlightr.setTheme(to: theme)
                textStorage?.highlightr.theme.setCodeFont(
                    .monospacedSystemFont(ofSize: 13, weight: .regular)
                )
                self.currentThemeName = theme
            }
            
            themeDebounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
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
