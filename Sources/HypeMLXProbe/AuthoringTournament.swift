import Foundation
import HypeCore

/// The 127-prompt authoring tournament, run in-process: the real engine, the
/// real chat template and tool-call parser, and — unlike the Python harness in
/// `scripts/ai-training`, which answers every tool call with a canned string —
/// the real `HypeToolExecutor` working on a real stack.
///
/// That difference matters for models that look before they write: a canned
/// `"OK"` for `get_part_property` teaches them nothing, so they keep asking
/// until the turn cap. Here a read returns what is actually on the card.
///
/// Prompts and grading are the harness's own (`eval/comprehensive_prompts.jsonl`,
/// case-insensitive substring checks over everything the model said and called),
/// so scores are comparable in kind — not in absolute value — with the Python runs.
struct TournamentPrompt: Decodable {
    let id: String
    let category: String
    let prompt: String
    let mustContain: [String]
    let mustNotContain: [String]

    enum CodingKeys: String, CodingKey {
        case id, category, prompt
        case mustContain = "must_contain"
        case mustNotContain = "must_not_contain"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "uncategorized"
        prompt = try container.decode(String.self, forKey: .prompt)
        mustContain = try container.decodeIfPresent([String].self, forKey: .mustContain) ?? []
        mustNotContain = try container.decodeIfPresent([String].self, forKey: .mustNotContain) ?? []
    }

    static func load(from path: String) throws -> [TournamentPrompt] {
        let text = try String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return try decoder.decode(TournamentPrompt.self, from: Data(trimmed.utf8))
        }
    }
}

struct TournamentOutcome: Encodable {
    let id: String
    let category: String
    let passed: Bool
    let missingRequired: [String]
    let presentForbidden: [String]
    let rounds: Int
    /// `answered` (the model stopped calling tools), `round_cap`, or `error`.
    let terminatedBy: String
    let seconds: Double
    let generatedTokens: Int
    let output: String
}

/// The stack every tournament prompt talks about (the harness's synthetic
/// `CURRENT STATE`), built with the same tools the model uses.
enum TournamentStack {
    struct Seeded {
        var document: HypeDocument
        var currentCardId: UUID
        var log: [String]
    }

    /// The harness's four sprites, plus the `player` several prompts refer to.
    static let arenaSprites = ["ball", "target", "enemy", "orb", "player"]

    static func make() async -> Seeded {
        var document = HypeDocument.newDocument(name: "TestStack")
        var currentCardId = document.sortedCards[0].id
        let executor = HypeToolExecutor()
        var log: [String] = []

        func run(_ tool: String, _ arguments: [String: String]) async {
            let result = await executor.execute(
                toolName: tool, arguments: arguments, document: &document, currentCardId: currentCardId)
            if result.hasPrefix("CREATED_CARD:"), let id = UUID(uuidString: String(result.dropFirst(13))) {
                currentCardId = id
            } else if result.hasPrefix("NAVIGATE:") {
                let name = String(result.dropFirst(9)).lowercased()
                if let card = document.cards.first(where: { $0.name.lowercased() == name }) {
                    currentCardId = card.id
                }
            }
            log.append("\(tool)(\(arguments.keys.sorted().map { "\($0)=\(arguments[$0] ?? "")" }.joined(separator: ", "))) -> \(result.prefix(120))")
        }

        let firstCard = document.sortedCards[0]
        let firstBackground = document.backgrounds.first { $0.id == firstCard.backgroundId }
        await run("set_card_name", ["card_name": firstCard.name, "new_name": "intro"])
        await run("set_background_name", ["background_name": firstBackground?.name ?? "", "new_name": "title_bg"])
        await run("create_field", [
            "name": "title", "left": "0", "top": "0", "width": "600", "height": "40", "on_background": "true",
        ])
        await run("create_card", ["name": "first", "background_name": "title_bg"])
        await run("create_button", ["name": "play", "left": "100", "top": "100", "width": "100", "height": "40"])
        await run("create_image", ["name": "logo", "left": "220", "top": "100", "width": "80", "height": "80"])
        await run("create_field", ["name": "score", "left": "100", "top": "160", "width": "200", "height": "30"])
        await run("create_field", ["name": "shared_status", "left": "100", "top": "200", "width": "200", "height": "30"])
        await run("create_sprite_area", [
            "name": "arena", "scene_name": "main", "left": "100", "top": "260", "width": "400", "height": "300",
        ])
        for (index, sprite) in arenaSprites.enumerated() {
            await run("add_sprite_to_scene", [
                "sprite_area_name": "arena", "sprite_name": sprite,
                "x": String(40 + index * 75), "y": "150", "width": "32", "height": "32",
            ])
        }
        // A few prompts talk about a second sprite area; with real tools it has to exist.
        await run("create_sprite_area", [
            "name": "playfield", "scene_name": "level", "left": "520", "top": "260", "width": "300", "height": "200",
        ])
        let first = currentCardId
        await run("create_card", ["name": "second", "background_name": "title_bg"])
        currentCardId = first
        return Seeded(document: document, currentCardId: currentCardId, log: log)
    }

