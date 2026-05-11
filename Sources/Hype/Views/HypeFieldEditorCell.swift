import AppKit
import HypeCore

/// Custom NSTextFieldCell whose text drawing rect matches
/// `FieldRenderer.draw`, so the inline editor
/// overlay puts characters at the same screen position as the
/// static rendering.
///
/// **Why this exists**
///
/// The static path renders field text through `FieldTextLayout`.
/// NSTextField's default cell instead uses an intrinsic ~2pt edge
/// inset plus a 5pt `lineFragmentPadding` in its underlying text
/// container. Together those produce a visible jump when the user
/// taps a field: characters slide right or vertically snap.
///
/// This cell forces:
/// - drawingRect / titleRect = the shared static-renderer text rect
/// - the field-editor's frame to match that text rect, so the live
///   cursor sits where the static text drew
/// - zero `lineFragmentPadding`, so AppKit does not add a second
///   horizontal inset on top of Hype's field margins
final class HypeFieldEditorCell: NSTextFieldCell {

    /// Symmetric inset matching `FieldTextLayout.padding`.
    var hypePadding: CGFloat = 4

    /// Extra leading inset for styles with an inline glyph, currently
    /// the search field magnifying glass.
    var leadingTextInset: CGFloat = 0

    /// When the field has the `scrolling` style, FieldRenderer
    /// reserves 16pt on the right edge for the scrollbar track.
    /// Mirror that here so
    /// the editor's text wraps at the same column the static
    /// rendering does.
    var rightScrollbarReserve: CGFloat = 0

    private func contentRect(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.minX + hypePadding + leadingTextInset,
            y: rect.minY + hypePadding,
            width: max(0, rect.width - hypePadding * 2 - leadingTextInset - rightScrollbarReserve),
            height: max(0, rect.height - hypePadding * 2)
        )
    }

    private func currentAttributedStringForMeasurement() -> NSAttributedString {
        if attributedStringValue.length > 0 {
            return attributedStringValue
        }

        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = stringValue.isEmpty ? " " : stringValue
        return NSAttributedString(string: text, attributes: [.font: font])
    }

    private func fieldTextRect(_ rect: NSRect) -> NSRect {
        FieldTextLayout.verticallyCenteredTextRect(
            in: contentRect(rect),
            attributedString: currentAttributedStringForMeasurement(),
            fallbackFont: font
        )
    }

    // MARK: - Layout overrides

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        // The default implementation adds its own intrinsic ~2pt
        // inset on top of whatever we return; bypass by skipping
        // super entirely.
        fieldTextRect(rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        fieldTextRect(rect)
    }

    // MARK: - Field-editor placement

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: fieldTextRect(rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
        configureFieldEditor(textObj)
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: fieldTextRect(rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
        configureFieldEditor(textObj)
    }

    /// Force the field editor (an NSTextView when AppKit grants
    /// one) to use a zero `lineFragmentPadding` so the live cursor
    /// sits flush with the shared `FieldTextLayout` rect. Without
    /// this step there's a 5pt left-edge offset on the live cursor.
    private func configureFieldEditor(_ textObj: NSText) {
        guard let textView = textObj as? NSTextView,
              let container = textView.textContainer
        else { return }
        container.lineFragmentPadding = 0
        textView.textContainerInset = .zero
    }

    // MARK: - Display drawing

    override func drawInterior(
        withFrame cellFrame: NSRect,
        in controlView: NSView
    ) {
        super.drawInterior(withFrame: fieldTextRect(cellFrame), in: controlView)
    }
}
