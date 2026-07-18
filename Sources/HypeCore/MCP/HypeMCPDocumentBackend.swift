import CoreGraphics
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

    /// Sentinel written in place of secure field-body text on every MCP
    /// transport read, and recognized on `hype_replace_part` as "leave the
    /// stored value alone." Matches the curated masking one-liners
    /// (`HypeToolExecutor.get_part_property`, `formatAllProperties`,
    /// HypeTalk `the text of field …`) exactly.
    private static let secureFieldMask = "(masked)"

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
            HypeMCPResource(uri: "hype://stack/\(stackId)/document", name: "Full Active Stack Document", description: "Full HypeDocument JSON, including scripts and all persisted attributes. Secure field textContent, htmlContent, and searchText are masked."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/cards", name: "Cards", description: "Cards in the active stack."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/backgrounds", name: "Backgrounds", description: "Backgrounds in the active stack."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/parts", name: "Parts", description: "Parts visible to the active stack."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/stack/full", name: "Full Stack Object", description: "Full stack object JSON, including script."),
            HypeMCPResource(uri: "hype://stack/\(stackId)/card/\(currentCardId)/full", name: "Full Current Card", description: "Full current card object JSON, including script.")
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
            if uri.hasSuffix("/document") {
                return fullDocumentResource()
            }
            if uri.hasSuffix("/stack/full") {
                return .object(["objectType": .string("stack"), "object": codableJSONValue(document.stack)])
            }
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
            if uri.contains("/part/"), uri.hasSuffix("/full"),
               let idText = uri.split(separator: "/").dropLast().last,
               let id = UUID(uuidString: String(idText)),
               let part = document.parts.first(where: { $0.id == id }) {
                return .object(["objectType": .string("part"), "object": codableJSONValue(maskedForTransport(part))])
            }
            if uri.contains("/card/"), let idText = uri.split(separator: "/").last, let id = UUID(uuidString: String(idText)),
               let card = document.cards.first(where: { $0.id == id }) {
                return cardSummary(card)
            }
            if uri.contains("/card/"), uri.hasSuffix("/full"),
               let idText = uri.split(separator: "/").dropLast().last,
               let id = UUID(uuidString: String(idText)),
               let card = document.cards.first(where: { $0.id == id }) {
                return .object(["objectType": .string("card"), "object": codableJSONValue(card)])
            }
            if uri.contains("/background/"), uri.hasSuffix("/full"),
               let idText = uri.split(separator: "/").dropLast().last,
               let id = UUID(uuidString: String(idText)),
               let background = document.backgrounds.first(where: { $0.id == id }) {
                return .object(["objectType": .string("background"), "object": codableJSONValue(background)])
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

    public func resetTestStack(
        name: String = "MCP Test Stack",
        deploymentTargets: StackDeploymentTargets = .automationDefault()
    ) {
        document = HypeDocument.newDocument(name: name, deploymentTargets: deploymentTargets)
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
        case "hype_get_stack_document":
            return fullDocumentResource()
        case "hype_get_object":
            return getObject(arguments: arguments)
        case "hype_canvas_hit_test":
            return logicalCanvasHitTest(arguments: arguments)
        case "hype_open_script_editor":
            return .object([
                "result": .string("Script editor open is available only through the live Hype debug server."),
                "requestedObject": getObject(arguments: arguments)
            ])
        case "hype_dispatch_message":
            return error("Message dispatch is available only through the live Hype debug server.")
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
        case "hype_set_script":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            return setScript(arguments: arguments)
        case "hype_replace_part":
            guard allowMutations else { return error("MCP mutations are disabled.") }
            return replacePart(arguments: arguments)
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
            resetTestStack(
                name: arguments["name"]?.flattenedString.nilIfEmpty ?? "MCP Test Stack",
                deploymentTargets: automationDeploymentTargets(from: arguments)
            )
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

    private func automationDeploymentTargets(from arguments: [String: HypeMCPJSONValue]) -> StackDeploymentTargets {
        let selected = automationTargetPlatforms(from: arguments["target_platforms"] ?? arguments["targetPlatforms"])
        let primary = (arguments["primary_target_platform"] ?? arguments["primaryTargetPlatform"])
            .flatMap { $0.flattenedString }
            .flatMap(HypeTargetPlatform.parse)
        return .automationDefault(selectedPlatforms: selected.isEmpty ? [.macOS] : selected, primaryPlatform: primary)
    }

    private func automationTargetPlatforms(from value: HypeMCPJSONValue?) -> [HypeTargetPlatform] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return array.compactMap { $0.flattenedString }.compactMap(HypeTargetPlatform.parse)
        }
        return value.flattenedString
            .split(separator: ",")
            .compactMap { HypeTargetPlatform.parse(String($0)) }
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
            "userLevel": .number(Double(document.stack.userLevel)),
            "userLevelName": .string(document.stack.userLevel.hypeUserLevel.displayName),
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
            "userLevel": .number(Double(document.stack.userLevel)),
            "userLevelName": .string(document.stack.userLevel.hypeUserLevel.displayName),
            "aiContextItemCount": .number(Double(document.aiContextLibrary.itemCount)),
            "aiContextCloudSharingAllowed": .bool(document.stack.aiContextCloudSharingAllowed),
            "aiContextPolicy": .string(aiContextPolicy.stateDescription),
            "targetPlatforms": .array(document.stack.deploymentTargets.selectedPlatforms.map { .string($0.rawValue) }),
            "primaryTargetPlatform": .string(document.stack.deploymentTargets.primaryPlatform.rawValue),
            "targetSelectionPromptAcknowledged": .bool(document.stack.deploymentTargets.selectionPromptAcknowledged)
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

    private func fullDocumentResource() -> HypeMCPJSONValue {
        .object([
            "objectType": .string("document"),
            "document": codableJSONValue(maskedForTransport(document)),
            "state": appState()
        ])
    }

    private func getObject(arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        let type = arguments["object_type"]?.flattenedString
            ?? arguments["objectType"]?.flattenedString
            ?? "part"
        let identifier = arguments["id_or_name"]?.flattenedString
            ?? arguments["idOrName"]?.flattenedString
            ?? arguments["id"]?.flattenedString
            ?? arguments["name"]?.flattenedString
            ?? ""

        switch type.normalizedObjectType {
        case "stack":
            return .object(["objectType": .string("stack"), "object": codableJSONValue(document.stack)])
        case "card":
            guard let card = resolveCard(identifier) else { return error("No card matched '\(identifier)'.") }
            return .object(["objectType": .string("card"), "object": codableJSONValue(card)])
        case "background":
            guard let background = resolveBackground(identifier) else { return error("No background matched '\(identifier)'.") }
            return .object(["objectType": .string("background"), "object": codableJSONValue(background)])
        case "part", "button", "field", "object":
            guard let part = resolvePart(identifier) else { return error("No part matched '\(identifier)'.") }
            return .object(["objectType": .string("part"), "object": codableJSONValue(maskedForTransport(part))])
        default:
            return error("Unsupported object_type '\(type)'. Use stack, card, background, or part.")
        }
    }

    private func logicalCanvasHitTest(arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        guard let x = arguments["x"]?.doubleValue,
              let y = arguments["y"]?.doubleValue else {
            return error("hype_canvas_hit_test requires numeric x and y.")
        }
        let cardId = (arguments["card_id"] ?? arguments["cardId"])
            .flatMap { UUID(uuidString: $0.flattenedString) }
            ?? currentCardId
        let point = CGPoint(x: x, y: y)
        let part = CardRenderer().partAtPoint(point, document: document, cardId: cardId)
        return .object([
            "point": .object(["x": .number(x), "y": .number(y)]),
            "currentCardId": .string(cardId.uuidString),
            "logicalTopPart": part.map(partSummary) ?? .null,
            "source": .string("document-renderer")
        ])
    }

    private func setScript(arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        let script = arguments["script"]?.flattenedString ?? ""
        let shouldValidate = (arguments["validate"]?.flattenedString).mcpBool(default: true)
        if shouldValidate, let validationError = scriptValidationError(script) {
            return error(validationError)
        }

        let type = arguments["object_type"]?.flattenedString
            ?? arguments["objectType"]?.flattenedString
            ?? "part"
        let identifier = arguments["id_or_name"]?.flattenedString
            ?? arguments["idOrName"]?.flattenedString
            ?? arguments["id"]?.flattenedString
            ?? arguments["name"]?.flattenedString
            ?? ""

        switch type.normalizedObjectType {
        case "stack":
            document.stack.script = script
            return .object(["result": .string("Updated stack script."), "object": codableJSONValue(document.stack)])
        case "card":
            guard let index = resolveCardIndex(identifier) else { return error("No card matched '\(identifier)'.") }
            document.cards[index].script = script
            return .object(["result": .string("Updated card script."), "object": codableJSONValue(document.cards[index])])
        case "background":
            guard let index = resolveBackgroundIndex(identifier) else { return error("No background matched '\(identifier)'.") }
            document.backgrounds[index].script = script
            return .object(["result": .string("Updated background script."), "object": codableJSONValue(document.backgrounds[index])])
        case "part", "button", "field", "object":
            guard let index = resolvePartIndex(identifier) else { return error("No part matched '\(identifier)'.") }
            document.parts[index].script = script
            return .object(["result": .string("Updated part script."), "object": codableJSONValue(maskedForTransport(document.parts[index]))])
        default:
            return error("Unsupported object_type '\(type)'. Use stack, card, background, or part.")
        }
    }

    private func replacePart(arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        let rawPart = arguments["part_json"] ?? arguments["partJson"] ?? arguments["part"]
        guard let rawPart,
              let replacement = decodePart(from: rawPart) else {
            return error("hype_replace_part requires part_json containing a full Part JSON object.")
        }
        guard let index = document.partIndex(byId: replacement.id) else {
            return error("No existing part has id \(replacement.id.uuidString).")
        }
        guard replacement.cardId.map({ cardId in document.cards.contains(where: { $0.id == cardId }) }) ?? true else {
            return error("Replacement part references a missing cardId.")
        }
        guard replacement.backgroundId.map({ backgroundId in document.backgrounds.contains(where: { $0.id == backgroundId }) }) ?? true else {
            return error("Replacement part references a missing backgroundId.")
        }
        let shouldValidate = (arguments["validate_script"]?.flattenedString
            ?? arguments["validateScript"]?.flattenedString).mcpBool(default: true)
        if shouldValidate, let validationError = scriptValidationError(replacement.script) {
            return error(validationError)
        }

        let existing = document.parts[index]
        var stored = replacement
        var preservedSecureText = false
        // Round-trip guard (design.md Decision 2): preserve ONLY when the
        // replacement KEEPS the part a field. If the same replace converts
        // the part away from `.field` (e.g. to a button) while a sentinel is
        // present, the sentinel writes through as the literal "(masked)" —
        // fail-closed. The real secret is never restored onto a non-field
        // part, because restoring it there would render it on screen and
        // leak it on every future read (maskedForTransport's `.field &&
        // .secure` predicate would no longer match). The three sentinel
        // checks are independent: a client may edit any subset of the
        // masked field-body properties in one replace, and each is
        // preserved on its own sentinel, never coupled to the others.
        if existing.partType == .field, existing.fieldStyle == .secure, replacement.partType == .field {
            if replacement.textContent == Self.secureFieldMask {
                stored.textContent = existing.textContent
                preservedSecureText = true
            }
            if replacement.htmlContent == Self.secureFieldMask {
                stored.htmlContent = existing.htmlContent
                preservedSecureText = true
            }
            if replacement.searchText == Self.secureFieldMask {
                stored.searchText = existing.searchText
                preservedSecureText = true
            }
        }
        document.parts[index] = stored

        var resultText = "Replaced part \(stored.name.isEmpty ? stored.id.uuidString : stored.name)."
        if preservedSecureText {
            resultText += " Preserved stored secure-field text (\"(masked)\" sentinel detected)."
        }
        var response: [String: HypeMCPJSONValue] = [
            "result": .string(resultText),
            "object": codableJSONValue(maskedForTransport(stored)),
            "state": appState()
        ]
        if preservedSecureText {
            response["preservedSecureText"] = .bool(true)
        }
        return .object(response)
    }

    private func scriptValidationError(_ script: String) -> String? {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let result = executor.checkScriptResponse(script)
        guard result.hasPrefix("OK:") else {
            return "Script validation failed: \(result)"
        }
        return nil
    }

    private func decodePart(from value: HypeMCPJSONValue) -> Part? {
        let data: Data?
        if case .string(let text) = value {
            data = text.data(using: .utf8)
        } else {
            data = try? JSONEncoder().encode(value)
        }
        guard let data else { return nil }
        return try? JSONDecoder().decode(Part.self, from: data)
    }

    private func resolvePart(_ identifier: String) -> Part? {
        guard !identifier.isEmpty else { return nil }
        if let id = UUID(uuidString: identifier) {
            return document.parts.first { $0.id == id }
        }
        return document.parts.first { $0.name.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    private func resolvePartIndex(_ identifier: String) -> Int? {
        guard !identifier.isEmpty else { return nil }
        if let id = UUID(uuidString: identifier) {
            return document.partIndex(byId: id)
        }
        return document.parts.firstIndex { $0.name.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    private func resolveCard(_ identifier: String) -> Card? {
        guard !identifier.isEmpty else { return document.cards.first { $0.id == currentCardId } }
        if let id = UUID(uuidString: identifier) {
            return document.cards.first { $0.id == id }
        }
        return document.cards.first { $0.name.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    private func resolveCardIndex(_ identifier: String) -> Int? {
        guard !identifier.isEmpty else { return document.cards.firstIndex { $0.id == currentCardId } }
        if let id = UUID(uuidString: identifier) {
            return document.cards.firstIndex { $0.id == id }
        }
        return document.cards.firstIndex { $0.name.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    private func resolveBackground(_ identifier: String) -> Background? {
        if !identifier.isEmpty, let id = UUID(uuidString: identifier) {
            return document.backgrounds.first { $0.id == id }
        }
        if !identifier.isEmpty {
            return document.backgrounds.first { $0.name.caseInsensitiveCompare(identifier) == .orderedSame }
        }
        return document.cards.first { $0.id == currentCardId }
            .flatMap { card in document.backgrounds.first { $0.id == card.backgroundId } }
    }

    private func resolveBackgroundIndex(_ identifier: String) -> Int? {
        if !identifier.isEmpty, let id = UUID(uuidString: identifier) {
            return document.backgrounds.firstIndex { $0.id == id }
        }
        if !identifier.isEmpty {
            return document.backgrounds.firstIndex { $0.name.caseInsensitiveCompare(identifier) == .orderedSame }
        }
        guard let card = document.cards.first(where: { $0.id == currentCardId }) else { return nil }
        return document.backgrounds.firstIndex { $0.id == card.backgroundId }
    }

    private func codableJSONValue<T: Encodable>(_ value: T) -> HypeMCPJSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let any = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return HypeMCPJSONValue(any: any)
    }

    /// Copy of `part` safe for MCP transport: every field-body text
    /// property replaced by the sentinel when the part is a secure field.
    /// Predicate mirrors `HypeToolExecutor.swift` `get_part_property`
    /// text/textcontent exactly (`part.partType == .field && part.fieldStyle
    /// == .secure`).
    ///
    /// Masked set (design.md Decision 1, the field-body-text rule):
    /// `textContent`, `htmlContent`, and `searchText` — every `Part` String
    /// property that is settable with no `fieldStyle` guard and can plausibly
    /// hold the field's bound value. Masking is unconditional, including when
    /// a masked property is already empty, matching the curated one-liners.
    /// No other `Part` property is altered.
    private func maskedForTransport(_ part: Part) -> Part {
        guard part.partType == .field, part.fieldStyle == .secure else { return part }
        var masked = part
        masked.textContent = Self.secureFieldMask
        masked.htmlContent = Self.secureFieldMask
        masked.searchText = Self.secureFieldMask
        return masked
    }

    /// Copy of `document` with every part masked for transport via
    /// `maskedForTransport(_:Part)`. Never mutates `self.document`.
    private func maskedForTransport(_ document: HypeDocument) -> HypeDocument {
        var masked = document
        masked.parts = document.parts.map(maskedForTransport)
        return masked
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

    var normalizedObjectType: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }
}

private extension Optional where Wrapped == String {
    func mcpBool(default defaultValue: Bool) -> Bool {
        guard let text = self?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !text.isEmpty else {
            return defaultValue
        }
        switch text {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return defaultValue
        }
    }
}

private extension HypeMCPJSONValue {
    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let text):
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}
