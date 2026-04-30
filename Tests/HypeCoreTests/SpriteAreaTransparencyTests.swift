import Testing
import Foundation
@testable import HypeCore

#if canImport(AppKit)
import AppKit
#endif

/// Coverage for the sprite-area transparent-background flag.
/// Mirrors the image-part variant — same `Part.transparentBackground`
/// boolean, same HypeTalk + AI surface, but the renderer side is
/// SKView's `allowsTransparency` plus an `SKScene.backgroundColor =
/// .clear` override (verified indirectly via the model + AI tools
/// here; full AppKit/SpriteKit compositing is exercised manually).
@Suite("Sprite area transparent background — model + HypeTalk + AI plumbing")
struct SpriteAreaTransparencyTests {

    private func docWithSpriteArea(_ name: String) -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Transparency")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: name,
                        left: 20, top: 20, width: 400, height: 300)
        area.setSpriteAreaSpec(
            SpriteAreaSpec(defaultSceneNamed: "main",
                           fallbackSize: SizeSpec(width: 400, height: 300))
        )
        doc.addPart(area)
        return (doc, cardId)
    }

    // MARK: - Model

    @Test("Sprite area part defaults transparentBackground to false")
    func defaultsFalse() {
        let (doc, _) = docWithSpriteArea("arena")
        #expect(doc.parts[0].transparentBackground == false)
    }

    @Test("Sprite area transparentBackground round-trips through Codable")
    func roundTrips() throws {
        var (doc, _) = docWithSpriteArea("arena")
        doc.parts[0].transparentBackground = true

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: data)
        let recovered = decoded.parts.first(where: { $0.name == "arena" })
        #expect(recovered?.transparentBackground == true)
    }

    // MARK: - AI tools

    @Test("AI set_part_property writes transparentBackground on a sprite area")
    func aiSetsOnSpriteArea() async {
        var (doc, cardId) = docWithSpriteArea("arena")
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "arena",
                "property": "transparentBackground",
                "value": "true",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.first(where: { $0.name == "arena" })?.transparentBackground == true)
    }

    @Test("AI synonym 'transparent' works for sprite area")
    func aiSetsTransparentSynonym() async {
        var (doc, cardId) = docWithSpriteArea("arena")
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "arena",
                "property": "transparent",
                "value": "true",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.first(where: { $0.name == "arena" })?.transparentBackground == true)
    }

    @Test("AI get_part_property reads transparentBackground on a sprite area")
    func aiReadsOnSpriteArea() async {
        var (doc, cardId) = docWithSpriteArea("arena")
        doc.parts[0].transparentBackground = true
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "arena", "property": "transparentBackground"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.lowercased().contains("true"),
                "expected true in result, got \(result)")
    }

    @Test("AI set_part_property toggle off resets the flag")
    func aiTogglesOff() async {
        var (doc, cardId) = docWithSpriteArea("arena")
        doc.parts[0].transparentBackground = true
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "arena",
                "property": "transparentBackground",
                "value": "false",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.first(where: { $0.name == "arena" })?.transparentBackground == false)
    }
}
