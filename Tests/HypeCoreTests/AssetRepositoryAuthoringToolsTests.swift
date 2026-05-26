import Testing
import Foundation
@testable import HypeCore

// MARK: - Tests

@Suite("Asset Repository Authoring Tools — Meshy tool allowlist (Phase 5)")
struct AssetRepositoryAuthoringToolsTests {

    private let toolNames: Set<String> = {
        Set(HypeToolDefinitions.assetRepositoryAuthoringTools.map(\.function.name))
    }()

    // MARK: Existing tools remain in the allowlist

    @Test("existing asset repository tools are present")
    func existingToolsPresent() {
        #expect(toolNames.contains("list_repository_assets"))
        #expect(toolNames.contains("get_repository_asset"))
        #expect(toolNames.contains("import_repository_asset"))
        #expect(toolNames.contains("generate_sprite_asset"))
        #expect(toolNames.contains("classify_asset_as_tileset"))
        #expect(toolNames.contains("write_ai_context_note"))
    }

    @Test("get_repository_asset reports audio asset metadata")
    func getRepositoryAssetReportsAudioMetadata() async throws {
        var document = HypeDocument.newDocument(name: "Asset Metadata")
        let cardId = try #require(document.cards.first?.id)
        document.assetRepository.addAsset(Asset(
            name: "Sound 128",
            kind: .audioClip,
            mimeType: "audio/wav",
            data: Data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]),
            tags: ["hypercard-import", "sound-resource"]
        ))

        let result = await HypeToolExecutor().execute(
            toolName: "get_repository_asset",
            arguments: ["name": "Sound 128"],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("kind=audioClip"))
        #expect(result.contains("mimeType=audio/wav"))
        #expect(result.contains("byteCount=12"))
        #expect(result.contains("tags=hypercard-import,sound-resource"))
    }

    // MARK: New Meshy 3D tools are in the allowlist

    @Test("generate_3d_model_from_text is in asset repository allowlist")
    func generateFromTextPresent() {
        #expect(toolNames.contains("generate_3d_model_from_text"),
                "3D text generation must be available in the Asset Repository AI chat")
    }

    @Test("generate_3d_model_from_image is in asset repository allowlist")
    func generateFromImagePresent() {
        #expect(toolNames.contains("generate_3d_model_from_image"),
                "3D image-to-model generation must be available in the Asset Repository AI chat")
    }

    @Test("generate_3d_model_from_images is in asset repository allowlist")
    func generateFromImagesPresent() {
        #expect(toolNames.contains("generate_3d_model_from_images"),
                "Multi-image 3D generation must be available in the Asset Repository AI chat")
    }

    @Test("list_3d_models is in asset repository allowlist")
    func list3DModelsPresent() {
        #expect(toolNames.contains("list_3d_models"),
                "list_3d_models must be available in the Asset Repository AI chat")
    }

    @Test("remesh_3d_model is in asset repository allowlist")
    func remeshPresent() {
        #expect(toolNames.contains("remesh_3d_model"),
                "remesh_3d_model must be available in the Asset Repository AI chat")
    }

    @Test("retexture_3d_model is in asset repository allowlist")
    func retexturePresent() {
        #expect(toolNames.contains("retexture_3d_model"),
                "retexture_3d_model must be available in the Asset Repository AI chat")
    }

    // MARK: Non-repository tools remain excluded

    @Test("generate_image (card-level tool) is NOT in asset repository allowlist")
    func generateImageNotPresent() {
        #expect(!toolNames.contains("generate_image"),
                "generate_image is a card-level tool and must stay out of the asset repository allowlist")
    }

    @Test("create_scene3d (card-level tool) is NOT in asset repository allowlist")
    func createScene3dNotPresent() {
        #expect(!toolNames.contains("create_scene3d"),
                "create_scene3d creates card parts and must stay out of the asset repository allowlist")
    }
}
