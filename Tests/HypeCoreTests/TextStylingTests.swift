import Testing
import Foundation
@testable import HypeCore

// MARK: - Test Helpers

/// Minimal test doc used by HypeTalk get/set tests in this file.
/// We mirror the shape of `makeTestDoc()` in ComprehensiveScriptTests
/// (a button + a field on the first card) so the existing
/// dispatcher patterns work unchanged.
private func makeTestDoc() -> (HypeDocument, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id

    var btn = Part(partType: .button, cardId: cardId, name: "TestButton",
                   left: 10, top: 10, width: 100, height: 30)
    btn.script = ""
    doc.addPart(btn)

    var field = Part(partType: .field, cardId: cardId, name: "output",
                     left: 10, top: 50, width: 200, height: 30)
    doc.addPart(field)

    return (doc, cardId, btn.id)
}

/// Run a HypeTalk handler on the named target. The 8 MB-stack
/// thread mirrors `runOnLargeStack` usage elsewhere in the suite.
private func runScript(_ script: String,
                       on doc: inout HypeDocument,
                       cardId: UUID,
                       targetId: UUID) async -> ExecutionResult {
    doc.updatePart(id: targetId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    let snapshot = doc
    let result = await runOnLargeStack {
        dispatcher.dispatch(
            message: "mouseUp", params: [], targetId: targetId,
            document: snapshot, currentCardId: cardId
        )
    }
    if let modified = result.modifiedDocument { doc = modified }
    return result
}

/// Sprite-area test doc: one card with a single label node so we
/// can exercise the `textStyle of node ... of card sprite area ...`
/// HypeTalk path.
private func makeSpriteLabelDoc() -> (HypeDocument, UUID, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id

    var btn = Part(partType: .button, cardId: cardId, name: "Trigger",
                   left: 0, top: 0, width: 50, height: 30)
    btn.script = ""
    doc.addPart(btn)

    var area = Part(partType: .spriteArea, cardId: cardId, name: "scene",
                    left: 0, top: 0, width: 400, height: 300)
    var spec = SceneSpec(name: "Main", size: SizeSpec(width: 400, height: 300))
    let label = HypeNodeSpec(name: "Title", nodeType: .label,
                             position: PointSpec(x: 50, y: 50),
                             text: "Hello", fontName: "Helvetica",
                             fontSize: 24, fontColor: "#000000")
    spec.nodes = [label]
    // Sprite-area scene state lives in the JSON-encoded
    // `sceneSpec` payload — `activeSceneSpec` is a derived
    // accessor. Set the persisted form, mirroring the pattern in
    // `ComprehensiveScriptTests.makeSceneDoc()`.
    area.sceneSpec = spec.toJSON()
    doc.addPart(area)

    return (doc, cardId, btn.id, label.id)
}

// MARK: - TextStyleFlags parser

@Suite("TextStyleFlags parser & emitter")
struct TextStyleFlagsParserTests {

    @Test func plainAndEmptyAreEquivalent() {
        // Empty string and "plain" should both parse to all-false.
        let a = TextStyleFlags(string: "")
        let b = TextStyleFlags(string: "plain")
        #expect(a.isPlain)
        #expect(b.isPlain)
        #expect(a == b)
        // Canonical emit of plain is the literal "plain".
        #expect(a.rawString == "plain")
    }

    @Test func singleFlagsParse() {
        #expect(TextStyleFlags(string: "bold").bold)
        #expect(TextStyleFlags(string: "italic").italic)
        #expect(TextStyleFlags(string: "underline").underline)
        #expect(TextStyleFlags(string: "strikethrough").strikethrough)
    }

    @Test func combinedFlags() {
        let f = TextStyleFlags(string: "bold,italic")
        #expect(f.bold)
        #expect(f.italic)
        #expect(!f.underline)
        #expect(!f.strikethrough)
    }

    @Test func whitespaceAndCaseInsensitive() {
        // "BOLD,  Italic , underline " should parse identically to
        // the canonical lowercased "bold, italic, underline".
        let messy = TextStyleFlags(string: "BOLD,  Italic , underline ")
        let clean = TextStyleFlags(string: "bold, italic, underline")
        #expect(messy == clean)
    }

    @Test func aliases() {
        // strike / strikeout → strikethrough
        #expect(TextStyleFlags(string: "strike").strikethrough)
        #expect(TextStyleFlags(string: "strikeout").strikethrough)
        // underlined → underline
        #expect(TextStyleFlags(string: "underlined").underline)
    }

    @Test func unknownTokensIgnored() {
        // Forward-compat: an unknown token shouldn't blow up. The
        // known tokens still apply.
        let f = TextStyleFlags(string: "bold, sparkly, italic")
        #expect(f.bold)
        #expect(f.italic)
    }

    @Test func rawStringRoundTrip() {
        // Setting flags directly should emit a stable canonical
        // string, and re-parsing that string should produce the
        // same flags.
        let f = TextStyleFlags(bold: true, italic: false,
                               underline: true, strikethrough: false)
        #expect(f.rawString == "bold, underline")
        let again = TextStyleFlags(string: f.rawString)
        #expect(again == f)
    }

    @Test func canonicalEmitOrder() {
        // Even when constructed in an unusual order, the rawString
        // emits in the canonical bold/italic/underline/strikethrough
        // order so HypeTalk `is` comparisons stay reliable.
        let f = TextStyleFlags(bold: true, italic: true,
                               underline: true, strikethrough: true)
        #expect(f.rawString == "bold, italic, underline, strikethrough")
    }
}

// MARK: - Codable round-trip

@Suite("Text-styling Codable round-trip")
struct TextStylingCodableTests {

    @Test func partFontColorRoundTrip() throws {
        var p = Part(partType: .field, name: "f", left: 0, top: 0, width: 100, height: 30)
        p.fontColor = "#33AAFF"
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.fontColor == "#33AAFF")
    }

    @Test func partFontColorDefaultIsEmpty() throws {
        // A part encoded WITHOUT a fontColor key (forward-compat
        // path) decodes with `fontColor == ""`, the "auto" sentinel
        // the renderer's contrast-aware fallback expects. We
        // construct the legacy-shaped JSON by encoding a current
        // Part and removing the fontColor key — that gives us a
        // payload with every other required field intact.
        let p = Part(partType: .field, name: "x", left: 0, top: 0, width: 100, height: 30)
        let data = try JSONEncoder().encode(p)
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Could not parse encoded Part as JSON dict")
            return
        }
        dict.removeValue(forKey: "fontColor")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.fontColor == "")
    }

    @Test func nodeTextStyleRoundTrip() throws {
        var n = HypeNodeSpec(name: "lbl", nodeType: .label, text: "hi", textStyle: "bold, italic")
        let data = try JSONEncoder().encode(n)
        let decoded = try JSONDecoder().decode(HypeNodeSpec.self, from: data)
        #expect(decoded.textStyle == "bold, italic")

        n.textStyle = nil
        let data2 = try JSONEncoder().encode(n)
        let decoded2 = try JSONDecoder().decode(HypeNodeSpec.self, from: data2)
        #expect(decoded2.textStyle == nil)
    }
}

