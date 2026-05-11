import Testing
import Foundation
@testable import Hype
@testable import HypeCore

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("Inline field editor layout")
struct FieldEditorCellLayoutTests {

    @Test("Editor cell vertically centers single-line text like static renderer")
    func editorCellVerticallyCentersSingleLineText() {
        let cell = HypeFieldEditorCell(textCell: "Hello")
        cell.font = NSFont.systemFont(ofSize: 14)
        cell.hypePadding = FieldTextLayout.padding(wideMargins: false)

        let bounds = NSRect(x: 0, y: 0, width: 200, height: 60)
        let content = FieldTextLayout.contentRect(
            in: bounds,
            wideMargins: false,
            fieldStyle: .rectangle
        )
        let title = cell.titleRect(forBounds: bounds)

        let topGap = title.minY - content.minY
        let bottomGap = content.maxY - title.maxY
        #expect(title.minX == content.minX)
        #expect(title.width == content.width)
        #expect(title.minY > content.minY)
        #expect(abs(topGap - bottomGap) <= 1)
    }

    @Test("Editor cell applies search leading inset and scrolling trailing reserve")
    func editorCellAppliesStyleInsets() {
        let cell = HypeFieldEditorCell(textCell: "Hello")
        cell.font = NSFont.systemFont(ofSize: 14)
        cell.hypePadding = FieldTextLayout.padding(wideMargins: false)
        cell.leadingTextInset = FieldTextLayout.leadingInset(fieldStyle: .search)
        cell.rightScrollbarReserve = FieldTextLayout.trailingInset(fieldStyle: .scrolling)

        let bounds = NSRect(x: 0, y: 0, width: 200, height: 60)
        let title = cell.titleRect(forBounds: bounds)

        #expect(title.minX == 28)
        #expect(title.width == 152)
    }
}
#endif
