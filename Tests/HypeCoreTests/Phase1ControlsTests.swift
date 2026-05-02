import Testing
import Foundation
@testable import HypeCore

/// PDF, Map, and ColorWell parts — the second wave of Phase 1
/// framework controls per AppleFrameworksRoadmap.md.
///
/// Tests focus on the model + AI tool + interpreter property
/// surface; the live PDFView/MKMapView/NSColorWell pixels are not
/// instantiated in this suite (those tests would require a
/// running window server which Swift Testing doesn't provide).
@Suite("Phase 1 controls — PDF, Map, ColorWell model + AI tools")
struct Phase1ControlsTests {

    // MARK: - PDF

    @Test("PDF defaults: empty URL, page 1, continuous mode, autoScales true")
    func pdfDefaults() {
        let part = Part(partType: .pdf, name: "manual")
        #expect(part.partType == .pdf)
        #expect(part.pdfURL == "")
        #expect(part.pdfCurrentPage == 1)
        #expect(part.pdfDisplayMode == "continuous")
        #expect(part.pdfAutoScales == true)
    }

    @Test("PDF fields round-trip through Codable")
    func pdfCodable() throws {
        var part = Part(partType: .pdf, name: "manual")
        part.pdfURL = "/tmp/manual.pdf"
        part.pdfCurrentPage = 7
        part.pdfDisplayMode = "twoUp"
        part.pdfAutoScales = false
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.pdfURL == "/tmp/manual.pdf")
        #expect(decoded.pdfCurrentPage == 7)
        #expect(decoded.pdfDisplayMode == "twoUp")
        #expect(decoded.pdfAutoScales == false)
    }

    @Test("create_pdf builds a PDF part with the requested fields")
    func aiCreatePDF() async {
        var doc = HypeDocument.newDocument(name: "PDFTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_pdf",
            arguments: [
                "name": "manual",
                "left": "10", "top": "20",
                "width": "400", "height": "500",
                "pdfurl": "/tmp/x.pdf",
                "current_page": "3",
                "display_mode": "twoUp",
                "auto_scales": "false"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .pdf }
        #expect(part?.pdfURL == "/tmp/x.pdf")
        #expect(part?.pdfCurrentPage == 3)
        #expect(part?.pdfDisplayMode == "twoUp")
        #expect(part?.pdfAutoScales == false)
    }

    @Test("set_part_property accepts current_page on a PDF")
    func aiSetPDFCurrentPage() async {
        var doc = HypeDocument.newDocument(name: "PDFTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_pdf",
            arguments: ["name": "manual", "left": "0", "top": "0", "width": "100", "height": "100"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "manual", "property": "current_page", "value": "12"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .pdf }?.pdfCurrentPage == 12)
    }

    @Test("HypeTalk parser accepts `the currentPage of pdf \"X\"`")
    func hypeTalkPDF() throws {
        let source = "the currentPage of pdf \"manual\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "currentPage",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "pdf")
        } else {
            Issue.record("expected propertyAccess(currentPage, objectRef(pdf, ...)), got \(expr)")
        }
    }

    // MARK: - Map

    @Test("Map defaults: SF coordinates, span 0.05, standard")
    func mapDefaults() {
        let part = Part(partType: .map, name: "store")
        #expect(part.mapCenterLat == 37.7749)
        #expect(part.mapCenterLon == -122.4194)
        #expect(part.mapSpan == 0.05)
        #expect(part.mapType == "standard")
        #expect(part.mapAnnotationsJSON == "")
    }

    @Test("create_map respects center / span / type arguments")
    func aiCreateMap() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_map",
            arguments: [
                "name": "store",
                "left": "0", "top": "0", "width": "400", "height": "300",
                "center_lat": "40.7128",
                "center_lon": "-74.0060",
                "span": "0.02",
                "map_type": "satellite"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .map }
        #expect(part?.mapCenterLat == 40.7128)
        #expect(part?.mapCenterLon == -74.0060)
        #expect(part?.mapSpan == 0.02)
        #expect(part?.mapType == "satellite")
    }

    @Test("add_map_annotation appends pins, clear_map_annotations empties them")
    func aiMapAnnotations() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_map",
            arguments: ["name": "store", "left": "0", "top": "0", "width": "400", "height": "300"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "add_map_annotation",
            arguments: ["map_name": "store", "lat": "40.7128", "lon": "-74.0060", "title": "NYC"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "add_map_annotation",
            arguments: ["map_name": "store", "lat": "37.7749", "lon": "-122.4194", "title": "SF"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .map }
        let json = part?.mapAnnotationsJSON ?? ""
        // Parse to count entries — encoder ordering may differ.
        let data = json.data(using: .utf8)!
        let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(arr?.count == 2)

        _ = await executor.execute(
            toolName: "clear_map_annotations",
            arguments: ["map_name": "store"],
            document: &doc, currentCardId: cardId
        )
        let cleared = doc.parts.first { $0.partType == .map }?.mapAnnotationsJSON
        #expect(cleared == "")
    }

    @Test("HypeTalk parser accepts `the centerLat of map \"X\"`")
    func hypeTalkMap() throws {
        let source = "the centerLat of map \"store\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "centerLat",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "map")
        } else {
            Issue.record("expected propertyAccess(centerLat, objectRef(map, ...)), got \(expr)")
        }
    }

    // MARK: - ColorWell

    @Test("ColorWell defaults: orange-ish hex, interactive true")
    func colorWellDefaults() {
        let part = Part(partType: .colorWell, name: "fill")
        #expect(part.colorWellHex == "#FF5500")
        #expect(part.colorWellInteractive == true)
    }

    @Test("create_color_well writes color + interactive flag")
    func aiCreateColorWell() async {
        var doc = HypeDocument.newDocument(name: "CWTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_color_well",
            arguments: [
                "name": "fill",
                "left": "0", "top": "0", "width": "60", "height": "30",
                "color": "#3399FF",
                "interactive": "false"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .colorWell }
        #expect(part?.colorWellHex == "#3399FF")
        #expect(part?.colorWellInteractive == false)
    }

    @Test("set_part_property updates colorHex on a colorWell")
    func aiSetColor() async {
        var doc = HypeDocument.newDocument(name: "CWTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_color_well",
            arguments: ["name": "fill", "left": "0", "top": "0", "width": "60", "height": "30"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "fill", "property": "color", "value": "#00CC88"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .colorWell }?.colorWellHex == "#00CC88")
    }

    @Test("HypeTalk parser accepts `the color of colorWell \"X\"`")
    func hypeTalkColorWell() throws {
        let source = "the color of colorWell \"fill\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "color",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "colorwell" || ref.objectType == "colorWell")
        } else {
            Issue.record("expected propertyAccess(color, objectRef(colorWell, ...)), got \(expr)")
        }
    }
}