// MARK: - HypeTalk get / set

@Suite("HypeTalk fontColor & textStyle")
struct HypeTalkTextStylingTests {

    @Test func setFontColorOnPart() async {
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the fontColor of button "TestButton" to "#FF0000"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.fontColor == "#FF0000")
    }

    @Test func setFontColorAliases() async {
        // textColor / color should be accepted as aliases on parts.
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the textColor of button "TestButton" to "#00FF00"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.fontColor == "#00FF00")
    }

    @Test func clearFontColorBackToAuto() async {
        var (doc, cardId, btnId) = makeTestDoc()
        // Pre-set a value, then clear by setting empty.
        doc.updatePart(id: btnId) { $0.fontColor = "#123456" }
        let result = await runScript("""
        on mouseUp
          set the fontColor of button "TestButton" to ""
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.fontColor == "")
    }

    @Test func setTextStyleNormalizesAliasInput() async {
        // The setter should normalize "BOLD, italic" through
        // TextStyleFlags so the canonical "bold, italic" lands on
        // the part — round-trips through the inspector / Codable
        // stay stable.
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the textStyle of button "TestButton" to "BOLD, italic"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.textStyle == "bold, italic")
    }

    @Test func setTextStyleAliasStrike() async {
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the textStyle of button "TestButton" to "strike"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.textStyle == "strikethrough")
    }

    @Test func setTextStylePlainClearsToCanonical() async {
        // Setting "plain" stores the canonical "plain" rawString,
        // not an empty string. This matches the canonical emit and
        // keeps `the textStyle of cd btn 1 is "plain"` working.
        var (doc, cardId, btnId) = makeTestDoc()
        doc.updatePart(id: btnId) { $0.textStyle = "bold" }
        let result = await runScript("""
        on mouseUp
          set the textStyle of button "TestButton" to "plain"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let btn = result.modifiedDocument?.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.textStyle == "plain")
    }

    @Test func getFontColorReturnsLiteralStored() async {
        // Reading back must return the stored hex (or empty for
        // "auto"), not a transformed value.
        var (doc, cardId, btnId) = makeTestDoc()
        doc.updatePart(id: btnId) { $0.fontColor = "#abcdef" }
        let result = await runScript("""
        on mouseUp
          put the fontColor of button "TestButton" into field "output"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let out = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(out?.textContent == "#abcdef")
    }

    @Test func getTextStyleAfterSet() async {
        var (doc, cardId, btnId) = makeTestDoc()
        let result = await runScript("""
        on mouseUp
          set the textStyle of button "TestButton" to "italic, underline"
          put the textStyle of button "TestButton" into field "output"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let out = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(out?.textContent == "italic, underline")
    }

    @Test func setNodeTextStyleNormalizes() async {
        // Sprite-area label node — `set the X of label "Y"` resolves
        // the label through the active scene of any sprite area on
        // the current card. The setter runs the value through
        // TextStyleFlags so aliased input round-trips to the
        // canonical form.
        var (doc, cardId, btnId, _) = makeSpriteLabelDoc()
        let result = await runScript("""
        on mouseUp
          set the textStyle of label "Title" to "Bold,Strike"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)
        #expect(result.status == .completed)
        let area = result.modifiedDocument?.parts.first(where: { $0.name == "scene" })
        let label = area?.activeSceneSpec?.nodes.first(where: { $0.name == "Title" })
        #expect(label?.textStyle == "bold, strikethrough")
    }
}

// MARK: - AI tool surface

@Suite("AI tool surface for fontColor / textStyle")
struct AIToolTextStylingTests {

    @Test func setPartPropertyFontColorViaAITool() async {
        var (doc, cardId, _) = makeTestDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "TestButton",
                "property": "fontColor",
                "value": "#112233",
            ],
            document: &doc, currentCardId: cardId
        )
        let btn = doc.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.fontColor == "#112233")
    }

    @Test func setPartPropertyTextStyleNormalizesViaAITool() async {
        // The AI tool dispatcher should run the value through
        // TextStyleFlags too, matching the HypeTalk path. Otherwise
        // the model could write "BOLD,italic" via the tool and read
        // back something different via `the textStyle of cd btn 1`.
        var (doc, cardId, _) = makeTestDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "TestButton",
                "property": "textStyle",
                "value": "BOLD, italic, strike",
            ],
            document: &doc, currentCardId: cardId
        )
        let btn = doc.parts.first(where: { $0.name == "TestButton" })
        #expect(btn?.textStyle == "bold, italic, strikethrough")
    }

    @Test func formatAllPropertiesIncludesFontColor() async {
        var (doc, cardId, _) = makeTestDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "list_all_properties",
            arguments: ["part_name": "TestButton"],
            document: &doc, currentCardId: cardId
        )
        // The dump must explicitly mention fontColor and textStyle
        // — that's how the model discovers the surface.
        #expect(result.contains("fontColor"))
        #expect(result.contains("textStyle"))
    }
}

// MARK: - Renderer ink budget (regression — bold draws more pixels than plain)

#if canImport(AppKit)
import AppKit

@Suite("Renderer ink budget")
struct RendererInkBudgetTests {

    /// Render the field's text content into a CGContext-backed
    /// bitmap and count how many pixels have non-trivial luminance.
    /// Returns the count of "inked" pixels.
    private func inkPixelCount(textStyle: String) -> Int {
        let width = 200
        let height = 60

        var part = Part(partType: .field, name: "x", left: 0, top: 0,
                        width: Double(width), height: Double(height))
        part.textContent = "WWWW"  // wide glyphs amplify the
                                   // bold-vs-plain delta
        part.textFont = "Helvetica"
        part.textSize = 24
        part.fillColor = "#FFFFFF"  // white background
        part.fontColor = "#000000"  // black foreground
        part.textStyle = textStyle
        part.fieldStyle = .transparent  // skip frame strokes — we
                                        // only want text ink

        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return 0 }

        // Paint the canvas white so any ink shows up as a dark pixel.
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        FieldRenderer.draw(ctx: ctx, part: part,
                           rect: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = ctx.data else { return 0 }
        let buf = data.assumingMemoryBound(to: UInt8.self)
        var inked = 0
        for i in 0..<(width * height) {
            // Anything sufficiently darker than white counts as ink.
            if buf[i] < 200 { inked += 1 }
        }
        return inked
    }

    @Test func boldDrawsMoreInkThanPlain() {
        let plain = inkPixelCount(textStyle: "plain")
        let bold  = inkPixelCount(textStyle: "bold")
        // Both must actually draw text — a 0 means the renderer
        // bailed without drawing, which would invalidate the test.
        #expect(plain > 0)
        #expect(bold  > 0)
        // Bold should have strictly more dark pixels than plain.
        // We use a 5% margin so this isn't flaky on AA pixel jitter
        // across macOS versions / font fallback choices.
        #expect(Double(bold) > Double(plain) * 1.05)
    }
}
#endif
