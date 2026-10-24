import Foundation
import Testing
@testable import HypeCore

@Suite("Chatter speech service")
struct ChatterSpeechClientTests {
    @Test("automatic narration submits one short summary to Chatter, never the full response")
    func assistantSummaryPayload() async throws {
        let fixture = ChatterSpeechFixture()
        let client = ChatterSpeechClient(toolCall: { try await fixture.call($0, $1) }, defaults: { .init(defaultPace: 1, studioTone: "natural") }, pollingDelay: .zero)
        var planner = AIResponseSpeechPlanner()
        let id = UUID()
        let text = "Updated the customer form and fixed its navigation. "
            + String(repeating: "The implementation contains many detailed field settings and layout notes. ", count: 50)
            + "\n```\nprivate-implementation-payload\n```"
        let expected = try #require(AIResponseSpeechPlanner.summary(of: text))
        for _ in 0..<2 {
            if let summary = planner.prepare(text, responseID: id) {
                _ = try await client.speak(.init(text: summary))
            }
        }
        let sent = await fixture.calls.filter { $0.0 == "chatter_speak" }.map { $0.1["text"] }
        #expect(sent == [.string(expected)])
        #expect(expected.count <= 320)
        #expect(expected != text)
        #expect(!expected.contains("private-implementation-payload"))
    }

    @Test("Text-only uses Chatter default voice and current local defaults without Hype overrides")
    func defaults() async throws {
        let fixture = ChatterSpeechFixture()
        let client = ChatterSpeechClient(toolCall: { try await fixture.call($0, $1) }, defaults: { .init(defaultPace: 0.8, studioTone: "calm") }, pollingDelay: .zero)
        let result = try await client.speak(.init(text: "Hello"))
        #expect(result.value == "job-1")
        let args = try #require(await fixture.calls.first { $0.0 == "chatter_speak" }?.1)
        #expect(args["voice"] == .string("default-id"))
        #expect(args["pace"] == .number(0.8))
        #expect(args["tone"] == .string("calm"))
        #expect(args["quality"] == nil)
        #expect(args["mode"] == nil)
        #expect(await fixture.calls.filter { $0.0 == "chatter_job" }.count == 1)
    }

    @Test("Explicit parameters and all text reach Chatter; WAV waits for a real completed path")
    func explicitOptions() async throws {
        let fixture = ChatterSpeechFixture()
        let client = ChatterSpeechClient(toolCall: { try await fixture.call($0, $1) }, defaults: { throw ScriptSpeechError.failed("Defaults should not be read") }, pollingDelay: .zero, validateWAV: { $0 == "/tmp/chatter-test.wav" })
        let text = String(repeating: "Exact words. ", count: 150)
        let result = try await client.speak(.init(text: text, voice: "Ryan", tone: "warm", pace: 0.9, quality: "balanced", output: "wav"))
        #expect(result.value == "/tmp/chatter-test.wav")
        #expect(result.warnings == ["Save uses Studio"])
        let args = try #require(await fixture.calls.first?.1)
        #expect(args["text"] == .string(text))
        #expect(args["voice"] == .string("Ryan"))
        #expect(args["tone"] == .string("warm"))
        #expect(args["quality"] == .string("balanced"))
        #expect(args["mode"] == .string("save"))
    }

    @Test("Voice metadata includes default, readiness, and tone support")
    func voices() async throws {
        let fixture = ChatterSpeechFixture()
        let client = ChatterSpeechClient(toolCall: { try await fixture.call($0, $1) })
        #expect(try await client.voices() == [.init(id: "default-id", name: "Default", isDefault: true, ready: true, supportsTone: false)])
    }

    @Test("Failures, missing WAVs, and missing default voice are errors")
    func failures() async {
        for (state, message) in [("failed", "Engine failed"), ("cancelled", "speech job was cancelled"), ("missing-file", "readable WAV file"), ("no-default", "Choose a default voice")] {
            let fixture = ChatterSpeechFixture(variant: state)
            let client = ChatterSpeechClient(toolCall: { try await fixture.call($0, $1) }, defaults: { .init() }, pollingDelay: .zero, validateWAV: { _ in false })
            do { _ = try await client.speak(.init(text: "Hello", output: "wav")); Issue.record("Expected failure for \(state)") }
            catch { #expect(error.localizedDescription.contains(message)) }
        }
    }

    @Test("Polling deadline does not replay or resubmit speech")
    func timeout() async {
        let fixture = ChatterSpeechFixture(variant: "pending")
        let client = ChatterSpeechClient(toolCall: { try await fixture.call($0, $1) }, defaults: { .init() }, pollingDelay: .zero, deadline: .zero)
        do { _ = try await client.speak(.init(text: "Hello")); Issue.record("Expected polling deadline") }
        catch { #expect(error.localizedDescription.contains("job-1")) }
        #expect(await fixture.calls.filter { $0.0 == "chatter_speak" }.count == 1)
    }

    @Test("Cancellation stops only the accepted caller job")
    func cancellation() async throws {
        let fixture = ChatterSpeechFixture(variant: "pending")
        let client = ChatterSpeechClient(toolCall: { try await fixture.call($0, $1) }, defaults: { .init() }, pollingDelay: .seconds(10))
        let task = Task { try await client.speak(.init(text: "Hello")) }
        for _ in 0..<100 {
            if await fixture.calls.contains(where: { $0.0 == "chatter_speak" }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(await fixture.calls.last?.0 == "chatter_cancel")
        #expect(await fixture.calls.last?.1["id"] == .string("job-1"))
    }

    @Test("WAV validation checks content instead of just file existence")
    func wavHeader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a WAV file".utf8).write(to: url)
        #expect(try !ChatterSpeechClient.isWAV(url.path))
        try Data("RIFF1234WAVE".utf8).write(to: url)
        #expect(try ChatterSpeechClient.isWAV(url.path))
    }

    @Test("Live installed Chatter voice discovery", .enabled(if: ProcessInfo.processInfo.environment["HYPE_CHATTER_LIVE_TEST"] == "1"))
    func liveVoices() async throws {
        let voices = try await ChatterSpeechConfiguration.makeClient().voices()
        #expect(voices.contains { $0.name == "Aiden" && $0.supportsTone })
        #expect(voices.contains { $0.isDefault && $0.ready })
    }
}

private actor ChatterSpeechFixture {
    var calls: [(String, [String: HypeMCPJSONValue])] = []
    let variant: String
    init(variant: String = "normal") { self.variant = variant }
    func call(_ name: String, _ args: [String: HypeMCPJSONValue]) throws -> HypeMCPJSONValue {
        calls.append((name, args))
        if name == "chatter_voices" {
            return .object(["voices": .array([.object(["id": .string("default-id"), "name": .string("Default"), "isDefault": .bool(variant != "no-default"), "ready": .bool(true), "supportsInstructions": .bool(false)])])])
        }
        if name == "chatter_speak" || variant == "pending" { return .object(["id": .string("job-1"), "state": .string("queued")]) }
        return .object(["id": .string("job-1"), "state": .string(["failed", "cancelled"].contains(variant) ? variant : "completed"), "message": .string("Engine failed"), "path": .string("/tmp/chatter-test.wav"), "warnings": .array([.string("Save uses Studio")])])
    }
}
