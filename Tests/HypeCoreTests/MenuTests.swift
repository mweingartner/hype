import Testing
import Foundation
@testable import HypeCore

/// Menu part — a pull-down menu with inline HypeTalk actions.
///
/// Tests cover model defaults, Codable, backward-compat decode,
/// AI tool create + set/get, HypeTalk parser/setter, and the security
/// conditions: inline script parse validation (malformed scripts
/// must be rejected), 64 KB cap on menuItems.
@Suite("Menu — model, AI tools, HypeTalk grammar, script validation, length cap")
struct MenuTests {

    // MARK: - Model defaults

    @Test("Menu defaults: empty menuItems, title 'Menu'")
    func defaults() {
        let part = Part(partType: .menu, name: "actions")
        #expect(part.partType == .menu)
        #expect(part.menuItems == "")
        #expect(part.menuTitle == "Menu")
    }

    // MARK: - Codable round-trip

    @Test("Menu fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .menu, name: "actions")
        part.menuTitle = "Options"
        part.menuItems = "Save||put 1 into x\nCancel||\nDelete||delete card"
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.menuTitle == "Options")
        #expect(decoded.menuItems == "Save||put 1 into x\nCancel||\nDelete||delete card")
    }

    // MARK: - Backward-compat decode

    @Test("Old document without menu fields decodes with defaults")
    func backwardCompat() throws {
        var part = Part(partType: .menu, name: "actions")
        part.menuTitle = "File"
        part.menuItems = "New||"
        let data = try JSONEncoder().encode(part)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "menuItems")
        dict.removeValue(forKey: "menuTitle")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.menuItems == "")
        #expect(decoded.menuTitle == "Menu")
    }

    // MARK: - AI tools

    @Test("create_menu builds a part with title and items")
    func aiCreate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_menu",
            arguments: [
                "name": "actions",
                "left": "10", "top": "20", "width": "120", "height": "28",
                "title": "Options",
                "items": "Save||put 1 into x\nCancel||\nHelp||go to card \"Help\""
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .menu }
        #expect(part?.menuTitle == "Options")
        #expect(part?.menuItems.contains("Save") == true)
        #expect(part?.menuItems.contains("Cancel") == true)
    }

    @Test("set_part_property updates menuTitle")
    func aiSetTitle() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_menu",
            arguments: ["name": "actions", "left": "0", "top": "0", "width": "120", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "actions", "property": "menutitle", "value": "File"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .menu }?.menuTitle == "File")
    }

    @Test("set_part_property accepts valid menuItems")
    func aiSetMenuItemsValid() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_menu",
            arguments: ["name": "actions", "left": "0", "top": "0", "width": "120", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "actions", "property": "menuitems",
                        "value": "Save||put 1 into x\nLoad||"],
            document: &doc, currentCardId: cardId
        )
        let stored = doc.parts.first { $0.partType == .menu }?.menuItems ?? ""
        #expect(stored.contains("Save"))
    }

    @Test("get_part_property reads menuItems")
    func aiGetMenuItems() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .menu, cardId: cardId, name: "actions",
                        left: 0, top: 0, width: 120, height: 28)
        part.menuItems = "Save||\nLoad||"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "actions", "property": "menuitems"],
            document: &doc, currentCardId: cardId
        )
        #expect(result.contains("Save"))
    }

    @Test("get_part_property reads menuTitle")
    func aiGetMenuTitle() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .menu, cardId: cardId, name: "actions",
                        left: 0, top: 0, width: 120, height: 28)
        part.menuTitle = "File"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "actions", "property": "menutitle"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "File")
    }

    // MARK: - HypeTalk grammar

    @Test("HypeTalk parser accepts `the menuTitle of menu \"X\"`")
    func hypeTalkParser() throws {
        let source = "the menuTitle of menu \"actions\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "menuTitle",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "menu")
        } else {
            Issue.record("expected propertyAccess(menuTitle, objectRef(menu, ...)), got \(expr)")
        }
    }

    @Test("HypeTalk: valid set the menuitems of menu stores new items")
    func hypeTalkSetMenuItemsValid() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .menu, cardId: cardId, name: "actions",
                        left: 0, top: 0, width: 120, height: 28)
        doc.addPart(part)
        let source = """
        on test
          set the menuitems of menu "actions" to "Save||put 1 into x"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let updated = (result.modifiedDocument ?? doc).parts.first { $0.name == "actions" }!
        #expect(updated.menuItems.contains("Save"))
    }

    // MARK: - Security: script validation

    @Test("create_menu rejects malformed inline script — part not created")
    func aiCreateMalformedScript() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        // "if x > 5 then" is an incomplete if-statement that's missing "end if",
        // which produces a genuine parse error when wrapped in on/end.
        let response = await executor.execute(
            toolName: "create_menu",
            arguments: [
                "name": "broken",
                "left": "0", "top": "0", "width": "120", "height": "28",
                "items": "Save||if x > 5 then"
            ],
            document: &doc, currentCardId: cardId
        )
        // Either the response indicates an error, OR the menu was not added to the doc.
        let partAdded = doc.parts.contains { $0.partType == .menu && $0.name == "broken" }
        let responseIndicatesError = response.lowercased().contains("error") ||
                                     response.lowercased().contains("syntax") ||
                                     response.lowercased().contains("fix")
        #expect(responseIndicatesError || !partAdded)
    }

    @Test("set_part_property menuItems rejects malformed inline script")
    func aiSetMalformedScript() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_menu",
            arguments: ["name": "actions", "left": "0", "top": "0", "width": "120", "height": "28",
                        "items": "Save||"],
            document: &doc, currentCardId: cardId
        )
        let originalItems = doc.parts.first { $0.partType == .menu }?.menuItems ?? ""
        // Incomplete if-statement — the parser rejects this when wrapped.
        let response = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "actions", "property": "menuitems",
                        "value": "Broken||if x > 5 then"],
            document: &doc, currentCardId: cardId
        )
        let storedAfter = doc.parts.first { $0.partType == .menu }?.menuItems ?? ""
        // Either an error is returned, OR the bad value was not stored.
        let responseIsError = response.lowercased().contains("error") ||
                              response.lowercased().contains("syntax")
        let valueUnchanged = storedAfter == originalItems
        #expect(responseIsError || valueUnchanged)
    }

    @Test("HypeTalk: set the menuitems with malformed script — value unchanged (silent reject)")
    func hypeTalkSetMalformedScript() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .menu, cardId: cardId, name: "actions",
                        left: 0, top: 0, width: 120, height: 28)
        part.menuItems = "GoodItem||"
        doc.addPart(part)
        // Incomplete if-statement — the parser rejects this when wrapped.
        let source = """
        on test
          set the menuitems of menu "actions" to "Save||if x > 5 then"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let stored = (result.modifiedDocument ?? doc).parts.first { $0.name == "actions" }!.menuItems
        // Bad input should be silently rejected — original value preserved
        #expect(stored == "GoodItem||")
    }

    @Test("HypeTalk: valid menuItems with inline script are stored")
    func hypeTalkSetValidScript() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .menu, cardId: cardId, name: "actions",
                        left: 0, top: 0, width: 120, height: 28)
        doc.addPart(part)
        let source = """
        on test
          set the menuitems of menu "actions" to "Save||put 1 into x"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let stored = (result.modifiedDocument ?? doc).parts.first { $0.name == "actions" }!.menuItems
        #expect(stored == "Save||put 1 into x")
    }

    // MARK: - Security: length cap

    @Test("menuItems clamps to 64KB (65536 chars) via set_part_property")
    func menuItemsLengthCappedViaAI() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_menu",
            arguments: ["name": "actions", "left": "0", "top": "0", "width": "120", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        // Build a string well over 64 KB using a simple repeating label (no inline script).
        let bigItems = String(repeating: "LongMenuItemLabel||", count: 4000)
        #expect(bigItems.count > 65536)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "actions", "property": "menuitems", "value": bigItems],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .menu }?.menuItems.count ?? 0 <= 65536)
    }

    @Test("menuItems clamps to 64KB via HypeTalk setter")
    func menuItemsLengthCappedViaHypeTalk() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let part = Part(partType: .menu, cardId: cardId, name: "actions",
                        left: 0, top: 0, width: 120, height: 28)
        doc.addPart(part)
        // Use a simple repeating label-only string exceeding 64 KB
        let bigLabel = String(repeating: "A", count: 70000)
        let source = """
        on test
          set the menuitems of menu "actions" to "\(bigLabel)"
        end test
        """
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        let stored = (result.modifiedDocument ?? doc).parts.first { $0.name == "actions" }!.menuItems
        #expect(stored.count <= 65536)
    }

    @Test("menuTitle clamps to 256 chars via set_part_property")
    func menuTitleCapped() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_menu",
            arguments: ["name": "actions", "left": "0", "top": "0", "width": "120", "height": "28"],
            document: &doc, currentCardId: cardId
        )
        let longTitle = String(repeating: "T", count: 500)
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "actions", "property": "menutitle", "value": longTitle],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .menu }?.menuTitle.count == 256)
    }
}
