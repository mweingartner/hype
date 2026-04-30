import Testing
import Foundation
@testable import HypeCore

#if canImport(AppKit)
import AppKit
import CoreGraphics
#endif

/// Coverage for the image / GIF transparent-background flag:
/// model field, codable round-trip, HypeTalk get/set, AI tool
/// surface, and the ImageChromaKey pixel walk.
@Suite("Image / GIF transparent background — model + chroma-key + AI")
struct TransparentBackgroundTests {

    // MARK: - Model

    @Test("Part defaults transparentBackground to false")
    func partDefaultsFalse() {
        let p = Part(partType: .image)
        #expect(p.transparentBackground == false)
    }

    @Test("Part round-trips transparentBackground through Codable")
    func partRoundTrips() throws {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var p = Part(partType: .image, cardId: cardId, name: "logo")
        p.transparentBackground = true
        doc.addPart(p)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: data)
        let recovered = decoded.parts.first(where: { $0.name == "logo" })
        #expect(recovered?.transparentBackground == true)
    }

    @Test("Old document without transparentBackground decodes with false")
    func backwardCompatDecode() throws {
        // Encode a doc, drop the field from the resulting JSON,
        // re-decode. Simulates a pre-feature .hype file.
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .image, cardId: cardId, name: "logo"))
        var dict = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(doc)
        ) as! [String: Any]
        var parts = dict["parts"] as! [[String: Any]]
        parts[0].removeValue(forKey: "transparentBackground")
        dict["parts"] = parts
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: stripped)
        #expect(decoded.parts[0].transparentBackground == false)
    }

    // MARK: - HypeTalk

    @Test("AI set_part_property accepts transparentBackground")
    func aiSetPartPropertyTransparentBackground() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .image, cardId: cardId, name: "logo"))
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "logo",
                "property": "transparentBackground",
                "value": "true",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.first(where: { $0.name == "logo" })?.transparentBackground == true)
    }

    @Test("AI set_part_property accepts the 'transparent' synonym")
    func aiSynonymTransparent() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.addPart(Part(partType: .image, cardId: cardId, name: "logo"))
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "logo",
                "property": "transparent",  // synonym
                "value": "true",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(doc.parts.first(where: { $0.name == "logo" })?.transparentBackground == true)
    }

    @Test("AI get_part_property reads transparentBackground")
    func aiGetPartPropertyTransparentBackground() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var p = Part(partType: .image, cardId: cardId, name: "logo")
        p.transparentBackground = true
        doc.addPart(p)

        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "logo", "property": "transparentBackground"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(result.lowercased().contains("true"),
                "expected true in result, got \(result)")
    }

    // MARK: - Chroma-key

    #if canImport(AppKit)

    /// Build an 8x8 CGImage whose outer ring is pure white and a
    /// 2x2 red square sits dead-center — the canonical "logo with
    /// white background" shape. Chroma-keying samples corner
    /// pixels at `(1, 1)` etc. (1-pixel inset to avoid edge
    /// anti-aliasing), so the image must be large enough that the
    /// inset corners are still in the white ring.
    private static func makeWhiteBackedLogoImage() -> CGImage? {
        let w = 8, h = 8
        let bpc = 8
        let bpr = w * 4
        let bitmap: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: bpc, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmap
        ) else { return nil }
        // Fill white over the whole image
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // 2x2 red center — well away from corner sample points
        // (1,1), (6,1), (1,6), (6,6).
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 3, y: 3, width: 2, height: 2))
        return ctx.makeImage()
    }

    private static func alpha(of image: CGImage, x: Int, y: Int) -> UInt8? {
        let w = image.width, h = image.height
        guard x >= 0, x < w, y >= 0, y < h else { return nil }
        let bpr = w * 4
        let bitmap: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmap
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let buf = ctx.data else { return nil }
        let pixels = buf.bindMemory(to: UInt8.self, capacity: bpr * h)
        return pixels[y * bpr + x * 4 + 3]  // alpha channel
    }

    @Test("ImageChromaKey zeros alpha on the matched corner color and preserves the body pixels")
    func chromaKeyMasksCornerColor() {
        guard let source = Self.makeWhiteBackedLogoImage() else {
            Issue.record("could not synthesize source image")
            return
        }
        let masked = ImageChromaKey.apply(to: source)

        // White ring pixels should now be alpha 0.
        #expect(Self.alpha(of: masked, x: 0, y: 0) == 0,
                "top-left ring pixel should be transparent")
        #expect(Self.alpha(of: masked, x: 7, y: 0) == 0,
                "top-right ring pixel should be transparent")
        #expect(Self.alpha(of: masked, x: 0, y: 7) == 0,
                "bottom-left ring pixel should be transparent")
        #expect(Self.alpha(of: masked, x: 7, y: 7) == 0,
                "bottom-right ring pixel should be transparent")

        // The 2x2 red center should keep full alpha.
        #expect(Self.alpha(of: masked, x: 3, y: 3) == 255,
                "red center pixel (3,3) should remain opaque")
        #expect(Self.alpha(of: masked, x: 4, y: 4) == 255,
                "red center pixel (4,4) should remain opaque")
    }

    @Test("ImageChromaKey caches the result — second call returns the same CGImage instance")
    func chromaKeyCachesByPointer() {
        guard let source = Self.makeWhiteBackedLogoImage() else {
            Issue.record("could not synthesize source image")
            return
        }
        let first = ImageChromaKey.apply(to: source)
        let second = ImageChromaKey.apply(to: source)
        // CGImage is a CFType — pointer equality means cache hit.
        #expect(first === second,
                "second apply() should reuse the cached masked image")
    }

    #endif
}
