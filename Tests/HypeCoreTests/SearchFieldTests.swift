import Testing
import Foundation
@testable import HypeCore

/// SearchField part — an NSSearchField-backed text input.
///
/// Tests cover model defaults, Codable, backward-compat decode,
/// AI tool create + set/get, HypeTalk parser/setter, and the
/// security condition capping searchText at 1 KB.
@Suite("SearchField — model, AI tools, HypeTalk grammar, length cap")
struct SearchFieldTests {

    // MARK: - Model defaults

    @Test("SearchField defaults: empty text, prompt 'Search', immediate false")
    func defaults() {
        let part = Part(partType: .searchField, name: "search")
        #expect(part.partType == .searchField)
        #expect(part.searchText == "")
        #expect(part.searchPrompt == "Search")
        #expect(part.searchSendsImmediately == false)
    }

    // MARK: - Codable round-trip

    @Test("SearchField fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .searchField, name: "search")
        part.searchText = "swift"
        part.searchPrompt = "Find…"
        part.searchSendsImmediately = true
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.searchText == "swift")
        #expect(decoded.searchPrompt == "Find…")
        #expect(decoded.searchSendsImmediately == true)
    }

    // MARK: - Backward-compat decode

    @Test("Old document without searchField fields decodes with defaults")
    func backwardCompat() throws {
        var part = Part(partType: .searchField, name: "search")
        part.searchText = "hello"
        part.searchPrompt = "Type here"
        let data = try JSONEncoder().encode(part)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "searchText")
        dict.removeValue(forKey: "searchPrompt")
        dict.removeValue(forKey: "searchSendsImmediately")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.searchText == "")
        #expect(decoded.searchPrompt == "Search")
        #expect(decoded.searchSendsImmediately == false)
    }

    // MARK: - AI tools

    @Test("create_searchfield builds a part with prompt and immediate flag")
    func aiCreate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_searchfield",
            arguments: [
                "name": "search",
                "left": "10", "top": "20", "width": "200", "height": "28",
                "prompt": "Find…",
                "immediate": "true"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .searchField }
        #expect(part?.searchPrompt == "Find…")
        #expect(part?.searchSendsImmediately == true)
        // searchText is empty on creation (user hasn't typed anything)
        #expect(part?.searchText == "")
    }

    @Test("create_searchfield with immediate false creates with sendsImmediately=false")
    func aiCreateImmediateFalse() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_searchfield",
            arguments: ["name": "search", "left": "0", "top": "0", "width": "200", "height": "28",
                        "immediate": "false"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .searchField }
        #expect(part?.searchSendsImmediately == false)
    }

    @Test("set_part_property updates searchText")
    func aiSetSearchText() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_searchfield",
            arguments: ["name": "search", "left": "0", "top": "0", "width": "200", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "search", "property": "searchtext", "value": "swift"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .searchField }?.searchText == "swift")
    }

    @Test("set_part_property updates searchPrompt")
    func aiSetSearchPrompt() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_searchfield",
            arguments: ["name": "search", "left": "0", "top": "0", "width": "200", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "search", "property": "prompt", "value": "Enter query…"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .searchField }?.searchPrompt == "Enter query…")
    }

    @Test("set_part_property updates searchSendsImmediately")
    func aiSetImmediate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_searchfield",
            arguments: ["name": "search", "left": "0", "top": "0", "width": "200", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "search", "property": "immediate", "value": "true"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .searchField }?.searchSendsImmediately == true)
    }

    @Test("get_part_property reads searchText")
    func aiGetSearchText() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .searchField, cardId: cardId, name: "search",
                        left: 0, top: 0, width: 200, height: 28)
        part.searchText = "swift"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "search", "property": "searchtext"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "swift")
    }

    @Test("get_part_property reads searchPrompt")
    func aiGetSearchPrompt() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .searchField, cardId: cardId, name: "search",
                        left: 0, top: 0, width: 200, height: 28)
        part.searchPrompt = "Find…"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "search", "property": "searchprompt"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "Find…")
    }

    // MARK: - HypeTalk grammar

    @Test("HypeTalk parser accepts `the searchText of searchField \"X\"`")
    func hypeTalkParser() throws {
        let source = "the searchText of searchField \"search\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "searchText",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "searchfield")
        } else {
            Issue.record("expected propertyAccess(searchText, objectRef(searchfield, ...)), got \(expr)")
        }
    }

    @Test("HypeTalk: `set the searchText of searchField \"X\" to ...` updates the model")
    func hypeTalkSetter() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .searchField, cardId: cardId, name: "search",
                        left: 0, top: 0, width: 200, height: 28)
        doc.addPart(part)
        let source = """
        on test
          set the searchText of searchField "search" to "swift concurrency"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "search" }!
        #expect(updated.searchText == "swift concurrency")
    }

    // MARK: - Security: length caps

    @Test("searchText clamps to 1 KB (1024 chars) via set_part_property")
    func searchTextLengthCappedViaAI() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_searchfield",
            arguments: ["name": "search", "left": "0", "top": "0", "width": "200", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        let longText = String(repeating: "q", count: 2000)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "search", "property": "searchtext", "value": longText],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .searchField }?.searchText.count == 1024)
    }

    @Test("searchText clamps to 1 KB via HypeTalk setter")
    func searchTextLengthCappedViaHypeTalk() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .searchField, cardId: cardId, name: "search",
                        left: 0, top: 0, width: 200, height: 28)
        doc.addPart(part)
        let longText = String(repeating: "q", count: 2000)
        let source = """
        on test
          set the searchText of searchField "search" to "\(longText)"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let stored = (result.modifiedDocument ?? doc).parts.first { $0.name == "search" }!.searchText
        #expect(stored.count <= 1024)
    }

    @Test("searchPrompt clamps to 256 chars via set_part_property")
    func searchPromptCapped() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_searchfield",
            arguments: ["name": "search", "left": "0", "top": "0", "width": "200", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        let longPrompt = String(repeating: "P", count: 500)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "search", "property": "searchprompt", "value": longPrompt],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .searchField }?.searchPrompt.count == 256)
    }
}
