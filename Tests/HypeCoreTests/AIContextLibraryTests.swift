import Foundation
import Testing
@testable import HypeCore

@Suite("AI Context Library")
struct AIContextLibraryTests {
    private let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    @Test("text notes are searchable and summarized for prompts")
    func textNoteSearchAndSummary() {
        var library = AIContextLibrary()
        let result = AIContextIngestor.makeTextNote(
            title: "Game Rules",
            text: "The player must collect keys, avoid lava, and reach the green exit portal.",
            role: .rules
        )

        library.addSource(result.0, items: result.1)

        #expect(library.itemCount == 1)
        #expect(library.search(query: "lava portal", role: .rules).count == 1)
        #expect(library.promptSummary().contains("Rules: 1"))
        #expect(library.promptSummary().contains("Game Rules"))
    }

    @Test("directory ingestion snapshots supported text and image files")
    func directoryIngestionSnapshotsSupportedFiles() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-ai-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try "Use a blue glass visual style for every panel.".write(
            to: temp.appendingPathComponent("style-guide.md"),
            atomically: true,
            encoding: .utf8
        )
        try onePixelPNG.write(to: temp.appendingPathComponent("player.png"))
        try Data([0, 1, 2]).write(to: temp.appendingPathComponent("ignored.bin"))

        let result = try AIContextIngestor.ingestDirectory(url: temp)
        let names = Set(result.1.map(\.relativePath))

        #expect(result.0.kind == .directory)
        #expect(result.1.count == 2)
        #expect(names.contains("style-guide.md"))
        #expect(names.contains("player.png"))
        #expect(result.1.first { $0.relativePath == "player.png" }?.role == .asset)
    }

    @Test("document codable round-trip preserves AI context library")
    func documentRoundTripPreservesContext() throws {
        var document = HypeDocument.newDocument(name: "Context Test")
        let result = AIContextIngestor.makeTextNote(title: "Rules", text: "Build the stack as a quiz.", role: .rules)
        document.aiContextLibrary.addSource(result.0, items: result.1)

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: encoded)

        #expect(decoded.aiContextLibrary.itemCount == 1)
        #expect(decoded.aiContextLibrary.items[0].name == "Rules")
    }
}
