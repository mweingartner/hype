import Foundation

@MainActor
public final class HypeMCPDocumentBackend: HypeMCPBackend {
    public private(set) var document: HypeDocument
    public private(set) var currentCardId: UUID
    public var selectedPartIds: Set<UUID>
    public var currentTool: String
    public var editingBackground: Bool
    public var allowMutations: Bool

    private var transactions: [UUID: AIEditTransaction] = [:]
    private let executor: HypeToolExecutor
    private let defaults: UserDefaults

    public init(
        document: HypeDocument,
        currentCardId: UUID? = nil,
        selectedPartIds: Set<UUID> = [],
        currentTool: String = "browse",
        editingBackground: Bool = false,
        allowMutations: Bool = true,
        executor: HypeToolExecutor = HypeToolExecutor(),
        defaults: UserDefaults = .standard
    ) {
        self.document = document
        self.currentCardId = currentCardId ?? document.sortedCards.first?.id ?? UUID()
        self.selectedPartIds = selectedPartIds
        self.currentTool = currentTool
        self.editingBackground = editingBackground
        self.allowMutations = allowMutations
        self.executor = executor
        self.defaults = defaults
    }

    public func listTools() async -> [HypeMCPTool] {
        HypeMCPToolBridge.tools(from: availableHypeTools())
    }

