import Foundation
import Testing
@testable import HypeCore

@Suite("HypeDocument self-contained persistence")
struct HypeDocumentSelfContainedPersistenceTests {
    @Test("portable document round-trip preserves stack-authored content surfaces")
    func portableDocumentRoundTripPreservesAuthoredContent() throws {
        var document = HypeDocument.newDocument(name: "Portable Stack")
        let cardId = try #require(document.cards.first?.id)
        let backgroundId = try #require(document.backgrounds.first?.id)

        document.stack.script = "on openStack\n  put \"ready\" into status\nend openStack"
        document.stack.webAssetsAllowed = true
        document.stack.aiContextCloudSharingAllowed = true
        document.stack.meshyEnabled = true
        document.stack.runtimeModeEnabled = true
        document.backgrounds[0].script = "on openBackground\n  pass openBackground\nend openBackground"
        document.cards[0].script = "on openCard\n  pass openCard\nend openCard"
        document.aiPromptHistory = ["create a maze game", "add ghosts"]

        var button = Part(partType: .button, cardId: cardId, name: "btn_start")
        button.script = "on mouseUp\n  send \"startGame\" to this stack\nend mouseUp"
        document.parts.append(button)

        document.spriteRepository.addAsset(SpriteAsset(
            name: "hero",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0, 1, 2, 3]),
            width: 1,
            height: 1
        ))

        let context = AIContextIngestor.makeTextNote(
            title: "Design Notes",
            text: "Keep the form controls native and store all asset choices in the stack.",
            role: .projectMemory
        )
        document.aiContextLibrary.addSource(context.0, items: context.1)
        document.setPaintLayer(CardPaintLayer(
            cardId: cardId,
            width: 1,
            height: 1,
            rgbaData: Data([255, 0, 0, 255])
        ))
        _ = document.duplicateTheme(named: BuiltInThemes.fallbackName, candidateName: "Portable Theme")
        document.stack.themeName = "Portable Theme"
        document.backgrounds[0].themeName = "Portable Theme"
        document.cards[0].themeName = "Portable Theme"

        document.scriptGlobals["sessionOnly"] = "do not persist"

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: encoded)

        #expect(decoded.stack.script == document.stack.script)
        #expect(decoded.stack.webAssetsAllowed)
        #expect(decoded.stack.aiContextCloudSharingAllowed)
        #expect(decoded.stack.meshyEnabled)
        #expect(decoded.stack.runtimeModeEnabled)
        #expect(decoded.backgrounds.first { $0.id == backgroundId }?.script == document.backgrounds[0].script)
        #expect(decoded.cards.first { $0.id == cardId }?.script == document.cards[0].script)
        #expect(decoded.parts.first { $0.id == button.id }?.script == button.script)
        #expect(decoded.spriteRepository.asset(byName: "hero")?.data == Data([0, 1, 2, 3]))
        #expect(decoded.aiContextLibrary.itemCount == 1)
        #expect(decoded.aiContextLibrary.items.first?.data?.isEmpty == false)
        #expect(decoded.aiPromptHistory == document.aiPromptHistory)
        #expect(decoded.paintLayer(forCardId: cardId)?.rgbaData == Data([255, 0, 0, 255]))
        #expect(decoded.themes.contains { $0.name == "Portable Theme" })
        #expect(decoded.stack.themeName == "Portable Theme")
        #expect(decoded.backgrounds.first { $0.id == backgroundId }?.themeName == "Portable Theme")
        #expect(decoded.cards.first { $0.id == cardId }?.themeName == "Portable Theme")
        #expect(decoded.scriptGlobals.isEmpty)
    }
}
