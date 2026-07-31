import SwiftUI
import AppKit
import HypeCore

final class HypeTalkGlyphOverlayLayer: CALayer {
    var renderedText = ""
}

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
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        let palette = Coordinator.resolvedPalette(for: scriptTheme)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.appearance = palette.appearance
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = HypeTalkLineNumberRulerView(scrollView: scrollView)
        ruler.onToggleBreakpoint = { line in
            context.coordinator.parent.onToggleBreakpoint?(line)
        }
        scrollView.verticalRulerView = ruler

        textView.appearance = palette.appearance
        textView.wantsLayer = true
        textView.layerContentsRedrawPolicy = .onSetNeedsDisplay
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
        let bg = palette.background
        let fg = palette.foreground
        scrollView.drawsBackground = true
        scrollView.backgroundColor = bg
        textView.backgroundColor = bg
        textView.drawsBackground = true
        textView.insertionPointColor = fg
        let font = NSFont(name: "Menlo", size: CGFloat(scriptTheme.fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(scriptTheme.fontSize), weight: .regular)
        textView.font = font
        textView.textColor = fg
        textView.typingAttributes = [.font: font, .foregroundColor: fg]
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selection,
            .foregroundColor: fg,
        ]
        textView.delegate = context.coordinator
        textView.setAccessibilityElement(true)
        textView.setAccessibilityRole(.textArea)
        textView.setAccessibilityLabel("HypeTalk script")
        textView.setAccessibilityIdentifier(accessibilityIdentifier)

        // Configure text container
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: max(1, scrollView.contentSize.width - 52),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: max(1, scrollView.contentSize.width),
                height: max(1, scrollView.contentSize.height)
            )
        )
        textView.minSize = NSSize(width: 0, height: max(1, scrollView.contentSize.height))
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Keep the gutter explicitly bound to the canonical text view.
        // A nil client makes AppKit overlay the ruler without tracking
        // the document view's layout or scrolling.
        ruler.clientView = textView
        scrollView.tile()

        context.coordinator.textView = textView
        textView.string = text
        context.coordinator.applySyntaxHighlight(in: textView, scriptTheme: scriptTheme)
        context.coordinator.installGlyphOverlay(
            for: textView,
            in: scrollView,
            scriptTheme: scriptTheme
        )
        textView.needsDisplay = true

        // Make first responder after window is ready
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard !context.coordinator.isUpdating else { return }
        let palette = Coordinator.resolvedPalette(for: scriptTheme)
        scrollView.appearance = palette.appearance
        textView.appearance = palette.appearance
        Coordinator.sizeDocumentView(textView, in: scrollView)
        let scrollOrigin = scrollView.contentView.bounds.origin
        if scrollOrigin.x != 0 {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollOrigin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
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
            ruler.appearance = palette.appearance
            ruler.backgroundColor = palette.background
            ruler.lineNumberColor = palette.lineNumber
            ruler.needsDisplay = true
        }

        // Re-apply theme palette in case the active theme changed
        // since this view was created. Cheap because NSTextView's
        // background/textColor setters compare-and-skip when the
        // value is unchanged.
        let bg = palette.background
        let fg = palette.foreground
        if scrollView.backgroundColor != bg { scrollView.backgroundColor = bg }
        if !scrollView.drawsBackground { scrollView.drawsBackground = true }
        if textView.backgroundColor != bg { textView.backgroundColor = bg }
        if !textView.drawsBackground { textView.drawsBackground = true }
        if textView.textColor != fg { textView.textColor = fg }
        textView.insertionPointColor = fg
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selection,
            .foregroundColor: fg,
        ]
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
        context.coordinator.updateGlyphOverlay(
            for: textView,
            in: scrollView,
            scriptTheme: scriptTheme
        )
        textView.needsDisplay = true

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
        struct ResolvedPalette {
            var appearance: NSAppearance
            var background: NSColor
            var foreground: NSColor
            var selection: NSColor
            var lineNumber: NSColor
        }

        var parent: HypeTalkTextView
        var textView: NSTextView?
        var isUpdating = false
        // Keep a root-level copy of the attributed glyphs visible. In the
        // script editor's SwiftUI split view, AppKit can composite the clip
        // view's document subtree behind the scroll surface even though the
        // NSTextView remains the canonical editable/accessibility view.
        private let glyphLayer = HypeTalkGlyphOverlayLayer()
        private nonisolated(unsafe) var scrollBoundsObserver: NSObjectProtocol?
        /// Last error line we painted, so we can diff against the
        /// incoming binding and avoid redundant layout-manager work
        /// on every text change. `nil` means no highlight is active.
        var currentErrorLine: Int? = nil

        init(parent: HypeTalkTextView) {
            self.parent = parent
        }

        deinit {
            if let scrollBoundsObserver {
                NotificationCenter.default.removeObserver(scrollBoundsObserver)
            }
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
            if let scrollView = tv.enclosingScrollView {
                updateGlyphOverlay(
                    for: tv,
                    in: scrollView,
                    scriptTheme: parent.scriptTheme
                )
            }
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
            let font = textView.font
                ?? NSFont(name: "Menlo", size: CGFloat(scriptTheme.fontSize))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(scriptTheme.fontSize), weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            let lineHeight = max(
                font.boundingRectForFont.height + 3,
                textView.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize
            )
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight

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
            let palette = Self.resolvedPalette(for: scriptTheme)
            let baseFG = Self.readableColor(
                Self.resolvedColor(baseFGRef.nsColor, appearance: palette.appearance),
                on: palette.background
            )
            storage.setAttributes(
                [
                    .font: font,
                    .foregroundColor: baseFG,
                    .paragraphStyle: paragraph,
                ],
                range: fullRange
            )

            for token in tokens {
                let nsRange = NSRange(token.range, in: source)
                guard nsRange.location + nsRange.length <= nsSource.length else { continue }
                let color = Self.readableColor(
                    Self.resolvedColor(
                        Self.color(for: token.category, theme: scriptTheme).nsColor,
                        appearance: palette.appearance
                    ),
                    on: palette.background
                )
                storage.addAttribute(.foregroundColor, value: color, range: nsRange)
            }
            storage.endEditing()
        }

        func installGlyphOverlay(
            for textView: NSTextView,
            in scrollView: NSScrollView,
            scriptTheme: HypeScriptTheme
        ) {
            scrollView.wantsLayer = true
            scrollView.contentView.postsBoundsChangedNotifications = true
            if scrollBoundsObserver == nil {
                scrollBoundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self, weak textView, weak scrollView] _ in
                    MainActor.assumeIsolated {
                        guard let self, let textView, let scrollView else { return }
                        self.updateGlyphOverlay(
                            for: textView,
                            in: scrollView,
                            scriptTheme: self.parent.scriptTheme
                        )
                    }
                }
            }
            updateGlyphOverlay(
                for: textView,
                in: scrollView,
                scriptTheme: scriptTheme
            )
        }

        func updateGlyphOverlay(
            for textView: NSTextView,
            in scrollView: NSScrollView,
            scriptTheme: HypeScriptTheme
        ) {
            guard let rootLayer = scrollView.layer,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            if glyphLayer.superlayer !== rootLayer {
                glyphLayer.removeFromSuperlayer()
                rootLayer.addSublayer(glyphLayer)
            }

            let scrollY = scrollView.contentView.bounds.origin.y
            let contentsScale = scrollView.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
            glyphLayer.frame = CGRect(
                x: 0,
                y: 0,
                width: max(0, scrollView.bounds.width),
                height: max(0, scrollView.bounds.height)
            )
            glyphLayer.zPosition = 10
            glyphLayer.contentsScale = contentsScale
            glyphLayer.isGeometryFlipped = true
            glyphLayer.backgroundColor = nil
            glyphLayer.renderedText = textView.string
            glyphLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

            let storage = textView.textStorage
                ?? NSTextStorage(string: textView.string)
            let selection = textView.selectedRange()
            let selectionColor = Self.resolvedPalette(for: scriptTheme).selection
            let textOrigin = textView.textContainerOrigin
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            layoutManager.enumerateLineFragments(
                forGlyphRange: glyphRange
            ) { _, usedRect, _, fragmentGlyphRange, _ in
                var characterRange = layoutManager.characterRange(
                    forGlyphRange: fragmentGlyphRange,
                    actualGlyphRange: nil
                )
                while characterRange.length > 0 {
                    let last = NSMaxRange(characterRange) - 1
                    let scalar = (textView.string as NSString).character(at: last)
                    guard scalar == 0x0A || scalar == 0x0D else { break }
                    characterRange.length -= 1
                }
                guard characterRange.length > 0 else { return }

                let attributed = NSMutableAttributedString(
                    attributedString: storage.attributedSubstring(from: characterRange)
                )
                let selectedCharacters = NSIntersectionRange(selection, characterRange)
                if selectedCharacters.length > 0 {
                    attributed.addAttribute(
                        .backgroundColor,
                        value: selectionColor,
                        range: NSRange(
                            location: selectedCharacters.location - characterRange.location,
                            length: selectedCharacters.length
                        )
                    )
                }

                let lineLayer = CATextLayer()
                lineLayer.frame = CGRect(
                    x: 44 + textOrigin.x + usedRect.minX,
                    y: self.glyphLayer.bounds.height
                        - (textOrigin.y + usedRect.maxY - scrollY),
                    width: max(1, scrollView.bounds.width - 48 - usedRect.minX),
                    height: max(1, usedRect.height)
                )
                lineLayer.contentsScale = contentsScale
                lineLayer.isGeometryFlipped = true
                lineLayer.alignmentMode = .left
                lineLayer.truncationMode = .none
                lineLayer.string = attributed
                self.glyphLayer.addSublayer(lineLayer)
            }
        }

        static func resolvedPalette(for theme: HypeScriptTheme) -> ResolvedPalette {
            let appearance = editorAppearance(for: theme)
            let background = resolvedColor(theme.background.nsColor, appearance: appearance)
            let foreground = readableColor(
                resolvedColor(theme.foreground.nsColor, appearance: appearance),
                on: background
            )
            return ResolvedPalette(
                appearance: appearance,
                background: background,
                foreground: foreground,
                selection: resolvedColor(theme.selection.nsColor, appearance: appearance),
                lineNumber: resolvedColor(theme.lineNumber.nsColor, appearance: appearance)
            )
        }

        static func sizeDocumentView(_ textView: NSTextView, in scrollView: NSScrollView) {
            let contentSize = scrollView.contentSize
            let width = max(1, contentSize.width)
            let height = max(1, contentSize.height)
            if textView.frame.width != width || textView.frame.height < height {
                textView.setFrameSize(
                    NSSize(width: width, height: max(height, textView.frame.height))
                )
            }
            textView.minSize = NSSize(width: 0, height: height)
            textView.textContainer?.containerSize = NSSize(
                width: max(1, width - 52),
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        static func editorAppearance(for theme: HypeScriptTheme) -> NSAppearance {
            if case .systemKey = theme.background {
                let current = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
                return NSAppearance(named: current == .darkAqua ? .darkAqua : .aqua)
                    ?? NSAppearance(named: .aqua)!
            }
            let background = resolvedColor(
                theme.background.nsColor,
                appearance: NSAppearance(named: .aqua)!
            )
            let luminance = rgbComponents(background)?.luminance ?? 1
            return NSAppearance(named: luminance > 0.5 ? .aqua : .darkAqua)
                ?? NSAppearance(named: .aqua)!
        }

        static func resolvedColor(_ color: NSColor, appearance: NSAppearance) -> NSColor {
            var resolved = color
            appearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB)
                    ?? color.usingColorSpace(.deviceRGB)
                    ?? color
            }
            return resolved
        }

        static func readableColor(_ color: NSColor, on background: NSColor) -> NSColor {
            guard let fg = rgbComponents(color), let bg = rgbComponents(background) else {
                return color.withAlphaComponent(1)
            }
            if contrastRatio(fg, bg) >= 7.0 {
                return color.withAlphaComponent(1)
            }
            return bg.luminance > 0.5 ? NSColor.black : NSColor.white
        }

        private static func rgbComponents(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, luminance: CGFloat)? {
            let converted = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB)
            guard let converted else { return nil }
            let blended = blendAlpha(
                (converted.redComponent, converted.greenComponent, converted.blueComponent),
                alpha: converted.alphaComponent
            )
            let luminance = relativeLuminance(blended)
            return (blended.0, blended.1, blended.2, luminance)
        }

        private static func blendAlpha(_ rgb: (CGFloat, CGFloat, CGFloat), alpha: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            guard alpha < 1 else { return rgb }
            let white: CGFloat = 1
            return (
                rgb.0 * alpha + white * (1 - alpha),
                rgb.1 * alpha + white * (1 - alpha),
                rgb.2 * alpha + white * (1 - alpha)
            )
        }

        private static func contrastRatio(
            _ a: (r: CGFloat, g: CGFloat, b: CGFloat, luminance: CGFloat),
            _ b: (r: CGFloat, g: CGFloat, b: CGFloat, luminance: CGFloat)
        ) -> CGFloat {
            let lighter = max(a.luminance, b.luminance)
            let darker = min(a.luminance, b.luminance)
            return (lighter + 0.05) / (darker + 0.05)
        }

        private static func relativeLuminance(_ rgb: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
            func channel(_ value: CGFloat) -> CGFloat {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
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
            if let scrollView = tv.enclosingScrollView {
                updateGlyphOverlay(
                    for: tv,
                    in: scrollView,
                    scriptTheme: parent.scriptTheme
                )
            }
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
    var backgroundColor: NSColor = .textBackgroundColor
    var lineNumberColor: NSColor = .secondaryLabelColor

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
        backgroundColor.setFill()
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
            .foregroundColor: HypeTalkTextView.Coordinator.readableColor(lineNumberColor, on: backgroundColor),
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
