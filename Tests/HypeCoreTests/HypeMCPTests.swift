import Foundation
import Testing
@testable import HypeCore

@Suite("Hype MCP interface")
@MainActor
struct HypeMCPTests {
    @Test("initialize reports MCP capabilities")
    func initializeReportsCapabilities() async throws {
        let backend = HypeMCPDocumentBackend(document: HypeDocument.newDocument(name: "MCP"))
        let response = try await processorResponse(
            backend: backend,
            request: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [:]
            ]
        )

        #expect(response.error == nil)
        #expect(response.result?.object?["protocolVersion"]?.string == "2025-06-18")
        let capabilities = response.result?.object?["capabilities"]?.object
        #expect(capabilities?["tools"] != nil)
        #expect(capabilities?["resources"] != nil)
        #expect(capabilities?["prompts"] != nil)
    }

    @Test("tool bridge exposes existing AI tools and MCP control tools")
    func toolBridgeExposesTools() async {
        let tools = HypeMCPToolBridge.allTools
        let names = Set(tools.map(\.name))

        for tool in HypeToolDefinitions.allTools {
            #expect(names.contains(tool.function.name), "Missing MCP wrapper for \(tool.function.name)")
        }
        #expect(names.contains("hype_get_app_state"))
        #expect(names.contains("hype_preview_transaction"))
        #expect(names.contains("hype_create_test_stack"))
    }

    @Test("tools/list and resources/list are JSON-RPC compatible")
    func processorListsToolsAndResources() async throws {
        let backend = HypeMCPDocumentBackend(document: HypeDocument.newDocument(name: "MCP"))

        let tools = try await processorResponse(
            backend: backend,
            request: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list"
            ]
        )
        let toolNames = Set(tools.result?.object?["tools"]?.array?.compactMap { $0.object?["name"]?.string } ?? [])
        #expect(toolNames.contains("create_button"))
        #expect(toolNames.contains("hype_get_preferences"))

        let resources = try await processorResponse(
            backend: backend,
            request: [
                "jsonrpc": "2.0",
                "id": 3,
                "method": "resources/list"
            ]
        )
        let resourceURIs = Set(resources.result?.object?["resources"]?.array?.compactMap { $0.object?["uri"]?.string } ?? [])
        #expect(resourceURIs.contains("hype://app/state"))
        #expect(resourceURIs.contains("hype://app/preferences"))
        #expect(resourceURIs.contains("hype://stacks"))
    }

    @Test("MCP tool list applies AI context policy")
    func mcpToolListAppliesAIContextPolicy() async {
        let emptyBackend = HypeMCPDocumentBackend(document: HypeDocument.newDocument(name: "MCP"))
        let emptyNames = Set(await emptyBackend.listTools().map(\.name))
        #expect(!emptyNames.contains("list_ai_context"))
        #expect(emptyNames.contains("write_ai_context_note"))

        let suiteName = "HypeMCPTests.contextPolicy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(HypeAIProvider.openAI.rawValue, forKey: HypeAIConfiguration.providerKey)

        var document = HypeDocument.newDocument(name: "MCP Context")
        document.stack.aiContextCloudSharingAllowed = false
        let note = AIContextIngestor.makeTextNote(title: "Rules", text: "Use native controls.", role: .rules)
        document.aiContextLibrary.addSource(note.0, items: note.1)
        let contextBackend = HypeMCPDocumentBackend(document: document, defaults: defaults)
        let contextNames = Set(await contextBackend.listTools().map(\.name))

        #expect(contextNames.contains("list_ai_context"))
        #expect(contextNames.contains("read_ai_context_item"))
    }

    @Test("MCP rejects context read tools that are unavailable under policy")
    func mcpRejectsUnavailableContextReadTool() async {
        let backend = HypeMCPDocumentBackend(document: HypeDocument.newDocument(name: "MCP"))

        let result = await backend.callTool(name: "list_ai_context", arguments: [:])

        #expect(result.object?["error"]?.string?.contains("not available") == true)
    }

    @Test("preferences resource redacts secrets")
    func preferencesRedactSecrets() async throws {
        let suiteName = "HypeMCPTests.preferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("openai", forKey: HypeAIConfiguration.providerKey)

        let backend = HypeMCPDocumentBackend(
            document: HypeDocument.newDocument(name: "MCP"),
            defaults: defaults
        )
        let snapshot = await backend.readResource(uri: "hype://app/preferences")

        let preferences = snapshot.object?["preferences"]?.array ?? []
        #expect(preferences.contains { $0.object?["name"]?.string == "ai.provider" && $0.object?["value"]?.string == "openai" })

        let secrets = snapshot.object?["secrets"]?.array ?? []
        #expect(!secrets.isEmpty)
        for secret in secrets {
            #expect(secret.object?["isSet"] != nil)
            #expect(secret.object?["value"] == nil)
        }
    }

    @Test("direct MCP tool calls can mutate a document")
    func directToolCallCreatesButton() async {
        let backend = HypeMCPDocumentBackend(document: HypeDocument.newDocument(name: "MCP"))

        let result = await backend.callTool(
            name: "create_button",
            arguments: [
                "name": .string("MCP Button"),
                "left": .string("40"),
                "top": .string("50"),
                "width": .string("120"),
                "height": .string("32")
            ]
        )

        #expect(result.object?["result"]?.string?.contains("Created button") == true)
        #expect(backend.document.parts.count == 1)
        #expect(backend.document.parts.first?.name == "MCP Button")
    }

    @Test("mutation policy blocks write and preview tools")
    func mutationPolicyBlocksWritesAndPreviews() async {
        let backend = HypeMCPDocumentBackend(
            document: HypeDocument.newDocument(name: "MCP"),
            allowMutations: false
        )

        let directWrite = await backend.callTool(name: "create_button", arguments: ["name": .string("Blocked")])
        #expect(directWrite.object?["error"]?.string?.contains("disabled") == true)
        #expect(backend.document.parts.isEmpty)

        let preview = await backend.callTool(
            name: "hype_preview_transaction",
            arguments: [
                "tool_name": .string("create_button"),
                "arguments_json": .string(#"{"name":"Blocked Preview"}"#)
            ]
        )
        #expect(preview.object?["error"]?.string?.contains("disabled") == true)
        #expect(backend.document.parts.isEmpty)

        let read = await backend.callTool(name: "get_stack_property", arguments: ["property": .string("name")])
        #expect(read.object?["result"]?.string == "MCP")
    }

    @Test("transactions preview first and apply explicitly")
    func transactionsPreviewAndApplyExplicitly() async throws {
        let backend = HypeMCPDocumentBackend(document: HypeDocument.newDocument(name: "MCP"))

        let preview = await backend.callTool(
            name: "hype_preview_transaction",
            arguments: [
                "tool_name": .string("create_button"),
                "arguments_json": .string(#"{"name":"Preview Button","left":"70","top":"80"}"#),
                "prompt": .string("Create one button")
            ]
        )

        #expect(backend.document.parts.isEmpty)
        #expect(preview.object?["state"]?.string == "preview")
        #expect(preview.object?["operationCount"]?.number == 1)

        let transactionId = try #require(preview.object?["transactionId"]?.string)
        let applied = await backend.callTool(
            name: "hype_apply_transaction",
            arguments: ["transaction_id": .string(transactionId)]
        )

        #expect(applied.object?["state"]?.string == "applied")
        #expect(backend.document.parts.count == 1)
        #expect(backend.document.parts.first?.name == "Preview Button")
    }

    private func processorResponse(
        backend: HypeMCPDocumentBackend,
        request: [String: Any]
    ) async throws -> HypeMCPResponse {
        let data = try JSONSerialization.data(withJSONObject: request)
        let responseData = try #require(await HypeMCPProcessor(backend: backend).handle(data: data))
        return try JSONDecoder().decode(HypeMCPResponse.self, from: responseData)
    }
}

private extension HypeMCPJSONValue {
    var object: [String: HypeMCPJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var array: [HypeMCPJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
