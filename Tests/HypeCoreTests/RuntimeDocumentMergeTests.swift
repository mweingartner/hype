import Foundation
import Testing
@testable import HypeCore

@Suite("Runtime document merge")
struct RuntimeDocumentMergeTests {
    @Test("stale runtime snapshot preserves AI-created sprite area and assets")
    func staleRuntimeSnapshotPreservesCurrentOnlyAuthoringEntities() throws {
        var base = HypeDocument.newDocument()
        let cardId = try #require(base.sortedCards.first?.id)
        var score = Part(partType: .field, cardId: cardId, name: "score", left: 10, top: 10, width: 120, height: 28)
        score.textContent = "Score: 0"
        base.addPart(score)

        var runtime = base
        runtime.updatePart(id: score.id) { part in
            part.textContent = "Score: 10"
        }

        var current = base
        var area = Part(partType: .spriteArea, cardId: cardId, name: "missileCommandArea", left: 20, top: 40, width: 760, height: 520)
        area.setSpriteAreaSpec(SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 760, height: 520)))
        current.addPart(area)
        current.spriteRepository.addAsset(SpriteAsset(name: "mc_turret", data: Data([1, 2, 3]), width: 64, height: 64))

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current
        )

        #expect(result.preservedCurrentOnlyEntities)
        #expect(result.document.parts.first(where: { $0.id == score.id })?.textContent == "Score: 10")
        #expect(result.document.parts.contains(where: { $0.id == area.id && $0.name == "missileCommandArea" }))
        #expect(result.document.spriteRepository.asset(byName: "mc_turret") != nil)
    }

    @Test("runtime-only entities are kept while current-only entities are preserved")
    func runtimeOnlyEntitiesAreKept() throws {
        var base = HypeDocument.newDocument()
        let cardId = try #require(base.sortedCards.first?.id)
        let currentOnly = Part(partType: .button, cardId: cardId, name: "New Game", left: 12, top: 12, width: 112, height: 38)
        let runtimeOnly = Part(partType: .field, cardId: cardId, name: "runtimeStatus", left: 12, top: 56, width: 160, height: 28)

        var current = base
        current.addPart(currentOnly)

        var runtime = base
        runtime.addPart(runtimeOnly)

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current
        )

        #expect(result.document.parts.contains(where: { $0.id == currentOnly.id }))
        #expect(result.document.parts.contains(where: { $0.id == runtimeOnly.id }))
    }
}
