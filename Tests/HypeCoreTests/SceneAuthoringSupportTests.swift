import Testing
import Foundation
@testable import HypeCore

@Suite("Scene authoring support")
struct SceneAuthoringSupportTests {

    @Test("asset usages are reported across named scenes")
    func assetUsagesAcrossNamedScenes() {
        var document = HypeDocument.newDocument(name: "Game")
        let texture = Asset(name: "hero")
        let tiles = Asset(
            name: "terrain",
            kind: .tileSet,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 4,
            tileRows: 4
        )
        document.assetRepository.assets = [texture, tiles]

        var part = Part(partType: .spriteArea, cardId: document.cards[0].id, name: "Game Area", left: 20, top: 20, width: 400, height: 300)
        var areaSpec = SpriteAreaSpec(defaultSceneNamed: "main", fallbackSize: SizeSpec(width: 400, height: 300))
        var main = areaSpec.activeScene!
        main.nodes = [
            HypeNodeSpec(
                name: "player",
                nodeType: .sprite,
                position: PointSpec(x: 100, y: 100),
                assetRef: document.assetRepository.assetRef(for: texture)
            )
        ]
        areaSpec.setActiveScene(main)
        var bonus = SceneSpec(name: "bonus", size: SizeSpec(width: 400, height: 300))
        var tileMap = HypeNodeSpec(name: "world", nodeType: .tileMap, position: PointSpec(x: 200, y: 150))
        tileMap.tileMapSpec = TileMapSpec(
            columns: 10,
            rows: 8,
            tileWidth: 32,
            tileHeight: 32,
            tileSetAssetRef: document.assetRepository.assetRef(for: tiles),
            tileSetColumns: 4
        )
        bonus.nodes = [tileMap]
        let bonusEntry = SpriteAreaScene(scene: bonus)
        areaSpec.scenes.append(bonusEntry)
        part.setSpriteAreaSpec(areaSpec)
        document.parts = [part]

        let textureUsages = document.assetUsages(for: texture.id)
        #expect(textureUsages.count == 1)
        #expect(textureUsages[0].sceneName == "main")
        #expect(textureUsages[0].role == .nodeTexture)

        let tileUsages = document.assetUsages(for: tiles.id)
        #expect(tileUsages.count == 1)
        #expect(tileUsages[0].sceneName == "bonus")
        #expect(tileUsages[0].role == .tileSet)
    }

    @Test("authoring checklist flags missing setup areas")
    func checklistFlagsMissingAreas() {
        let scene = SceneSpec(
            name: "",
            size: SizeSpec(width: 0, height: 0),
            nodes: []
        )

        let checklist = scene.authoringChecklist(using: AssetRepository())
        let basics = checklist.first(where: { $0.key == "basics" })
        let world = checklist.first(where: { $0.key == "world" })
        let scripts = checklist.first(where: { $0.key == "scripts" })

        #expect(basics?.status == .missing)
        #expect(world?.status == .missing)
        #expect(scripts?.status == .recommended)
    }

    @Test("diagnostics report missing assets and duplicate node names")
    func diagnosticsReportProblems() {
        let missingID = UUID()
        let scene = SceneSpec(
            name: "battle",
            size: SizeSpec(width: 640, height: 480),
            nodes: [
                HypeNodeSpec(
                    name: "enemy",
                    nodeType: .sprite,
                    position: PointSpec(x: 100, y: 100),
                    assetRef: AssetRef(id: missingID, name: "missing", mimeType: "image/png")
                ),
                HypeNodeSpec(
                    name: "enemy",
                    nodeType: .shape,
                    position: PointSpec(x: 200, y: 100),
                    shapeSpec: ShapeNodeSpec(shapeType: .rect)
                )
            ]
        )

        let report = scene.diagnostics(using: AssetRepository())
        #expect(report.nodeCount == 2)
        #expect(report.missingAssetCount == 1)
        #expect(report.missingAssetIDs == [missingID])
        #expect(report.issues.contains(where: { $0.message.contains("missing asset") }))
        #expect(report.issues.contains(where: { $0.message.contains("Duplicate node name") }))
    }
}