    /// The untuned authoring prompt `AIChatPanel` sends: rules, the full HypeTalk
    /// guide, then the per-turn `CURRENT STATE:` block.
    static func systemPrompt(for document: HypeDocument, cardId: UUID) -> String {
        let card = document.cards.first { $0.id == cardId }
        let background = document.backgrounds.first { $0.id == card?.backgroundId }
        func describe(_ parts: [Part]) -> String {
            parts.map { "\($0.partType.rawValue) \"\($0.name)\" at \(Int($0.left)),\(Int($0.top)) \(Int($0.width))x\(Int($0.height))" }
                .joined(separator: "; ")
        }
        let cardParts = describe(document.parts.filter { $0.cardId == cardId })
        let backgroundParts = describe(document.parts.filter { $0.backgroundId != nil && $0.backgroundId == background?.id })
        let otherCards = document.sortedCards.filter { $0.id != cardId }.map { "\"\($0.name)\"" }.joined(separator: ", ")
        return """
        You are an AI assistant for Hype, a HyperCard-inspired app. The canvas is \(document.stack.width)x\(document.stack.height) points.

        RULES:
        - Call the needed tools to fulfill the user's request, then STOP and respond with a brief summary.
        - Do NOT repeat tool calls you have already made.
        - Do NOT call additional introspection tools after the first one that answers the user's question. (e.g. if the user asks "list scenes", call `list_scenes` and STOP — don't follow up with `add_scene`, `get_scene_nodes`, etc.)
        - When CURRENT STATE shows a part / card / background already exists with the requested name, MODIFY it with `set_part_property` (script attaches via `property="script"`), `set_card_script`, `set_background_script`, etc. Use `create_*` tools ONLY for parts that do NOT yet appear in CURRENT STATE.
        - If the user says to create something on the current card, do NOT call create_card first. Build on the current card unless the user explicitly asks for a new card.
        - Do NOT delete parts unless the user specifically asks you to.
        - Stay inside Hype stack-authoring tools. Do not assume filesystem or arbitrary web access is available.
        - Use descriptive names for all parts.
        - When the user says "background", set on_background to "true" in create tools. Background parts are shared across ALL cards that use that background.
        - To READ one property on the stack, card, or background, prefer get_stack_property / get_card_property / get_background_property over broad summaries.
        - To MODIFY one property on the stack, card, or background, prefer set_stack_property / set_card_property / set_background_property over unrelated part tools.
        - If the user asks to create, set, attach, install, replace, or update a script on the stack, card, background, button, field, sprite area, scene, or node, use the appropriate setter tool. Do not answer with bare HypeTalk unless the user explicitly asks only to write or explain code.
        - Before storing any HypeTalk script with create_button, create_field, set_part_property(property=script), set_node_script, set_scene_script, set_card_script, set_background_script, or set_stack_script, call check_script first and only store the script after it returns OK. If a storage tool returns a result starting with `__HYPE_INTERNAL_DRAFT_REFUSED_v1:`, the host has rejected your script. Read the failure list, fix the script, and call the SAME storage tool again with the corrected script.
        - For button scripts, just provide the HypeTalk command (e.g. "go next"). It will be auto-wrapped in on mouseUp/end mouseUp.
        - When writing HypeTalk scripts, use ONLY valid HypeTalk syntax as described in the guide below.
        - When creating a card, ALWAYS pass `name=` with the user's chosen card name. Without it, the new card gets an autogenerated name like "Card 4".
        - Lifecycle handlers REQUIRE the `on <event> ... end <event>` wrapper. `on openStack ... end openStack`, `on openCard ... end openCard`, `on beginContact otherName ... end beginContact`. Top-level statements without a handler are dead code.
        - Sprite position is `the loc of sprite "X"` (a `"x,y"` string). There is NO `the y of sprite "X"` or `the x of sprite "X"` — use `item 1 of` / `item 2 of` on `the loc` to read components.

        \(HypeTalkGuide.llmContext)

        CURRENT STATE:
        Stack: "\(document.stack.name)" (\(document.cards.count) cards)
        Current card: "\(card?.name ?? "")" | Background: "\(background?.name ?? "")"
        Card parts: \(cardParts.isEmpty ? "none" : cardParts)
        Background parts: \(backgroundParts.isEmpty ? "none" : backgroundParts)
        Sprites: scene "main" inside spriteArea "arena" (sprites: \(arenaSprites.joined(separator: ", "))); scene "level" inside spriteArea "playfield" (no sprites)
        Other cards: \(otherCards.isEmpty ? "none" : otherCards)
        """
    }
}

