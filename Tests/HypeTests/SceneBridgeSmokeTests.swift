import Testing
import AppKit
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

    private func pngData(color: NSColor) -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()

        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}
