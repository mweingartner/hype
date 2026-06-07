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
        current.assetRepository.addAsset(Asset(name: "mc_turret", data: Data([1, 2, 3]), width: 64, height: 64))

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current
        )

        #expect(result.preservedCurrentOnlyEntities)
        #expect(result.document.parts.first(where: { $0.id == score.id })?.textContent == "Score: 10")
        #expect(result.document.parts.contains(where: { $0.id == area.id && $0.name == "missileCommandArea" }))
        #expect(result.document.assetRepository.asset(byName: "mc_turret") != nil)
    }

    @Test("runtime-only entities are kept while current-only entities are preserved")
    func runtimeOnlyEntitiesAreKept() throws {
        let base = HypeDocument.newDocument()
        let cardId = try #require(base.sortedCards.first?.id)
        let currentOnly = Part(partType: .button, cardId: cardId, name: "New Game", left: 12, top: 12, width: 112, height: 38)
        let runtimeOnly = Part(partType: .field, cardId: cardId, name: "runtimeStatus", left: 12, top: 56, width: 160, height: 28)

        var current = base
        current.addPart(currentOnly)

        var runtime = base
        runtime.addPart(runtimeOnly)

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current,
            preserveCurrentRuntimeMode: true
        )

        #expect(result.document.parts.contains(where: { $0.id == currentOnly.id }))
        #expect(result.document.parts.contains(where: { $0.id == runtimeOnly.id }))
    }

    @Test("stale runtime snapshot cannot re-enter runtime mode after user switches to edit")
    func staleRuntimeSnapshotDoesNotReenableRuntimeMode() throws {
        var runtime = HypeDocument.newDocument()
        runtime.stack.runtimeModeEnabled = true

        var current = runtime
        current.stack.runtimeModeEnabled = false

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current,
            preserveCurrentRuntimeMode: true
        )

        #expect(result.preservedCurrentOnlyEntities)
        #expect(!result.document.stack.runtimeModeEnabled)
    }

    @Test("runtime can still turn runtime mode off intentionally")
    func runtimeCanDisableRuntimeMode() throws {
        var current = HypeDocument.newDocument()
        current.stack.runtimeModeEnabled = true

        var runtime = current
        runtime.stack.runtimeModeEnabled = false

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current
        )

        #expect(!result.document.stack.runtimeModeEnabled)
    }

    @Test("current-only AI context sources are preserved with their items")
    func currentOnlyAIContextSourcesArePreserved() throws {
        let runtime = HypeDocument.newDocument(name: "Runtime")
        var current = runtime
        let note = AIContextIngestor.makeTextNote(
            title: "Project Memory",
            text: "The current card uses the customer entry naming convention.",
            role: .projectMemory
        )
        current.aiContextLibrary.addSource(note.0, items: note.1)

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current
        )

        let source = try #require(result.document.aiContextLibrary.sources.first)
        let item = try #require(result.document.aiContextLibrary.items.first)
        #expect(result.preservedCurrentOnlyEntities)
        #expect(source.id == note.0.id)
        #expect(source.itemIds == [item.id])
        #expect(item.sourceId == source.id)
    }

    @Test("stale runtime result preserves newer current slider value when script changed another part")
    func staleRuntimeResultPreservesNewerCurrentSliderValue() throws {
        var base = HypeDocument.newDocument()
        let cardId = try #require(base.sortedCards.first?.id)
        var slider = Part(partType: .slider, cardId: cardId, name: "zoom", left: 10, top: 10, width: 32, height: 232)
        slider.controlMin = 0
        slider.controlMax = 100
        slider.controlValue = 10
        var map = Part(partType: .map, cardId: cardId, name: "mapper", left: 60, top: 10, width: 300, height: 220)
        map.mapSpan = 10
        base.addPart(slider)
        base.addPart(map)

        var runtime = base
        runtime.updatePart(id: map.id) { $0.mapSpan = 50 }

        var current = base
        current.updatePart(id: slider.id) { $0.controlValue = 80 }

        let result = RuntimeDocumentMerge.applyingRuntimeChanges(
            runtimeDocument: runtime,
            baseDocument: base,
            currentDocument: current
        )

        #expect(result.preservedCurrentOnlyEntities)
        #expect(result.document.parts.first(where: { $0.id == slider.id })?.controlValue == 80)
        #expect(result.document.parts.first(where: { $0.id == map.id })?.mapSpan == 50)
    }

    @Test("runtime notification merge preserves current editor mode")
    func runtimeNotificationMergePreservesCurrentEditorMode() throws {
        var current = HypeDocument.newDocument()
        let cardId = try #require(current.sortedCards.first?.id)
        var score = Part(partType: .field, cardId: cardId, name: "score", left: 10, top: 10, width: 120, height: 28)
        score.textContent = "Score: 0"
        current.addPart(score)
        current.stack.runtimeModeEnabled = false

        var runtime = current
        runtime.stack.runtimeModeEnabled = true
        runtime.updatePart(id: score.id) { part in
            part.textContent = "Score: 10"
        }

        let result = RuntimeDocumentMerge.preservingCurrentOnlyEntities(
            runtimeDocument: runtime,
            currentDocument: current,
            preserveCurrentRuntimeMode: true
        )

        #expect(result.preservedCurrentOnlyEntities)
        #expect(result.document.stack.runtimeModeEnabled == false)
        #expect(result.document.parts.first(where: { $0.id == score.id })?.textContent == "Score: 10")
    }
}
