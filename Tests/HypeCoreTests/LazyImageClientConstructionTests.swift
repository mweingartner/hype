import Foundation
import Testing
@testable import HypeCore

/// Regression coverage for the lazy image-generation client seam.
///
/// Background: `HypeDebugServer.makeExecutor` (and the two AI chat views) used
/// to build the OpenAI image client eagerly via
/// `try? HypeAIConfiguration.makeImageGenerationClient()`, which calls
/// `KeychainStore.getSecret` — a `kSecReturnData` decrypt. Under an
/// ad-hoc-signed / locked / headless session that decrypt can block on a
/// securityd GUI ACL prompt, wedging the caller (the debug-bridge main actor)
/// for *every* tool call — including recipe/scene/CRUD tools that never
/// generate images. The fix defers image-client construction behind
/// `HypeToolExecutor.imageGenerationClientFactory`, resolved only when an image
/// tool actually runs.
///
/// These tests pin that invariant by injecting a spy factory and asserting it is
/// never resolved while *building* an executor or running a *non-image* tool —
/// i.e. no synchronous keychain decrypt happens on those paths — while still
/// resolving exactly once when an image tool runs.
@Suite("Lazy image-generation client construction")
struct LazyImageClientConstructionTests {

    /// Minimal valid 1×1 PNG so the resolved fake generator returns real bytes.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    /// Stand-in image generator. Constructing it stands in for the real keychain
    /// decrypt: in production the factory body is what calls
    /// `KeychainStore.getSecret`, so counting factory invocations is a faithful
    /// proxy for "did a keychain decrypt happen on this path?".
    private struct FakeImageGenerator: HypeImageGenerating {
        let imageData: Data
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

    @Test("Building an executor and running a non-image tool never resolves the image-client factory")
    func nonImageToolDoesNotResolveImageFactory() async {
        let pngData = Self.onePixelPNG
        // `nonisolated(unsafe)` mirrors the existing Meshy factory-spy tests: the
        // factory is invoked synchronously inside `execute`, and every read below
        // is sequenced after an `await`, so there is no real data race.
        nonisolated(unsafe) var factoryInvocations = 0
        let executor = HypeToolExecutor(
            webAssetSession: nil,
            webAssetClient: nil,
            webAssetPipeline: nil,
            imageGenerationClientFactory: {
                factoryInvocations += 1
                return FakeImageGenerator(imageData: pngData)
            }
        )

        // 1. Construction alone must not resolve the factory. This is the exact
        //    regression: makeExecutor used to decrypt the key right here, before
        //    any tool had even been chosen.
        #expect(factoryInvocations == 0, "Constructing the executor must not resolve (decrypt) the image client")

        // 2. A representative non-image tool (the CRUD/scene/recipe family) must
        //    not resolve it either — only generate_image / generate_sprite_asset
        //    touch the image factory.
        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let initialCardCount = document.cards.count
        _ = await executor.execute(
            toolName: "create_card",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )

        #expect(document.cards.count == initialCardCount + 1, "create_card should add a card (proving the tool actually ran)")
        #expect(factoryInvocations == 0, "A non-image tool must never resolve (decrypt) the image client")
    }

    @Test("An image tool resolves the image-client factory exactly once")
    func imageToolResolvesImageFactoryOnce() async throws {
        let pngData = Self.onePixelPNG
        nonisolated(unsafe) var factoryInvocations = 0
        let executor = HypeToolExecutor(
            webAssetSession: nil,
            webAssetClient: nil,
            webAssetPipeline: nil,
            imageGenerationClientFactory: {
                factoryInvocations += 1
                return FakeImageGenerator(imageData: pngData)
            }
        )

        var document = HypeDocument.newDocument()
        let cardId = document.sortedCards[0].id
        let result = await executor.execute(
            toolName: "generate_image",
            arguments: ["name": "lazy_art", "prompt": "a glossy ball"],
            document: &document,
            currentCardId: cardId
        )

        // The lazy seam must still produce a real client when an image tool runs
        // and a key is available (here, the injected fake) — proving the fix did
        // not break image generation, and that resolution happens once per call.
        #expect(factoryInvocations == 1, "generate_image must resolve the image client exactly once")
        #expect(result.contains("Generated image part 'lazy_art'"))
        let part = try #require(document.parts.first { $0.name == "lazy_art" })
        #expect(part.partType == .image)
        #expect(part.imageData == pngData)
    }
}
