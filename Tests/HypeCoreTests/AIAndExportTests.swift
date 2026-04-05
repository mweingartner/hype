import Testing
@testable import HypeCore

@Suite("AIService Tests")
struct AIServiceTests {
    @Test func budgetTracking() async {
        let service = AIService()
        let usage = await service.getDailyUsage()
        #expect(usage == 0)
        let limit = await service.getDailyLimit()
        #expect(limit == 100_000)
    }

    @Test func hasNoKeyByDefault() async {
        let service = AIService()
        let hasKey = await service.hasApiKey()
        #expect(hasKey == false)
    }

    @Test func setApiKey() async {
        let service = AIService()
        await service.setApiKey("sk-ant-test123")
        let hasKey = await service.hasApiKey()
        #expect(hasKey == true)
    }
}

@Suite("StackGenerator Tests")
struct StackGeneratorTests {
    @Test func parseValidJSON() {
        let generator = StackGenerator()
        let json = """
        {
            "name": "Test Stack",
            "cards": [
                {
                    "name": "Home",
                    "parts": [
                        {
                            "type": "button",
                            "name": "Click Me",
                            "left": 100, "top": 100, "width": 120, "height": 40,
                            "textContent": "Hello",
                            "style": "roundRect"
                        }
                    ]
                }
            ]
        }
        """
        let doc = generator.parseGeneratedStack(json: json)
        #expect(doc != nil)
        #expect(doc?.stack.name == "Test Stack")
        #expect(doc?.cards.count == 1)
        #expect(doc?.parts.count == 1)
        #expect(doc?.parts.first?.name == "Click Me")
    }

    @Test func parseInvalidJSON() {
        let generator = StackGenerator()
        let doc = generator.parseGeneratedStack(json: "not json")
        #expect(doc == nil)
    }
}

@Suite("SyncService Tests")
struct SyncServiceTests {
    @Test func initiallyDisconnected() async {
        let service = SyncService()
        let status = await service.getStatus()
        #expect(status == .disconnected)
    }

    @Test func generateRoomId() async {
        let service = SyncService()
        let roomId = await service.generateRoomId()
        #expect(!roomId.isEmpty)
        #expect(roomId.count >= 32)
    }

    @Test func exportImportRoundTrip() async throws {
        let service = SyncService()
        let doc = HypeDocument.newDocument(name: "SyncTest")
        let data = try await service.exportForSharing(document: doc)
        let imported = try await service.importShared(data: data)
        #expect(imported.stack.name == "SyncTest")
    }
}

@Suite("ExtensionManager Tests")
struct ExtensionManagerTests {
    @Test func registerAndFind() async {
        let manager = ExtensionManager()
        let ext = HypeExtension(id: "test", name: "Test Extension", commands: ["mycommand"], functions: ["myfunc"])
        await manager.register(ext)

        let found = await manager.findCommand("mycommand")
        #expect(found?.name == "Test Extension")

        let funcFound = await manager.findFunction("myfunc")
        #expect(funcFound?.name == "Test Extension")
    }

    @Test func unregister() async {
        let manager = ExtensionManager()
        let ext = HypeExtension(id: "test", name: "Test")
        await manager.register(ext)
        await manager.unregister(id: "test")
        let result = await manager.getExtension(id: "test")
        #expect(result == nil)
    }
}

@Suite("DocumentExporter Tests")
struct DocumentExporterTests {
    @Test func exportJSON() throws {
        let exporter = DocumentExporter()
        let doc = HypeDocument.newDocument(name: "Export Test")
        let data = try exporter.exportJSON(document: doc)
        let string = String(data: data, encoding: .utf8)!
        #expect(string.contains("Export Test"))
    }

    @Test func exportHTML() {
        let exporter = DocumentExporter()
        var doc = HypeDocument.newDocument(name: "HTML Test")
        var btn = Part(partType: .button, cardId: doc.cards[0].id, name: "Click")
        btn.showName = true
        doc.addPart(btn)

        let html = exporter.exportHTML(document: doc)
        #expect(html.contains("<title>HTML Test</title>"))
        #expect(html.contains("Click"))
        #expect(html.contains("class=\"part button\""))
    }

    @Test func htmlEscapesSpecialChars() {
        let exporter = DocumentExporter()
        let doc = HypeDocument.newDocument(name: "Test <script>alert(1)</script>")
        let html = exporter.exportHTML(document: doc)
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }
}
