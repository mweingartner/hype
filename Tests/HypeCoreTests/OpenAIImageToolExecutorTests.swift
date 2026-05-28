import Foundation
import Testing
@testable import HypeCore

@Suite("OpenAI image tool executor")
struct OpenAIImageToolExecutorTests {
    private let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    @Test("generate_sprite_asset refuses missing asset name")
    func generateAssetRequiresName() async {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let executor = HypeToolExecutor(
            webAssetSession: nil,
            webAssetClient: nil,
            webAssetPipeline: nil,
            imageGenerationClient: FakeImageGenerator(imageData: onePixelPNG)
        )

        let result = await executor.execute(
            toolName: "generate_sprite_asset",
            arguments: ["prompt": "a blue ball"],
            document: &document,
            currentCardId: cardId
        )

        #expect(result.contains("requires 'asset_name'"))
        #expect(document.assetRepository.assets.isEmpty)
    }

    @Test("generate_sprite_asset adds AI-generated repository asset")
    func generateAssetAddsRepositoryAsset() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let executor = HypeToolExecutor(
            webAssetSession: nil,
            webAssetClient: nil,
            webAssetPipeline: nil,
            imageGenerationClient: FakeImageGenerator(imageData: onePixelPNG)
        )

        let result = await executor.execute(
            toolName: "generate_sprite_asset",
            arguments: [
                "asset_name": "blue_ball",
                "prompt": "a glossy blue ball game sprite",
                "background": "transparent"
            ],
            document: &document,
            currentCardId: cardId
        )

        let asset = try #require(document.assetRepository.asset(byName: "blue_ball"))
        #expect(result.contains("Generated sprite asset 'blue_ball'"))
        #expect(asset.data == onePixelPNG)
        #expect(asset.kind == .imageTexture)
        #expect(asset.tags.contains("ai-generated"))
        #expect(asset.provenance?.origin == .aiGenerated)
        #expect(asset.provenance?.searchQuery == "a glossy blue ball game sprite")
    }

    @Test("generate_image creates image part on current card")
    func generateImageCreatesCardPart() async throws {
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let executor = HypeToolExecutor(
            webAssetSession: nil,
            webAssetClient: nil,
            webAssetPipeline: nil,
            imageGenerationClient: FakeImageGenerator(imageData: onePixelPNG)
        )

        let result = await executor.execute(
            toolName: "generate_image",
            arguments: [
                "name": "hero_art",
                "prompt": "retro pixel art landscape",
                "left": "12",
                "top": "34",
                "width": "160",
                "height": "90"
            ],
            document: &document,
            currentCardId: cardId
        )

        let part = try #require(document.parts.first { $0.name == "hero_art" })
        #expect(result.contains("Generated image part 'hero_art'"))
        #expect(part.partType == .image)
        #expect(part.cardId == cardId)
        #expect(part.backgroundId == nil)
        #expect(part.left == 12)
        #expect(part.top == 34)
        #expect(part.width == 160)
        #expect(part.height == 90)
        #expect(part.imageData == onePixelPNG)
    }

    @Test("generate_image can place image part on current background")
    func generateImageCreatesBackgroundPart() async throws {
        var document = HypeDocument.newDocument()
        let card = document.sortedCards[0]
        let executor = HypeToolExecutor(
            webAssetSession: nil,
            webAssetClient: nil,
            webAssetPipeline: nil,
            imageGenerationClient: FakeImageGenerator(imageData: onePixelPNG)
        )

        let result = await executor.execute(
            toolName: "generate_image",
            arguments: [
                "name": "shared_sky",
                "prompt": "soft sky background",
                "on_background": "true"
            ],
            document: &document,
            currentCardId: card.id
        )

        let part = try #require(document.parts.first { $0.name == "shared_sky" })
        #expect(result.contains("on the background"))
        #expect(part.cardId == nil)
        #expect(part.backgroundId == card.backgroundId)
        #expect(part.imageData == onePixelPNG)
    }

    @Test("image generation tools are available to relevant AI catalogs")
    func toolCatalogIncludesImageGenerationTools() {
        let cardTools = Set(HypeToolDefinitions.cardControlAuthoringTools.map(\.function.name))
        let spriteTools = Set(HypeToolDefinitions.spriteSceneAuthoringTools.map(\.function.name))
        let repositoryTools = Set(HypeToolDefinitions.assetRepositoryAuthoringTools.map(\.function.name))

        #expect(cardTools.contains("generate_image"))
        #expect(cardTools.contains("generate_sprite_asset"))
        #expect(spriteTools.contains("generate_image"))
        #expect(spriteTools.contains("generate_sprite_asset"))
        #expect(repositoryTools.contains("generate_sprite_asset"))
        #expect(!repositoryTools.contains("generate_image"))
    }

    private struct FakeImageGenerator: HypeImageGenerating {
        var imageData: Data

        func generateImage(
            prompt: String,
            model: String?,
            size: String?,
            quality: String?,
            background: String?
        ) async throws -> HypeGeneratedImage {
            HypeGeneratedImage(data: imageData, mimeType: "image/png")
        }
    }
}