enum TournamentGrader {
    /// The harness's `normalize_chat_output`, minus its JSON echo of each call:
    /// the visible text, then one `name(key=value, …)` line per tool call.
    static func transcriptLine(text: String, toolCalls: [BuiltInToolCall]) -> String {
        var lines: [String] = []
        if !text.isEmpty { lines.append(text) }
        for call in toolCalls {
            let arguments = call.arguments.keys.sorted().map { "\($0)=\(call.arguments[$0] ?? "")" }
            lines.append("\(call.name)(\(arguments.joined(separator: ", ")))")
        }
        return lines.joined(separator: "\n")
    }

    /// The harness's `score_prompt`: case-insensitive substring checks.
    static func grade(_ prompt: TournamentPrompt, output: String) -> (missing: [String], forbidden: [String]) {
        let haystack = output.lowercased()
        return (
            prompt.mustContain.filter { !haystack.contains($0.lowercased()) },
            prompt.mustNotContain.filter { haystack.contains($0.lowercased()) }
        )
    }

    static func report(_ outcomes: [TournamentOutcome], label: String) -> String {
        let passed = outcomes.filter(\.passed).count
        var lines = [
            String(format: "%@: %.1f%% (%d/%d)", label, percent(passed, outcomes.count), passed, outcomes.count),
        ]
        let categories = Dictionary(grouping: outcomes, by: \.category)
        for category in categories.keys.sorted() {
            let rows = categories[category] ?? []
            let ok = rows.filter(\.passed).count
            lines.append(String(format: "  %-22@ %3.0f%% (%d/%d)", category as NSString, percent(ok, rows.count), ok, rows.count))
        }
        let endings = Dictionary(grouping: outcomes.filter { !$0.passed }, by: \.terminatedBy).mapValues(\.count)
        lines.append("  failures by ending: \(endings.keys.sorted().map { "\($0)=\(endings[$0] ?? 0)" }.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    private static func percent(_ part: Int, _ whole: Int) -> Double {
        whole == 0 ? 0 : Double(part) / Double(whole) * 100
    }
}
