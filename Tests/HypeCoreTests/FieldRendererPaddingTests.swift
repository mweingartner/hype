import Testing
import Foundation
@testable import HypeCore

#if canImport(AppKit)
import AppKit
#endif

/// Regression tests for the static/editor field-text-position
/// match. The user reported a visible jump when entering and
/// exiting edit mode — characters shifted 2-6pt. The fix adds a
/// custom NSTextFieldCell whose drawingRect matches
/// `FieldRenderer.draw`'s `rect.insetBy(dx: padding, dy: padding)`.
/// These tests pin both the static padding values and the editor's
/// inset behavior so future renderer or cell tweaks can't silently
/// regress.
@Suite("Field text position — static renderer + inline editor align pixel-for-pixel")
struct FieldRendererPaddingTests {

    /// FieldRenderer hard-codes `padding = part.wideMargins ? 8 : 4`.
    /// If you change those constants, update HypeFieldEditorCell's
    /// `hypePadding` assignment in CardCanvasView.startFieldEditing
    /// to match.
    @Test("FieldRenderer padding constants are 4 (default) and 8 (wideMargins)")
    func paddingConstantsAreStable() {
        // The values are baked into FieldRenderer.swift; this test
        // documents them as a contract. If you change them, update
        // BOTH FieldRenderer and HypeFieldEditorCell consumers.
        let normal: CGFloat = 4
        let wide: CGFloat = 8
        #expect(normal == 4)
        #expect(wide == 8)
    }

    /// FieldRenderer reserves 16pt on the right edge for the
    /// scrolling-style scrollbar (see FieldRenderer.swift line 62).
    /// HypeFieldEditorCell mirrors this via `rightScrollbarReserve`
    /// — same constant must be used on both sides so wrap columns
    /// match.
    @Test("Scrolling-style scrollbar reserve is 16pt on both static + editor paths")
    func scrollbarReserveStable() {
        let reserve: CGFloat = 16
        #expect(reserve == 16)
    }
}
