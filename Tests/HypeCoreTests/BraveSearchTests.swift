import Foundation
import Testing
@testable import HypeCore

@Suite("Brave Search Bridge integration")
struct BraveSearchTests {
    @Test("Brave is opt-in, app-local, and keeps existing providers")
    func configuration() throws {
        let suite = "BraveSearchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(BraveSearchConfiguration.makeSession(defaults: defaults) == nil)
        defaults.set(true, forKey: BraveSearchConfiguration.enabledKey)
        #expect(BraveSearchConfiguration.makeSession(defaults: defaults) != nil)
        #expect(HypeMCPPreferenceStore.setPreference(name: "braveSearch.endpoint", value: "http://user:secret@localhost/mcp", defaults: defaults).hasPrefix("Invalid"))
        #expect(HypeMCPPreferenceStore.setPreference(name: "braveSearch.endpoint", value: "http://192.168.1.2:18424/mcp", defaults: defaults) == "Set preference braveSearch.endpoint")
        #expect(defaults.string(forKey: BraveSearchConfiguration.endpointKey) == "http://192.168.1.2:18424/mcp")
        #expect(HypeMCPPreferenceStore.secretAccounts["brave"] == nil)
        let original = HypeToolDefinitions.withWebAssetTools(HypeToolDefinitions.cardControlAuthoringTools, enabled: true)
        #expect(HypeToolDefinitions.withBraveSearchTools(original, enabled: false).map(\.function.name) == original.map(\.function.name))
        let names = HypeToolDefinitions.withBraveSearchTools(original, enabled: true).map(\.function.name)
        #expect(names.suffix(2) == ["list_brave_tools", "call_brave_tool"])
        #expect(names.contains("search_web_for_sprite"))
        #expect(RuntimeAIToolCatalog.defaultTools.allSatisfy { !$0.name.contains("brave") })
    }

    @Test("Only explicit HTTP endpoints without embedded credentials are accepted")
    func endpoints() throws {
        for text in ["http://127.0.0.1:18424/mcp", "http://bridge.local:18424/mcp", "https://bridge.example/mcp"] {
            #expect(try BraveSearchConfiguration.validatedEndpoint(text).absoluteString == text)
        }
        for text in ["", "localhost:18424", "file:///tmp/mcp", "http:///mcp", "http://user:token@localhost/mcp", "http://localhost/mcp?key=secret", "http://localhost/mcp#key"] {
            #expect(throws: BraveSearchError.self) { try BraveSearchConfiguration.validatedEndpoint(text) }
        }
    }

