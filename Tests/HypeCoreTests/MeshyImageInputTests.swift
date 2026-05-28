import Foundation
import Testing
@testable import HypeCore

// MARK: - Helpers

private func pngMagicBytes() -> Data {
    // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
    Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x42, count: 16))
}

private func jpegMagicBytes() -> Data {
    // JPEG magic bytes: FF D8 FF
    Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x42, count: 16))
}

private func webpMagicBytes() -> Data {
    // WebP: RIFF....WEBP
    let riff: [UInt8] = [0x52, 0x49, 0x46, 0x46]  // "RIFF"
    let size: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    let webp: [UInt8] = [0x57, 0x45, 0x42, 0x50]  // "WEBP"
    return Data(riff + size + webp + Array(repeating: 0x42, count: 16))
}

private func svgBytes() -> Data {
    Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
}

private func makeRepository(assets: [Asset] = []) -> AssetRepository {
    var repo = AssetRepository()
    for asset in assets { repo.addAsset(asset) }
    return repo
}

private func makePNGAsset(name: String, size: Int = 1024, kind: AssetKind = .imageTexture) -> Asset {
    var data = pngMagicBytes()
    if data.count < size {
        data.append(Data(repeating: 0x42, count: size - data.count))
    }
    var asset = Asset(name: name, data: data)
    asset.kind = kind
    return asset
}

// MARK: - Tests

@Suite("MeshyImageInput resolution + validation", .serialized)
struct MeshyImageInputTests {

    // MARK: (a) filePath rejects relative path

    @Test("filePath rejects relative path")
    func filePathRejectsRelative() throws {
        let input = MeshyImageInput.filePath("relative/path/image.png")
        let repo = makeRepository()
        do {
            _ = try input.resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_path")
        }
    }

    // MARK: (b) filePath rejects path containing ".."

    @Test("filePath rejects path with '..' traversal segment")
    func filePathRejectsTraversal() throws {
        let input = MeshyImageInput.filePath("/Users/alice/../etc/passwd")
        let repo = makeRepository()
        do {
            _ = try input.resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_path")
        }
    }

    // MARK: (c) filePath rejects /etc/passwd

    @Test("filePath rejects /etc/passwd (blocked prefix)")
    func filePathRejectsEtcPasswd() throws {
        let input = MeshyImageInput.filePath("/etc/passwd")
        let repo = makeRepository()
        do {
            _ = try input.resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_path")
        }
    }

    // MARK: (d) filePath rejects /Library/Keychains/...

    @Test("filePath rejects /Library/Keychains/ path")
    func filePathRejectsKeychains() throws {
        let input = MeshyImageInput.filePath("/Library/Keychains/System.keychain")
        let repo = makeRepository()
        do {
            _ = try input.resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_path")
        }
    }

    // MARK: (e) assetName rejects audioClip asset

    @Test("assetName rejects audioClip kind asset")
    func assetNameRejectsAudioClip() throws {
        var asset = Asset(name: "sound.mp3", data: Data(repeating: 0, count: 64))
        asset.kind = .audioClip
        let repo = makeRepository(assets: [asset])
        do {
            _ = try MeshyImageInput.assetName("sound.mp3").resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_asset_name")
        }
    }

    // MARK: (f) assetName rejects model3D asset

    @Test("assetName rejects model3D kind asset")
    func assetNameRejectsModel3D() throws {
        var asset = Asset(name: "robot.glb", data: Data(repeating: 0, count: 64))
        asset.kind = .model3D
        let repo = makeRepository(assets: [asset])
        do {
            _ = try MeshyImageInput.assetName("robot.glb").resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_asset_name")
        }
    }

    // MARK: (g) assetName rejects asset > 10 MB

    @Test("assetName rejects asset larger than 10 MB")
    func assetNameRejectsOversized() throws {
        let oversize = MeshyImageInput.maxBytesPerImage + 1
        var assetData = pngMagicBytes()
        assetData.append(Data(repeating: 0x42, count: oversize - assetData.count))
        var asset = Asset(name: "huge.png", data: assetData)
        asset.kind = .imageTexture
        let repo = makeRepository(assets: [asset])
        do {
            _ = try MeshyImageInput.assetName("huge.png").resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_asset_name")
        }
    }

    // MARK: (h) base64 with "data:image/png;base64,..." prefix decodes

    @Test("base64 with data URI prefix decodes correctly")
    func base64WithDataURIPrefix() throws {
        let pngData = pngMagicBytes()
        let b64 = pngData.base64EncodedString()
        let dataURI = "data:image/png;base64,\(b64)"
        let repo = makeRepository()
        let resolved = try MeshyImageInput.base64(dataURI).resolve(in: repo)
        #expect(resolved.mimeType == "image/png")
        #expect(resolved.data == pngData)
    }

    // MARK: (i) base64 > 14 MB encoded is rejected

