import Foundation
import Testing
import HypeCore
import MLXLMCommon
@testable import HypeMLX

// These tests cover HypeMLX's pure translation logic. They link MLX but never
// run a GPU operation: live inference is exercised by the `hype-mlx-probe` tool.

@Suite("ThinkingFilter")
struct ThinkingFilterTests {
    private func run(_ chunks: [String], startsInside: Bool = false) -> (visible: String, thinking: String) {
        var filter = ThinkingFilter(startsInsideThinking: startsInside)
        var visible = ""
        for chunk in chunks { visible += filter.consume(chunk) }
        visible += filter.finish()
        return (visible, filter.thinking)
    }

    @Test("plain text passes through untouched")
    func plainText() {
        let result = run(["Hello, ", "world"])
        #expect(result.visible == "Hello, world")
        #expect(result.thinking.isEmpty)
    }

    @Test("reasoning is separated even when tags are split across chunks")
    func splitTags() {
        let result = run(["<thi", "nk>plan the ", "layout</th", "ink>Done", "."])
        #expect(result.visible == "Done.")
        #expect(result.thinking == "plan the layout")
    }

    @Test("a reply that starts inside a think block hides it until the block closes")
    func startsInsideThinking() {
        let result = run(["weighing options", "</think>\n\nUse a field."], startsInside: true)
        #expect(result.visible == "\n\nUse a field.")
        #expect(result.thinking == "weighing options")
    }

    @Test("text that only resembles a tag is not swallowed")
    func lookalikeText() {
        let result = run(["if a < b then", " put \"<t\" into x"])
        #expect(result.visible == "if a < b then put \"<t\" into x")
    }

    @Test("an unterminated think block never leaks into visible text")
    func unterminatedBlock() {
        let result = run(["Answer: <think>still reasoning"])
        #expect(result.visible == "Answer: ")
        #expect(result.thinking == "still reasoning")
    }
}

/// A tiny, seedable PRNG (splitmix64) so the chunking fuzz test below is
/// reproducible: a failure always replays with the same seed and chunks.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("ThinkingFilter chunking property test")
struct ThinkingFilterChunkingPropertyTests {
    /// Splits `text` (by Character, so multi-scalar emoji stay intact) into a
    /// random sequence of non-empty chunks using `rng`.
    private static func randomChunks(of text: String, using rng: inout SplitMix64) -> [String] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        var chunks: [String] = []
        var index = 0
        while index < characters.count {
            let remaining = characters.count - index
            let length = Int.random(in: 1...remaining, using: &rng)
            chunks.append(String(characters[index..<(index + length)]))
            index += length
        }
        return chunks
    }

    private static func run(_ chunks: [String], startsInside: Bool) -> (visible: String, thinking: String) {
        var filter = ThinkingFilter(startsInsideThinking: startsInside)
        var visible = ""
        for chunk in chunks { visible += filter.consume(chunk) }
        visible += filter.finish()
        return (visible, filter.thinking)
    }

    private static let samples: [(text: String, startsInside: Bool)] = [
        ("Plain reply with no reasoning at all, just words.", false),
        ("<think>weigh the options</think>Use a text field.", false),
        ("<think>partial thought, never closed", false),
        ("still reasoning</think>Then the answer.", true),
        ("Before<think>middle</think>after<think>more</think>end", false),
        ("if a < b then put \"<t\" into x -- no real tag here", false),
        ("emoji stress: 🧵<think>🤔 thinking in 中文 and emoji 🎉</think>done ✅", false),
        ("", false),
    ]

    /// However a streamed reply is sliced into chunks, the visible and
    /// thinking text it produces must be identical — the split points are an
    /// artifact of the network/scheduler, never part of the model's output.
    @Test("random chunkings of the same text always yield identical visible and thinking output", arguments: 0..<8)
    func chunkingIsOrderIndependent(sampleIndex: Int) {
        let sample = Self.samples[sampleIndex]
        let reference = Self.run([sample.text], startsInside: sample.startsInside)

        for seed: UInt64 in [1, 2, 3, 4, 5] {
            var rng = SplitMix64(seed: seed &+ UInt64(sampleIndex) &* 1000)
            let chunks = Self.randomChunks(of: sample.text, using: &rng)
            let result = Self.run(chunks, startsInside: sample.startsInside)
            #expect(result.visible == reference.visible, "seed \(seed), sample \(sampleIndex), chunks \(chunks)")
            #expect(result.thinking == reference.thinking, "seed \(seed), sample \(sampleIndex), chunks \(chunks)")
        }
    }
}

