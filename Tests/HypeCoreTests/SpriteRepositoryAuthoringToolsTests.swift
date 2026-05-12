import Testing
import Foundation
@testable import HypeCore

// MARK: - Tests

@Suite("Sprite Repository Authoring Tools — Meshy tool allowlist (Phase 5)")
struct SpriteRepositoryAuthoringToolsTests {

    private let toolNames: Set<String> = {
        Set(HypeToolDefinitions.spriteRepositoryAuthoringTools.map(\.function.name))
    }()

    // MARK: Existing tools remain in the allowlist

    @Test("existing sprite repository tools are present")
    func existingToolsPresent() {
        #expect(toolNames.contains("list_repository_assets"))
        #expect(toolNames.contains("import_repository_asset"))
        #expect(toolNames.contains("generate_sprite_asset"))
        #expect(toolNames.contains("classify_asset_as_tileset"))
        #expect(toolNames.contains("write_ai_context_note"))
    }

    // MARK: New Meshy 3D tools are in the allowlist

    @Test("generate_3d_model_from_text is in sprite repository allowlist")
    func generateFromTextPresent() {
        #expect(toolNames.contains("generate_3d_model_from_text"),
                "3D text generation must be available in the Sprite Repository AI chat")
    }

    @Test("generate_3d_model_from_image is in sprite repository allowlist")
    func generateFromImagePresent() {
        #expect(toolNames.contains("generate_3d_model_from_image"),
                "3D image-to-model generation must be available in the Sprite Repository AI chat")
    }

    @Test("generate_3d_model_from_images is in sprite repository allowlist")
    func generateFromImagesPresent() {
        #expect(toolNames.contains("generate_3d_model_from_images"),
                "Multi-image 3D generation must be available in the Sprite Repository AI chat")
    }

    @Test("list_3d_models is in sprite repository allowlist")
    func list3DModelsPresent() {
        #expect(toolNames.contains("list_3d_models"),
                "list_3d_models must be available in the Sprite Repository AI chat")
    }

    @Test("remesh_3d_model is in sprite repository allowlist")
    func remeshPresent() {
        #expect(toolNames.contains("remesh_3d_model"),
                "remesh_3d_model must be available in the Sprite Repository AI chat")
    }

    @Test("retexture_3d_model is in sprite repository allowlist")
    func retexturePresent() {
        #expect(toolNames.contains("retexture_3d_model"),
                "retexture_3d_model must be available in the Sprite Repository AI chat")
    }

    // MARK: Non-repository tools remain excluded

    @Test("generate_image (card-level tool) is NOT in sprite repository allowlist")
    func generateImageNotPresent() {
        #expect(!toolNames.contains("generate_image"),
                "generate_image is a card-level tool and must stay out of the sprite repository allowlist")
    }

    @Test("create_scene3d (card-level tool) is NOT in sprite repository allowlist")
    func createScene3dNotPresent() {
        #expect(!toolNames.contains("create_scene3d"),
                "create_scene3d creates card parts and must stay out of the sprite repository allowlist")
    }
}
