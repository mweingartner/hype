import SwiftUI
import AppKit

/// A focused, zero-inset multi-line text input for the AI chat panel.
///
/// SwiftUI's `TextEditor` wraps an `NSTextView` whose default
/// `textContainerInset` (~5 pt) and `textContainer.lineFragmentPadding`
/// (~5 pt) shift typed text inwards — meaning text inside `TextEditor`
/// does NOT line up with a sibling `Text` placeholder rendered with the
/// same SwiftUI padding. The user-visible symptom is that the moment
/// focus enters the field, the cursor jumps a few points right and
/// down relative to where the placeholder was.
///
/// This wrapper bypasses both insets (sets them to zero) so the live
/// glyphs sit exactly at the NSTextView's local origin. SwiftUI
/// `.padding(N)` on the wrapper then yields text at `(N, N)` — same
/// math as `Text` with `.padding(N)`.
///
/// Behaviors carried over from the old `TextEditor` call site:
/// - **Enter** (without Shift) sends the message via `onSubmit`.
/// - **Shift+Enter** inserts a literal newline (multi-line composition).
/// - **Up / Down arrow** call `onHistoryUp` / `onHistoryDown` for
///   recall of previously-sent messages.
/// - `isEnabled = false` makes the text view non-editable AND keeps
///   the existing focused-color so the disable transition isn't
///   visually jarring (Hype suspends the input while a chat round
///   is in flight).
struct AIChatInputView: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool = true
    var onSubmit: () -> Void = {}
    var onHistoryUp: () -> Void = {}
    var onHistoryDown: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = ChatInputTextView()
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        // The whole point of this view: zero out the inherited
        // NSTextView insets so glyphs sit at the local origin.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        textView.onSubmit = { context.coordinator.parent.onSubmit() }
        textView.onHistoryUp = { context.coordinator.parent.onHistoryUp() }
        textView.onHistoryDown = { context.coordinator.parent.onHistoryDown() }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.string = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChatInputTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            // External text mutation (e.g. clear after send, history recall).
            // Set string AFTER preserving insertion point at end so the
            // cursor doesn't snap to position 0 unexpectedly.
            textView.string = text
            let len = (text as NSString).length
            textView.setSelectedRange(NSRange(location: len, length: 0))
        }
        if textView.isEditable != isEnabled {
            textView.isEditable = isEnabled
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AIChatInputView
        weak var textView: ChatInputTextView?

        init(_ parent: AIChatInputView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Push the new value back to the SwiftUI binding. The
            // round-trip through updateNSView is guarded by the
            // `textView.string != text` check so it doesn't loop.
            parent.text = textView.string
        }
    }
}

/// NSTextView subclass that intercepts Enter (no shift) and
/// Up / Down arrow presses for the chat input's send + history
/// behavior, leaving every other key as native NSTextView input.
final class ChatInputTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onHistoryUp: () -> Void = {}
    var onHistoryDown: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        // Enter key: send unless Shift is held.
        // keyCode 36 = Return, keyCode 76 = numpad Enter.
        if (event.keyCode == 36 || event.keyCode == 76)
            && !event.modifierFlags.contains(.shift) {
            onSubmit()
            return
        }

        // Up arrow recalls older history entries IF the cursor is
        // on the first line — otherwise let NSTextView move the
        // cursor as usual. Same logic for Down on the last line.
        if event.keyCode == 126,  // up arrow
           cursorIsOnFirstLine() {
            onHistoryUp()
            return
        }
        if event.keyCode == 125,  // down arrow
           cursorIsOnLastLine() {
            onHistoryDown()
            return
        }

        super.keyDown(with: event)
    }

    private func cursorIsOnFirstLine() -> Bool {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return true }
        let selRange = selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selRange, actualCharacterRange: nil)
        let lineRange = layoutManager.lineFragmentRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: nil
        )
        // First line ⇔ its line-fragment rect's origin.y is 0.
        _ = textContainer
        return lineRange.origin.y == 0
    }

    private func cursorIsOnLastLine() -> Bool {
        guard let layoutManager = layoutManager else { return true }
        let totalGlyphs = layoutManager.numberOfGlyphs
        guard totalGlyphs > 0 else { return true }
        let selRange = selectedRange()
        let glyphIdx = layoutManager.glyphRange(
            forCharacterRange: selRange,
            actualCharacterRange: nil
        ).location
        // If cursor is past the last glyph, treat as last line.
        if glyphIdx >= totalGlyphs - 1 { return true }
        let cursorRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIdx,
            effectiveRange: nil
        )
        let lastRect = layoutManager.lineFragmentRect(
            forGlyphAt: totalGlyphs - 1,
            effectiveRange: nil
        )
        return cursorRect.origin.y == lastRect.origin.y
    }
}
