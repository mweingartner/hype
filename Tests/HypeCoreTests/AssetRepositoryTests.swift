import Foundation
import Testing
@testable import HypeCore

@Suite("AssetRepository")
struct AssetRepositoryTests {
    @Test("repository filters and searches multiple asset categories")
    func filtersAndSearchesMultipleAssetCategories() {
        let image = Asset(name: "Hero", kind: .imageTexture, mimeType: "image/png", data: Data([1]))
        let audio = Asset(name: "Hero", kind: .audioClip, mimeType: "audio/wav", data: Data([2]))
        let video = Asset(name: "Intro", kind: .videoClip, mimeType: "video/mp4", data: Data([3]))
        let model = Asset(name: "Robot", kind: .model3D, mimeType: "model/gltf-binary", data: Data([4]))
        let particles = Asset(name: "Smoke", kind: .particlePreset, mimeType: "application/x-spritekit-particle", data: Data([5]))
        let repository = AssetRepository(assets: [image, audio, video, model, particles])

        #expect(repository.assets(in: .image).map(\.id) == [image.id])
        #expect(repository.assets(in: .audio).map(\.id) == [audio.id])
        #expect(repository.assets(in: .video).map(\.id) == [video.id])
        #expect(repository.assets(in: .model3D).map(\.id) == [model.id])
        #expect(repository.assets(in: .effects).map(\.id) == [particles.id])
        #expect(repository.asset(byName: "Hero", kind: .audioClip)?.id == audio.id)
        #expect(repository.searchAssets(named: "ro", category: .model3D).map(\.id) == [model.id])
    }

    @Test("HypeDocument exposes assetRepository while preserving assetRepository storage")
    func documentAssetRepositoryAliasMutatesStoredRepository() {
        var document = HypeDocument.newDocument()
        let sound = Asset(name: "Click", kind: .audioClip, mimeType: "audio/wav", data: Data([1, 2, 3]))

        document.assetRepository.addAsset(sound)

        #expect(document.assetRepository.asset(byName: "Click", kind: .audioClip)?.id == sound.id)
        #expect(document.assetRepository.assets(in: .audio).count == 1)
    }
}
