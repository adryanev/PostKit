import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var clientTextView: NSTextView?
    private var pendingRedraw = false
    private let lineNumberFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    
    private var lineNumberCache: [Int: NSAttributedString] = [:]
    private var cachedLineCount: Int = 1
    
    private var lineNumberAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        return [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
    }
    
    init(scrollView: NSScrollView, clientView: NSTextView) {
        self.clientTextView = clientView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: clientView
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: clientView
        )
        
        clientView.postsFrameChangedNotifications = true
        ruleThickness = 40
        
        precacheLineNumbers()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func precacheLineNumbers() {
        for i in 1...1000 {
            lineNumberCache[i] = NSAttributedString(string: "\(i)", attributes: lineNumberAttributes)
        }
    }
    
    @objc private func textDidChange(_ notification: Notification) {
        if let tv = clientTextView {
            cachedLineCount = countLines(in: tv.string as NSString)
        }
        scheduleRedraw()
    }
    
    @objc private func frameDidChange(_ notification: Notification) {
        scheduleRedraw()
    }
    
    private func scheduleRedraw() {
        guard !pendingRedraw else { return }
        pendingRedraw = true
        DispatchQueue.main.async { [weak self] in
            self?.pendingRedraw = false
            self?.needsDisplay = true
        }
    }
    
    override var ruleThickness: CGFloat {
        didSet {
            scrollView?.verticalRulerView?.needsDisplay = true
        }
    }
    
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        
        let visibleRect = scrollView?.contentView.bounds ?? .zero
        
        let textVisibleRect = NSRect(
            x: 0,
            y: visibleRect.origin.y,
            width: textView.bounds.width,
            height: visibleRect.height
        )
        
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textVisibleRect, in: textContainer)
        
        guard glyphRange.length > 0 else { return }
        
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let text = textView.string as NSString
        
        var lineNumber = 1
        var charIndex = 0
        
        while charIndex < charRange.location {
            if charIndex < text.length, text.character(at: charIndex) == Character("\n").asciiValue! {
                lineNumber += 1
            }
            charIndex += 1
        }
        
        updateRuleThickness(forLineCount: max(lineNumber, cachedLineCount))
        
        var currentCharIndex = charRange.location
        var lastDrawnY: CGFloat = -.infinity
        let minLineSpacing: CGFloat = 12
        
        while currentCharIndex < charRange.location + charRange.length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: currentCharIndex)
            
            var effectiveGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveGlyphRange)
            
            let lineEndCharIndex = layoutManager.characterIndexForGlyph(at: effectiveGlyphRange.location + effectiveGlyphRange.length)
            
            let lineY = lineRect.origin.y
            let textY = lineY - textVisibleRect.origin.y
            let rulerY = bounds.height - textY - lineRect.height + 2
            
            if rulerY >= -20 && rulerY <= bounds.height + 20 && lineY - lastDrawnY >= minLineSpacing {
                let lineNumberString: NSAttributedString
                if let cached = lineNumberCache[lineNumber] {
                    lineNumberString = cached
                } else {
                    lineNumberString = NSAttributedString(string: "\(lineNumber)", attributes: lineNumberAttributes)
                }
                
                let textSize = lineNumberString.size()
                let drawRect = NSRect(
                    x: ruleThickness - textSize.width - 8,
                    y: rulerY,
                    width: textSize.width,
                    height: textSize.height
                )
                lineNumberString.draw(in: drawRect)
                lastDrawnY = lineY
            }
            
            for i in currentCharIndex..<min(lineEndCharIndex, text.length) {
                if text.character(at: i) == Character("\n").asciiValue! {
                    lineNumber += 1
                }
            }
            
            currentCharIndex = lineEndCharIndex
        }
    }
    
    private func countLines(in text: NSString) -> Int {
        var lineCount = 1
        for i in 0..<text.length {
            if text.character(at: i) == Character("\n").asciiValue! {
                lineCount += 1
            }
        }
        return lineCount
    }
    
    private func updateRuleThickness(forLineCount lineCount: Int) {
        let digitCount = max(3, "\(lineCount)".count)
        let newThickness: CGFloat = 40 + CGFloat(max(0, digitCount - 3)) * 8
        if abs(ruleThickness - newThickness) > 0.5 {
            ruleThickness = newThickness
        }
    }
}
