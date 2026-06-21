import SwiftUI
import AppKit
import HypeCore

/// NSTextView-based code editor with HypeTalk syntax highlighting.
///
/// **Theming**: reads `\.hypeTheme` from the SwiftUI environment and
/// applies its `scriptTheme` palette to background, foreground, and
/// every `TokenCategory` produced by `HypeTalkHighlighter`. When the
/// active theme changes (e.g. user picks a different theme in the
/// inspector), the editor re-tokenizes and re-applies attributes
/// the next time `updateNSView` runs. The `themeRevision` parameter
/// is incremented by the parent view to force a re-render even when
/// the underlying text hasn't changed.
///
/// The legacy "force light appearance, hard-coded black on white"
/// branch is gone — every visible color now comes from
/// `theme.scriptTheme`. `BuiltInThemes.system` reproduces the old
/// look so this is backward-compatible by default.
struct HypeTalkTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var partNames: [String] = []
    /// 1-based line number to render with a red error background. When
    /// non-nil the line is highlighted and scrolled into view on the
    /// next `updateNSView` tick. `nil` clears any existing highlight.
    /// The binding lets `ScriptEditor` drop the highlight as soon as
    /// the user edits the script.
    var errorHighlightLine: Binding<Int?>? = nil
    var breakpointLines: Set<Int> = []
    var onToggleBreakpoint: ((Int) -> Void)? = nil
    var onTextChange: (() -> Void)? = nil
    var accessibilityIdentifier: String = HypeAccessibilityID.scriptEditorText
    /// The active theme's script-editor sub-palette. Drives every
    /// color and font decision. Defaults to the System theme so this
    /// view still works in previews/tests outside the document tree.
    var scriptTheme: HypeScriptTheme = BuiltInThemes.system.scriptTheme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.appearance = NSAppearance(named: .aqua)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = HypeTalkLineNumberRulerView(scrollView: scrollView)
        ruler.onToggleBreakpoint = { line in
            context.coordinator.parent.onToggleBreakpoint?(line)
        }
        scrollView.verticalRulerView = ruler

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 8)

        // Apply the script theme's palette + font.
        let bg = scriptTheme.background.nsColor
        let fg = scriptTheme.foreground.nsColor
        textView.backgroundColor = bg
        textView.insertionPointColor = fg
        let font = NSFont(name: "Menlo", size: CGFloat(scriptTheme.fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(scriptTheme.fontSize), weight: .regular)
        textView.font = font
        textView.textColor = fg
        textView.typingAttributes = [.font: font, .foregroundColor: fg]
        textView.delegate = context.coordinator
        textView.setAccessibilityElement(true)
        textView.setAccessibilityRole(.textArea)
        textView.setAccessibilityLabel("HypeTalk script")
        textView.setAccessibilityIdentifier(accessibilityIdentifier)

        // Configure text container
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView

        context.coordinator.textView = textView
        textView.string = text

        // Make first responder after window is ready
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard !context.coordinator.isUpdating else { return }
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            // Restore selection if valid
            let maxLoc = (text as NSString).length
            if selectedRange.location <= maxLoc {
                textView.setSelectedRange(NSRange(location: min(selectedRange.location, maxLoc), length: 0))
            }
            context.coordinator.isUpdating = false
        }
        context.coordinator.parent = self
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
        if let ruler = scrollView.verticalRulerView as? HypeTalkLineNumberRulerView {
            ruler.stringProvider = { textView.string }
            ruler.breakpointLines = breakpointLines
            ruler.font = textView.font ?? NSFont.monospacedSystemFont(ofSize: CGFloat(scriptTheme.fontSize), weight: .regular)
            ruler.needsDisplay = true
        }

        // Re-apply theme palette in case the active theme changed
        // since this view was created. Cheap because NSTextView's
        // background/textColor setters compare-and-skip when the
        // value is unchanged.
        let bg = scriptTheme.background.nsColor
        let fg = scriptTheme.foreground.nsColor
        if textView.backgroundColor != bg { textView.backgroundColor = bg }
        if textView.textColor != fg { textView.textColor = fg }
        textView.insertionPointColor = fg
        if let font = NSFont(name: "Menlo", size: CGFloat(scriptTheme.fontSize))
                  ?? .none {
            if textView.font != font { textView.font = font }
            textView.typingAttributes = [.font: font, .foregroundColor: fg]
        }

        // Re-tokenize and re-color. NSTextStorage edits are batched
        // inside beginEditing/endEditing so the layout manager only
        // re-lays out once per pass.
        context.coordinator.applySyntaxHighlight(
            in: textView, scriptTheme: scriptTheme
        )

        // Apply (or clear) the runtime-error line highlight. We do
        // this every update tick rather than only when the line
        // changes, because restoring the text above can wipe the
        // temporary attributes the layout manager was holding — so
        // a fresh application on every pass keeps the banner-and-
        // stripe state consistent with the binding.
        let requested = errorHighlightLine?.wrappedValue
        let current = context.coordinator.currentErrorLine
        if requested != current || requested != nil {
            context.coordinator.applyErrorHighlight(line: requested, in: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HypeTalkTextView
        var textView: NSTextView?
        var isUpdating = false
        /// Last error line we painted, so we can diff against the
        /// incoming binding and avoid redundant layout-manager work
        /// on every text change. `nil` means no highlight is active.
        var currentErrorLine: Int? = nil

        init(parent: HypeTalkTextView) {
            self.parent = parent
        }

        /// Paint (or clear) a red error-line background on the
        /// NSTextView using the layout manager's temporary-
        /// attributes API. Temporary attributes are NSLayoutManager-
        /// scoped visual overlays that don't mutate the backing
        /// attributed string — exactly what we want for a transient
        /// runtime-error marker that vanishes as soon as the user
        /// edits.
        ///
        /// The line number is 1-based to match the ParseError /
        /// Token line numbering the rest of the HypeTalk stack
        /// uses. Passing `nil` (or a line <= 0) clears any existing
        /// highlight.
        func applyErrorHighlight(line: Int?, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            // Clear any prior highlight first.
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(
                .backgroundColor,
                forCharacterRange: fullRange
            )

            guard let line = line, line > 0 else {
                currentErrorLine = nil
                return
            }
            guard let range = Self.characterRange(for: line, in: textView.string) else {
                currentErrorLine = nil
                return
            }
            // Use a translucent red so the surrounding code is still
            // readable through the highlight.
            let red = NSColor.red.withAlphaComponent(0.22)
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: red,
                forCharacterRange: range
            )
            // Scroll and select so the user's eye lands on the line.
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
            currentErrorLine = line
        }

        /// Translate a 1-based line number into the NSRange of that
        /// line's characters inside `source`. Returns `nil` if the
        /// line number is out of bounds.
        ///
        /// Splits on `\n` without trimming, so empty lines and the
        /// final line-without-terminator both have defined ranges.
        private static func characterRange(for line: Int, in source: String) -> NSRange? {
            guard line >= 1 else { return nil }
            let nsString = source as NSString
            var currentLine = 1
            var rangeStart = 0
            var idx = 0
            let length = nsString.length
            while idx < length {
                if currentLine == line {
                    // Find end of this line (up to but not including \n)
                    var end = idx
                    while end < length {
                        let ch = nsString.character(at: end)
                        if ch == 0x0A { break }
                        end += 1
                    }
                    return NSRange(location: rangeStart, length: end - rangeStart)
                }
                // Advance to start of next line
                if nsString.character(at: idx) == 0x0A {
                    currentLine += 1
                    rangeStart = idx + 1
                }
                idx += 1
            }
            // Ran off the end — return the last line if requested
            if currentLine == line {
                return NSRange(location: rangeStart, length: length - rangeStart)
            }
            return nil
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = textView else { return }
            isUpdating = true
            parent.text = tv.string
            // Re-tokenize on every keystroke so colors track the
            // user's edits live. The pass is fast (the highlighter
            // is a single linear scan) and NSTextStorage batching
            // collapses the layout-manager work into one pass.
            applySyntaxHighlight(in: tv, scriptTheme: parent.scriptTheme)
            parent.onTextChange?()
            isUpdating = false
        }

        /// Highlighter cached on the coordinator (it's a value type
        /// with no per-call setup, but holding the instance lets us
        /// extend it with stack-derived part names later without
        /// re-allocating per keystroke).
        private let highlighter = HypeTalkHighlighter()

        /// Tokenize the text view's current contents and apply per-
        /// token foreground colors derived from `scriptTheme`. Wraps
        /// every NSTextStorage edit in begin/endEditing so the
        /// layout manager re-lays out exactly once.
        ///
        /// This MUST run on the main actor (NSTextStorage is not
        /// thread-safe). It's called from `updateNSView` and
        /// `textDidChange`, both of which are already on the main
        /// thread by SwiftUI / AppKit contract.
        func applySyntaxHighlight(in textView: NSTextView, scriptTheme: HypeScriptTheme) {
            guard let storage = textView.textStorage else { return }
            let source = textView.string
            let nsSource = source as NSString
            let fullRange = NSRange(location: 0, length: nsSource.length)
            guard fullRange.length > 0 else { return }

            let tokens = highlighter.highlight(source)

            storage.beginEditing()
            // Reset to the theme's foreground first so any previously
            // colored run that's now plain text reverts. Run through
            // ensuringContrast so user themes with low-contrast
            // foregrounds get auto-darkened/lightened against the
            // editor background.
            let baseFGRef: ColorRef
            if case .hex(let bgHex) = scriptTheme.background {
                baseFGRef = scriptTheme.foreground.ensuringContrast(
                    against: bgHex, minRatio: 4.5
                )
            } else {
                baseFGRef = scriptTheme.foreground
            }
            let baseFG = baseFGRef.nsColor
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.addAttribute(.foregroundColor, value: baseFG, range: fullRange)

            for token in tokens {
                let nsRange = NSRange(token.range, in: source)
                guard nsRange.location + nsRange.length <= nsSource.length else { continue }
                let color = Self.color(for: token.category, theme: scriptTheme).nsColor
                storage.addAttribute(.foregroundColor, value: color, range: nsRange)
            }
            storage.endEditing()
        }

        /// Map a `HypeTalkHighlighter.TokenCategory` to a `ColorRef`
        /// from the script theme. Categories that don't have an
        /// exact 1:1 fall back to nearest-neighbor — e.g. `objectType`
        /// uses the property color (because object names in HypeTalk
        /// often appear in property-access positions like
        /// `the field of card`), and `constant` reuses the number
        /// literal color.
        ///
        /// Every returned color is run through `ensuringContrast`
        /// against the script theme's background, so user-authored
        /// themes (and AI-authored ones) can't drop a token color
        /// that becomes invisible on its own background — the
        /// renderer auto-darkens or auto-lightens until the WCAG
        /// AA bar (4.5:1) is met. This is belt-and-suspenders on
        /// top of the static built-in themes which are already
        /// audited via `ThemeContrastAuditTests`.
        private static func color(
            for category: TokenCategory,
            theme: HypeScriptTheme
        ) -> ColorRef {
            let raw: ColorRef
            switch category {
            case .keyword:        raw = theme.keyword
            case .command:        raw = theme.command
            case .objectType:     raw = theme.property
            case .constant:       raw = theme.numberLiteral
            case .stringLiteral:  raw = theme.stringLiteral
            case .numberLiteral:  raw = theme.numberLiteral
            case .comment:        raw = theme.comment
            case .operator_:      raw = theme.operatorSymbol
            case .plain:          raw = theme.foreground
            }
            // Resolve background to its hex form for the contrast
            // check. systemKey backgrounds skip auto-correction
            // (system handles its own contrast).
            guard case .hex(let bgHex) = theme.background else { return raw }
            return raw.ensuringContrast(against: bgHex, minRatio: 4.5)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let tv = textView else { return }
            parent.selectedRange = tv.selectedRange()
        }

        private var isInsertingText = false

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text = text else { return true }
            // Prevent recursion — insertText triggers shouldChangeTextIn again
            guard !isInsertingText else { return true }

            // Tab → 2 spaces
            if text == "\t" {
                isInsertingText = true
                textView.insertText("  ", replacementRange: range)
                isInsertingText = false
                return false
            }
            // Return → auto-indent
            if text == "\n" {
                let source = textView.string
                let nsString = source as NSString
                guard range.location <= nsString.length else { return true }
                let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
                let currentLine = nsString.substring(with: lineRange).trimmingCharacters(in: .newlines)
                var indent = ""
                for ch in currentLine {
                    if ch == " " { indent += " " } else { break }
                }
                let trimmed = currentLine.trimmingCharacters(in: .whitespaces).lowercased()
                if trimmed.hasPrefix("on ") || trimmed.hasPrefix("repeat") || trimmed.hasPrefix("function ") || trimmed == "else" || (trimmed.hasPrefix("if ") && trimmed.hasSuffix("then")) {
                    indent += "  "
                }
                isInsertingText = true
                textView.insertText("\n" + indent, replacementRange: range)
                isInsertingText = false
                return false
            }
            return true
        }
    }
}