@Suite("ChatRendering")
struct ChatRenderingTests {
    @Test("messages keep roles, tool calls become template dictionaries, images are declared unreadable")
    func rendersMessages() throws {
        let call = OllamaToolCall(function: OllamaToolCallFunction(name: "create_button", arguments: ["name": "Go"]))
        let rendered = ChatRendering.templateMessages(from: [
            OllamaMessage(role: "system", content: "rules"),
            OllamaMessage(role: "user", content: "look", images: ["aGk="]),
            OllamaMessage(role: "assistant", content: nil, tool_calls: [call]),
            OllamaMessage(role: "tool", content: "Created button 'Go'"),
        ])

        #expect(rendered.map { $0["role"] as? String } == ["system", "user", "assistant", "tool"])
        #expect((rendered[1]["content"] as? String)?.contains(ChatRendering.imageOmittedNote) == true)
        #expect(rendered[2]["content"] as? String == "")
        let calls = try #require(rendered[2]["tool_calls"] as? [[String: any Sendable]])
        let function = try #require(calls.first?["function"] as? [String: any Sendable])
        #expect(function["name"] as? String == "create_button")
        #expect((function["arguments"] as? [String: any Sendable])?["name"] as? String == "Go")
        #expect(rendered[3]["content"] as? String == "Created button 'Go'")
    }

    @Test("tool schemas keep types, descriptions, enums and required lists")
    func rendersTools() throws {
        let tool = OllamaTool(type: "function", function: OllamaFunction(
            name: "set_part_property",
            description: "Set a property",
            parameters: OllamaParameters(
                type: "object",
                properties: [
                    "property": OllamaProperty(type: "string", description: "Which", enum: ["script", "name"]),
                    "value": OllamaProperty(type: "string", description: "New value"),
                ],
                required: ["property", "value"]
            )
        ))
        let rendered = try #require(ChatRendering.templateTools(from: [tool]).first)
        let function = try #require(rendered["function"] as? [String: any Sendable])
        let parameters = try #require(function["parameters"] as? [String: any Sendable])
        let properties = try #require(parameters["properties"] as? [String: any Sendable])
        let property = try #require(properties["property"] as? [String: any Sendable])

        #expect(rendered["type"] as? String == "function")
        #expect(function["name"] as? String == "set_part_property")
        #expect(parameters["required"] as? [String] == ["property", "value"])
        #expect(property["enum"] as? [String] == ["script", "name"])
        #expect((properties["value"] as? [String: any Sendable])?["enum"] == nil)
    }

    @Test("non-string tool arguments are flattened to the strings Hype's tools expect")
    func flattensArguments() {
        let call = ToolCall(function: .init(name: "create_field", arguments: [
            "name": .string("Score"),
            "left": .int(40),
            "width": .double(120.0),
            "opacity": .double(0.5),
            "locked": .bool(true),
            "note": .null,
            "tags": .array([.string("a"), .int(2)]),
        ]))
        let flattened = ChatRendering.toolCall(from: call)

        #expect(flattened.name == "create_field")
        #expect(flattened.arguments["name"] == "Score")
        #expect(flattened.arguments["left"] == "40")
        #expect(flattened.arguments["width"] == "120")
        #expect(flattened.arguments["opacity"] == "0.5")
        #expect(flattened.arguments["locked"] == "true")
        #expect(flattened.arguments["note"] == "")
        #expect(flattened.arguments["tags"] == "[\"a\",2]")
    }

