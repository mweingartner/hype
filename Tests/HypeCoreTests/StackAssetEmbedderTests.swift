import Foundation
import Testing
@testable import HypeCore

@Suite("Stack asset embedder")
struct StackAssetEmbedderTests {
    @Test("local PDF video and 3D references are embedded into the stack repository")
    func localControlReferencesEmbedIntoRepository() throws {
        let fixtureDir = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureDir) }
        let pdfURL = try writeFixture("sample.pdf", bytes: "%PDF-1.4\n".data(using: .utf8)!, in: fixtureDir)
        let videoURL = try writeFixture("intro.mov", bytes: Data([0, 1, 2, 3]), in: fixtureDir)
        let modelURL = try writeFixture("ship.usdz", bytes: Data([4, 5, 6, 7]), in: fixtureDir)

        var document = HypeDocument.newDocument(name: "Embedded Media")
        let cardId = try #require(document.cards.first?.id)
        var pdf = Part(partType: .pdf, cardId: cardId, name: "Spec PDF")
        pdf.pdfURL = pdfURL.path
        var video = Part(partType: .video, cardId: cardId, name: "Intro Video")
        video.videoURL = videoURL.path
        var model = Part(partType: .scene3D, cardId: cardId, name: "Ship Model")
        model.scene3DURL = modelURL.path
        document.addPart(pdf)
        document.addPart(video)
        document.addPart(model)

        let report = try StackAssetEmbedder.embedReferencedAssets(in: &document)

        #expect(report.updatedPartIds.count == 3)
        #expect(report.embeddedAssetIds.count == 3)
        #expect(document.assetRepository.assets.map(\.kind).contains(.document))
        #expect(document.assetRepository.assets.map(\.kind).contains(.videoClip))
        #expect(document.assetRepository.assets.map(\.kind).contains(.model3D))
        let embeddedPDF = try #require(document.parts.first { $0.name == "Spec PDF" })
        let embeddedVideo = try #require(document.parts.first { $0.name == "Intro Video" })
        let embeddedModel = try #require(document.parts.first { $0.name == "Ship Model" })
        #expect(embeddedPDF.pdfAssetRef != nil)
        #expect(embeddedPDF.pdfURL.hasPrefix("asset://"))
        #expect(embeddedVideo.videoAssetRef != nil)
        #expect(embeddedVideo.videoURL.hasPrefix("asset://"))
        #expect(embeddedModel.scene3DAssetRef != nil)
        #expect(embeddedModel.scene3DURL.isEmpty)
        #expect(StackAssetEmbedder.selfContainmentIssues(in: document).isEmpty)
    }

    @Test("remote media references are reported rather than fetched implicitly")
    func remoteMediaReferencesAreDeploymentIssues() throws {
        var document = HypeDocument.newDocument(name: "Remote Media")
        let cardId = try #require(document.cards.first?.id)
        var pdf = Part(partType: .pdf, cardId: cardId, name: "Remote PDF")
        pdf.pdfURL = "https://example.com/spec.pdf"
        document.addPart(pdf)

        _ = try StackAssetEmbedder.embedReferencedAssets(in: &document)
        let issues = StackAssetEmbedder.selfContainmentIssues(in: document)

        #expect(issues.count == 1)
        #expect(issues.first?.partId == pdf.id)
        #expect(issues.first?.reason.contains("Remote media") == true)
    }

    @Test("missing explicit asset references are reported even when path fields are empty")
    func missingExplicitAssetReferencesAreReported() throws {
        var document = HypeDocument.newDocument(name: "Missing Asset")
        let cardId = try #require(document.cards.first?.id)
        var pdf = Part(partType: .pdf, cardId: cardId, name: "Missing PDF")
        pdf.pdfAssetRef = AssetRef(id: UUID(), name: "missing.pdf", mimeType: "application/pdf")
        document.addPart(pdf)

        let issues = StackAssetEmbedder.selfContainmentIssues(in: document)

        #expect(issues.count == 1)
        #expect(issues.first?.property == "pdfAssetRef")
        #expect(issues.first?.reason.contains("missing stack asset") == true)
    }

    @Test("runtime package export embeds local media before writing Stack.hype")
    func runtimePackageExportEmbedsLocalMedia() throws {
        let fixtureDir = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureDir) }
        let pdfURL = try writeFixture("manual.pdf", bytes: "%PDF-1.4\n".data(using: .utf8)!, in: fixtureDir)
        let videoURL = try writeFixture("clip.mov", bytes: Data([1, 1, 2, 3]), in: fixtureDir)

        var document = HypeDocument.newDocument(name: "Runtime Media")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        let cardId = try #require(document.cards.first?.id)
        var pdf = Part(partType: .pdf, cardId: cardId, name: "Manual")
        pdf.pdfURL = pdfURL.path
        var video = Part(partType: .video, cardId: cardId, name: "Clip")
        video.videoURL = videoURL.path
        document.addPart(pdf)
        document.addPart(video)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeEmbeddedRuntime-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try #require(TargetRuntimePackageBuilder().buildPackages(for: document, at: output).first)
        let embeddedStackURL = result.packageURL
            .appendingPathComponent(TargetRuntimePackageBuilder.stackDirectoryName, isDirectory: true)
            .appendingPathComponent(TargetRuntimePackageBuilder.embeddedStackName, isDirectory: true)
        let runtimeDocument = try HypeSQLiteStackStore().load(fromPackageAt: embeddedStackURL)

        #expect(runtimeDocument.assetRepository.assets.count == 2)
        #expect(runtimeDocument.parts.first { $0.name == "Manual" }?.pdfAssetRef != nil)
        #expect(runtimeDocument.parts.first { $0.name == "Manual" }?.pdfURL.hasPrefix("asset://") == true)
        #expect(runtimeDocument.parts.first { $0.name == "Clip" }?.videoAssetRef != nil)
        #expect(runtimeDocument.parts.first { $0.name == "Clip" }?.videoURL.hasPrefix("asset://") == true)
        #expect(StackAssetEmbedder.selfContainmentIssues(in: runtimeDocument).isEmpty)
    }

    private func makeFixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeAssetEmbedderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFixture(_ name: String, bytes: Data, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }
}
