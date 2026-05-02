import Testing
import Foundation
@testable import HypeCore
#if canImport(AppKit)
import AppKit
#endif

/// CoreImage filter pass on Image parts. Tests focus on the model
/// + AI tool surface; the actual CIFilter render path is exercised
/// in one shape-test using a tiny in-memory image.
@Suite("Image filters — Part fields, AI tool, render passthrough")
struct ImageFilterTests {

    @Test("Defaults: empty filter, 0.7 intensity")
    func defaults() {
        let part = Part(partType: .image, name: "photo")
        #expect(part.imageFilter == "")
        #expect(part.imageFilterIntensity == 0.7)
    }

    @Test("Image filter fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .image, name: "photo")
        part.imageFilter = "sepia"
        part.imageFilterIntensity = 0.4
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.imageFilter == "sepia")
        #expect(decoded.imageFilterIntensity == 0.4)
    }

    @Test("set_image_filter AI tool writes filter + intensity on the image part")
    func aiSetFilter() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .image, cardId: cardId, name: "photo", left: 0, top: 0, width: 100, height: 100)
        doc.addPart(part)
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_image_filter",
            arguments: ["image_name": "photo", "filter": "blur", "intensity": "0.5"],
            document: &doc, currentCardId: cardId
        )
        let updated = doc.parts.first { $0.partType == .image }
        #expect(updated?.imageFilter == "blur")
        #expect(updated?.imageFilterIntensity == 0.5)
    }

    @Test("set_image_filter 'none' clears the filter back to empty string")
    func aiClearFilter() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .image, cardId: cardId, name: "photo", left: 0, top: 0, width: 100, height: 100)
        part.imageFilter = "sepia"
        doc.addPart(part)
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_image_filter",
            arguments: ["image_name": "photo", "filter": "none"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .image }?.imageFilter == "")
    }

    @Test("set_image_filter rejects non-image parts gracefully")
    func aiRejectNonImage() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        // No image part; the call should return a "not found" string,
        // never crash.
        let result = await executor.execute(
            toolName: "set_image_filter",
            arguments: ["image_name": "ghost", "filter": "sepia"],
            document: &doc, currentCardId: cardId
        )
        #expect(result.contains("not found"))
    }

    @Test("Intensity is clamped to 0..1 even when AI passes out-of-range values")
    func aiClampIntensity() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .image, cardId: cardId, name: "photo", left: 0, top: 0, width: 100, height: 100)
        doc.addPart(part)
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_image_filter",
            arguments: ["image_name": "photo", "filter": "blur", "intensity": "5.0"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .image }?.imageFilterIntensity == 1.0)

        _ = await executor.execute(
            toolName: "set_image_filter",
            arguments: ["image_name": "photo", "filter": "blur", "intensity": "-2.0"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .image }?.imageFilterIntensity == 0.0)
    }

    #if canImport(AppKit)
    @Test("ImageFilter.apply returns the original CGImage when filter name is empty/unknown")
    func applyReturnsOriginalForUnknownFilter() {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        guard let original = bitmap.cgImage else {
            Issue.record("could not build CGImage for test")
            return
        }
        let result = ImageFilter.apply("not-a-real-filter", intensity: 0.5, to: original)
        #expect(result === original)
    }

    @Test("ImageFilter.apply produces a different CGImage when filter name is recognized")
    func applyProducesNewImageForRecognizedFilter() {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        guard let original = bitmap.cgImage else {
            Issue.record("could not build CGImage for test")
            return
        }
        let result = ImageFilter.apply("sepia", intensity: 0.7, to: original)
        // We don't pin a specific identity (cache may reuse), but
        // the filtered CGImage's color components shouldn't match
        // an empty in-memory bitmap byte-for-byte under sepia.
        // The cheapest assertion is that the bytes differ —
        // CGImageGetDataProvider gives us that.
        let originalBytes = original.dataProvider?.data
        let resultBytes = result.dataProvider?.data
        #expect(originalBytes != resultBytes)
    }
    #endif

    @Test("HypeTalk parser accepts `the imageFilter of image \"X\"`")
    func hypeTalkImageFilter() throws {
        let source = "the imageFilter of image \"photo\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, _) = expr {
            #expect(prop == "imageFilter")
        } else {
            Issue.record("expected propertyAccess(imageFilter, ...), got \(expr)")
        }
    }
}
