import Testing
import Foundation
@testable import HypeCore

#if canImport(AppKit)
import AppKit
#endif

/// Regression tests for the static/editor field-text-position
/// match. Text should honor Hype's horizontal alignment while being
/// vertically centered in the field control in both static and edit
/// modes. These tests pin the shared constants and the layout helper
/// used by both paths.
#if canImport(AppKit)
@Suite("Field text position — static renderer + inline editor align pixel-for-pixel")
struct FieldRendererPaddingTests {

    @Test("FieldRenderer padding constants are 4 (default) and 8 (wideMargins)")
    func paddingConstantsAreStable() {
        #expect(FieldTextLayout.padding(wideMargins: false) == 4)
        #expect(FieldTextLayout.padding(wideMargins: true) == 8)
    }

    @Test("Scrolling-style scrollbar reserve is 16pt on both static + editor paths")
    func scrollbarReserveStable() {
        #expect(FieldTextLayout.trailingInset(fieldStyle: .scrolling) == 16)
        #expect(FieldTextLayout.trailingInset(fieldStyle: .rectangle) == 0)
    }

    @Test("Search fields reserve leading icon space")
    func searchFieldsReserveLeadingIconSpace() {
        #expect(FieldTextLayout.leadingInset(fieldStyle: .search) == 24)
        #expect(FieldTextLayout.leadingInset(fieldStyle: .rectangle) == 0)
    }

    @Test("Single-line field text is vertically centered within padded content")
    func singleLineTextIsVerticallyCentered() {
        let font = NSFont.systemFont(ofSize: 14)
        let attributed = NSAttributedString(string: "Hello", attributes: [.font: font])
        let fieldRect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let content = FieldTextLayout.contentRect(
            in: fieldRect,
            wideMargins: false,
            fieldStyle: .rectangle
        )
        let textRect = FieldTextLayout.verticallyCenteredTextRect(
            in: fieldRect,
            wideMargins: false,
            fieldStyle: .rectangle,
            attributedString: attributed,
            fallbackFont: font
        )

        let topGap = textRect.minY - content.minY
        let bottomGap = content.maxY - textRect.maxY
        #expect(textRect.minY > content.minY)
        #expect(abs(topGap - bottomGap) <= 1)
    }

    @Test("Oversized multiline field text keeps the top padded edge")
    func oversizedMultilineTextUsesTopPaddedEdge() {
        let font = NSFont.systemFont(ofSize: 18)
        let text = Array(repeating: "Line", count: 20).joined(separator: "\n")
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let fieldRect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let content = FieldTextLayout.contentRect(
            in: fieldRect,
            wideMargins: false,
            fieldStyle: .rectangle
        )
        let textRect = FieldTextLayout.verticallyCenteredTextRect(
            in: fieldRect,
            wideMargins: false,
            fieldStyle: .rectangle,
            attributedString: attributed,
            fallbackFont: font
        )

        #expect(textRect.minY == content.minY)
        #expect(textRect.height == content.height)
    }

    @Test("Theme field palette uses theme tokens for default field colors")
    func themePaletteUsesFieldTokensForDefaultColors() {
        let part = Part(partType: .field)
        let palette = FieldTextLayout.palette(for: part, theme: BuiltInThemes.modernDark)

        #expect(palette.fill.hexString == "#1A1A22")
        #expect(palette.stroke.hexString == "#404048")
        #expect(palette.text.hexString == "#E8E8EC")
    }

    @Test("Explicit field colors override theme defaults")
    func explicitFieldColorsOverrideThemeDefaults() {
        var part = Part(partType: .field)
        part.fillColor = "#FF0000"
        part.strokeColor = "#00FF00"
        part.fontColor = "#123456"

        let palette = FieldTextLayout.palette(for: part, theme: BuiltInThemes.modernDark)

        #expect(palette.fill.hexString == "#FF0000")
        #expect(palette.stroke.hexString == "#00FF00")
        #expect(palette.text.hexString == "#123456")
    }
}
#endif