    public func callTool(name: String, arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue {
        if HypeMCPToolBridge.mcpControlToolNames.contains(name) {
            return await callControlTool(name: name, arguments: arguments)
        }

        guard availableHypeToolNames.contains(name) else {
            return error("Tool \(name) is not available under the current AI context policy.")
        }

        guard allowMutations || isReadOnlyHypeTool(name) else {
            return error("MCP mutations are disabled. Enable preference mcp.allowMutations to call \(name).")
        }

        return .object([
            "tool": .string(name),
            "result": .string(await runExistingTool(name: name, arguments: HypeMCPToolBridge.stringArguments(from: arguments))),
            "state": appState()
        ])
    }

    public func listResources() async -> [HypeMCPResource] {
        let stackId = document.stack.id.uuidString
        return [
            HypeMCPResource(uri: "hype://app/state", name: "App State", description: "Current Hype app and active stack state."),
            HypeMCPResource(uri: "hype://app/preferences", name: "Preferences", description: "MCP-exposed Hype preferences and redacted secret status."),
            HypeMCPResource(uri: "hype://stacks", name: "Open Stacks", description: "Open stack summaries."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/summary", name: "Active Stack Summary", description: "Stack, card, background, part, repository, and context summary."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/cards", name: "Cards", description: "Cards in the active stack."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/backgrounds", name: "Backgrounds", description: "Backgrounds in the active stack."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/parts", name: "Parts", description: "Parts visible to the active stack.")
        ]
    }

    public func readResource(uri: String) async -> HypeMCPJSONValue {
        switch uri {
        case "hype://app/state":
            return appState()
        case "hype://app/preferences":
            return HypeMCPPreferenceStore.snapshot(defaults: defaults)
        case "hype://stacks":
            return .object(["stacks": .array([stackSummary(compact: true)])])
        default:
            if uri.hasSuffix("/cards") {
                return .object(["cards": .array(document.sortedCards.map(cardSummary))])
            }
            if uri.hasSuffix("/backgrounds") {
                return .object(["backgrounds": .array(sortedBackgrounds.map(backgroundSummary))])
            }
            if uri.hasSuffix("/parts") {
                return .object(["parts": .array(document.parts.map(partSummary))])
            }
            if uri.contains("/part/"), let idText = uri.split(separator: "/").last, let id = UUID(uuidString: String(idText)),
               let part = document.parts.first(where: { $0.id == id }) {
                return partSummary(part)
            }
            if uri.contains("/card/"), let idText = uri.split(separator: "/").last, let id = UUID(uuidString: String(idText)),
               let card = document.cards.first(where: { $0.id == id }) {
                return cardSummary(card)
            }
            return stackSummary(compact: false)
        }
    }

    public func listPrompts() async -> [HypeMCPPrompt] {
        [
            HypeMCPPrompt(
                name: "diagnose_current_stack",
                description: "Inspect the current stack, console, selected parts, scripts, and available tools before proposing a fix.",
                arguments: []
            ),
            HypeMCPPrompt(
                name: "create_test_stack",
                description: "Create a deterministic test stack through MCP, then inspect and mutate it with Hype tools.",
                arguments: [
                    .init(name: "goal", description: "What the test stack should validate.", required: false)
                ]
            )
        ]
    }

    public func getPrompt(name: String, arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue {
        let text: String
        switch name {
        case "create_test_stack":
            let goal = arguments["goal"]?.flattenedString ?? "Validate a Hype behavior end to end."
            text = """
            Create a deterministic Hype test stack for this goal: \(goal)
            First call hype_get_app_state, then use hype_preview_transaction for multi-tool changes, apply only after reviewing the delta, and finally re-read the changed resources.
            """
        default:
            text = """
            Diagnose the current Hype stack through MCP.
            Read hype://app/state and hype://stack/{id}/summary, inspect selected parts and scripts, use read-only tools first, then preview mutations with hype_preview_transaction before applying them.
            """
        }
        return .object([
            "description": .string(name),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string(text)
                    ])
                ])
            ])
        ])
    }

    public func resetTestStack(name: String = "MCP Test Stack") {
        document = HypeDocument.newDocument(name: name)
        currentCardId = document.sortedCards.first?.id ?? UUID()
        selectedPartIds = []
        currentTool = "browse"
        editingBackground = false
        transactions.removeAll()
    }

    public func replaceDocument(_ newDocument: HypeDocument, currentCardId: UUID? = nil) {
        document = newDocument
        self.currentCardId = currentCardId ?? newDocument.sortedCards.first?.id ?? self.currentCardId
    }

    private func callControlTool(name: String, arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue {
        switch name {
        case "hype_get_app_state", "hype_list_open_stacks":
            return appState()
        case "hype_get_preferences":
            return HypeMCPPreferenceStore.snapshot(defaults: defaults)
        case "hype_set_preference":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            return .object([
                "result": .string(HypeMCPPreferenceStore.setPreference(
                    name: arguments["name"]?.flattenedString ?? "",
                    value: arguments["value"]?.flattenedString ?? "",
                    defaults: defaults
                )),
                "preferences": HypeMCPPreferenceStore.snapshot(defaults: defaults)
            ])
        case "hype_set_secret":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            return .object([
                "result": .string(HypeMCPPreferenceStore.setSecret(
                    name: arguments["name"]?.flattenedString ?? "",
                    value: arguments["value"]?.flattenedString ?? "",
                    defaults: defaults
                )),
                "preferences": HypeMCPPreferenceStore.snapshot(defaults: defaults)
            ])
        case "hype_delete_secret":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            return .object([
                "result": .string(HypeMCPPreferenceStore.deleteSecret(
                    name: arguments["name"]?.flattenedString ?? "",
                    defaults: defaults
                )),
                "preferences": HypeMCPPreferenceStore.snapshot(defaults: defaults)
            ])
        case "hype_run_existing_tool":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            let toolName = arguments["tool_name"]?.flattenedString ?? ""
            let toolArgs = HypeMCPToolBridge.parseArgumentsJSON(arguments["arguments_json"]?.flattenedString ?? "{}")
            return .object([
                "tool": .string(toolName),
                "result": .string(await runExistingTool(name: toolName, arguments: toolArgs)),
                "state": appState()
            ])
        case "hype_preview_transaction":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            return await previewTransaction(arguments: arguments)
        case "hype_apply_transaction":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            return applyTransaction(idText: arguments["transaction_id"]?.flattenedString ?? "")
        case "hype_rollback_transaction":
            return rollbackTransaction(idText: arguments["transaction_id"]?.flattenedString ?? "")
        case "hype_create_test_stack":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            resetTestStack(name: arguments["name"]?.flattenedString.nilIfEmpty ?? "MCP Test Stack")
            return appState()
        default:
            return error("Unknown MCP control tool \(name)")
        }
    }

    private func runExistingTool(name: String, arguments: [String: String]) async -> String {
        var draft = document
        let result = await executor.execute(
            toolName: name,
            arguments: arguments,
            document: &draft,
            currentCardId: currentCardId
        )
        document = draft
        updateNavigation(from: result)
        return result
    }

    private func previewTransaction(arguments: [String: HypeMCPJSONValue]) async -> HypeMCPJSONValue {
        let calls = transactionCalls(from: arguments)
        guard !calls.isEmpty else {
            return error("hype_preview_transaction requires tool_calls_json or tool_name.")
        }
        let transaction = await AIEditTransactionRunner(executor: executor).preview(
            toolCalls: calls,
            document: document,
            currentCardId: currentCardId,
            prompt: arguments["prompt"]?.flattenedString ?? "MCP transaction",
            providerName: "mcp"
        )
        transactions[transaction.id] = transaction
        return transactionSummary(transaction)
    }

    private func applyTransaction(idText: String) -> HypeMCPJSONValue {
        guard let id = UUID(uuidString: idText), var transaction = transactions[id] else {
            return error("Unknown transaction \(idText)")
        }
        let applied = AIEditTransactionRunner(executor: executor).apply(&transaction, to: &document)
        transactions[id] = applied
        return transactionSummary(applied)
    }

    private func rollbackTransaction(idText: String) -> HypeMCPJSONValue {
        guard let id = UUID(uuidString: idText), var transaction = transactions[id] else {
            return error("Unknown transaction \(idText)")
        }
        var rollbackDocument = document
        let rolledBack = AIEditTransactionRunner(executor: executor).rollback(&transaction, to: &rollbackDocument)
        document = rollbackDocument
        transactions[id] = rolledBack
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
                let args = HypeMCPToolBridge.stringArguments(from: object["arguments"])
                return OllamaToolCall(function: OllamaToolCallFunction(name: name, arguments: args))
            }
        }

        guard let name = arguments["tool_name"]?.flattenedString.nilIfEmpty else { return [] }
        let args = HypeMCPToolBridge.parseArgumentsJSON(arguments["arguments_json"]?.flattenedString ?? "{}")
        return [OllamaToolCall(function: OllamaToolCallFunction(name: name, arguments: args))]
    }

    private func updateNavigation(from result: String) {
        if result.hasPrefix("CREATED_CARD:") {
            let raw = String(result.dropFirst("CREATED_CARD:".count))
            if let id = UUID(uuidString: raw) {
                currentCardId = id
            }
        }
    }

    private func appState() -> HypeMCPJSONValue {
        .object([
            "activeStackId": .string(document.stack.id.uuidString),
            "openStacks": .array([stackSummary(compact: true)]),
            "currentCardId": .string(currentCardId.uuidString),
            "currentCardName": .string(document.cards.first(where: { $0.id == currentCardId })?.name ?? ""),
            "selectedPartIds": .array(selectedPartIds.map { .string($0.uuidString) }),
            "currentTool": .string(currentTool),
            "editingBackground": .bool(editingBackground),
            "allowMutations": .bool(allowMutations),
            "mcp": .object([
                "protocolVersion": .string("2025-06-18"),
                "transport": .string("stdio-debug-socket"),
                "aiContextPolicy": .string(aiContextPolicy.stateDescription)
            ])
        ])
    }

    private func stackSummary(compact: Bool) -> HypeMCPJSONValue {
        var object: [String: HypeMCPJSONValue] = [
            "id": .string(document.stack.id.uuidString),
            "name": .string(document.stack.name),
            "size": .object(["width": .number(Double(document.stack.width)), "height": .number(Double(document.stack.height))]),
            "cardCount": .number(Double(document.cards.count)),
            "backgroundCount": .number(Double(document.backgrounds.count)),
            "partCount": .number(Double(document.parts.count)),
            "currentCardId": .string(currentCardId.uuidString),
            "runtimeModeEnabled": .bool(document.stack.runtimeModeEnabled),
            "aiContextItemCount": .number(Double(document.aiContextLibrary.itemCount)),
            "aiContextCloudSharingAllowed": .bool(document.stack.aiContextCloudSharingAllowed),
            "aiContextPolicy": .string(aiContextPolicy.stateDescription),
            "targetPlatforms": .array(document.stack.deploymentTargets.selectedPlatforms.map { .string($0.rawValue) })
        ]
        if !compact {
            object["cards"] = .array(document.sortedCards.map(cardSummary))
            object["backgrounds"] = .array(sortedBackgrounds.map(backgroundSummary))
            object["selectedParts"] = .array(document.parts.filter { selectedPartIds.contains($0.id) }.map(partSummary))
        }
        return .object(object)
    }

    private func cardSummary(_ card: Card) -> HypeMCPJSONValue {
        let cardParts = document.parts.filter { $0.cardId == card.id }
        return .object([
            "id": .string(card.id.uuidString),
            "name": .string(card.name),
            "backgroundId": .string(card.backgroundId.uuidString),
            "partCount": .number(Double(cardParts.count)),
            "scriptLength": .number(Double(card.script.count)),
            "themeName": .string(card.themeName ?? "")
        ])
    }

    private func backgroundSummary(_ background: Background) -> HypeMCPJSONValue {
        let backgroundParts = document.parts.filter { $0.backgroundId == background.id }
        return .object([
            "id": .string(background.id.uuidString),
            "name": .string(background.name),
            "partCount": .number(Double(backgroundParts.count)),
            "scriptLength": .number(Double(background.script.count)),
            "themeName": .string(background.themeName ?? "")
        ])
    }

    private var sortedBackgrounds: [Background] {
        document.backgrounds.sorted { $0.sortKey < $1.sortKey }
    }

    private var aiContextPolicy: AIContextToolPolicy {
        AIContextToolPolicy(
            provider: HypeAIConfiguration.selectedProvider(defaults: defaults),
            trustBoundary: .localDebugMCP,
            document: document
        )
    }

    private func availableHypeTools() -> [OllamaTool] {
        HypeToolDefinitions.toolsApplyingAIContextPolicy(
            HypeToolDefinitions.allTools,
            policy: aiContextPolicy
        )
    }

    private var availableHypeToolNames: Set<String> {
        Set(availableHypeTools().map { $0.function.name })
    }

    private func partSummary(_ part: Part) -> HypeMCPJSONValue {
        .object([
            "id": .string(part.id.uuidString),
            "name": .string(part.name),
            "partType": .string(part.partType.rawValue),
            "cardId": .string(part.cardId?.uuidString ?? ""),
            "backgroundId": .string(part.backgroundId?.uuidString ?? ""),
            "rect": .object([
                "left": .number(part.left),
                "top": .number(part.top),
                "width": .number(part.width),
                "height": .number(part.height)
            ]),
            "visible": .bool(part.visible),
            "enabled": .bool(part.enabled),
            "scriptLength": .number(Double(part.script.count)),
            "helpText": .string(part.helpText)
        ])
    }

    private func transactionSummary(_ transaction: AIEditTransaction) -> HypeMCPJSONValue {
        .object([
            "transactionId": .string(transaction.id.uuidString),
            "state": .string(transaction.state.rawValue),
            "operationCount": .number(Double(transaction.operations.count)),
            "diagnostics": .array(transaction.diagnostics.map { .string($0) }),
            "operations": .array(transaction.operations.map { operation in
                .object([
                    "toolName": .string(operation.toolName),
                    "result": .string(operation.result),
                    "phase": .string(operation.phase.rawValue),
                    "delta": .object([
                        "createdPartIds": .array(operation.delta.createdPartIds.map { .string($0.uuidString) }),
                        "deletedPartIds": .array(operation.delta.deletedPartIds.map { .string($0.uuidString) }),
                        "changedPartIds": .array(operation.delta.changedPartIds.map { .string($0.uuidString) }),
                        "createdCardIds": .array(operation.delta.createdCardIds.map { .string($0.uuidString) }),
                        "changedCardIds": .array(operation.delta.changedCardIds.map { .string($0.uuidString) }),
                        "stackChanged": .bool(operation.delta.stackChanged)
                    ])
                ])
            })
        ])
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
