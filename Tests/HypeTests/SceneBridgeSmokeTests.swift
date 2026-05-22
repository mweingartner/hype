import Testing
import AppKit
import SpriteKit
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("SceneBridge smoke tests")
struct SceneBridgeSmokeTests {

    @Test("preloadTextures warms the cache for referenced scene assets")
    func preloadTexturesWarmsCache() {
        let textureAsset = SpriteAsset(
            name: "hero",
            kind: .imageTexture,
            mimeType: "image/png",
            data: pngData(color: .systemBlue),
            width: 16,
            height: 16
        )
        let tilesetAsset = SpriteAsset(
            name: "terrain",
            kind: .tileSet,
            mimeType: "image/png",
            data: pngData(color: .systemGreen),
            width: 64,
            height: 64,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 2,
            tileRows: 2
        )
        let repository = SpriteRepository(assets: [textureAsset, tilesetAsset])

        var sprite = HypeNodeSpec(
            name: "player",
            nodeType: .sprite,
            position: PointSpec(x: 100, y: 100)
        )
        sprite.assetRef = repository.assetRef(for: textureAsset)

        var tileMap = HypeNodeSpec(
            name: "world",
            nodeType: .tileMap,
            position: PointSpec(x: 200, y: 150)
        )
        tileMap.tileMapSpec = TileMapSpec(
            columns: 5,
            rows: 4,
            tileWidth: 32,
            tileHeight: 32,
            tileSetAssetRef: repository.assetRef(for: tilesetAsset),
            tileSetColumns: 2
        )

        let scene = SceneSpec(
            name: "main",
            size: SizeSpec(width: 640, height: 480),
            nodes: [sprite, tileMap]
        )
        let bridge = SceneBridge(sceneHeight: scene.size.height)

        let coldStats = bridge.textureCacheStats(for: scene, repository: repository)
        #expect(coldStats.referencedTextureCount == 2)
        #expect(coldStats.cachedTextureCount == 0)

        bridge.preloadTextures(for: scene, repository: repository)

        let warmStats = bridge.textureCacheStats(for: scene, repository: repository)
        #expect(warmStats.cachedTextureCount == 2)
        #expect(warmStats.missingTextureCount == 0)

        bridge.invalidateTexture(for: textureAsset.id)
        let partialStats = bridge.textureCacheStats(for: scene, repository: repository)
        #expect(partialStats.cachedTextureCount == 1)

        bridge.clearTextureCache()
        let clearedStats = bridge.textureCacheStats(for: scene, repository: repository)
        #expect(clearedStats.cachedTextureCount == 0)
    }

    @Test("tile maps anchor at top-left Hype coordinates")
    func tileMapsAnchorAtTopLeftCoordinates() {
        let tilesetAsset = SpriteAsset(
            name: "maze_tiles",
            kind: .tileSet,
            mimeType: "image/png",
            data: pngData(color: .systemBlue),
            width: 64,
            height: 64,
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 2,
            tileRows: 2
        )
        let repository = SpriteRepository(assets: [tilesetAsset])
        var tileMap = HypeNodeSpec(
            name: "maze",
            nodeType: .tileMap,
            position: PointSpec(x: 0, y: 0)
        )
        tileMap.tileMapSpec = TileMapSpec(
            columns: 2,
            rows: 2,
            tileWidth: 32,
            tileHeight: 32,
            tileSetAssetRef: repository.assetRef(for: tilesetAsset),
            tileSetColumns: 2,
            tileData: [[0, 0], [0, 0]]
        )
        let scene = SceneSpec(
            name: "main",
            size: SizeSpec(width: 64, height: 64),
            nodes: [tileMap]
        )
        let bridge = SceneBridge(sceneHeight: scene.size.height)
        let skScene = SKScene(size: CGSize(width: scene.size.width, height: scene.size.height))

        bridge.apply(spec: scene, to: skScene, repository: repository)

        let rendered = skScene.childNode(withName: "maze") as? SKTileMapNode
        #expect(rendered?.anchorPoint == CGPoint(x: 0, y: 1))
        #expect(rendered?.position == CGPoint(x: 0, y: 64))
    }

    @Test("single-tile generated tilesets render as one full-image tile")
    func singleTileGeneratedTilesetsRenderAsOneFullImageTile() {
        let tilesetAsset = SpriteAsset(
            name: "maze_wall",
            kind: .tileSet,
            mimeType: "image/png",
            data: pngData(color: .systemBlue, size: 128),
            width: 128,
            height: 128,
            tags: ["ai-generated"],
            tileWidth: 32,
            tileHeight: 32,
            tileColumns: 1,
            tileRows: 1
        )
        let repository = SpriteRepository(assets: [tilesetAsset])
        var tileMap = HypeNodeSpec(
            name: "maze",
            nodeType: .tileMap,
            position: PointSpec(x: 0, y: 0)
        )
        tileMap.tileMapSpec = TileMapSpec(
            columns: 1,
            rows: 1,
            tileWidth: 32,
            tileHeight: 32,
            tileSetAssetRef: repository.assetRef(for: tilesetAsset),
            tileSetColumns: 1,
            tileData: [[0]]
        )
        let scene = SceneSpec(
            name: "main",
            size: SizeSpec(width: 32, height: 32),
            nodes: [tileMap]
        )
        let bridge = SceneBridge(sceneHeight: scene.size.height)
        let skScene = SKScene(size: CGSize(width: scene.size.width, height: scene.size.height))

        bridge.apply(spec: scene, to: skScene, repository: repository)

        let rendered = skScene.childNode(withName: "maze") as? SKTileMapNode
        #expect(rendered?.tileSet.tileGroups.count == 2)
        #expect(rendered?.tileGroup(atColumn: 0, row: 0) != nil)
    }

