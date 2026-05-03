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

    @Test("Map location defaults to empty string")
    func mapLocationDefault() {
        let part = Part(partType: .map, name: "store")
        #expect(part.mapLocation == "")
    }

    @Test("Map location round-trips through Codable")
    func mapLocationCodable() throws {
        var part = Part(partType: .map, name: "store")
        part.mapLocation = "97537"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.mapLocation == "97537")
    }

    @Test("Map location backward-compat: JSON without mapLocation decodes to empty string")
    func mapLocationBackwardCompat() throws {
        var part = Part(partType: .map, name: "store")
        part.mapLocation = "Rogue River, OR"
        var dict = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(part)
        ) as! [String: Any]
        dict.removeValue(forKey: "mapLocation")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.mapLocation == "")
    }

    @Test("create_map with location writes mapLocation, leaves lat/lon at SF defaults")
    func aiCreateMapWithLocation() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_map",
            arguments: [
                "name": "store",
                "left": "0", "top": "0", "width": "400", "height": "300",
                "location": "Rogue River, OR"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .map }
        #expect(part?.mapLocation == "Rogue River, OR")
        // lat/lon remain at the Part defaults when no explicit center args given
        #expect(part?.mapCenterLat == 37.7749)
        #expect(part?.mapCenterLon == -122.4194)
    }

    @Test("set_part_property accepts location on a map")
    func aiSetMapLocation() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_map",
            arguments: ["name": "store", "left": "0", "top": "0", "width": "400", "height": "300"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "store", "property": "location", "value": "97537"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .map }?.mapLocation == "97537")
    }

    @Test("HypeTalk parser accepts `the location of map \"store\"`")
    func hypeTalkMapLocation() throws {
        let source = "the location of map \"store\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "location",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "map")
        } else {
            Issue.record("expected propertyAccess(location, objectRef(map, ...)), got \(expr)")
        }
    }

    @Test("mapLocation is clamped to 256 chars via set_part_property")
    func mapLocationClampedTo256() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_map",
            arguments: ["name": "store", "left": "0", "top": "0", "width": "400", "height": "300"],
            document: &doc, currentCardId: cardId
        )
        let longValue = String(repeating: "A", count: 1000)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "store", "property": "location", "value": longValue],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .map }?.mapLocation.count == 256)
    }

    @Test("HypeTalk: `set the location of map \"X\" to \"97537\"` routes to mapLocation (not coords)")
    func hypeTalkMapLocationOverloadString() throws {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let originalLeft: Double = 100
        let originalTop: Double = 50
        let part = Part(partType: .map, cardId: cardId, name: "store",
                        left: originalLeft, top: originalTop, width: 400, height: 300)
        doc.addPart(part)

        let source = "on test\n  set the location of map \"store\" to \"97537\"\nend test"
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)

        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "store" }!
        #expect(updated.mapLocation == "97537")
        // Geometry must NOT have moved.
        #expect(updated.left == originalLeft)
        #expect(updated.top == originalTop)
    }

    @Test("HypeTalk: `set the location of map \"X\" to \"100,200\"` still moves the part (coords)")
    func hypeTalkMapLocationOverloadCoords() throws {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let part = Part(partType: .map, cardId: cardId, name: "store",
                        left: 0, top: 0, width: 400, height: 300)
        doc.addPart(part)

        let source = "on test\n  set the location of map \"store\" to \"100,200\"\nend test"
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)

        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "store" }!
        // 100,200 is a center so left = 100 - 400/2 = -100, top = 200 - 300/2 = 50.
        #expect(updated.left == -100)
        #expect(updated.top == 50)
        #expect(updated.mapLocation == "")
    }

    @Test("HypeTalk: cross-object — a button's mouseUp script can set the location of a map part")
    func hypeTalkButtonScriptSetsMapLocation() throws {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let map = Part(partType: .map, cardId: cardId, name: "store",
                       left: 0, top: 0, width: 400, height: 300)
        let btn = Part(partType: .button, cardId: cardId, name: "trigger",
                       left: 500, top: 0, width: 100, height: 30)
        doc.addPart(map)
        doc.addPart(btn)

        // Compose a button-style mouseUp handler — exactly what an
        // author would type into a button or text-field script.
        let source = """
        on mouseUp
          set the location of map "store" to "97537"
        end mouseUp
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: btn.id, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)

        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "store" }!
        #expect(updated.mapLocation == "97537")
    }

    @Test("AI tool getter: `location` on map returns mapLocation when set")
    func aiGetMapLocationWhenSet() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        var part = Part(partType: .map, cardId: cardId, name: "store",
                        left: 100, top: 200, width: 400, height: 300)
        part.mapLocation = "97537"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let read = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "store", "property": "location"],
            document: &doc, currentCardId: cardId
        )
        #expect(read == "97537")
    }

    @Test("AI tool: list_all_properties returns map-specific properties")
    func aiListAllPropertiesMap() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_map",
            arguments: ["name": "store", "left": "0", "top": "0", "width": "400", "height": "300", "location": "97537"],
            document: &doc, currentCardId: cardId
        )
        let result = await executor.execute(
            toolName: "list_all_properties",
            arguments: ["part_name": "store"],
            document: &doc, currentCardId: cardId
        )
        // Map-specific section is present
        #expect(result.contains("centerLat"))
        #expect(result.contains("centerLon"))
        #expect(result.contains("span"))
        #expect(result.contains("mapType"))
        #expect(result.contains("location"))
        #expect(result.contains("annotations"))
        #expect(result.contains("97537"))
        // Common section is present
        #expect(result.contains("visible"))
        #expect(result.contains("script"))
        #expect(result.contains("textFont"))
        // Setter hint is present
        #expect(result.contains("set_part_property"))
        #expect(result.contains("HypeTalk"))
    }

    @Test("AI tool: list_all_properties returns Part not found for unknown name")
    func aiListAllPropertiesNotFound() async {
        var doc = HypeDocument.newDocument(name: "MapTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "list_all_properties",
            arguments: ["part_name": "doesNotExist"],
            document: &doc, currentCardId: cardId
        )
        #expect(result.contains("not found"))
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