    @Test("base64 > 14 MB encoded is rejected")
    func base64TooLargeEncoded() throws {
        // Generate a string longer than Int(10MB * 1.4) = 14,680,064 chars.
        let overCap = Int(Double(MeshyImageInput.maxBytesPerImage) * 1.4) + 1
        let bigString = String(repeating: "A", count: overCap)
        let repo = makeRepository()
        do {
            _ = try MeshyImageInput.base64(bigString).resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_base64")
        }
    }

    // MARK: (j) sniffMimeType returns nil for SVG bytes

    @Test("sniffMimeType returns nil for SVG bytes")
    func sniffNilForSVG() {
        let result = MeshyImageInput.sniffMimeType(svgBytes())
        #expect(result == nil)
    }

    // MARK: (k) Sniff disagrees with claimed MIME → trust sniff

    @Test("base64 with wrong data URI claim → sniffed MIME wins")
    func sniffTrumpsClaimedMIME() throws {
        // Data is actually PNG bytes, but claim says SVG.
        let pngData = pngMagicBytes()
        let b64 = pngData.base64EncodedString()
        let dataURI = "data:image/svg+xml;base64,\(b64)"
        let repo = makeRepository()
        let resolved = try MeshyImageInput.base64(dataURI).resolve(in: repo)
        // The resolved MIME should be image/png (sniffed), not svg.
        #expect(resolved.mimeType == "image/png")
    }

    // MARK: (l) PNG / JPEG / WebP magic bytes recognised

    @Test("sniffMimeType identifies PNG magic bytes")
    func sniffPNG() {
        #expect(MeshyImageInput.sniffMimeType(pngMagicBytes()) == "image/png")
    }

    @Test("sniffMimeType identifies JPEG magic bytes")
    func sniffJPEG() {
        #expect(MeshyImageInput.sniffMimeType(jpegMagicBytes()) == "image/jpeg")
    }

    @Test("sniffMimeType identifies WebP magic bytes")
    func sniffWebP() {
        #expect(MeshyImageInput.sniffMimeType(webpMagicBytes()) == "image/webp")
    }

    @Test("base64 WebP bytes are sniffed but rejected")
    func base64WebPIsRejected() throws {
        let b64 = webpMagicBytes().base64EncodedString()
        let repo = makeRepository()
        do {
            _ = try MeshyImageInput.base64(b64).resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, let reason) {
            #expect(field == "image_base64")
            #expect(reason.contains("PNG or JPEG"))
        }
    }

    @Test("assetName WebP bytes are sniffed but rejected")
    func assetNameWebPIsRejected() throws {
        var asset = Asset(name: "sprite.webp", data: webpMagicBytes())
        asset.kind = .imageTexture
        let repo = makeRepository(assets: [asset])
        do {
            _ = try MeshyImageInput.assetName("sprite.webp").resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, let reason) {
            #expect(field == "image_asset_name")
            #expect(reason.contains("PNG or JPEG"))
        }
    }

    // MARK: (m) dataURI uses sniffed MIME type, not claimed type

    @Test("dataURI uses sniffed MIME type in prefix")
    func dataURIUsesSniffedMIME() throws {
        let pngData = pngMagicBytes()
        let b64 = pngData.base64EncodedString()
        let repo = makeRepository()
        let resolved = try MeshyImageInput.base64(b64).resolve(in: repo)
        #expect(resolved.dataURI.hasPrefix("data:image/png;base64,"))
    }

    // MARK: (n) assetName happy path resolves correctly

    @Test("assetName resolves valid imageTexture asset")
    func assetNameResolvesImageTexture() throws {
        let asset = makePNGAsset(name: "sprite.png", kind: .imageTexture)
        let repo = makeRepository(assets: [asset])
        let resolved = try MeshyImageInput.assetName("sprite.png").resolve(in: repo)
        #expect(resolved.mimeType == "image/png")
        #expect(resolved.sourceDescriptor == "asset:sprite.png")
    }

    // MARK: (o) sourceDescriptor for filePath inputs is "file" (H1)

    @Test("filePath sourceDescriptor is 'file', not the raw path (H1)")
    func filePathSourceDescriptorIsOpaque() throws {
        // We use a temp file so the resolution can read it without hitting
        // the blocked-prefix or outside-home checks.
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID()).png")
        let pngData = pngMagicBytes()
        try pngData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let repo = makeRepository()
        let resolved = try MeshyImageInput.filePath(tempURL.path).resolve(in: repo)
        #expect(resolved.sourceDescriptor == "file", "sourceDescriptor must not expose the raw path")
        #expect(!resolved.sourceDescriptor.contains(tempURL.path))
    }

    // MARK: (p) assetName not found returns validationFailed

    @Test("assetName for missing asset returns validationFailed")
    func assetNameNotFound() throws {
        let repo = makeRepository()
        do {
            _ = try MeshyImageInput.assetName("nonexistent").resolve(in: repo)
            Issue.record("Expected validationFailed")
        } catch MeshyError.validationFailed(let field, _) {
            #expect(field == "image_asset_name")
        }
    }
}
