import AppKit

/// Custom NSTextFieldCell whose text drawing rect matches
/// `FieldRenderer.draw` byte-for-byte, so the inline editor
/// overlay puts characters at the same screen position as the
/// static rendering.
///
/// **Why this exists**
///
/// The static path renders field text via `NSString.draw(in:)`
/// inside `rect.insetBy(dx: padding, dy: padding)` (4 or 8 for
/// wideMargins). NSTextField's default cell instead uses an
/// intrinsic ~2pt edge inset PLUS a 5pt `lineFragmentPadding` in
/// its underlying text container, AND it vertically centers
/// single-line text. Together those produce a 2-6pt jump in both
/// axes when the user taps a field — characters slide right and
/// up (or down) at the moment editing begins, and slide back when
/// editing ends.
///
/// This cell forces:
/// - drawingRect / titleRect = `rect.insetBy(dx: padding, dy: padding)`
/// - the field-editor's frame to match (so the live cursor sits
///   in the same place the static text drew)
/// - `wraps = true`, `usesSingleLineMode = false` to disable the
///   vertical-centering shortcut and keep text top-aligned (which
///   is what FieldRenderer does)
final class HypeFieldEditorCell: NSTextFieldCell {

    /// Symmetric inset matching `FieldRenderer.draw`'s
    /// `rect.insetBy(dx: padding, dy: padding)`. Defaults to 4
    /// (the renderer's value when `wideMargins` is false).
    var hypePadding: CGFloat = 4

    /// When the field has the `scrolling` style, FieldRenderer
    /// reserves 16pt on the right edge for the scrollbar track
    /// (see `FieldRenderer.swift` line 62). Mirror that here so
    /// the editor's text wraps at the same column the static
    /// rendering does.
    var rightScrollbarReserve: CGFloat = 0

    private func paddedRect(_ rect: NSRect) -> NSRect {
        let inset = NSRect(
            x: rect.minX + hypePadding,
            y: rect.minY + hypePadding,
            width: max(0, rect.width - hypePadding * 2 - rightScrollbarReserve),
            height: max(0, rect.height - hypePadding * 2)
        )
        return inset
    }

    // MARK: - Layout overrides

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        // The default implementation adds its own intrinsic ~2pt
        // inset on top of whatever we return; bypass by skipping
        // super entirely.
        paddedRect(rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        paddedRect(rect)
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
            withFrame: paddedRect(rect),
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
            withFrame: paddedRect(rect),
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
    /// sits flush with `paddedRect.minX` — matching how
    /// `NSString.draw` lays out the static text. Without this
    /// step there's a 5pt left-edge offset on the live cursor.
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
        super.drawInterior(withFrame: paddedRect(cellFrame), in: controlView)
    }
}
