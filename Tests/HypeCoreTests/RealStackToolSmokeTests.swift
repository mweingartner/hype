import Testing
import Foundation
@testable import HypeCore

@Suite(
    "Real stack AI tool smoke",
    .disabled(if: ProcessInfo.processInfo.environment["HYPE_REAL_STACK_SMOKE_PATH"] == nil)
)
struct RealStackToolSmokeTests {
    @Test("property/script/introspection tools mutate a real stack copy in memory")
    func realStackToolSmoke() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["HYPE_REAL_STACK_SMOKE_PATH"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var doc = try JSONDecoder().decode(HypeDocument.self, from: data)
        let cardId = try #require(
            doc.sortedCards.first(where: { card in
                doc.effectivePartsForCard(card.id).contains(where: { $0.partType == .spriteArea })
            })?.id ?? doc.sortedCards.first?.id
        )
        let executor = HypeToolExecutor()

        func run(_ tool: String, _ args: [String: String] = [:]) async -> String {
            await executor.execute(
                toolName: tool,
                arguments: args,
                document: &doc,
                currentCardId: cardId
            )
        }

        let originalWidth = await run("get_stack_property", ["property": "width"])
        #expect(Int(originalWidth) != nil)
        _ = await run("set_stack_property", ["property": "width", "value": "801"])
        #expect(await run("get_stack_property", ["property": "width"]) == "801")

        _ = await run("set_card_property", ["property": "marked", "value": "true"])
        #expect(await run("get_card_property", ["property": "marked"]) == "true")
        let backgroundName = await run("get_card_property", ["property": "backgroundName"])
        #expect(!backgroundName.isEmpty)

        _ = await run("set_background_property", ["property": "sortKey", "value": "smoke-sort"])
        #expect(await run("get_background_property", ["property": "sortKey"]) == "smoke-sort")
        #expect(Int(await run("get_background_property", ["property": "cardCount"])) != nil)

        let cardParts = await run("get_card_parts")
        #expect(cardParts.contains("Parts on current card:"))
        #expect(!cardParts.contains("No parts"))
        let backgrounds = await run("list_backgrounds")
        #expect(backgrounds.contains(backgroundName))

        let button = try #require(doc.effectivePartsForCard(cardId).first(where: { $0.partType == .button }))
        _ = await run("set_part_property", [
            "part_name": button.name,
            "property": "script",
            "value": "go next"
        ])
        let buttonScript = await run("get_part_property", ["part_name": button.name, "property": "script"])
        #expect(buttonScript.contains("on mouseUp"))
        #expect(buttonScript.contains("go next"))

        let cardScript = "on openCard\n  put \"opened\" into smokeCardState\nend openCard"
        _ = await run("set_card_script", ["script": cardScript])
        #expect(await run("get_card_script") == cardScript)

        let backgroundScript = "on openBackground\n  put \"opened\" into smokeBackgroundState\nend openBackground"
        _ = await run("set_background_script", ["script": backgroundScript])
        #expect(await run("get_background_script") == backgroundScript)

        let area = try #require(doc.effectivePartsForCard(cardId).first(where: {
            $0.partType == .spriteArea && $0.activeSceneSpec != nil
        }))
        let scene = try #require(area.activeSceneSpec)
        let node = try #require(scene.allNodes.first(where: { !$0.name.isEmpty }))

        let sceneScript = "on frameUpdate\n  if the hoveredSprite is \"\(node.name)\" then\n    set the alpha of sprite \"\(node.name)\" to 0.9\n  end if\nend frameUpdate"
        _ = await run("set_scene_script", [
            "sprite_area_name": area.name,
            "script": sceneScript
        ])
        #expect(await run("get_scene_script", ["sprite_area_name": area.name]) == sceneScript)
        #expect(await run("get_part_property", ["part_name": area.name, "property": "script"]) == sceneScript)

        let nodeScript = "on mouseDown\n  set the alpha of me to 0.75\nend mouseDown"
        _ = await run("set_node_script", [
            "sprite_area_name": area.name,
            "node_name": node.name,
            "script": nodeScript
        ])
        #expect(await run("get_node_script", [
            "sprite_area_name": area.name,
            "node_name": node.name
        ]) == nodeScript)

        _ = await run("set_scene_property", [
            "sprite_area_name": area.name,
            "property": "backgroundColor",
            "value": "#112233"
        ])
        #expect(await run("get_scene_spec", ["sprite_area_name": area.name]).contains("#112233"))

        _ = await run("set_node_property", [
            "sprite_area_name": area.name,
            "node_name": node.name,
            "property": "alpha",
            "value": "0.5"
        ])
        #expect(await run("get_node_property", [
            "sprite_area_name": area.name,
            "node_name": node.name,
            "property": "alpha"
        ]) == "0.5")
    }
}
