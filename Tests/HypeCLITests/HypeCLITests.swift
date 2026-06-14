import Foundation
@testable import HypeCore
import Testing

@Suite("HypeCLI Integration Tests")
struct HypeCLITests {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var binaryPath: String {
        // Different Swift toolchains lay out the build directory differently:
        // SwiftPM's classic layout is .build/<triple>/debug, while the newer
        // Swift Build system (Xcode 16+/beta) emits to .build/debug. Pick the
        // freshest existing `hypetalk` among the known candidates so the CLI
        // integration tests run the current binary regardless of toolchain.
        let candidates = [
            ".build/debug/hypetalk",
            ".build/arm64-apple-macosx/debug/hypetalk",
            ".build/release/hypetalk",
            ".build/arm64-apple-macosx/release/hypetalk",
        ].map { projectRoot.appendingPathComponent($0).path }
        let fm = FileManager.default
        let existing = candidates.filter { fm.fileExists(atPath: $0) }
        let newest = existing.max { a, b in
            let da = (try? fm.attributesOfItem(atPath: a)[.modificationDate] as? Date) ?? nil
            let db = (try? fm.attributesOfItem(atPath: b)[.modificationDate] as? Date) ?? nil
            return (da ?? .distantPast) < (db ?? .distantPast)
        }
        return newest ?? candidates[0]
    }

    private var scriptDir: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HypeCLITests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runHypetalkScript(_ script: String) -> ProcessResult {
        let scriptFile = scriptDir.appendingPathComponent("script.hypetalk")
        try? script.write(to: scriptFile, atomically: true, encoding: .utf8)

        return runBinary(filePath: scriptFile.path)
    }

    private func runBinary(filePath: String) -> ProcessResult {
        runBinary(arguments: [filePath])
    }

