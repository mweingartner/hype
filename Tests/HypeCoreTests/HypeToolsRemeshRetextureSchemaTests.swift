import Foundation
import Testing
@testable import HypeCore

// MARK: - HypeToolsRemeshRetextureSchemaTests

@Suite("Tool schemas — remesh_3d_model and retexture_3d_model")
struct HypeToolsRemeshRetextureSchemaTests {

    private let allTools = HypeToolDefinitions.allTools

    // MARK: (a) remesh_3d_model tool exists with required params

    @Test("remesh_3d_model tool exists with source_asset_name and target_polycount as required")
    func remeshToolExistsWithRequiredParams() {
        guard let tool = allTools.first(where: { $0.function.name == "remesh_3d_model" }) else {
            Issue.record("remesh_3d_model tool not found in HypeToolDefinitions.allTools")
            return
        }

        let params = tool.function.parameters
        #expect(params.properties["source_asset_name"] != nil, "source_asset_name param must exist")
        #expect(params.properties["target_polycount"] != nil, "target_polycount param must exist")
        #expect(params.required.contains("source_asset_name"), "source_asset_name must be required")
        #expect(params.required.contains("target_polycount"), "target_polycount must be required")
    }

    // MARK: (b) retexture_3d_model tool exists with required params

    @Test("retexture_3d_model tool exists with source_asset_name and style_prompt as required")
    func retextureToolExistsWithRequiredParams() {
        guard let tool = allTools.first(where: { $0.function.name == "retexture_3d_model" }) else {
            Issue.record("retexture_3d_model tool not found in HypeToolDefinitions.allTools")
            return
        }

        let params = tool.function.parameters
        #expect(params.properties["source_asset_name"] != nil, "source_asset_name param must exist")
        #expect(params.properties["style_prompt"] != nil, "style_prompt param must exist")
        #expect(params.required.contains("source_asset_name"), "source_asset_name must be required")
        #expect(params.required.contains("style_prompt"), "style_prompt must be required")
    }

    // MARK: (c) Both tools appear in requiredEditTools allowlists (C16)

    @Test("remesh_3d_model and retexture_3d_model appear in cardControlAuthoringTools")
    func remeshToolIsInCardControlAuthoringTools() {
        let names = HypeToolDefinitions.cardControlAuthoringTools.map { $0.function.name }
        #expect(names.contains("remesh_3d_model"),
                "remesh_3d_model must be in cardControlAuthoringTools allowlist (C16)")
        #expect(names.contains("retexture_3d_model"),
                "retexture_3d_model must be in cardControlAuthoringTools allowlist (C16)")
    }

    @Test("remesh_3d_model and retexture_3d_model appear in spriteSceneAuthoringTools")
    func remeshToolIsInSpriteSceneAuthoringTools() {
        let names = HypeToolDefinitions.spriteSceneAuthoringTools.map { $0.function.name }
        #expect(names.contains("remesh_3d_model"),
                "remesh_3d_model must be in spriteSceneAuthoringTools allowlist (C16)")
        #expect(names.contains("retexture_3d_model"),
                "retexture_3d_model must be in spriteSceneAuthoringTools allowlist (C16)")
    }
}