    @Test("templateMessages and templateTools render identical structure across repeated calls with the same input")
    func renderingIsDeterministic() throws {
        let call = OllamaToolCall(function: OllamaToolCallFunction(name: "create_button", arguments: ["name": "Go"]))
        let messages = [
            OllamaMessage(role: "system", content: "rules"),
            OllamaMessage(role: "user", content: "look", images: ["aGk="]),
            OllamaMessage(role: "assistant", content: nil, tool_calls: [call]),
        ]
        func summarizeMessages(_ rendered: [[String: any Sendable]]) -> [String] {
            rendered.map { entry in
                let role = entry["role"] as? String ?? ""
                let content = entry["content"] as? String ?? ""
                let callCount = (entry["tool_calls"] as? [[String: any Sendable]])?.count ?? 0
                return "\(role)|\(content)|\(callCount)"
            }
        }
        let firstMessages = summarizeMessages(ChatRendering.templateMessages(from: messages))
        let secondMessages = summarizeMessages(ChatRendering.templateMessages(from: messages))
        #expect(firstMessages == secondMessages)
        #expect(firstMessages == ["system|rules|0", "user|look\n\n\(ChatRendering.imageOmittedNote)|0", "assistant||1"])

        let tool = OllamaTool(type: "function", function: OllamaFunction(
            name: "set_part_property",
            description: "Set a property",
            parameters: OllamaParameters(
                type: "object",
                properties: [
                    "property": OllamaProperty(type: "string", description: "Which", enum: ["script", "name"]),
                    "value": OllamaProperty(type: "string", description: "New value"),
                ],
                required: ["property", "value"]
            )
        ))
        func summarizeTool(_ rendered: [[String: any Sendable]]) -> String? {
            guard let entry = rendered.first,
                  let function = entry["function"] as? [String: any Sendable],
                  let name = function["name"] as? String,
                  let parameters = function["parameters"] as? [String: any Sendable],
                  let required = parameters["required"] as? [String] else { return nil }
            return "\(name)|\(required.joined(separator: ","))"
        }
        let firstTools = summarizeTool(ChatRendering.templateTools(from: [tool]))
        let secondTools = summarizeTool(ChatRendering.templateTools(from: [tool]))
        #expect(firstTools == secondTools)
        #expect(firstTools == "set_part_property|property,value")
    }
}

@Suite("Prompt cache boundaries and integrity")
struct PromptCacheSafetyTests {
    @Test("the static prefix ends at the FIRST marker, so document text can never extend it")
    func staticPrefixEndsAtFirstMarker() throws {
        let prompt = "RULES\nguide text\n\nCURRENT STATE:\nCard parts: button \"CURRENT STATE: spoof\"\nnotes: CURRENT STATE: again"
        let end = try #require(MLXBuiltInModelEngine.staticPrefixEnd(of: prompt, markers: ["CURRENT STATE:"]))
        #expect(String(prompt[..<end]) == "RULES\nguide text\n\n")
        #expect(MLXBuiltInModelEngine.staticPrefixEnd(of: "no marker here", markers: ["CURRENT STATE:"]) == nil)
        let earliest = try #require(MLXBuiltInModelEngine.staticPrefixEnd(of: "a STATE: b CURRENT STATE: c", markers: ["CURRENT STATE:", "STATE:"]))
        #expect(String("a STATE: b CURRENT STATE: c"[..<earliest]) == "a ")
    }

    @Test("the per-install key is created once, kept private, and reused")
    func installKeyIsStableAndPrivate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hype-mlx-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try #require(PromptPrefixDiskCache.installKey(root: root))
        let second = try #require(PromptPrefixDiskCache.installKey(root: root))
        #expect(first == second)
        let keyFile = root.appendingPathComponent(".prompt-cache-key")
        let permissions = try #require(try FileManager.default.attributesOfItem(atPath: keyFile.path)[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == 0o600)
        #expect(try Data(contentsOf: keyFile).count == 32)
    }

    @Test("a cache file's tag changes when one byte changes, and with a different key")
    func authenticationCodeDetectsTampering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hype-mlx-mac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("prefix.safetensors")
        var bytes = Data((0..<100_000).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        let key = try #require(PromptPrefixDiskCache.installKey(root: root))

        let original = try #require(PromptPrefixDiskCache.authenticationCode(of: file, key: key))
        #expect(original.count == 32)
        #expect(PromptPrefixDiskCache.authenticationCode(of: file, key: key) == original)

        bytes[50_000] ^= 0x01
        try bytes.write(to: file)
        #expect(PromptPrefixDiskCache.authenticationCode(of: file, key: key) != original)

        let otherRoot = root.appendingPathComponent("other")
        let otherKey = try #require(PromptPrefixDiskCache.installKey(root: otherRoot))
        bytes[50_000] ^= 0x01
        try bytes.write(to: file)
        #expect(PromptPrefixDiskCache.authenticationCode(of: file, key: otherKey) != original)
        #expect(PromptPrefixDiskCache.tagURL(for: file).lastPathComponent == "prefix.safetensors.mac")
    }
}