private final class HypeTalkLineNumberRulerView: NSRulerView {
    var breakpointLines: Set<Int> = []
    var stringProvider: (() -> String)?
    var onToggleBreakpoint: ((Int) -> Void)?
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private let gutterWidth: CGFloat = 44

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = scrollView.documentView
        ruleThickness = gutterWidth
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        ruleThickness = gutterWidth
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = scrollView?.documentView as? NSTextView else { return }
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        rect.fill()

        let source = stringProvider?() ?? textView.string
        let lineCount = max(1, source.components(separatedBy: "\n").count)
        let lineHeight = max(font.boundingRectForFont.height + 3, textView.layoutManager?.defaultLineHeight(for: font) ?? 16)
        let insetY = textView.textContainerInset.height
        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let firstLine = max(1, Int(floor((visibleRect.minY - insetY) / lineHeight)) + 1)
        let lastLine = min(lineCount, Int(ceil((visibleRect.maxY - insetY) / lineHeight)) + 2)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        for line in firstLine...max(firstLine, lastLine) where line <= lineCount {
            let y = insetY + CGFloat(line - 1) * lineHeight - visibleRect.minY
            if breakpointLines.contains(line) {
                let dotRect = NSRect(x: 6, y: y + 3, width: 8, height: 8)
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            let labelRect = NSRect(x: 14, y: y, width: gutterWidth - 18, height: lineHeight)
            NSString(string: "\(line)").draw(in: labelRect, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let textView = scrollView?.documentView as? NSTextView else { return }
        let point = convert(event.locationInWindow, from: nil)
        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let lineHeight = max(font.boundingRectForFont.height + 3, textView.layoutManager?.defaultLineHeight(for: font) ?? 16)
        let insetY = textView.textContainerInset.height
        let line = Int(floor((point.y + visibleRect.minY - insetY) / lineHeight)) + 1
        guard line > 0 else { return }
        onToggleBreakpoint?(line)
        needsDisplay = true
    }
}
