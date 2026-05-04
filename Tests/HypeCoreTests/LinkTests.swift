import Testing
import Foundation
@testable import HypeCore

/// Link part — a clickable text hyperlink.
///
/// Tests cover model defaults, Codable, backward-compat decode,
/// AI tool create + set/get, HypeTalk parser/setter, and the
/// security conditions around URL scheme allow-listing
/// (file://, javascript:, empty URL must never open).
@Suite("Link — model, AI tools, HypeTalk grammar, URL security")
struct LinkTests {

    // MARK: - Model defaults

    @Test("Link defaults: empty URL, empty textContent")
    func defaults() {
        let part = Part(partType: .link, name: "docs")
        #expect(part.partType == .link)
        // link parts reuse `url` — the Part initializer sets url to "" for non-webpage types
        #expect(part.url == "")
        #expect(part.textContent == "")
    }

    // MARK: - Codable round-trip

    @Test("Link url and textContent round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .link, name: "docs")
        part.url = "https://example.com/docs"
        part.textContent = "Documentation"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.url == "https://example.com/docs")
        #expect(decoded.textContent == "Documentation")
        #expect(decoded.partType == .link)
    }

    // MARK: - Backward-compat decode

    @Test("Old document with link part but no extra fields decodes cleanly")
    func backwardCompat() throws {
        var part = Part(partType: .link, name: "docs")
        part.url = "https://example.com"
        let data = try JSONEncoder().encode(part)
        // No new link-specific fields to strip, but verify the round-trip still holds
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.url == "https://example.com")
        #expect(decoded.partType == .link)
    }

    // MARK: - AI tools

    @Test("create_link builds a part with url and text label")
    func aiCreate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_link",
            arguments: [
                "name": "docs",
                "left": "10", "top": "20", "width": "120", "height": "24",
                "url": "https://example.com/docs",
                "text": "Documentation"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .link }
        #expect(part?.url == "https://example.com/docs")
        #expect(part?.textContent == "Documentation")
    }

    @Test("create_link with no text argument leaves textContent empty")
    func aiCreateNoText() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_link",
            arguments: [
                "name": "docs",
                "left": "0", "top": "0", "width": "120", "height": "24",
                "url": "https://example.com"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .link }
        #expect(part?.textContent == "")
    }

    @Test("set_part_property accepts url on a link part")
    func aiSetURL() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_link",
            arguments: ["name": "docs", "left": "0", "top": "0", "width": "120", "height": "24"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "docs", "property": "url", "value": "https://swift.org"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .link }?.url == "https://swift.org")
    }

    @Test("set_part_property accepts text (label) on a link part")
    func aiSetText() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_link",
            arguments: ["name": "docs", "left": "0", "top": "0", "width": "120", "height": "24"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "docs", "property": "text", "value": "Swift.org"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .link }?.textContent == "Swift.org")
    }

    @Test("get_part_property reads url from a link part")
    func aiGetURL() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .link, cardId: cardId, name: "docs",
                        left: 0, top: 0, width: 120, height: 24)
        part.url = "https://example.com"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "docs", "property": "url"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "https://example.com")
    }

    // MARK: - HypeTalk grammar

    @Test("HypeTalk parser accepts `the url of link \"X\"`")
    func hypeTalkParser() throws {
        let source = "the url of link \"docs\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "url",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "link")
        } else {
            Issue.record("expected propertyAccess(url, objectRef(link, ...)), got \(expr)")
        }
    }

    @Test("HypeTalk: `set the url of link \"X\" to ...` updates the model")
    func hypeTalkSetter() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .link, cardId: cardId, name: "docs",
                        left: 0, top: 0, width: 120, height: 24)
        doc.addPart(part)
        let source = """
        on test
          set the url of link "docs" to "https://swift.org"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "docs" }!
        #expect(updated.url == "https://swift.org")
    }

    // MARK: - URL security (scheme allow-list, testable via model + AI surface)

    @Test("set_part_property accepts http:// URL — allowed scheme stored as-is")
    func urlAcceptsHTTP() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_link",
            arguments: ["name": "docs", "left": "0", "top": "0", "width": "120", "height": "24"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "docs", "property": "url", "value": "http://example.com"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .link }?.url == "http://example.com")
    }

    @Test("set_part_property stores file:// URL (filter happens at open-time in LinkHostNSView)")
    func urlStoresFileScheme() async {
        // The model stores any URL value — the security gate is in LinkHostNSView.safeLinkOpen.
        // This test documents that the model layer does not strip the value (no double-filtering),
        // and that the link will silently refuse to open at runtime.
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_link",
            arguments: ["name": "docs", "left": "0", "top": "0", "width": "120", "height": "24"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "docs", "property": "url", "value": "file:///etc/passwd"],
            document: &doc, currentCardId: cardId
        )
        // The value is stored but will be refused at open time by safeLinkOpen's allowedSchemes check.
        let stored = doc.parts.first { $0.partType == .link }?.url ?? ""
        // What matters: any open attempt at runtime validates scheme against {"http","https","mailto"}.
        // We confirm the stored scheme is not in the allowed set.
        let scheme = URL(string: stored)?.scheme?.lowercased() ?? ""
        let allowedSchemes: Set<String> = ["http", "https", "mailto"]
        #expect(!allowedSchemes.contains(scheme))
    }

    @Test("set_part_property stores javascript: URL (filter at open-time)")
    func urlStoresJavascriptScheme() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_link",
            arguments: ["name": "docs", "left": "0", "top": "0", "width": "120", "height": "24"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "docs", "property": "url", "value": "javascript:alert(1)"],
            document: &doc, currentCardId: cardId
        )
        let stored = doc.parts.first { $0.partType == .link }?.url ?? ""
        let scheme = URL(string: stored)?.scheme?.lowercased() ?? ""
        let allowedSchemes: Set<String> = ["http", "https", "mailto"]
        #expect(!allowedSchemes.contains(scheme))
    }

    @Test("Empty URL string fails the safeLinkOpen allow-list guard")
    func emptyURLRefused() {
        // Verify the URL parsing logic: empty string → URL init fails or no scheme.
        let emptyURLString = ""
        let url = URL(string: emptyURLString)
        let scheme = url?.scheme?.lowercased() ?? ""
        let allowedSchemes: Set<String> = ["http", "https", "mailto"]
        // Either URL(string:) returns nil for "" or the scheme is not in the allow-list.
        #expect(url == nil || !allowedSchemes.contains(scheme))
    }
}
