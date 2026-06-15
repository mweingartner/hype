import AppKit
import Testing
@testable import HypeCore

@Suite("CardRenderer paint layers")
struct CardRendererPaintLayerTests {
    @Test func renderToImageIncludesCardPaintLayer() async throws {
        var document = HypeDocument.newDocument()
        let cardId = try #require(document.cards.first?.id)
        let redPixels = Data([255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255])
        document.setPaintLayer(CardPaintLayer(cardId: cardId, width: 2, height: 2, rgbaData: redPixels))

        let image = await MainActor.run {
            CardRenderer().renderToImage(
                document: document,
                cardId: cardId,
                size: NSSize(width: 2, height: 2)
            )
        }
        let data = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        let color = try #require(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))

        #expect(color.redComponent > 0.8)
        #expect(color.redComponent > color.greenComponent + 0.5)
        #expect(color.redComponent > color.blueComponent + 0.5)
        #expect(color.alphaComponent > 0.95)
    }

    @Test func renderToImageSkipsImportedPaintLayerImageWhenCardPaintLayerExists() async throws {
        var document = HypeDocument.newDocument()
        let cardId = try #require(document.cards.first?.id)
        document.stack.width = 2
        document.stack.height = 2
        let redPixels = Data([255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255])
        document.setPaintLayer(CardPaintLayer(cardId: cardId, width: 2, height: 2, rgbaData: redPixels))
        var importedPaintPart = Part(partType: .image, cardId: cardId, name: "Card 1 Paint Layer", left: 0, top: 0, width: 2, height: 2)
        importedPaintPart.imageData = try png(width: 2, height: 2, color: NSColor.blue)
        document.addPart(importedPaintPart)

        let image = await MainActor.run {
            CardRenderer().renderToImage(
                document: document,
                cardId: cardId,
                size: NSSize(width: 2, height: 2)
            )
        }
        let data = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        let color = try #require(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))

        #expect(color.redComponent > 0.8)
        #expect(color.blueComponent < 0.2)
    }

    @Test func renderToImageDoesNotSkipImportedPaintLayerImageForOpaqueBlackPlaceholderLayer() async throws {
        var document = HypeDocument.newDocument()
        let cardId = try #require(document.cards.first?.id)
        document.stack.width = 2
        document.stack.height = 2
        let blackPixels = Data(repeating: 0, count: 2 * 2 * 4).enumerated().map { index, value in
            index % 4 == 3 ? UInt8(255) : value
        }
        document.setPaintLayer(CardPaintLayer(cardId: cardId, width: 2, height: 2, rgbaData: Data(blackPixels)))
        var importedPaintPart = Part(partType: .image, cardId: cardId, name: "Card 1 Paint Layer", left: 0, top: 0, width: 2, height: 2)
        importedPaintPart.animated = false
        document.addPart(importedPaintPart)

        let image = await MainActor.run {
            CardRenderer().renderToImage(
                document: document,
                cardId: cardId,
                size: NSSize(width: 2, height: 2)
            )
        }
        let data = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        let color = try #require(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))

        #expect(color.redComponent > 0.4)
        #expect(color.greenComponent > 0.4)
        #expect(color.blueComponent > 0.4)
    }

    @Test func renderToImageSkipsImportedPaintLayerImageWhenFullCardHTChangePictExists() async throws {
        var document = HypeDocument.newDocument()
        let cardId = try #require(document.cards.first?.id)
        document.stack.width = 20
        document.stack.height = 20
        var importedPaintPart = Part(partType: .image, cardId: cardId, name: "Card 1 Paint Layer", sortKey: "a000000", left: 0, top: 0, width: 20, height: 20)
        importedPaintPart.visible = true
        importedPaintPart.animated = false
        importedPaintPart.transparentBackground = false
        importedPaintPart.imageData = try png(width: 20, height: 20, color: NSColor.blue)
        document.addPart(importedPaintPart)
        var replacement = Part(partType: .image, cardId: cardId, name: "HTChangePict PICT_1008", left: 0, top: 0, width: 20, height: 20)
        replacement.helpText = "hypercard-htchangepict"
        replacement.visible = true
        replacement.animated = false
        replacement.transparentBackground = false
        replacement.imageData = try png(width: 20, height: 20, color: NSColor.red)
        document.addPart(replacement)

        let parts = CardRenderer().renderableCardParts(
            document: document,
            cardId: cardId,
            size: NSSize(width: 20, height: 20)
        )

        #expect(parts.contains { $0.id == replacement.id })
        #expect(!parts.contains { $0.id == importedPaintPart.id })
    }

    private func png(width: Int, height: Int, color: NSColor) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ))
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(color, atX: x, y: y)
            }
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