    private func runBinary(arguments: [String]) -> ProcessResult {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.currentDirectoryURL = projectRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(stdout: "", stderr: error.localizedDescription, exitStatus: -1)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitStatus: process.terminationStatus
        )
    }

    @Test func testArithmeticAddition() {
        let result = runHypetalkScript("""
        on main
        put 2 + 3 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "5")
    }

    @Test func testStringConcatenation() {
        let result = runHypetalkScript("""
        on main
        put "Hello, " & "World" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello, World")
    }

    @Test func testSpacedConcatenation() {
        let result = runHypetalkScript("""
        on main
        put "Hello" && "World" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello World")
    }

    @Test func testVariableAssignment() {
        let result = runHypetalkScript("""
        on main
        put 42 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    }

    @Test func testNestedExpression() {
        let result = runHypetalkScript("""
        on main
        put (3 + 4) * 2 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "14")
    }

    @Test func testStringLength() {
        let result = runHypetalkScript("""
        on main
        put length("Hello") into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "5")
    }

    @Test func testChunkWordOf() {
        let result = runHypetalkScript("""
        on main
        put word 2 of "one two three" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "two")
    }

    @Test func testChunkCharOf() {
        let result = runHypetalkScript("""
        on main
        put char 1 of "Hello" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "H")
    }

    @Test func testIsAOperator() {
        let result = runHypetalkScript("""
        on main
        if 42 is a number then
          return "yes"
        else
          return "no"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "yes")
    }

    @Test func testIsNotAOperator() {
        let result = runHypetalkScript("""
        on main
        if "hello" is not a number then
          return "yes"
        else
          return "no"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "yes")
    }

    @Test func testContainsOperator() {
        let result = runHypetalkScript("""
        on main
        if "Hello World" contains "World" then
          return "yes"
        else
          return "no"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "yes")
    }

    @Test func testRepeatLoop() {
        let result = runHypetalkScript("""
        on main
        put 0 into total
        repeat with i from 1 to 5
          add i to total
        end repeat
        return total
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "15")
    }

    @Test func testIfThenElse() {
        let result = runHypetalkScript("""
        on main
        if 5 > 3 then
          return "greater"
        else
          return "lesser"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "greater")
    }

    @Test func testIfElseIf() {
        let result = runHypetalkScript("""
        on main
        if 1 > 2 then
          return "a"
        else if 2 > 1 then
          return "b"
        else
          return "c"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "b")
    }

    @Test func testDivideOperator() {
        let result = runHypetalkScript("""
        on main
        put 10 div 3 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "3")
    }

    @Test func testModuloOperator() {
        let result = runHypetalkScript("""
        on main
        put 10 mod 3 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
    }

    @Test func testHyperCardImportSummaryCommand() {
        let fixture = projectRoot
            .deletingLastPathComponent()
            .appendingPathComponent("stackimport/Resources.stak")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            return
        }

        let result = runBinary(arguments: ["--import-hypercard", fixture.path])
        #expect(result.exitStatus == 0)
        #expect(result.stdout.contains("status\tcards\tbackgrounds"))
        #expect(result.stdout.contains("ok\t10\t1"))
        #expect(result.stdout.contains("Resources.stak"))
    }

    @Test func testHyperCardImportOutputPackageCommand() throws {
        let fixture = projectRoot
            .deletingLastPathComponent()
            .appendingPathComponent("stackimport/Resources.stak")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            return
        }

        let outputURL = scriptDir.appendingPathComponent("Resources-imported.hype", isDirectory: true)
        let result = runBinary(arguments: ["--import-hypercard", fixture.path, "--output", outputURL.path])

        #expect(result.exitStatus == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let imported = try HypeSQLiteStackStore().load(fromPackageAt: outputURL)
        #expect(imported.cards.count == 10)
        #expect(imported.backgrounds.count == 1)
        #expect(imported.stack.name == "Resources.stak")
    }

    @Test func testHyperCardImportCorpusOutputDirectoryCommand() throws {
        let fixture = projectRoot
            .deletingLastPathComponent()
            .appendingPathComponent("stackimport/Resources.stak")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            return
        }

        let tempDir = scriptDir
        let corpusDir = tempDir.appendingPathComponent("corpus", isDirectory: true)
        let outputDir = tempDir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: corpusDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture,
            to: corpusDir.appendingPathComponent("Resources.stak")
        )

        let result = runBinary(arguments: [
            "--import-corpus", corpusDir.path,
            "--output-dir", outputDir.path
        ])

        #expect(result.exitStatus == 0)
        #expect(result.stderr.contains("imported=1"))
        let outputURL = outputDir.appendingPathComponent("Resources.stak.hype", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let imported = try HypeSQLiteStackStore().load(fromPackageAt: outputURL)
        #expect(imported.cards.count == 10)
        #expect(imported.backgrounds.count == 1)
        #expect(imported.stack.name == "Resources.stak")
    }

    @Test func testValidateScriptsExportsWithoutExecuting() throws {
        var document = HypeDocument.newDocument(name: "Validation Fixture")
        document.stack.script = "on openStack\r  put \"do not print\" into x -- classic comment\rend openStack"
        let cardId = try #require(document.cards.first?.id)
        document.cards[0].script = "on openCard\r\n  put 1 into y\r\nend openCard"
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = "on mouseUp\n  return \"should not execute\"\nend mouseUp"
        document.parts.append(button)

        let packageURL = scriptDir.appendingPathComponent("ValidationFixture.hype", isDirectory: true)
        let exportURL = scriptDir.appendingPathComponent("scripts", isDirectory: true)
        try HypeSQLiteStackStore().save(document, toPackageAt: packageURL)

        let result = runBinary(arguments: [
            "--validate-scripts", packageURL.path,
            "--export-scripts", exportURL.path,
        ])

        #expect(result.exitStatus == 0)
        #expect(result.stdout.contains("status\townerType\townerName"))
        #expect(result.stdout.contains("ok\tstack\tValidation Fixture"))
        #expect(result.stdout.contains("ok\tcard\tCard 1"))
        #expect(result.stdout.contains("ok\tbutton\tRun"))
        #expect(!result.stdout.contains("should not execute"))
        #expect(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("scripts.tsv").path))
        #expect(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("scripts.json").path))
        #expect(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("summary.txt").path))
        #expect(result.stdout.contains("sourceBytes\tnormalizedBytes\tsha256\tlineEndings"))

        let exported = try FileManager.default.contentsOfDirectory(atPath: exportURL.path)
        let scriptFiles = exported.filter { $0.hasSuffix(".hypetalk") }
        #expect(scriptFiles.count == 3)
        let stackFile = try #require(scriptFiles.first { $0.contains("-stack-") })
        let stackSource = try String(contentsOf: exportURL.appendingPathComponent(stackFile), encoding: .utf8)
        #expect(stackSource.contains("\n  put \"do not print\""))
        #expect(!stackSource.contains("\r"))
    }

    @Test func testValidateScriptsReportsSemanticImportIssues() throws {
        var document = HypeDocument.newDocument(name: "Semantic Validation Fixture")
        let cardId = try #require(document.cards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = """
        on mouseUp
          visual effect dissolve fast
          wait 30
          play "MachineHum"
          goNext
        end mouseUp

        on goNext
          go next
        end goNext
        """
        document.parts.append(button)

        let packageURL = scriptDir.appendingPathComponent("SemanticValidationFixture.hype", isDirectory: true)
        let exportURL = scriptDir.appendingPathComponent("semantic-scripts", isDirectory: true)
        try HypeSQLiteStackStore().save(document, toPackageAt: packageURL)

        let result = runBinary(arguments: [
            "--validate-scripts", packageURL.path,
            "--export-scripts", exportURL.path,
        ])

        #expect(result.exitStatus == 0)
        #expect(result.stdout.contains("warning\tbutton\tRun"))
        #expect(result.stdout.contains("bare line is evaluated as a variable"))
        #expect(result.stdout.contains("not translated to Hype transition durations"))
        #expect(result.stdout.contains("has no embedded audio asset"))

        let summary = try String(contentsOf: exportURL.appendingPathComponent("summary.txt"), encoding: .utf8)
        #expect(summary.contains("warning\t1"))
        let scriptsJSON = try String(contentsOf: exportURL.appendingPathComponent("scripts.json"), encoding: .utf8)
        #expect(scriptsJSON.contains("bare-handler-call"))
        #expect(scriptsJSON.contains("sound-asset"))
    }

    @Test func testValidateScriptsAcceptsClassicMediaSoundAliases() throws {
        var document = HypeDocument.newDocument(name: "Classic Media Sound Fixture")
        document.assetRepository.addAsset(Asset(
            name: "EL GenAll MoV-modern-audio.m4a",
            kind: .audioClip,
            mimeType: "audio/mp4",
            data: Data("audio".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "El GenRun"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("El GenRun"))
            ]
        ))
        document.assetRepository.addAsset(Asset(
            name: "DR Drawer Close.wav",
            kind: .audioClip,
            mimeType: "audio/wav",
            data: Data("audio".utf8),
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "DR Drawer Close"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("DR Drawer Close"))
            ]
        ))
        let cardId = try #require(document.cards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = """
        on mouseUp
          put "SW Buzzer" into theSound
          play theSound
          play "El GenRun"
          play "DR drawerClose"
        end mouseUp
        """
        document.parts.append(button)

        let packageURL = scriptDir.appendingPathComponent("ClassicMediaSoundFixture.hype", isDirectory: true)
        let exportURL = scriptDir.appendingPathComponent("classic-media-scripts", isDirectory: true)
        try HypeSQLiteStackStore().save(document, toPackageAt: packageURL)

        let result = runBinary(arguments: [
            "--validate-scripts", packageURL.path,
            "--export-scripts", exportURL.path,
        ])

        #expect(result.exitStatus == 0)
        #expect(!result.stdout.contains("has no embedded audio asset"))
        let scriptsJSON = try String(contentsOf: exportURL.appendingPathComponent("scripts.json"), encoding: .utf8)
        #expect(!scriptsJSON.contains("sound-asset"))
    }

    @Test func testValidateScriptsAcceptsDynamicAndStackLibraryCardReferences() throws {
        var document = HypeDocument.newDocument(name: "Stack Library Card Fixture")
        document.stackLibrary = HypeStackLibrary(entries: [
            HypeStackLibraryEntry(
                stackName: "Myst",
                source: .importedStackPackage,
                cardReferences: [
                    HypeStackLibraryCardReference(name: "dock"),
                    HypeStackLibraryCardReference(name: "reStart")
                ]
            )
        ])
        let cardId = try #require(document.cards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = """
        on mouseUp
          put "Card 1" into this
          go to card this
          go to card "this"
          go to card "dock"
          go to card "reStart"
        end mouseUp
        """
        document.parts.append(button)

        let packageURL = scriptDir.appendingPathComponent("StackLibraryCardFixture.hype", isDirectory: true)
        let exportURL = scriptDir.appendingPathComponent("stack-library-card-scripts", isDirectory: true)
        try HypeSQLiteStackStore().save(document, toPackageAt: packageURL)

        let result = runBinary(arguments: [
            "--validate-scripts", packageURL.path,
            "--export-scripts", exportURL.path,
        ])

        #expect(result.exitStatus == 0)
        #expect(!result.stdout.contains("does not resolve"))
        let scriptsJSON = try String(contentsOf: exportURL.appendingPathComponent("scripts.json"), encoding: .utf8)
        #expect(!scriptsJSON.contains("object-reference"))
    }

    @Test func testPowerOperator() {
        let result = runHypetalkScript("""
        on main
        put 2 ^ 8 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "256")
    }

    @Test func testGlobalVariable() {
        let result = runHypetalkScript("""
        on main
        global x
        put 42 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    }

    @Test func testExitRepeat() {
        let result = runHypetalkScript("""
        on main
        put 0 into i
        repeat 100
          add 1 to i
          if i > 10 then
            exit repeat
          end if
        end repeat
        return i
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "11")
    }

    @Test func testBeepStatement() {
        let result = runHypetalkScript("""
        on main
        beep
        return "ok"
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "ok")
    }

    @Test func testBenchmarkSuiteTextOutput() {
        let result = runBinary(arguments: ["--benchmark", "--benchmark-iterations", "1"])
        #expect(result.exitStatus == 0)
        #expect(result.stdout.contains("HypeTalk benchmark"))
        #expect(result.stdout.contains("looping-and-expressions"))
        #expect(result.stdout.contains("property-access"))
        #expect(result.stdout.contains("callback requests"))
        #expect(result.stderr.isEmpty)
    }

    /// Confirms the extended harness emits the four micro-benchmark cases in the
    /// full-suite text output.
    @Test func testBenchmarkSuiteIncludesMicroCases() {
        let result = runBinary(arguments: ["--benchmark", "--benchmark-iterations", "1"])
        #expect(result.exitStatus == 0)
        #expect(result.stdout.contains("micro-arith-loop"))
        #expect(result.stdout.contains("micro-chunk-churn"))
        #expect(result.stdout.contains("micro-property-churn"))
        #expect(result.stdout.contains("micro-idle-game-loop"))
        #expect(result.stderr.isEmpty)
    }

    /// Confirms the production-wall-clock column is present alongside the pure-CPU
    /// column in the full-suite text output.  The three wall-clock lines must appear
    /// for every handler case (not idle-burst cases, which use StackRuntime).
    @Test func testBenchmarkSuiteRealisticRuntimeColumnsPresent() {
        let result = runBinary(arguments: ["--benchmark", "--benchmark-iterations", "1"])
        #expect(result.exitStatus == 0)
        // The realistic-runtime section headings must appear at least once.
        #expect(result.stdout.contains("wall-clock total:"))
        #expect(result.stdout.contains("wall-clock avg:"))
        #expect(result.stdout.contains("publish count:"))
        #expect(result.stderr.isEmpty)
    }

    /// Confirms the pure-CPU path is still present and the familiar column labels
    /// have not been removed by the dual-run change.
    @Test func testBenchmarkSuitePureCPUColumnsUnchanged() {
        let result = runBinary(arguments: ["--benchmark", "--benchmark-iterations", "1"])
        #expect(result.exitStatus == 0)
        #expect(result.stdout.contains("execute total:"))
        #expect(result.stdout.contains("execute avg:"))
        #expect(result.stdout.contains("parse:"))
        #expect(result.stdout.contains("total execute:"))
        #expect(result.stderr.isEmpty)
    }

    @Test func testBenchmarkScriptJSONOutput() throws {
        let scriptFile = scriptDir.appendingPathComponent("bench.hypetalk")
        try """
        on main
          put 0 into total
          repeat with i from 1 to 5
            add i to total
          end repeat
          return total
        end main
        """.write(to: scriptFile, atomically: true, encoding: .utf8)

        let result = runBinary(arguments: [
            "--benchmark",
            "--benchmark-iterations", "2",
            "--benchmark-format", "json",
            scriptFile.path
        ])

        #expect(result.exitStatus == 0)
        let data = try #require(result.stdout.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["iterations"] as? Int == 2)
        let cases = try #require(json?["cases"] as? [[String: Any]])
        #expect(cases.first?["iterations"] as? Int == 2)
        let diagnostics = try #require(cases.first?["diagnostics"] as? [String: Any])
        #expect((diagnostics["statements"] as? Int ?? 0) > 0)
        #expect((diagnostics["loopIterations"] as? Int ?? 0) == 10)
    }

    @Test func testInferenceSmokeOptionsAreExposed() {
        let result = runBinary(arguments: ["--help"])

        #expect(result.exitStatus == 0)
        #expect(result.stdout.contains("--inference-smoke"))
        #expect(result.stdout.contains("--ollama-tool-smoke"))
        #expect(result.stdout.contains("--ollama-model"))
    }

    @Test func testSwiftInferenceProviderAdapterBridgesChatContract() async throws {
        let client = RecordingInferenceClient()
        let provider = HypeAIClientChatInferenceProvider(client: client)
        let request = AIChatInferenceRequest(
            messages: [OllamaMessage(role: "user", content: "Build a button")],
            tools: []
        )

        #expect(provider.providerName == "test-provider")
        #expect(provider.modelName == "test-model")
        #expect(provider.supportsStreaming)
        #expect(try await provider.availableModels() == ["test-model"])
        #expect(try await provider.generate(prompt: "hello", model: nil, system: "system") == "generated: hello")

        try await provider.preloadModel()
        let response = try await provider.chat(request)
        var streamed = ""
        for await token in provider.chatStream(request) {
            streamed += token
        }

        #expect(response.message.content == "chat reply")
        #expect(await client.chatMessageCount() == 1)
        #expect(await client.didPreloadModel())
        #expect(streamed == "hello world")
    }
}

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitStatus: Int32
}

private actor RecordingInferenceClient: HypeAIClient {
    nonisolated let providerName = "test-provider"
    nonisolated let modelName = "test-model"
    nonisolated var supportsChatStreaming: Bool { true }

    private var recordedChatMessageCount = 0
    private var preloaded = false

    func availableModels() async throws -> [String] {
        ["test-model"]
    }

    func generate(prompt: String, model: String?, system: String?) async throws -> String {
        "generated: \(prompt)"
    }

    func chat(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat?
    ) async throws -> OllamaChatResponse {
        recordedChatMessageCount = messages.count
        return OllamaChatResponse(message: OllamaMessage(role: "assistant", content: "chat reply"), done: true)
    }

    func structuredChat<Response: Decodable & Sendable>(
        messages: [OllamaMessage],
        tools: [OllamaTool],
        format: OllamaResponseFormat
    ) async throws -> (response: OllamaChatResponse, decoded: Response) {
        throw RecordingInferenceError.unsupported
    }

    func preloadModel() async throws {
        preloaded = true
    }

    nonisolated func chatStream(messages: [OllamaMessage], tools: [OllamaTool]) -> AsyncStream<String> {
        AsyncStream { continuation in
            continuation.yield("hello")
            continuation.yield(" world")
            continuation.finish()
        }
    }

    func chatMessageCount() -> Int {
        recordedChatMessageCount
    }

    func didPreloadModel() -> Bool {
        preloaded
    }
}

private enum RecordingInferenceError: Error {
    case unsupported
}
