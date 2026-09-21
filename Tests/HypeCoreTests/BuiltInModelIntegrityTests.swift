import CryptoKit
import Foundation
import Testing
@testable import HypeCore

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hype-builtin-integrity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func variant(files: [BuiltInModelFile]) -> BuiltInModelVariant {
    BuiltInModelVariant(
        id: "integrity-variant", displayName: "Integrity Variant", summary: "fixture", tier: .standard,
        huggingFaceRepo: "hype-tests/integrity", revision: "rev1", files: files,
        license: "Apache-2.0", licenseURL: "https://example.invalid", kvBytesPerToken: 1024,
        fixedOverheadBytes: 1 << 20, nativeContextTokens: 32_768, minimumPhysicalMemoryGB: 8,
        recommendedPhysicalMemoryGB: 8, supportsVision: false, thinkingControl: .none)
}

/// Weights Hype did not download itself (a Hugging Face cache snapshot, a
/// relocated folder) are only trusted after their content matches the catalog.
@Suite("Built-in model integrity")
struct BuiltInModelIntegrityTests {
    @Test("a same-size edit to a small file (chat template, tokenizer, config) makes the variant not installed")
    func tamperedSmallFileIsRejected() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = Data("{{ messages }}".utf8)
        let model = variant(files: [BuiltInModelFile(path: "chat_template.jinja", size: Int64(template.count), sha256: sha256Hex(template))])
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let file = store.installDirectory(for: model).appendingPathComponent("chat_template.jinja")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try template.write(to: file)
        #expect(store.location(of: model) != nil)

        // Same length, different instructions. Push the date forward so the
        // change is visible even on a coarse-grained filesystem clock.
        try Data("{{ evilmsgs }}".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        #expect(store.location(of: model) == nil)

        let sizesOnly = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil, integrity: .sizesOnly)
        #expect(sizesOnly.location(of: model) != nil)
    }

    @Test("weight files are hashed once, remembered, and hashed again when they change")
    func weightsAreVerifiedOnceAndReverifiedOnChange() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let size = BuiltInModelStore.smallFileLimit + 1
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let placeholder = variant(files: [BuiltInModelFile(path: "model.safetensors", size: size, sha256: String(repeating: "0", count: 64))])
        let file = store.installDirectory(for: placeholder).appendingPathComponent("model.safetensors")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        let model = variant(files: [BuiltInModelFile(path: "model.safetensors", size: size, sha256: try BuiltInModelDownloader.sha256(of: file))])
        let directory = try store.installedDirectory(of: model)

        #expect(!store.weightsAreVerified(of: model, at: directory))
        try store.verifyWeights(of: model, at: directory)
        #expect(store.weightsAreVerified(of: model, at: directory))
        #expect(FileManager.default.fileExists(atPath: store.ledgerURL.path))

        // Flip one byte without changing the size.
        let writer = try FileHandle(forWritingTo: file)
        try writer.seek(toOffset: 1024)
        try writer.write(contentsOf: Data([0xFF]))
        try writer.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)

        #expect(!store.weightsAreVerified(of: model, at: directory))
        #expect(throws: BuiltInModelDownloadError.checksumMismatch(path: "model.safetensors")) {
            try store.verifyWeights(of: model, at: directory)
        }
        #expect(!store.weightsAreVerified(of: model, at: directory))
    }

    @Test("the client refuses to load weights that do not match the catalog")
    func clientRefusesUnverifiedWeights() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let size = BuiltInModelStore.smallFileLimit + 1
        let model = variant(files: [BuiltInModelFile(path: "model.safetensors", size: size, sha256: String(repeating: "a", count: 64))])
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let file = store.installDirectory(for: model).appendingPathComponent("model.safetensors")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()

        let engine = RecordingEngine()
        let client = BuiltInModelClient(
            variant: model, engine: engine, store: store,
            device: BuiltInDeviceProfile(physicalMemoryBytes: 64 << 30))
        await #expect(throws: BuiltInModelDownloadError.checksumMismatch(path: "model.safetensors")) {
            try await client.preloadModel()
        }
        await #expect(throws: BuiltInModelDownloadError.checksumMismatch(path: "model.safetensors")) {
            _ = try await client.chat(messages: [OllamaMessage(role: "user", content: "hi")], tools: [])
        }
        #expect(await engine.calls == 0)
    }

    @Test("identifiers can never step outside the models folder")
    func pathComponentsAreSanitized() {
        #expect(BuiltInModelStore.safeComponent("qwen3.8-27b-4bit") == "qwen3.8-27b-4bit")
        #expect(BuiltInModelStore.safeComponent("../../etc") == "_.._etc")
        #expect(BuiltInModelStore.safeComponent("..") == "_")
        #expect(BuiltInModelStore.safeComponent("a/b") == "a_b")
        #expect(BuiltInModelStore.safeComponent("") == "_")
        for hostile in ["../..", "/abs", "a/../../b", "..", "."] {
            let component = BuiltInModelStore.safeComponent(hostile)
            #expect(!component.contains("/"))
            #expect(component != ".." && component != ".")
        }
    }
}

private actor RecordingEngine: BuiltInModelEngine {
    private(set) var calls = 0
    func load(variant: BuiltInModelVariant, from directory: URL) async throws { calls += 1 }
    func generate(_ request: BuiltInGenerationRequest, onText: (@Sendable (String) -> Void)?) async throws -> BuiltInGenerationResult {
        calls += 1
        return BuiltInGenerationResult(text: "")
    }
    func unload() async {}
    func status() async -> BuiltInEngineStatus { BuiltInEngineStatus() }
}
