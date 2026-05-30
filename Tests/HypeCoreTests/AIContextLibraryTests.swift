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

    @Test("directory ingestion report explains skipped files and risky text")
    func directoryIngestionReportExplainsSkipsAndSecrets() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-ai-context-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try "OPENAI_API_KEY=sk-thisLooksLikeATestSecretValue123456".write(
            to: temp.appendingPathComponent("deployment-rules.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0, 1, 2]).write(to: temp.appendingPathComponent("ignored.bin"))

        let report = AIContextIngestor.ingestDirectoryWithReport(url: temp)

        #expect(report.importedItemCount == 1)
        #expect(report.issues.contains { $0.relativePath == "ignored.bin" && $0.reason == .unsupportedFileType })
        #expect(report.secretFindings.contains { $0.kind == .openAIKey || $0.kind == .credentialAssignment })
        #expect(report.userSummary.contains("Skipped 1 item"))
        #expect(report.userSummary.contains("Potential secret-like text"))
    }

    @Test("file ingestion report keeps successes and failures separate")
    func fileIngestionReportSeparatesSuccessesAndFailures() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-ai-context-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let valid = temp.appendingPathComponent("notes.md")
        let invalid = temp.appendingPathComponent("archive.bin")
        try "Use compact card layouts.".write(to: valid, atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: invalid)

        let report = AIContextIngestor.ingestFiles(urls: [valid, invalid])

        #expect(report.importedSourceCount == 1)
        #expect(report.importedItemCount == 1)
        #expect(report.issues.count == 1)
        #expect(report.issues.first?.reason == .unsupportedFileType)
    }

    @Test("text and image context items use SHA-256 hashes")
    func contextItemsUseSHA256Hashes() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-ai-context-hash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let file = temp.appendingPathComponent("rules.md")
        try "Always preserve stack portability.".write(to: file, atomically: true, encoding: .utf8)

        let result = try AIContextIngestor.ingestFile(url: file)
        let item = try #require(result.1.first)

        #expect(item.hash.count == 64)
        #expect(item.hash.allSatisfy { $0.isHexDigit })
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
