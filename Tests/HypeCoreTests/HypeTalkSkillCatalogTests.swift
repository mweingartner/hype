import Foundation
import Testing
@testable import HypeCore

@Suite("HypeTalk skill tools")
struct HypeTalkSkillCatalogTests {
    @Test("skill catalog is compact, source-attributed, and discoverable")
    func skillCatalogIsCompactAndDiscoverable() {
        let list = HypeTalkSkillCatalog.compactSkillList()

        #expect(HypeTalkSkillCatalog.descriptors.count >= 8)
        #expect(list.contains("message_hierarchy"))
        #expect(list.contains("custom_handlers"))
        #expect(!list.contains("Techniques for Stack Development"))
        #expect(list.count < 4_000)
        #expect(HypeTalkSkillCatalog.descriptors.allSatisfy {
            $0.sourceURL == HypeTalkSkillCatalog.jaedworksScriptingURL
        })
    }

    @Test("focused guide stays bounded and uses Hype compatibility language")
    func focusedGuideIsBounded() {
        let guide = HypeTalkSkillCatalog.guide(
            for: "custom_handlers",
            detailLevel: "full",
            intent: "many buttons should run the same action"
        )

        #expect(guide.contains("Custom Handlers"))
        #expect(guide.contains(HypeTalkSkillCatalog.jaedworksScriptingURL))
        #expect(guide.contains("Hype compatibility"))
        #expect(guide.contains("button_delegates_to_stack"))
        #expect(guide.count < 3_000)
    }

    @Test("all shipped HypeTalk patterns parse")
    func patternsParse() throws {
        for pattern in HypeTalkSkillCatalog.patterns {
            var lexer = Lexer(source: pattern.script)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            let script = try parser.parse()
            #expect(!script.handlers.isEmpty, "\(pattern.id) must include at least one handler")
        }
    }

    @Test("skill tools are exposed to card and scene authoring surfaces")
    func skillToolsAreVisible() {
        let cardTools = Set(HypeToolDefinitions.cardControlAuthoringTools.map(\.function.name))
        let sceneTools = Set(HypeToolDefinitions.spriteSceneAuthoringTools.map(\.function.name))
        let expected: Set<String> = [
            "list_hypetalk_skills",
            "get_hypetalk_skill_guide",
            "plan_hypetalk_script",
            "inspect_message_path",
            "suggest_handler_location",
            "get_hypetalk_pattern",
            "review_hypetalk_script",
        ]

        #expect(expected.isSubset(of: cardTools))
        #expect(expected.isSubset(of: sceneTools))
    }

    @Test("executor plans, inspects, and reviews scripts")
    func executorPlansInspectsAndReviews() async {
        var document = HypeDocument.newDocument(name: "Skill Stack")
        let cardId = document.cards[0].id
        document.cards[0].name = "Home"
        let button = Part(partType: .button, cardId: cardId, name: "Run")
        document.addPart(button)
        let executor = HypeToolExecutor()

        let skills = await executor.execute(
            toolName: "list_hypetalk_skills",
            arguments: ["query": "shared buttons"],
            document: &document,
            currentCardId: cardId
        )
        #expect(skills.contains("custom_handlers"))

        let plan = await executor.execute(
            toolName: "plan_hypetalk_script",
            arguments: [
                "intent": "many buttons should run the same shared action",
                "target_scope": "part",
                "target_name": "Run",
            ],
            document: &document,
            currentCardId: cardId
        )
        #expect(plan.contains("custom_handlers"))
        #expect(plan.contains("check_script"))
        #expect(plan.contains("review_hypetalk_script"))

        let path = await executor.execute(
            toolName: "inspect_message_path",
            arguments: ["target_name": "Run"],
            document: &document,
            currentCardId: cardId
        )
        #expect(path.contains("part \"Run\" -> card \"Home\""))
        #expect(path.contains("pass <message>"))

        let review = await executor.execute(
            toolName: "review_hypetalk_script",
            arguments: [
                "script": """
                on mouseUp
                  send "doPrimaryAction" to this stack
                end mouseUp
                """,
                "intent": "reuse this behavior for many buttons",
                "target_scope": "part",
                "event_name": "mouseUp",
            ],
            document: &document,
            currentCardId: cardId
        )
        #expect(review.contains("OK:") || review.contains("WARN:"))
        #expect(review.contains("check_script"))
    }

    @Test("review tool blocks invalid scripts")
    func reviewToolBlocksInvalidScripts() async {
        var document = HypeDocument.newDocument(name: "Skill Stack")
        let cardId = document.cards[0].id
        let executor = HypeToolExecutor()

        let review = await executor.execute(
            toolName: "review_hypetalk_script",
            arguments: [
                "script": "hype.showNextCard();",
                "intent": "show a dialog",
                "target_scope": "part",
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(review.hasPrefix("FAIL:"))
    }
}
