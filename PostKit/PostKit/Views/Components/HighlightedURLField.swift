import SwiftUI
import AppKit

// MARK: - HighlightedURLField

/// A single-line text field that highlights URL components and `{{variableName}}` template variables inline.
///
/// Uses an NSTextView configured for single-line editing so we get full control over
/// `NSAttributedString` styling while preserving standard text field behaviours
/// (copy/paste, undo, focus ring, on-submit).
struct HighlightedURLField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    var onSubmit: (() -> Void)?

    // Matches {{anything-except-closing-braces}}
    private static let variableRegex = try! NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#)
    // Matches URL scheme (http://, https://, etc.)
    private static let schemeRegex = try! NSRegularExpression(pattern: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#)
    // Matches query parameter keys (after ? or &)
    private static let queryParamRegex = try! NSRegularExpression(pattern: #"[?&]([^=&\s]+)(?==)"#)
    // Matches path segments
    private static let pathSegmentRegex = try! NSRegularExpression(pattern: #"(/[^/?#\s]*)"#)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = SingleLineTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isFieldEditor = true
        textView.drawsBackground = false
        textView.font = font
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.string = text

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.lastWrittenText = text
        applyHighlighting(to: textView)
        applyPlaceholder(to: textView, text: text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SingleLineTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = onSubmit

        guard !context.coordinator.isUpdatingFromDelegate else { return }

        if text != context.coordinator.lastWrittenText {
            context.coordinator.isUpdatingFromSwiftUI = true
            textView.string = text
            // Place caret at end-of-text; restoring old selection is unsafe
            // if the new text is shorter (would cause NSRangeException).
            let endOfText = (text as NSString).length
            textView.setSelectedRange(NSRange(location: endOfText, length: 0))
            context.coordinator.lastWrittenText = text
            applyHighlighting(to: textView)
            context.coordinator.isUpdatingFromSwiftUI = false
        }

        applyPlaceholder(to: textView, text: text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Highlighting

    private func applyHighlighting(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullString = storage.string
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        
        // Reset to base style
        storage.setAttributes([
            .font: font,
            .foregroundColor: NSColor.textColor
        ], range: fullRange)

        // Highlight URL scheme (https://) in blue
        let schemeMatches = Self.schemeRegex.matches(in: fullString, range: fullRange)
        for match in schemeMatches {
            storage.addAttributes([
                .foregroundColor: NSColor.systemBlue
            ], range: match.range)
        }

        // Highlight query parameter keys in purple
        let queryMatches = Self.queryParamRegex.matches(in: fullString, range: fullRange)
        for match in queryMatches {
            if match.numberOfRanges > 1 {
                let keyRange = match.range(at: 1)
                storage.addAttributes([
                    .foregroundColor: NSColor.systemPurple
                ], range: keyRange)
            }
        }

        // Highlight {{variable}} tokens in orange with medium weight
        let variableMatches = Self.variableRegex.matches(in: fullString, range: fullRange)
        for match in variableMatches {
            storage.addAttributes([
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .medium)
            ], range: match.range)
        }
        
        storage.endEditing()
    }

    private func applyPlaceholder(to textView: NSTextView, text: String) {
        guard let singleLine = textView as? SingleLineTextView else { return }
        singleLine.placeholderString = text.isEmpty ? placeholder : nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedURLField
        weak var textView: NSTextView?
        var isUpdatingFromSwiftUI = false
        var isUpdatingFromDelegate = false
        var lastWrittenText: String = ""

        init(parent: HighlightedURLField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI else { return }
            guard let textView = notification.object as? NSTextView else { return }

            isUpdatingFromDelegate = true
            let newText = textView.string
            parent.text = newText
            lastWrittenText = newText
            parent.applyHighlighting(to: textView)
            isUpdatingFromDelegate = false
        }
    }
}

// MARK: - SingleLineTextView

/// An NSTextView subclass that intercepts Return/Enter to fire `onSubmit` instead of
/// inserting a newline, mimicking NSTextField submit behaviour.
final class SingleLineTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func insertNewline(_ sender: Any?) {
        onSubmit?()
    }

    override func insertTab(_ sender: Any?) {
        // Move focus to next responder like a regular text field
        window?.selectNextKeyView(self)
    }

    // Prevent pasting multi-line text — collapse to single line
    override func paste(_ sender: Any?) {
        guard let pasteboard = NSPasteboard.general.string(forType: .string) else { return }
        let singleLine = pasteboard.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
        insertText(singleLine, replacementRange: selectedRange())
    }

    /// Draws a placeholder when the field is empty, matching NSTextField style.
    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty, let placeholder = placeholderString {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let inset = textContainerInset
            let padding = textContainer?.lineFragmentPadding ?? 0
            let point = NSPoint(x: inset.width + padding, y: inset.height)
            NSAttributedString(string: placeholder, attributes: attrs).draw(at: point)
        }
    }
}
