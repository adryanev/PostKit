import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var clientTextView: NSTextView?
    private var pendingRedraw = false
    private let lineNumberFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    
    private var lineNumberCache: [Int: NSAttributedString] = [:]
    private let maxCachedLineNumbers = 10000
    
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        for i in 1...min(maxCachedLineNumbers, 1000) {
            lineNumberCache[i] = NSAttributedString(string: "\(i)", attributes: attributes)
        }
    }
    
    @objc private func textDidChange(_ notification: Notification) {
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
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        var lineNumber = 1
        var charIndex = 0
        
        while charIndex < charRange.location {
            if charIndex < text.length, text.character(at: charIndex) == Character("\n").asciiValue! {
                lineNumber += 1
            }
            charIndex += 1
        }
        
        let totalLineCount = countLines(in: text)
        updateRuleThickness(forLineCount: max(lineNumber, totalLineCount))
        
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
                    lineNumberString = NSAttributedString(string: "\(lineNumber)", attributes: attributes)
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
        let digitCount = "\(lineCount)".count
        let baseThickness: CGFloat = 40
        let extraWidthPerDigit: CGFloat = 8
        
        let newThickness: CGFloat
        if lineCount > 9999 {
            newThickness = baseThickness + CGFloat(digitCount - 4) * extraWidthPerDigit
        } else if lineCount > 999 {
            newThickness = baseThickness + CGFloat(digitCount - 3) * extraWidthPerDigit
        } else {
            newThickness = baseThickness
        }
        
        if abs(ruleThickness - newThickness) > 0.5 {
            ruleThickness = newThickness
        }
    }
}
