import SwiftUI
import AppKit
import HypeCore

/// NSTextView-based code editor that exposes selection range for comment toggling.
/// Uses forced light appearance to ensure black-on-white text visibility.
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
    var onTextChange: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.appearance = NSAppearance(named: .aqua)

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

        // Force light appearance and explicit colors
        textView.appearance = NSAppearance(named: .aqua)
        textView.backgroundColor = .white
        textView.insertionPointColor = .black
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.font = font
        textView.textColor = .black
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.black]
        textView.delegate = context.coordinator

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
            parent.onTextChange?()
            isUpdating = false
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
