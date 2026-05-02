import Testing
import Foundation
@testable import HypeCore

/// Calendar part type — the first new framework-backed control after
/// the AppleFrameworksRoadmap kicked off. Verifies the model layer +
/// AI tool surface end-to-end without needing an AppKit picker on
/// screen.
@Suite("Calendar part — model, AI tools, HypeTalk grammar")
struct CalendarPartTests {

    // MARK: - Model

    @Test("Part defaults: empty selectedDate, graphical style")
    func defaults() {
        let part = Part(partType: .calendar, name: "due")
        #expect(part.partType == .calendar)
        #expect(part.selectedDate == "")
        #expect(part.displayMonth == "")
        #expect(part.minDate == "")
        #expect(part.maxDate == "")
        #expect(part.calendarStyle == "graphical")
    }

    @Test("Calendar fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .calendar, name: "due")
        part.selectedDate = "2026-12-25"
        part.displayMonth = "2026-12-01"
        part.minDate = "2026-01-01"
        part.maxDate = "2027-12-31"
        part.calendarStyle = "clockAndCalendar"

        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.selectedDate == "2026-12-25")
        #expect(decoded.displayMonth == "2026-12-01")
        #expect(decoded.minDate == "2026-01-01")
        #expect(decoded.maxDate == "2027-12-31")
        #expect(decoded.calendarStyle == "clockAndCalendar")
    }

    @Test("Decoder accepts a pre-calendar Part JSON without the new keys")
    func backwardCompatDecoder() throws {
        // Build a JSON object that mimics the Part shape from before
        // the calendar fields were added. The decoder must default
        // the missing fields (decodeIfPresent), not throw.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "partType": "button",
          "name": "play",
          "sortKey": "a0",
          "left": 100,
          "top": 100,
          "width": 120,
          "height": 40,
          "rotation": 0,
          "visible": true,
          "enabled": true,
          "hilite": false,
          "autoHilite": true,
          "textContent": "Play",
          "textFont": "System",
          "textSize": 14,
          "textStyle": "plain",
          "textAlign": "center",
          "buttonStyle": "rectangle",
          "showName": true,
          "family": 0,
          "popupItems": "",
          "fieldStyle": "rectangle",
          "lockText": false,
          "dontWrap": false,
          "wideMargins": false,
          "richText": false,
          "enterKeyEnabled": false,
          "htmlContent": "",
          "shapeType": "rectangle",
          "fillColor": "#FFFFFF",
          "strokeColor": "#000000",
          "strokeWidth": 1,
          "cornerRadius": 8,
          "pathData": [],
          "url": "",
          "videoURL": "",
          "chartData": "",
          "invertOnClick": false,
          "animated": true,
          "transparentBackground": false,
          "sceneSpec": "",
          "script": ""
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.partType == .button)
        #expect(decoded.selectedDate == "")
        #expect(decoded.calendarStyle == "graphical")
    }

    // MARK: - AI tool: create_calendar

    @Test("create_calendar tool builds a calendar part with the requested fields")
    func aiCreateCalendar() async {
        var doc = HypeDocument.newDocument(name: "CalTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_calendar",
            arguments: [
                "name": "due",
                "left": "50",
                "top": "60",
                "width": "300",
                "height": "200",
                "selected_date": "2026-12-25",
                "min_date": "2026-01-01",
                "max_date": "2027-12-31",
                "style": "clockAndCalendar"
            ],
            document: &doc,
            currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .calendar && $0.name == "due" }
        #expect(part != nil)
        #expect(part?.left == 50)
        #expect(part?.top == 60)
        #expect(part?.width == 300)
        #expect(part?.height == 200)
        #expect(part?.selectedDate == "2026-12-25")
        #expect(part?.minDate == "2026-01-01")
        #expect(part?.maxDate == "2027-12-31")
        #expect(part?.calendarStyle == "clockAndCalendar")
    }

    @Test("create_calendar with unknown style falls back to graphical")
    func aiUnknownStyle() async {
        var doc = HypeDocument.newDocument(name: "CalTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_calendar",
            arguments: ["name": "due", "left": "0", "top": "0", "width": "200", "height": "200", "style": "purple-monkey-dishwasher"],
            document: &doc,
            currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .calendar }
        #expect(part?.calendarStyle == "graphical")
    }

    @Test("set_part_property accepts selected_date on a calendar")
    func aiSetSelectedDate() async {
        var doc = HypeDocument.newDocument(name: "CalTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_calendar",
            arguments: ["name": "due", "left": "0", "top": "0", "width": "200", "height": "200"],
            document: &doc,
            currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "due", "property": "selected_date", "value": "2026-07-04"],
            document: &doc,
            currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .calendar }
        #expect(part?.selectedDate == "2026-07-04")
    }

    @Test("get_part_property reads the selectedDate")
    func aiGetSelectedDate() async {
        var doc = HypeDocument.newDocument(name: "CalTest")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_calendar",
            arguments: ["name": "due", "left": "0", "top": "0", "width": "200", "height": "200", "selected_date": "2026-09-15"],
            document: &doc,
            currentCardId: cardId
        )
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "due", "property": "selected_date"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result == "2026-09-15")
    }

    // MARK: - HypeTalk grammar

    @Test("HypeTalk parser accepts `the selectedDate of calendar \"X\"`")
    func hypeTalkParse() throws {
        let source = "on openCard\n  put the selectedDate of calendar \"due\" into d\nend openCard"
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].name == "openCard")
    }

    @Test("HypeTalk parser builds an objectRef(calendar, X) AST node")
    func hypeTalkObjectRefAST() throws {
        let source = "the selectedDate of calendar \"due\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr {
            #expect(prop == "selectedDate")
            if case .objectRef(let ref) = target ?? .literal("") {
                #expect(ref.objectType == "calendar")
            } else {
                Issue.record("expected objectRef target, got \(String(describing: target))")
            }
        } else {
            Issue.record("expected propertyAccess, got \(expr)")
        }
    }
}