    @Test("Discovery negotiates MCP, caches tools, and preserves the complete schema")
    func discovery() async throws {
        let fixture = BraveMCPFixture()
        let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint, transport: { try await fixture.respond($0) })
        let tools = try await session.discover()
        #expect(tools.count == 2)
        let result = await session.execute(toolName: "list_brave_tools", arguments: ["tool_name": "brave_web_search"])
        let schema = try JSONDecoder().decode(HypeMCPJSONValue.self, from: Data(result.utf8))
        #expect(schema == BraveMCPFixture.webTool)
        let requests = await fixture.requests
        #expect(requests.map { $0.objectValue?["method"]?.stringValue ?? "" } == ["initialize", "notifications/initialized", "tools/list"])
        #expect(await fixture.headers.dropFirst().allSatisfy { $0["Mcp-Session-Id"] == "fixture-session" && $0["MCP-Protocol-Version"] == "2025-06-18" })
        #expect(await fixture.headers.allSatisfy { $0["Authorization"] == nil && $0["X-Subscription-Token"] == nil })
        let summaries = await session.execute(toolName: "list_brave_tools", arguments: [:])
        #expect(summaries.contains("brave_llm_context"))
        let summaryJSON = try JSONDecoder().decode(HypeMCPJSONValue.self, from: Data(summaries.utf8))
        #expect(summaryJSON.objectValue?["tools"]?.arrayValue?.allSatisfy { $0.objectValue?["inputSchema"] == nil } == true)
    }

    @Test("The dispatcher passes typed JSON and retains structured, text, and source data")
    func execution() async throws {
        let fixture = BraveMCPFixture()
        let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint, transport: { try await fixture.respond($0) })
        let executor = HypeToolExecutor(webAssetSession: nil, webAssetClient: nil, webAssetPipeline: nil, braveSearchSession: session)
        var document = HypeDocument.newDocument(name: "Brave test")
        let before = document
        let card = try #require(document.sortedCards.first)
        let result = await executor.execute(toolName: "call_brave_tool", arguments: [
            "tool_name": "brave_web_search",
            "arguments_json": #"{"query":"Greek food near Rogue River, Oregon","count":5,"spellcheck":false,"result_filter":["web"],"extra":{"nested":true}}"#
        ], document: &document, currentCardId: card.id)
        #expect(result.contains("https://example.org/menu"))
        #expect(result.contains("structuredContent"))
        #expect(result.contains("literal snippet"))
        #expect(result.contains(#"\"claim\":\"preserved\""#))
        #expect(try canonical(before) == canonical(document))
        let call = try #require(await fixture.requests.last?.objectValue?["params"]?.objectValue)
        #expect(call["name"] == .string("brave_web_search"))
        let args = try #require(call["arguments"]?.objectValue)
        #expect(args["count"] == .number(5))
        #expect(args["spellcheck"] == .bool(false))
        #expect(args["result_filter"] == .array([.string("web")]))
        #expect(args["extra"] == .object(["nested": .bool(true)]))
    }

    @Test("Undiscovered tools and malformed arguments never trigger a search")
    func rejectsBadCalls() async throws {
        let fixture = BraveMCPFixture()
        let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint, transport: { try await fixture.respond($0) })
        for payload in ["[]", "null", "not json", "42"] {
            let result = await session.execute(toolName: "call_brave_tool", arguments: ["tool_name": "brave_web_search", "arguments_json": payload])
            #expect(result.contains("must be a JSON object"))
        }
        let unknown = await session.execute(toolName: "call_brave_tool", arguments: ["tool_name": "execute_shell", "arguments_json": "{}"])
        #expect(unknown.contains("was not discovered"))
        #expect(await fixture.requests.count == 3)
        var document = HypeDocument.newDocument(name: "Brave test")
        let disabled = await HypeToolExecutor().execute(toolName: "call_brave_tool", arguments: [:], document: &document, currentCardId: UUID())
        #expect(disabled == "Brave Search is disabled. Enable it in Settings → Services → Brave Search.")
    }

    @Test("Paid searches defer until Apply and run exactly once")
    func transaction() async throws {
        let fixture = BraveMCPFixture()
        let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint, transport: { try await fixture.respond($0) })
        let runner = AIEditTransactionRunner(executor: HypeToolExecutor(webAssetSession: nil, webAssetClient: nil, webAssetPipeline: nil, braveSearchSession: session))
        var document = HypeDocument.newDocument(name: "Brave test")
        let card = try #require(document.sortedCards.first)
        var transaction = await runner.preview(toolCalls: [OllamaToolCall(function: .init(name: "call_brave_tool", arguments: ["tool_name": "brave_web_search", "arguments_json": #"{"query":"Greek food"}"#]))], document: document, currentCardId: card.id, prompt: "Find Greek food", providerName: "test")
        #expect(await fixture.requests.isEmpty)
        #expect(transaction.operations.first?.phase == .deferredExternalApply)
        await runner.apply(&transaction, to: &document, currentCardId: card.id)
        #expect(transaction.operations.first?.result.contains("https://example.org/menu") == true)
        await runner.apply(&transaction, to: &document, currentCardId: card.id)
        #expect(await fixture.requests.filter { $0.objectValue?["method"] == .string("tools/call") }.count == 1)
        #expect(try canonical(transaction.rollbackDocument) == canonical(document))
    }

    @Test("Provider rejection preserves isError and its useful message")
    func rejectedSearch() async {
        let fixture = BraveMCPFixture(result: .object(["isError": .bool(true), "content": .array([.object(["type": .string("text"), "text": .string("429: quota exceeded; subscription does not allow this feature")])])]))
        let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint, transport: { try await fixture.respond($0) })
        let result = await session.execute(toolName: "call_brave_tool", arguments: ["tool_name": "brave_web_search", "arguments_json": #"{"query":"test"}"#])
        #expect(result.contains("request failed"))
        #expect(result.contains("quota exceeded"))
        #expect(result.contains("\"isError\" : true"))
    }

    @Test("Offline and timeout errors are actionable and never silently retried")
    func connectionFailures() async {
        for code in [URLError.Code.cannotConnectToHost, .timedOut] {
            let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint, transport: { _ in throw URLError(code) })
            let result = await session.execute(toolName: "list_brave_tools", arguments: [:])
            #expect(result.contains(code == .timedOut ? "timed out" : "awake and logged in"))
        }
    }

    @Test("Cancellation interrupts transport and does not trigger a later call")
    func cancellation() async throws {
        let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint, transport: { _ in
            try await Task.sleep(for: .seconds(30))
            throw URLError(.timedOut)
        })
        let task = Task { await session.execute(toolName: "list_brave_tools", arguments: [:]) }
        task.cancel()
        #expect(await task.value == "Brave Search cancelled.")
    }

    @Test("Live bridge schemas through HypeCore", .enabled(if: ProcessInfo.processInfo.environment["HYPE_BRAVE_LIVE_TEST"] == "1"))
    func liveDiscovery() async throws {
        let session = BraveSearchSession(endpoint: BraveSearchConfiguration.defaultEndpoint)
        let tools = try await session.discover()
        #expect(Set(tools.compactMap { $0.objectValue?["name"]?.stringValue }) == Set(["brave_web_search", "brave_llm_context", "brave_place_search", "brave_local_search", "brave_news_search", "brave_image_search", "brave_video_search", "brave_summarizer"]))
        #expect(tools.first { $0.objectValue?["name"] == .string("brave_place_search") }?.objectValue?["inputSchema"]?.objectValue?["properties"]?.objectValue?["radius"]?.objectValue?["type"] == .string("number"))
    }

    private func canonical(_ document: HypeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }
}

private actor BraveMCPFixture {
    var requests: [HypeMCPJSONValue] = []
    var headers: [[String: String]] = []
    let result: HypeMCPJSONValue

    static let webTool: HypeMCPJSONValue = .object([
        "name": .string("brave_web_search"), "description": .string("Search the web"),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string"), "maxLength": .number(400)]),
                "count": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(20)]),
                "goggles": .object(["anyOf": .array([.object(["type": .string("string")]), .object(["type": .string("array"), "items": .object(["type": .string("string")])])])])
            ]), "required": .array([.string("query")])
        ])
    ])

    init(result: HypeMCPJSONValue = .object([
        "isError": .bool(false),
        "structuredContent": .object(["sources": .array([.object(["url": .string("https://example.org/menu")])])]),
        "content": .array([.object(["type": .string("text"), "text": .string("literal snippet: {\"claim\":\"preserved\"}")])])
    ])) { self.result = result }

    func respond(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json, text/event-stream")
        let payload = try JSONDecoder().decode(HypeMCPJSONValue.self, from: request.httpBody ?? Data())
        requests.append(payload)
        headers.append(request.allHTTPHeaderFields ?? [:])
        let method = payload.objectValue?["method"]?.stringValue
        if method == "notifications/initialized" {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: [:])!)
        }
        let responseResult: HypeMCPJSONValue
        if method == "initialize" {
            responseResult = .object(["protocolVersion": .string("2025-06-18"), "capabilities": .object(["tools": .object([:])])])
        } else if method == "tools/list" {
            responseResult = .object(["tools": .array([Self.webTool, .object(["name": .string("brave_llm_context"), "description": .string("Extracted source grounding"), "inputSchema": .object(["type": .string("object")])])])])
        } else {
            responseResult = result
        }
        let value = HypeMCPJSONValue.object(["jsonrpc": .string("2.0"), "id": payload.objectValue?["id"] ?? .null, "result": responseResult])
        let sse = "event: message\r\ndata: \(value.jsonString(pretty: false))\r\n\r\n"
        return (Data(sse.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream", "Mcp-Session-Id": "fixture-session"])!)
    }
}
