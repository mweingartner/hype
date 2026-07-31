import AppKit
import SwiftUI
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("HypeTalk editor appearance")
struct HypeTalkTextViewAppearanceTests {
    private struct EditorHost: View {
        @State var text = """
            on mouseUp
              answer "Hello"
            end mouseUp
            """
        @State var selection = NSRange(location: 0, length: 0)

        var body: some View {
            HypeTalkTextView(text: $text, selectedRange: $selection)
        }
    }

    private final class ScriptDocumentBox {
        var document: HypeDocumentWrapper

        init(document: HypeDocumentWrapper) {
            self.document = document
        }
    }

    private struct ScriptEditorHost: View {
        let box: ScriptDocumentBox
        let partId: UUID

        var body: some View {
            ScriptEditor(
                document: Binding(
                    get: { box.document },
                    set: { box.document = $0 }
                ),
                partId: partId,
                target: .part(partId)
            )
        }
    }

    @Test("light and dark script palettes resolve to opaque contrasting colors")
    func palettesResolveWithReadableForegrounds() throws {
        for theme in [HypeScriptTheme.defaultLight, HypeScriptTheme.defaultDark] {
            let palette = HypeTalkTextView.Coordinator.resolvedPalette(for: theme)
            let foreground = try rgb(palette.foreground)
            let background = try rgb(palette.background)

            #expect(palette.foreground.alphaComponent == 1)
            #expect(palette.background.alphaComponent == 1)
            #expect(contrast(foreground, background) >= 7)
        }
    }

    @Test("script palette chooses an appearance matching its background")
    func paletteAppearanceMatchesBackground() {
        let light = HypeTalkTextView.Coordinator.resolvedPalette(for: .defaultLight)
        let dark = HypeTalkTextView.Coordinator.resolvedPalette(for: .defaultDark)

        #expect(light.appearance.name == .aqua)
        #expect(dark.appearance.name == .darkAqua)
    }

    @Test("native text view expands to the scroll view content area")
    func documentViewUsesScrollContentSize() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let textView = NSTextView(frame: .zero)
        scrollView.documentView = textView

        HypeTalkTextView.Coordinator.sizeDocumentView(textView, in: scrollView)

        #expect(textView.frame.width == scrollView.contentSize.width)
        #expect(textView.frame.height >= scrollView.contentSize.height)
        #expect(textView.textContainer?.containerSize.width == scrollView.contentSize.width - 52)
    }

    @Test("hosted editor lays out visible glyphs")
    func hostedEditorLaysOutVisibleGlyphs() throws {
        let hostingView = NSHostingView(rootView: EditorHost())
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let textView = try #require(findTextView(in: hostingView))
        let scrollView = try #require(textView.enclosingScrollView)
        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let glyphBounds = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        ).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)

        #expect(textView.string.contains("mouseUp"))
        #expect(textView.frame.width > 0)
        #expect(glyphRange.length > 0)
        #expect(glyphBounds.width > 0)
        #expect(textView.visibleRect.intersects(glyphBounds))
        #expect(scrollView.verticalRulerView?.clientView === textView)
        let visibleGlyphOverlay = try #require(
            scrollView.layer?.sublayers?
                .compactMap { $0 as? HypeTalkGlyphOverlayLayer }
                .first
        )
        #expect(visibleGlyphOverlay.superlayer === scrollView.layer)
        #expect(visibleGlyphOverlay.renderedText.contains("mouseUp"))
        #expect(visibleGlyphOverlay.sublayers?.contains { $0 is CATextLayer } == true)
    }

    @Test("open script editor adopts external document script changes")
    func hostedScriptEditorAdoptsExternalScriptChanges() throws {
        var document = HypeDocument.newDocument(name: "Script Sync")
        let cardId = try #require(document.sortedCards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = "on mouseUp\n  beep\nend mouseUp"
        document.addPart(button)

        var wrapper = HypeDocumentWrapper()
        wrapper.document = document
        let box = ScriptDocumentBox(document: wrapper)
        let hostingView = NSHostingView(rootView: ScriptEditorHost(box: box, partId: button.id))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1100, height: 680)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        let textView = try #require(findTextView(
            in: hostingView,
            accessibilityIdentifier: HypeAccessibilityID.scriptEditorText
        ))
        #expect(textView.string == button.script)

        let replacement = "on mouseUp\n  answer \"Updated externally\"\nend mouseUp"
        box.document.document.updatePart(id: button.id) { part in
            part.script = replacement
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        #expect(textView.string == replacement)
    }

    private func rgb(_ color: NSColor) throws -> (CGFloat, CGFloat, CGFloat) {
        let converted = try #require(color.usingColorSpace(.sRGB))
        return (converted.redComponent, converted.greenComponent, converted.blueComponent)
    }

    private func contrast(
        _ foreground: (CGFloat, CGFloat, CGFloat),
        _ background: (CGFloat, CGFloat, CGFloat)
    ) -> CGFloat {
        let a = luminance(foreground)
        let b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ rgb: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }

    private func findTextView(
        in view: NSView,
        accessibilityIdentifier: String? = nil
    ) -> NSTextView? {
        if let textView = view as? NSTextView,
           accessibilityIdentifier == nil
                || textView.accessibilityIdentifier() == accessibilityIdentifier {
            return textView
        }
        for subview in view.subviews {
            if let textView = findTextView(
                in: subview,
                accessibilityIdentifier: accessibilityIdentifier
            ) {
                return textView
            }
        }
        return nil
    }
}
