import Foundation
import HypeCore

@MainActor
final class HypeLiveMCPBackend: HypeMCPBackend {
    private let registry: HypeAutomationRegistry
    private let defaults: UserDefaults
    private var transactions: [UUID: (stackId: UUID, transaction: AIEditTransaction)] = [:]

    init(registry: HypeAutomationRegistry = .shared, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.defaults = defaults
    }

    func listTools() async -> [HypeMCPTool] {
        HypeMCPToolBridge.allTools
    }

    func callTool(name: String, arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue {
        if name == "hype_get_app_state" || name == "hype_list_open_stacks" {
            return appState()
        }
        if name == "hype_get_preferences" {
            return HypeMCPPreferenceStore.snapshot(defaults: defaults)
        }
        if name == "hype_set_preference" {
            return setPreference(arguments)
        }
        if name == "hype_set_secret" {
            return setSecret(arguments)
        }
        if name == "hype_delete_secret" {
            return deleteSecret(arguments)
        }

        guard mutationAllowed || isReadOnlyHypeTool(name) else {
            return error("MCP mutations are disabled. Enable preference mcp.allowMutations.")
        }
        guard let session = registry.activeSession() else {
            return error("No open Hype stack is registered.")
        }

        switch name {
        case "hype_run_existing_tool":
            let toolName = arguments["tool_name"]?.flattenedString ?? ""
            let toolArgs = HypeMCPToolBridge.parseArgumentsJSON(arguments["arguments_json"]?.flattenedString ?? "{}")
            return await runTool(name: toolName, arguments: toolArgs, session: session)
        case "hype_preview_transaction":
            return await previewTransaction(arguments: arguments, session: session)
        case "hype_apply_transaction":
            return await applyTransaction(arguments: arguments)
        case "hype_rollback_transaction":
            return rollbackTransaction(arguments: arguments)
        case "hype_create_test_stack":
            let document = HypeDocument.newDocument(name: arguments["name"]?.flattenedString.nilIfEmpty ?? "MCP Test Stack")
            registry.apply(
                document: document,
                to: session,
                currentCardId: document.sortedCards.first?.id,
                actionName: "MCP Create Test Stack"
            )
            return appState()
        default:
            return await runTool(
                name: name,
                arguments: HypeMCPToolBridge.stringArguments(from: arguments),
                session: session
            )
        }
    }

    func listResources() async -> [HypeMCPResource] {
        var resources = [
            HypeMCPResource(uri: "hype://app/state", name: "App State", description: "Current Hype app and open stack state."),
            HypeMCPResource(uri: "hype://app/preferences", name: "Preferences", description: "MCP-exposed Hype preferences and redacted secret status."),
            HypeMCPResource(uri: "hype://app/console", name: "Console", description: "Recent automation-visible console events."),
            HypeMCPResource(uri: "hype://stacks", name: "Open Stacks", description: "All registered open Hype stacks.")
        ]
        for session in registry.listSessions() {
            let id = session.stackId.uuidString
            resources.append(contentsOf: [
                HypeMCPResource(uri: "hype://stack/\(id)/summary", name: "\(session.document.stack.name) Summary", description: "Stack summary."),
                HypeMCPResource(uri: "hype://stack/\(id)/cards", name: "\(session.document.stack.name) Cards", description: "Cards in the stack."),
                HypeMCPResource(uri: "hype://stack/\(id)/backgrounds", name: "\(session.document.stack.name) Backgrounds", description: "Backgrounds in the stack."),
                HypeMCPResource(uri: "hype://stack/\(id)/parts", name: "\(session.document.stack.name) Parts", description: "Parts in the stack.")
            ])
        }
        return resources
    }

    func readResource(uri: String) async -> HypeMCPJSONValue {
        if uri == "hype://app/state" { return appState() }
        if uri == "hype://app/preferences" { return HypeMCPPreferenceStore.snapshot(defaults: defaults) }
        if uri == "hype://app/console" {
            return .object(["message": .string("Console streaming is reserved for the next MCP phase; tool calls are logged through HypeLogger.")])
        }
        if uri == "hype://stacks" {
            return .object(["stacks": .array(registry.listSessions().map { stackSummary($0, compact: true) })])
        }

        let components = uri.split(separator: "/").map(String.init)
        guard let stackIndex = components.firstIndex(of: "stack"),
              components.indices.contains(stackIndex + 1),
              let stackId = UUID(uuidString: components[stackIndex + 1]),
              let session = registry.session(stackId: stackId) else {
            return error("Unknown resource \(uri)")
        }

        let backend = HypeMCPDocumentBackend(
            document: session.document,
            currentCardId: session.currentCardId,
            selectedPartIds: session.selectedPartIds,
            currentTool: session.currentTool.rawValue,
            editingBackground: session.editingBackground,
            allowMutations: mutationAllowed,
            defaults: defaults
        )
        return await backend.readResource(uri: uri)
    }

    func listPrompts() async -> [HypeMCPPrompt] {
        let session = registry.activeSession()
        let backend = HypeMCPDocumentBackend(
            document: session?.document ?? HypeDocument.newDocument(name: "No Stack"),
            currentCardId: session?.currentCardId,
            defaults: defaults
        )
        return await backend.listPrompts()
    }

    func getPrompt(name: String, arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue {
        let session = registry.activeSession()
        let backend = HypeMCPDocumentBackend(
            document: session?.document ?? HypeDocument.newDocument(name: "No Stack"),
            currentCardId: session?.currentCardId,
            defaults: defaults
        )
        return await backend.getPrompt(name: name, arguments: arguments)
    }

    private var mutationAllowed: Bool {
        if defaults.object(forKey: HypeMCPConfiguration.allowMutationsKey) == nil {
            return true
        }
        return defaults.bool(forKey: HypeMCPConfiguration.allowMutationsKey)
    }

    private func setPreference(_ arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        guard mutationAllowed else { return error("MCP mutations are disabled.") }
        return .object([
            "result": .string(HypeMCPPreferenceStore.setPreference(
                name: arguments["name"]?.flattenedString ?? "",
                value: arguments["value"]?.flattenedString ?? "",
                defaults: defaults
            )),
            "preferences": HypeMCPPreferenceStore.snapshot(defaults: defaults)
        ])
    }

    private func setSecret(_ arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        guard mutationAllowed else { return error("MCP mutations are disabled.") }
        return .object([
            "result": .string(HypeMCPPreferenceStore.setSecret(
                name: arguments["name"]?.flattenedString ?? "",
                value: arguments["value"]?.flattenedString ?? "",
                defaults: defaults
            )),
            "preferences": HypeMCPPreferenceStore.snapshot(defaults: defaults)
        ])
    }

    private func deleteSecret(_ arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        guard mutationAllowed else { return error("MCP mutations are disabled.") }
        return .object([
            "result": .string(HypeMCPPreferenceStore.deleteSecret(
                name: arguments["name"]?.flattenedString ?? "",
                defaults: defaults
            )),
            "preferences": HypeMCPPreferenceStore.snapshot(defaults: defaults)
        ])
    }

    private func runTool(
        name: String,
        arguments: [String: String],
        session: HypeAutomationSession
    ) async -> HypeMCPJSONValue {
        var document = session.document
        let before = document
        let currentCardId = session.currentCardId ?? document.sortedCards.first?.id ?? UUID()
        let result = await HypeToolExecutor().execute(
            toolName: name,
            arguments: arguments,
            document: &document,
            currentCardId: currentCardId
        )
        let newCardId = cardId(after: result, document: document, fallback: currentCardId)
        if !HypeDocumentSnapshotCodec.equivalent(before, document) {
            registry.apply(
                document: document,
                to: session,
                currentCardId: newCardId,
                actionName: "MCP \(name)"
            )
        }
        return .object([
            "tool": .string(name),
            "result": .string(result),
            "state": appState()
        ])
    }

    private func previewTransaction(
        arguments: [String: HypeMCPJSONValue],
        session: HypeAutomationSession
    ) async -> HypeMCPJSONValue {
        let calls = transactionCalls(from: arguments)
        guard !calls.isEmpty else { return error("hype_preview_transaction requires tool_calls_json or tool_name.") }
        let currentCardId = session.currentCardId ?? session.document.sortedCards.first?.id ?? UUID()
        let transaction = await AIEditTransactionRunner(executor: HypeToolExecutor()).preview(
            toolCalls: calls,
            document: session.document,
            currentCardId: currentCardId,
            prompt: arguments["prompt"]?.flattenedString ?? "MCP transaction",
            providerName: "mcp"
        )
        transactions[transaction.id] = (session.stackId, transaction)
        return transactionSummary(transaction)
    }

    private func applyTransaction(arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue {
        guard let id = UUID(uuidString: arguments["transaction_id"]?.flattenedString ?? ""),
              var stored = transactions[id],
              let session = registry.session(stackId: stored.stackId) else {
            return error("Unknown transaction.")
        }
        var document = session.document
        let currentCardId = session.currentCardId ?? document.sortedCards.first?.id ?? UUID()
        let applied = await AIEditTransactionRunner(executor: HypeToolExecutor()).apply(
            &stored.transaction,
            to: &document,
            currentCardId: currentCardId
        )
        registry.apply(document: document, to: session, currentCardId: currentCardId, actionName: "MCP Apply Transaction")
        transactions[id] = (stored.stackId, applied)
        return transactionSummary(applied)
    }

    private func rollbackTransaction(arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        guard let id = UUID(uuidString: arguments["transaction_id"]?.flattenedString ?? ""),
              var stored = transactions[id] else {
            return error("Unknown transaction.")
        }
        var document = stored.transaction.previewDocument
        let rolledBack = AIEditTransactionRunner(executor: HypeToolExecutor()).rollback(&stored.transaction, to: &document)
        transactions[id] = (stored.stackId, rolledBack)
        return transactionSummary(rolledBack)
    }

    private func transactionCalls(from arguments: [String: HypeMCPJSONValue]) -> [OllamaToolCall] {
        if let json = arguments["tool_calls_json"]?.flattenedString,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(HypeMCPJSONValue.self, from: data),
           let array = decoded.arrayValue {
            return array.compactMap { item in
                guard let object = item.objectValue,
                      let name = object["tool_name"]?.flattenedString.nilIfEmpty ?? object["name"]?.flattenedString.nilIfEmpty else {
                    return nil
                }
                return OllamaToolCall(function: OllamaToolCallFunction(
                    name: name,
                    arguments: HypeMCPToolBridge.stringArguments(from: object["arguments"])
                ))
            }
        }
        guard let name = arguments["tool_name"]?.flattenedString.nilIfEmpty else { return [] }
        return [OllamaToolCall(function: OllamaToolCallFunction(
            name: name,
            arguments: HypeMCPToolBridge.parseArgumentsJSON(arguments["arguments_json"]?.flattenedString ?? "{}")
        ))]
    }

    private func cardId(after result: String, document: HypeDocument, fallback: UUID) -> UUID {
        if result.hasPrefix("CREATED_CARD:") {
            let raw = String(result.dropFirst("CREATED_CARD:".count))
            return UUID(uuidString: raw) ?? fallback
        }
        return fallback
    }

    private func appState() -> HypeMCPJSONValue {
        .object([
            "activeStackId": .string(registry.activeSession()?.stackId.uuidString ?? ""),
            "openStacks": .array(registry.listSessions().map { stackSummary($0, compact: true) }),
            "preferences": .object([
                "mcpEnabled": .bool(defaults.object(forKey: HypeMCPConfiguration.enabledKey) == nil ? true : defaults.bool(forKey: HypeMCPConfiguration.enabledKey)),
                "allowMutations": .bool(mutationAllowed),
                "port": .string(defaults.string(forKey: HypeMCPConfiguration.portKey) ?? HypeMCPConfiguration.defaultPort)
            ])
        ])
    }

    private func stackSummary(_ session: HypeAutomationSession, compact: Bool) -> HypeMCPJSONValue {
        if compact {
            return .object([
                "id": .string(session.stackId.uuidString),
                "name": .string(session.document.stack.name),
                "currentCardId": .string((session.currentCardId ?? session.document.sortedCards.first?.id)?.uuidString ?? ""),
                "selectedPartIds": .array(session.selectedPartIds.map { .string($0.uuidString) }),
                "currentTool": .string(session.currentTool.rawValue),
                "editingBackground": .bool(session.editingBackground),
                "cardCount": .number(Double(session.document.cards.count)),
                "partCount": .number(Double(session.document.parts.count))
            ])
        }
        let cardValues: [HypeMCPJSONValue] = session.document.sortedCards.map { card in
            .object([
                "id": .string(card.id.uuidString),
                "name": .string(card.name),
                "backgroundId": .string(card.backgroundId.uuidString),
                "scriptLength": .number(Double(card.script.count))
            ])
        }
        let backgroundValues: [HypeMCPJSONValue] = session.document.backgrounds.sorted { $0.sortKey < $1.sortKey }.map { background in
            .object([
                "id": .string(background.id.uuidString),
                "name": .string(background.name),
                "scriptLength": .number(Double(background.script.count))
            ])
        }
        let partValues: [HypeMCPJSONValue] = session.document.parts.map { part in
            .object([
                "id": .string(part.id.uuidString),
                "name": .string(part.name),
                "partType": .string(part.partType.rawValue),
                "cardId": .string(part.cardId?.uuidString ?? ""),
                "backgroundId": .string(part.backgroundId?.uuidString ?? ""),
                "scriptLength": .number(Double(part.script.count))
            ])
        }
        return .object([
            "id": .string(session.stackId.uuidString),
            "name": .string(session.document.stack.name),
            "currentCardId": .string((session.currentCardId ?? session.document.sortedCards.first?.id)?.uuidString ?? ""),
            "selectedPartIds": .array(session.selectedPartIds.map { .string($0.uuidString) }),
            "currentTool": .string(session.currentTool.rawValue),
            "editingBackground": .bool(session.editingBackground),
            "cards": .array(cardValues),
            "backgrounds": .array(backgroundValues),
            "parts": .array(partValues)
        ])
    }

    private func transactionSummary(_ transaction: AIEditTransaction) -> HypeMCPJSONValue {
        HypeMCPDocumentBackend(document: transaction.previewDocument).readTransactionSummary(transaction)
    }

    private func isReadOnlyHypeTool(_ name: String) -> Bool {
        name.hasPrefix("get_")
            || name.hasPrefix("list_")
            || name.hasPrefix("capture_")
            || name.hasPrefix("search_")
            || name == "check_script"
            || name == "review_hypetalk_script"
            || name == "plan_hypetalk_script"
            || name == "inspect_message_path"
            || name == "suggest_handler_location"
    }

    private func error(_ message: String) -> HypeMCPJSONValue {
        .object(["error": .string(message)])
    }
}

private extension HypeMCPDocumentBackend {
    func readTransactionSummary(_ transaction: AIEditTransaction) -> HypeMCPJSONValue {
        return .object([
            "transactionId": .string(transaction.id.uuidString),
            "state": .string(transaction.state.rawValue),
            "operationCount": .number(Double(transaction.operations.count)),
            "diagnostics": .array(transaction.diagnostics.map { .string($0) }),
            "operations": .array(transaction.operations.map { operation in
                .object([
                    "toolName": .string(operation.toolName),
                    "result": .string(operation.result),
                    "phase": .string(operation.phase.rawValue)
                ])
            })
        ])
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