    @Test("velocity-only live updates preserve dynamic runtime positions")
    func velocityOnlyLiveUpdatePreservesDynamicRuntimePosition() {
        var body = PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: 2,
            contactTestBitmask: 0,
            collisionBitmask: 1,
            velocityX: 0,
            velocityY: 0
        )
        body.affectedByGravity = false
        var player = HypeNodeSpec(
            name: "pacmanPlayer",
            nodeType: .sprite,
            position: PointSpec(x: 48, y: 496)
        )
        player.size = SizeSpec(width: 28, height: 28)
        player.physicsBody = body
        let previous = SceneSpec(
            name: "main",
            size: SizeSpec(width: 768, height: 544),
            nodes: [player]
        )
        let bridge = SceneBridge(sceneHeight: previous.size.height)
        let skScene = SKScene(size: CGSize(width: previous.size.width, height: previous.size.height))
        bridge.apply(spec: previous, to: skScene, repository: SpriteRepository())

        let livePlayer = bridge.registry.node(for: player.id)
        livePlayer?.position = CGPoint(x: 160, y: 120)

        var updated = previous
        _ = updated.updateNode(id: player.id) { node in
            node.physicsBody?.velocityX = 180
            node.physicsBody?.velocityY = 0
        }

        let needsRebuild = bridge.applyLiveUpdates(
            spec: updated,
            previousSpec: previous,
            to: skScene,
            repository: SpriteRepository()
        )

        #expect(needsRebuild == false)
        #expect(livePlayer?.position == CGPoint(x: 160, y: 120))
        #expect(livePlayer?.physicsBody?.velocity.dx == 180)
        #expect(livePlayer?.physicsBody?.velocity.dy == 0)
    }

    @Test("removing a pellet live does not rebuild or reset dynamic sprites")
    func removingPelletLiveDoesNotResetDynamicSprites() {
        var playerBody = PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: 2,
            contactTestBitmask: 8,
            collisionBitmask: 1,
            velocityX: 100,
            velocityY: 0
        )
        playerBody.affectedByGravity = false
        var player = HypeNodeSpec(
            name: "pacmanPlayer",
            nodeType: .sprite,
            position: PointSpec(x: 48, y: 496)
        )
        player.size = SizeSpec(width: 28, height: 28)
        player.physicsBody = playerBody

        var ghostBody = PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: 4,
            contactTestBitmask: 2,
            collisionBitmask: 1,
            velocityX: -120,
            velocityY: 0
        )
        ghostBody.affectedByGravity = false
        var ghost = HypeNodeSpec(
            name: "ghost_blinky",
            nodeType: .sprite,
            position: PointSpec(x: 368, y: 272)
        )
        ghost.size = SizeSpec(width: 28, height: 28)
        ghost.physicsBody = ghostBody

        var pellet = HypeNodeSpec(
            name: "pellet_1",
            nodeType: .sprite,
            position: PointSpec(x: 80, y: 496)
        )
        pellet.size = SizeSpec(width: 8, height: 8)

        let previous = SceneSpec(
            name: "main",
            size: SizeSpec(width: 768, height: 544),
            nodes: [player, ghost, pellet]
        )
        let bridge = SceneBridge(sceneHeight: previous.size.height)
        let skScene = SKScene(size: CGSize(width: previous.size.width, height: previous.size.height))
        bridge.apply(spec: previous, to: skScene, repository: SpriteRepository())

        let livePlayer = bridge.registry.node(for: player.id)
        let liveGhost = bridge.registry.node(for: ghost.id)
        livePlayer?.position = CGPoint(x: 150, y: 120)
        liveGhost?.position = CGPoint(x: 300, y: 180)

        var updated = previous
        _ = updated.removeNode(id: pellet.id)

        let needsRebuild = bridge.applyLiveUpdates(
            spec: updated,
            previousSpec: previous,
            to: skScene,
            repository: SpriteRepository()
        )

        #expect(needsRebuild == false)
        #expect(bridge.registry.node(for: pellet.id) == nil)
        #expect(livePlayer?.position == CGPoint(x: 150, y: 120))
        #expect(liveGhost?.position == CGPoint(x: 300, y: 180))
    }

    private func pngData(color: NSColor, size: CGFloat = 16) -> Data {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()

        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}
