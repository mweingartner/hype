import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import HypeCore

@Suite("HyperCard External Isolation Tests", .serialized)
struct HyperCardExternalIsolationTests {
    @Test func isolatedXMemoryReturnsValueAndRuntimeGlobalsWithoutStackScript() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xMemory",
            kind: .xfcn,
            arguments: ["1"]
        )

        #expect(result.value == "16777216")
        #expect(result.result == "16777216")
        #expect(result.runtimeGlobals["hypercard.xmemory.query"] == "1")
        #expect(result.runtimeGlobals["hypercard.xmemory.value"] == "16777216")
        #expect(result.modifiedDocument == nil)
    }

    @Test func isolatedHTVisualExposesTransitionIntentAndArguments() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTVisual",
            arguments: ["wipe right", "", "10,20,30,40", "1", "32"]
        )

        #expect(result.value == "wipe right")
        #expect(result.result == "wipe right")
        #expect(result.visualEffect == "wipe right")
        #expect(result.visualEffectDuration != nil)
        #expect(result.runtimeGlobals["hypercard.htvisual.effect"] == "wipe right")
        #expect(result.runtimeGlobals["hypercard.htvisual.arguments"] == "wipe right\t\t10,20,30,40\t1\t32")
    }

    @Test func isolatedXSetSoundVolClampsInputAndReportsRuntimeState() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xSetSoundVol",
            arguments: ["300"]
        )

        #expect(result.value == "255")
        #expect(result.result == "255")
        #expect(result.runtimeGlobals["hypercard.sound.volume"] == "255")
        #expect(result.runtimeGlobals["hypercard.xsetsoundvol.arguments"] == "300")
        #expect(result.modifiedDocument != nil)
    }

    @Test func isolatedXGetSoundVolDefaultsAndReadsRuntimeState() async {
        let defaultResult = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xGetSoundVol",
            kind: .xfcn
        )
        #expect(defaultResult.value == "255")
        #expect(defaultResult.result == "255")
        #expect(defaultResult.runtimeGlobals["hypercard.sound.volume"] == "255")

        var document = HypeDocument.newDocument(name: "Sound Volume Test")
        document.scriptGlobals["hypercard.sound.volume"] = "42"
        let storedResult = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xGetSoundVol",
            kind: .xfcn,
            document: document
        )
        #expect(storedResult.value == "42")
        #expect(storedResult.result == "42")
        #expect(storedResult.runtimeGlobals["hypercard.sound.volume"] == "42")
    }

    @Test func isolatedSetModeRecordsDisplayModeAndDepthIntent() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "SetMode",
            arguments: ["C", "7.6"]
        )

        #expect(result.value == "")
        #expect(result.result == "")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals["hypercard.display.mode"] == "c")
        #expect(result.runtimeGlobals["hypercard.display.depth"] == "8")
        #expect(result.runtimeGlobals["hypercard.display.value"] == "c,8")
        #expect(result.runtimeGlobals["hypercard.setmode.arguments"] == "C\t7.6")
    }

    @Test func isolatedGetModeReadsStoredDisplayState() async {
        var document = HypeDocument.newDocument(name: "GetMode Test")
        document.scriptGlobals["hypercard.setmode.mode"] = "bw"
        document.scriptGlobals["hypercard.setmode.depth"] = "1"

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "GetMode",
            kind: .xfcn,
            document: document
        )

        #expect(result.value == "bw,1")
        #expect(result.result == "bw,1")
        #expect(result.runtimeGlobals["hypercard.setmode.mode"] == "bw")
        #expect(result.runtimeGlobals["hypercard.setmode.depth"] == "1")
        #expect(result.runtimeGlobals["hypercard.setmode.value"] == "bw,1")
    }

    @Test func isolatedXVirtualReportsDeterministicDisabledVirtualMemory() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xVirtual",
            kind: .xfcn,
            arguments: ["query"]
        )

        #expect(result.value == "0")
        #expect(result.result == "0")
        #expect(result.runtimeGlobals["hypercard.xvirtual.value"] == "0")
        #expect(result.runtimeGlobals["hypercard.xvirtual.arguments"] == "query")
    }

    @Test func isolatedXDepthReadsDisplayDepthState() async {
        var document = HypeDocument.newDocument(name: "xDepth Test")
        document.scriptGlobals["hypercard.setmode.depth"] = "4"

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xDepth",
            kind: .xfcn,
            document: document
        )

        #expect(result.value == "4")
        #expect(result.result == "4")
        #expect(result.runtimeGlobals["hypercard.xdepth.value"] == "4")
        #expect(result.runtimeGlobals["hypercard.setmode.depth"] == "4")
    }

    @Test func isolatedVariantReportsClassicCompatibilityVersion() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "variant",
            kind: .xfcn,
            arguments: ["long"]
        )

        #expect(result.value == "2.1")
        #expect(result.result == "2.1")
        #expect(result.runtimeGlobals["hypercard.variant.value"] == "2.1")
        #expect(result.runtimeGlobals["hypercard.variant.arguments"] == "long")
    }

    @Test func isolatedXAboutRecordsDialogIntentWithoutShowingModalUI() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xAbout",
            arguments: ["Myst", "1", "install"]
        )

        #expect(result.value == "")
        #expect(result.result == "")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals["hypercard.xabout.invoked"] == "true")
        #expect(result.runtimeGlobals["hypercard.xabout.arguments"] == "Myst\t1\tinstall")
    }

    @Test func isolatedHTLockNormalizesScreenLockIntent() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTLock",
            arguments: ["off"]
        )

        #expect(result.value == "false")
        #expect(result.result == "false")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals["hypercard.htlock.mode"] == "false")
        #expect(result.runtimeGlobals["hypercard.htlock.arguments"] == "off")
    }

    @Test func isolatedDeCurseRecordsCursorResourceIntent() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "DeCurse",
            arguments: ["cursor", "3000", "cicn", "animated"]
        )

        #expect(result.value == "cursor")
        #expect(result.result == "cursor")
        #expect(result.runtimeGlobals["hypercard.decurse.mode"] == "cursor")
        #expect(result.runtimeGlobals["hypercard.decurse.resource"] == "3000")
        #expect(result.runtimeGlobals["hypercard.decurse.kind"] == "cicn")
        #expect(result.runtimeGlobals["hypercard.decurse.options"] == "animated")
    }

    @Test func isolatedMoveCursorRecordsGlobalCursorPositionIntent() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "moveCursor",
            arguments: ["101", "202"]
        )

        #expect(result.value == "101,202")
        #expect(result.result == "101,202")
        #expect(result.runtimeGlobals["hypercard.movecursor.x"] == "101")
        #expect(result.runtimeGlobals["hypercard.movecursor.y"] == "202")
        #expect(result.runtimeGlobals["hypercard.movecursor.loc"] == "101,202")
        #expect(result.runtimeGlobals["hypercard.cursor.mode"] == "move")
    }

    @Test func isolatedXClipRecordsQuickDrawClipRectIntent() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xClip",
            arguments: ["10,20,110,220"]
        )

        #expect(result.value == "10,20,110,220")
        #expect(result.result == "10,20,110,220")
        #expect(result.runtimeGlobals["hypercard.xclip.rect"] == "10,20,110,220")
        #expect(result.runtimeGlobals["hypercard.quickdraw.clipRect"] == "10,20,110,220")
        #expect(result.runtimeGlobals["hypercard.xclip.arguments"] == "10,20,110,220")
        #expect(result.modifiedDocument == nil)
    }

    @Test func isolatedXLineRendersClippedQuickDrawLineIntoCardPaintLayer() async throws {
        var document = HypeDocument.newDocument(name: "xLine Test")
        document.scriptGlobals["hypercard.quickdraw.clipRect"] = "2,0,4,1"

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xLine",
            arguments: ["0,0", "5,0", "1", "200"],
            document: document
        )

        #expect(result.value == "0,0,5,0,1,200")
        #expect(result.result == "0,0,5,0,1,200")
        #expect(result.runtimeGlobals["hypercard.xline.start"] == "0,0")
        #expect(result.runtimeGlobals["hypercard.xline.end"] == "5,0")
        #expect(result.runtimeGlobals["hypercard.xline.penSize"] == "1")
        #expect(result.runtimeGlobals["hypercard.xline.color"] == "200")
        #expect(result.runtimeGlobals["hypercard.xline.renderedPixels"] == "2")

        let modifiedDocument = try #require(result.modifiedDocument)
        let cardId = try #require(modifiedDocument.cards.first?.id)
        let layer = try #require(modifiedDocument.paintLayer(forCardId: cardId))
        let data = layer.normalizedRGBAData
        let pixel2 = 2 * 4
        let pixel3 = 3 * 4
        #expect(data[pixel2] == 200)
        #expect(data[pixel2 + 1] == 200)
        #expect(data[pixel2 + 2] == 200)
        #expect(data[pixel2 + 3] == 255)
        #expect(data[pixel3] == 200)
        #expect(data[pixel3 + 1] == 200)
        #expect(data[pixel3 + 2] == 200)
        #expect(data[pixel3 + 3] == 255)
        #expect(data[0] == 0)
        #expect(data[4] == 0)
        #expect(data[16] == 0)
    }

    @Test func isolatedXLineUsesActivePaletteColorGlobals() async throws {
        var document = HypeDocument.newDocument(name: "xLine Palette Test")
        document.scriptGlobals["hypercard.htudefpal.colors"] = "#010203\t#A0B0C0"

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xLine",
            arguments: ["0,0", "0,0", "1", "1"],
            document: document
        )

        #expect(result.runtimeGlobals["hypercard.xline.color"] == "1")
        #expect(result.runtimeGlobals["hypercard.xline.renderedPixels"] == "1")

        let modifiedDocument = try #require(result.modifiedDocument)
        let cardId = try #require(modifiedDocument.cards.first?.id)
        let layer = try #require(modifiedDocument.paintLayer(forCardId: cardId))
        let data = layer.normalizedRGBAData
        #expect(data[0] == 0xA0)
        #expect(data[1] == 0xB0)
        #expect(data[2] == 0xC0)
        #expect(data[3] == 255)
    }

    @Test func isolatedHTChangePictUsesSyntheticDocumentAssets() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let asset = Asset(
            name: "finalBookOpen Myst",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 544,
            height: 332,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "finalBookOpen Myst"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("finalBookOpen Myst"))
            ]
        )
        var document = HypeDocument.newDocument(name: "External Asset Test")
        document.assetRepository = AssetRepository(assets: [asset])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTChangePict",
            arguments: ["finalBookOpen Myst", "srcCopy"],
            document: document
        )

        #expect(result.value == "finalBookOpen Myst")
        #expect(result.result == "finalBookOpen Myst")
        #expect(result.runtimeGlobals["hypercard.htchangepict.asset"] == "finalBookOpen Myst")
        #expect(result.runtimeGlobals["hypercard.htchangepict.transferMode"] == "srcCopy")

        let modifiedDocument = try #require(result.modifiedDocument)
        let replacement = try #require(modifiedDocument.parts.first { part in
            part.partType == .image && part.name == "HTChangePict finalBookOpen Myst"
        })
        #expect(replacement.left == 0)
        #expect(replacement.top == 0)
        #expect(Int(replacement.width) == modifiedDocument.stack.width)
        #expect(Int(replacement.height) == modifiedDocument.stack.height)
        #expect(replacement.imageData == imageData)
    }

    @Test func isolatedHTChangePictDrawsDecodedImageIntoCardViewport() async throws {
        let imageData = try png(width: 1, height: 1, rgba: [200, 40, 10, 255])
        let asset = Asset(
            name: "bookClosed",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 1,
            height: 1,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "bookClosed")]
        )
        var document = HypeDocument.newDocument(name: "HTChangePict Viewport Test")
        document.assetRepository = AssetRepository(assets: [asset])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTChangePict",
            arguments: ["bookClosed"],
            document: document
        )

        #expect(result.value == "bookClosed")
        #expect(result.runtimeGlobals["hypercard.htchangepict.transferMode"] == "srcCopy")
        #expect(result.runtimeGlobals["hypercard.htchangepict.outputSurface"] == "cardPaintLayer")
        #expect(result.runtimeGlobals["hypercard.htchangepict.compositedPixels"] == String(document.stack.width * document.stack.height))

        let modifiedDocument = try #require(result.modifiedDocument)
        let cardId = try #require(modifiedDocument.cards.first?.id)
        let layer = try #require(modifiedDocument.paintLayer(forCardId: cardId))
        let layerData = layer.normalizedRGBAData
        #expect(layer.width == modifiedDocument.stack.width)
        #expect(layer.height == modifiedDocument.stack.height)
        #expect(layerData[0] == 200)
        #expect(layerData[1] == 40)
        #expect(layerData[2] == 10)
        #expect(layerData[3] == 255)

        let replacement = try #require(modifiedDocument.parts.first { $0.helpText == "hypercard-htchangepict" })
        #expect(replacement.visible == false)
    }

    @Test func isolatedHTAddPictCreatesTransparentOverlayFromAsset() async throws {
        let imageData = try png(width: 1, height: 1, rgba: [90, 80, 70, 255])
        let asset = Asset(
            name: "overlay-pict",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 1,
            height: 1,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "overlay")]
        )
        var document = HypeDocument.newDocument(name: "HTAddPict Test")
        document.assetRepository = AssetRepository(assets: [asset])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTAddPict",
            arguments: ["overlay", "10,20,11,21", "srcOr"],
            document: document
        )

        #expect(result.value == "overlay-pict")
        #expect(result.runtimeGlobals["hypercard.htaddpict.asset"] == "overlay-pict")
        #expect(result.runtimeGlobals["hypercard.htaddpict.transferMode"] == "srcOr")

        let modifiedDocument = try #require(result.modifiedDocument)
        let overlay = try #require(modifiedDocument.parts.first { $0.helpText == "hypercard-htaddpict" })
        #expect(overlay.name == "HTAddPict overlay-pict")
        #expect(overlay.left == 10)
        #expect(overlay.top == 20)
        #expect(overlay.width == 1)
        #expect(overlay.height == 1)
        #expect(overlay.transparentBackground == true)
        #expect(overlay.imageData == imageData)
    }

    @Test func isolatedHTChangePictMissingAssetReportsDiagnostic() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTChangePict",
            arguments: ["missing-book"]
        )

        #expect(result.value == "")
        #expect(result.result == "Picture asset not found: missing-book")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals["hypercard.htchangepict.asset"] == "")
        #expect(result.runtimeGlobals["hypercard.htchangepict.arguments"] == "missing-book")
    }

    @Test func isolatedHTAddPictCropsDecodedSourceRect() async throws {
        let imageData = try png(
            width: 2,
            height: 2,
            rgba: [
                10, 20, 30, 255, 40, 50, 60, 255,
                70, 80, 90, 255, 100, 110, 120, 255,
            ]
        )
        let asset = Asset(
            name: "four-pixel-pict",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 2,
            height: 2,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "fourPixel")]
        )
        var document = HypeDocument.newDocument(name: "HTAddPict Crop Test")
        document.assetRepository = AssetRepository(assets: [asset])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTAddPict",
            arguments: ["fourPixel", "0,0,1,1", "srcCopy", "srcRect", "1,0,2,1"],
            document: document
        )

        #expect(result.value == "four-pixel-pict")
        #expect(result.runtimeGlobals["hypercard.htaddpict.sourceRect"] == "1,0,2,1")

        let modifiedDocument = try #require(result.modifiedDocument)
        let overlay = try #require(modifiedDocument.parts.first { $0.helpText == "hypercard-htaddpict" })
        let dimensions = try #require(PNGEncoding.imageDimensions(data: overlay.imageData ?? Data()))
        #expect(dimensions.width == 1)
        #expect(dimensions.height == 1)
    }

    @Test func isolatedHTAddPictRestoresCapturedClipboardAndRemovesIntersectingOverlay() async throws {
        let clipboardData = try png(width: 1, height: 1, rgba: [1, 2, 3, 255])
        let clipboard = Asset(
            name: "clipboard",
            kind: .imageTexture,
            mimeType: "image/png",
            data: clipboardData,
            width: 1,
            height: 1,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "clipboard"),
                AssetMetadataEntry(key: "lookup_key", value: "clipboard"),
                AssetMetadataEntry(key: "hypercard_compatibility_role", value: "clipboard"),
            ]
        )
        var document = HypeDocument.newDocument(name: "HTAddPict Clipboard Test")
        let cardId = try #require(document.cards.first?.id)
        var oldOverlay = Part(partType: .image, cardId: cardId, name: "old overlay", left: 0, top: 0, width: 20, height: 20)
        oldOverlay.helpText = "hypercard-htaddpict"
        document.parts = [oldOverlay]
        document.assetRepository = AssetRepository(assets: [clipboard])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTAddPict",
            arguments: ["", "0,0,10,10", "clipboard"],
            document: document
        )

        #expect(result.value == "clipboard")
        #expect(result.result == "clipboard")
        #expect(result.runtimeGlobals["hypercard.htaddpict.clipboardRect"] == "0,0,10,10")
        #expect(result.runtimeGlobals["hypercard.htaddpict.removedOverlayCount"] == "1")
        #expect(result.runtimeGlobals["hypercard.htaddpict.restoredClipboardAsset"] == "clipboard")

        let modifiedDocument = try #require(result.modifiedDocument)
        #expect(modifiedDocument.parts.count == 1)
        let restored = try #require(modifiedDocument.parts.first)
        #expect(restored.name == "HTAddPict Clipboard")
        #expect(restored.imageData == clipboardData)
    }

    @Test func isolatedHTSavePictCapturesPaintLayerRectToClipboardAsset() async throws {
        var document = HypeDocument.newDocument(name: "HTSavePict Test")
        let cardId = try #require(document.cards.first?.id)
        document.setPaintLayer(CardPaintLayer(
            cardId: cardId,
            width: 2,
            height: 1,
            rgbaData: Data([10, 20, 30, 255, 40, 50, 60, 255])
        ))

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTSavePict",
            arguments: ["1,0,2,1", "clipboard", "srcCopy"],
            document: document
        )

        #expect(result.value == "clipboard")
        #expect(result.result == "")
        #expect(result.runtimeGlobals["hypercard.htsavepict.destination"] == "clipboard")
        #expect(result.runtimeGlobals["hypercard.htsavepict.rect"] == "1,0,2,1")
        #expect(result.runtimeGlobals["hypercard.htsavepict.transferMode"] == "srcCopy")
        #expect(result.runtimeGlobals["hypercard.htsavepict.captured"] == "true")
        #expect(result.runtimeGlobals["hypercard.htsavepict.width"] == "1")
        #expect(result.runtimeGlobals["hypercard.htsavepict.height"] == "1")

        let modifiedDocument = try #require(result.modifiedDocument)
        let clipboard = try #require(modifiedDocument.assetRepository.asset(byClassicMediaName: "clipboard", kind: .imageTexture))
        #expect(clipboard.name == "clipboard")
        #expect(clipboard.width == 1)
        #expect(clipboard.height == 1)
        #expect(clipboard.tags.contains("clipboard"))
        #expect(clipboard.metadata.contains { $0.key == "source_rect" && $0.value == "1,0,2,1" })
    }

    @Test func isolatedHTRemoveDeletesCompatibilityOverlayParts() async throws {
        var document = HypeDocument.newDocument(name: "HTRemove Test")
        let cardId = try #require(document.cards.first?.id)
        var removable = Part(partType: .image, cardId: cardId, name: "overlay")
        removable.helpText = "hypercard-htaddpict"
        var retained = Part(partType: .image, cardId: cardId, name: "normal")
        retained.helpText = "user image"
        document.parts = [removable, retained]

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTRemove",
            arguments: ["all"],
            document: document
        )

        #expect(result.value == "1")
        #expect(result.result == "1")
        #expect(result.runtimeGlobals["hypercard.htremove.removedCount"] == "1")
        #expect(result.runtimeGlobals["hypercard.htremove.arguments"] == "all")

        let modifiedDocument = try #require(result.modifiedDocument)
        #expect(modifiedDocument.parts.count == 1)
        #expect(modifiedDocument.parts.first?.name == "normal")
    }

    @Test func isolatedHTUDefPalParsesImportedPalettePayload() async throws {
        let paletteData = Data(#"{"entries":[{"red":0,"green":32768,"blue":65535},{"red":65535,"green":0,"blue":0}]}"#.utf8)
        let palette = Asset(
            name: "PLTE 128",
            kind: .document,
            mimeType: "application/json",
            data: paletteData,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "plte"),
                AssetMetadataEntry(key: "resource_id", value: "128"),
                AssetMetadataEntry(key: "resource_path", value: "palette/128.json")
            ]
        )
        var document = HypeDocument.newDocument(name: "HTUDefPal Test")
        document.assetRepository = AssetRepository(assets: [palette])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTUDefPal",
            arguments: ["128"],
            document: document
        )

        #expect(result.value == "128")
        #expect(result.result == "")
        #expect(result.runtimeGlobals["hypercard.htudefpal.status"] == "resolved")
        #expect(result.runtimeGlobals["hypercard.htudefpal.assetName"] == "PLTE 128")
        #expect(result.runtimeGlobals["hypercard.htudefpal.payloadStatus"] == "parsed")
        #expect(result.runtimeGlobals["hypercard.htudefpal.colorCount"] == "2")
        #expect(result.runtimeGlobals["hypercard.htudefpal.firstColor"] == "#0080FF")
        #expect(result.runtimeGlobals["hypercard.htudefpal.lastColor"] == "#FF0000")
        #expect(result.runtimeGlobals["hypercard.htudefpal.resourceType"] == "plte")
        #expect(result.runtimeGlobals["hypercard.htudefpal.resourcePath"] == "palette/128.json")
    }

    @Test func isolatedHTUDefPalReportsMissingPaletteResource() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTUDefPal",
            arguments: ["999"]
        )

        #expect(result.value == "999")
        #expect(result.result == "")
        #expect(result.runtimeGlobals["hypercard.htudefpal.palette"] == "999")
        #expect(result.runtimeGlobals["hypercard.htudefpal.status"] == "missing")
    }

    @Test func isolatedHyperTintRecordsTimingDelayAndOptions() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HyperTint",
            arguments: ["fast", "3", "rect", "10,20,30,40"]
        )

        #expect(result.value == "")
        #expect(result.result == "")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals["hypercard.hypertint.timing"] == "fast")
        #expect(result.runtimeGlobals["hypercard.hypertint.delay"] == "3")
        #expect(result.runtimeGlobals["hypercard.hypertint.options"] == "rect\t10,20,30,40")
    }

    @Test func isolatedHTTB1TSRecordsTempBufferCopyIntent() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTTB1TS",
            arguments: ["10,20,30,40", "1,2,3,4", "srcXor", "noVBL"]
        )

        #expect(result.value == "10,20,30,40")
        #expect(result.result == "10,20,30,40")
        #expect(result.runtimeGlobals["hypercard.httb1ts.count"] == "1")
        #expect(result.runtimeGlobals["hypercard.httb1ts.destinationRect"] == "10,20,30,40")
        #expect(result.runtimeGlobals["hypercard.httb1ts.sourceRect"] == "1,2,3,4")
        #expect(result.runtimeGlobals["hypercard.httb1ts.transferMode"] == "srcXor")
        #expect(result.runtimeGlobals["hypercard.httb1ts.vbl"] == "false")
    }

    @Test func isolatedHTTB1TSMalformedRectsFallbackToIntentOnlyDefaults() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTTB1TS",
            arguments: ["not-a-rect", "also-not-a-rect"]
        )

        #expect(result.value == "")
        #expect(result.result == "")
        #expect(result.runtimeGlobals["hypercard.httb1ts.count"] == "1")
        #expect(result.runtimeGlobals["hypercard.httb1ts.transferMode"] == "srcCopy")
        #expect(result.runtimeGlobals["hypercard.httb1ts.vbl"] == "auto")
        #expect(result.runtimeGlobals["hypercard.httb1ts.destinationRect"] == nil)
        #expect(result.runtimeGlobals["hypercard.httb1ts.sourceRect"] == nil)
    }

    @Test func visibleEvidenceProbeCapturesExternalTraceAndPaintMediaState() async throws {
        let imageData = try png(width: 1, height: 1, rgba: [210, 20, 30, 255])
        let image = Asset(
            name: "probe-pict",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 1,
            height: 1,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "probePict")]
        )
        let movie = Asset(
            name: "probe-movie.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 160,
            height: 90,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "probeMovie")]
        )
        var document = HypeDocument.newDocument(name: "Visible Evidence Probe")
        document.assetRepository = AssetRepository(assets: [image, movie])

        let pictResult = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HTChangePict",
            arguments: ["probePict"],
            document: document
        )
        let pictDocument = try #require(pictResult.modifiedDocument)
        let tintResult = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "HyperTint",
            arguments: ["fast", "2", "rect", "0,0,1,1"],
            document: pictDocument
        )
        let movieResult = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "Movie",
            arguments: ["probeMovie", "borderless", "12,34", "visible", "ProbeWindow"],
            document: pictDocument
        )

        let cardId = try #require(pictDocument.cards.first?.id)
        let layer = try #require(pictDocument.paintLayer(forCardId: cardId))
        let layerData = layer.normalizedRGBAData
        #expect(layerData[0] == 210)
        #expect(layerData[1] == 20)
        #expect(layerData[2] == 30)
        #expect(layerData[3] == 255)

        let movieDocument = try #require(movieResult.modifiedDocument)
        let moviePart = try #require(movieDocument.parts.first { $0.partType == .video })
        #expect(moviePart.left == 12)
        #expect(moviePart.top == 34)
        #expect(moviePart.width == 160)
        #expect(moviePart.height == 90)

        let trace: [String: String] = [
            "htchangepict.asset": pictResult.runtimeGlobals["hypercard.htchangepict.asset"] ?? "",
            "htchangepict.outputSurface": pictResult.runtimeGlobals["hypercard.htchangepict.outputSurface"] ?? "",
            "htchangepict.compositedPixels": pictResult.runtimeGlobals["hypercard.htchangepict.compositedPixels"] ?? "",
            "hypertint.timing": tintResult.runtimeGlobals["hypercard.hypertint.timing"] ?? "",
            "hypertint.options": tintResult.runtimeGlobals["hypercard.hypertint.options"] ?? "",
            "movie.asset": movieResult.runtimeGlobals["hypercard.playqt.asset"] ?? "",
            "movie.rect": "\(Int(moviePart.left)),\(Int(moviePart.top)),\(Int(moviePart.left + moviePart.width)),\(Int(moviePart.top + moviePart.height))",
            "cardPaintLayer.size": "\(layer.width)x\(layer.height)",
        ]
        #expect(trace["htchangepict.asset"] == "probe-pict")
        #expect(trace["htchangepict.outputSurface"] == "cardPaintLayer")
        #expect(trace["hypertint.options"] == "rect\t0,0,1,1")
        #expect(trace["movie.asset"] == "probe-movie.mov")
        #expect(trace["movie.rect"] == "12,34,172,124")

        try writeVisibleEvidenceProbeArtifactsIfRequested(trace: trace, layer: layer)
    }

    @Test func isolatedPictureCreatesImageBackedCompatibilityWindow() async throws {
        let imageData = try png(width: 2, height: 1, rgba: [10, 20, 30, 255, 40, 50, 60, 255])
        let asset = Asset(
            name: "TowerScroll PICT",
            kind: .imageTexture,
            mimeType: "image/png",
            data: imageData,
            width: 640,
            height: 480,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "TowerScroll")]
        )
        var document = HypeDocument.newDocument(name: "Picture Window Test")
        document.assetRepository = AssetRepository(assets: [asset])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "Picture",
            arguments: ["TowerScroll", "resource", "rect", "false", "4"],
            document: document
        )

        #expect(result.value == "")
        #expect(result.result == "")
        #expect(result.runtimeGlobals["hypercard.picture.asset"] == "TowerScroll PICT")
        #expect(result.runtimeGlobals["hypercard.picture.window"] == "TowerScroll")
        #expect(result.runtimeGlobals["hypercard.picture.source"] == "resource")
        #expect(result.runtimeGlobals["hypercard.picture.visibleArgument"] == "false")
        #expect(result.runtimeGlobals["hypercard.picture.depth"] == "4")

        let windowKey = AssetRepository.classicMediaLookupKey("TowerScroll")
        #expect(result.runtimeGlobals["hypercard.window.\(windowKey).exists"] == "true")
        #expect(result.runtimeGlobals["hypercard.window.\(windowKey).visible"] == "false")
        #expect(result.runtimeGlobals["hypercard.window.\(windowKey).scroll"] == "0,0")

        let modifiedDocument = try #require(result.modifiedDocument)
        let picturePart = try #require(modifiedDocument.parts.first { $0.helpText == "hypercard-picture" })
        #expect(picturePart.partType == .image)
        #expect(picturePart.name == "TowerScroll")
        #expect(picturePart.visible == false)
        #expect(picturePart.imageData == imageData)
        #expect(Int(picturePart.width) == modifiedDocument.stack.width)
        #expect(Int(picturePart.height) == modifiedDocument.stack.height)
    }

    @Test func isolatedPictureMissingAssetReportsDiagnosticAndWindowState() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "Picture",
            arguments: ["MissingPict", "resource", "rect", "false"]
        )

        #expect(result.value == "")
        #expect(result.result == "Picture asset not found: MissingPict")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals["hypercard.picture.asset"] == "")
        #expect(result.runtimeGlobals["hypercard.picture.window"] == "MissingPict")
        let windowKey = AssetRepository.classicMediaLookupKey("MissingPict")
        #expect(result.runtimeGlobals["hypercard.window.\(windowKey).exists"] == "false")
        #expect(result.runtimeGlobals["hypercard.window.\(windowKey).visible"] == "false")
    }

    @Test func isolatedPictureEmptyNameReportsRequiredNameDiagnostic() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "Picture",
            arguments: ["   "]
        )

        #expect(result.value == "")
        #expect(result.result == "Picture requires a picture name")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals.isEmpty)
    }

    @Test func isolatedMovieCreatesRepositoryBackedVideoWindowAtClassicPoint() async throws {
        let movie = Asset(
            name: "MystLib.MooV-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 160,
            height: 90,
            metadata: [
                AssetMetadataEntry(key: "classic_name", value: "MystLib.MooV"),
                AssetMetadataEntry(key: "lookup_key", value: AssetRepository.classicMediaLookupKey("MystLib.MooV"))
            ]
        )
        var document = HypeDocument.newDocument(name: "Movie Window Test")
        document.assetRepository = AssetRepository(assets: [movie])
        document.scriptGlobals["hypercard.sound.volume"] = "128"

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "Movie",
            arguments: ["MystLib.MooV", "borderless", "230,173", "invisible", "Floating"],
            document: document
        )

        #expect(result.value == "MystLib.MooV-modern.mov")
        #expect(result.result == "MystLib.MooV-modern.mov")
        #expect(result.runtimeGlobals["hypercard.playqt.asset"] == "MystLib.MooV-modern.mov")
        #expect(result.runtimeGlobals["hypercard.playqt.audioOnly"] == "false")
        let windowKey = AssetRepository.classicMediaLookupKey("Floating")
        #expect(result.runtimeGlobals["hypercard.window.\(windowKey).movie"] == "MystLib.MooV")
        #expect(result.runtimeGlobals["hypercard.window.\(windowKey).exists"] == "true")

        let modifiedDocument = try #require(result.modifiedDocument)
        let video = try #require(modifiedDocument.parts.first { $0.partType == .video })
        #expect(video.name == "MystLib.MooV")
        #expect(video.left == 230)
        #expect(video.top == 173)
        #expect(video.width == 160)
        #expect(video.height == 90)
        #expect(video.videoAutoplay == true)
        #expect(video.videoLoop == false)
        #expect(video.videoVolume == 128.0 / 255.0)
        #expect(video.helpText.contains("hypercard-playqt"))
        #expect(video.helpText.contains("window=Floating"))
        #expect(video.videoAssetRef?.id == movie.id)
    }

    @Test func isolatedMovieMissingAssetReportsQuickTimeDiagnostic() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "Movie",
            arguments: ["Missing.MooV", "borderless", "230,173", "invisible", "Floating"]
        )

        #expect(result.value == "")
        #expect(result.result == "QuickTime asset not found: Missing.MooV")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals.isEmpty)
    }

    @Test func isolatedPlayQTCreatesLoopedRepositoryBackedVideoPart() async throws {
        let movie = Asset(
            name: "AtrusWrite-modern.mov",
            kind: .videoClip,
            mimeType: "video/quicktime",
            data: Data("movie".utf8),
            width: 120,
            height: 80,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "AtrusWrite")]
        )
        var document = HypeDocument.newDocument(name: "playQT Test")
        document.assetRepository = AssetRepository(assets: [movie])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "playQT",
            arguments: ["AtrusWrite", "", "loop", "30"],
            document: document
        )

        #expect(result.value == "AtrusWrite-modern.mov")
        #expect(result.result == "AtrusWrite-modern.mov")
        #expect(result.runtimeGlobals["hypercard.playqt.asset"] == "AtrusWrite-modern.mov")
        #expect(result.runtimeGlobals["hypercard.playqt.audioOnly"] == "false")
        #expect(result.runtimeGlobals["soundMooV"] == "AtrusWrite")

        let modifiedDocument = try #require(result.modifiedDocument)
        let video = try #require(modifiedDocument.parts.first { $0.partType == .video })
        #expect(video.name == "AtrusWrite")
        #expect(video.left == 0)
        #expect(video.top == 0)
        #expect(Int(video.width) == modifiedDocument.stack.width)
        #expect(Int(video.height) == modifiedDocument.stack.height)
        #expect(video.videoAutoplay == true)
        #expect(video.videoLoop == true)
        #expect(video.videoVolume == 1.0)
        #expect(video.helpText == "hypercard-playqt")
        #expect(video.videoAssetRef?.id == movie.id)
    }

    @Test func isolatedPlayQTAudioOnlyCreatesHiddenPlaybackPart() async throws {
        let audio = Asset(
            name: "Intro Wind Mov-modern-audio.m4a",
            kind: .videoClip,
            mimeType: "audio/mp4",
            data: Data("audio".utf8),
            width: 0,
            height: 0,
            metadata: [AssetMetadataEntry(key: "classic_name", value: "Intro Wind Mov")]
        )
        var document = HypeDocument.newDocument(name: "playQT Audio Test")
        document.assetRepository = AssetRepository(assets: [audio])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "playQT",
            arguments: ["Intro Wind Mov", "fadein", "loop", "255"],
            document: document
        )

        #expect(result.value == "Intro Wind Mov-modern-audio.m4a")
        #expect(result.runtimeGlobals["hypercard.playqt.audioOnly"] == "true")
        let modifiedDocument = try #require(result.modifiedDocument)
        let video = try #require(modifiedDocument.parts.first { $0.partType == .video })
        #expect(video.width == 1)
        #expect(video.height == 1)
        #expect(video.videoLoop == true)
        #expect(video.helpText.contains("audioOnly=true"))
    }

    @Test func isolatedPlayQTMissingAssetReportsQuickTimeDiagnostic() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "playQT",
            arguments: ["MissingMovie", "loop"]
        )

        #expect(result.value == "")
        #expect(result.result == "QuickTime asset not found: MissingMovie")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals.isEmpty)
    }

    @Test func isolatedXCIcon3CreatesCenteredTransparentIconOverlay() async throws {
        let iconData = try png(width: 1, height: 1, rgba: [0, 255, 0, 255])
        let icon = Asset(
            name: "cicn_3000",
            kind: .imageTexture,
            mimeType: "image/png",
            data: iconData,
            width: 16,
            height: 12,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "cicn"),
                AssetMetadataEntry(key: "resource_id", value: "3000")
            ]
        )
        var document = HypeDocument.newDocument(name: "xCIcon3 Test")
        document.assetRepository = AssetRepository(assets: [icon])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xCIcon3",
            arguments: ["20,30", "3000"],
            document: document
        )

        #expect(result.value == "cicn_3000")
        #expect(result.result == "cicn_3000")
        #expect(result.runtimeGlobals["hypercard.xcicon3.icon"] == "3000")
        #expect(result.runtimeGlobals["hypercard.xcicon3.asset"] == "cicn_3000")
        #expect(result.runtimeGlobals["hypercard.xcicon3.arguments"] == "20,30\t3000")

        let modifiedDocument = try #require(result.modifiedDocument)
        let overlay = try #require(modifiedDocument.parts.first { $0.helpText == "hypercard-xcicon3" })
        #expect(overlay.name == "xCIcon3 cicn_3000")
        #expect(overlay.left == 12)
        #expect(overlay.top == 24)
        #expect(overlay.width == 16)
        #expect(overlay.height == 12)
        #expect(overlay.transparentBackground == true)
        #expect(overlay.imageData == iconData)
    }

    @Test func isolatedXCIcon3MissingIconReportsDiagnostic() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xCIcon3",
            arguments: ["20,30", "9999"]
        )

        #expect(result.value == "")
        #expect(result.result == "Icon asset not found: 9999")
        #expect(result.modifiedDocument == nil)
        #expect(result.runtimeGlobals["hypercard.xcicon3.icon"] == "9999")
        #expect(result.runtimeGlobals["hypercard.xcicon3.arguments"] == "20,30\t9999")
    }

    @Test func isolatedXCIcon3ResolvesUppercaseIconResourceType() async throws {
        let iconData = try png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let icon = Asset(
            name: "ICON_4000",
            kind: .imageTexture,
            mimeType: "image/png",
            data: iconData,
            width: 8,
            height: 8,
            metadata: [
                AssetMetadataEntry(key: "resource_type", value: "ICON"),
                AssetMetadataEntry(key: "resource_id", value: "4000")
            ]
        )
        var document = HypeDocument.newDocument(name: "xCIcon3 ICON Test")
        document.assetRepository = AssetRepository(assets: [icon])

        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "xCIcon3",
            arguments: ["bad-loc", "4000"],
            document: document
        )

        #expect(result.value == "ICON_4000")
        #expect(result.result == "ICON_4000")
        #expect(result.runtimeGlobals["hypercard.xcicon3.asset"] == "ICON_4000")

        let modifiedDocument = try #require(result.modifiedDocument)
        let overlay = try #require(modifiedDocument.parts.first { $0.helpText == "hypercard-xcicon3" })
        #expect(overlay.left == 0)
        #expect(overlay.top == 0)
        #expect(overlay.width == 8)
        #expect(overlay.height == 8)
    }

    @Test func isolatedUnsupportedExternalReportsDiagnostic() async {
        let result = await HyperCardExternalRegistry.default.invokeIsolated(
            name: "DefinitelyMissingExternal",
            arguments: ["arg"]
        )

        #expect(result.value == "")
        #expect(result.result == "Can't Load External: XCMD 'DefinitelyMissingExternal' is not available in Hype.")
        #expect(result.diagnostic == result.result)
        #expect(result.modifiedDocument == nil)
    }

    private func png(width: Int, height: Int, rgba: [UInt8]) throws -> Data {
        var data = Data(rgba)
        let image = try data.withUnsafeMutableBytes { rawBuffer -> CGImage in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let image = context.makeImage() else {
                throw TestPNGError.creationFailed
            }
            return image
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw TestPNGError.creationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestPNGError.creationFailed
        }
        return output as Data
    }

    private func writeVisibleEvidenceProbeArtifactsIfRequested(
        trace: [String: String],
        layer: CardPaintLayer
    ) throws {
        guard let outputPath = ProcessInfo.processInfo.environment["HYPE_VISIBLE_EVIDENCE_OUTPUT"],
              !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let traceData = try JSONSerialization.data(
            withJSONObject: trace,
            options: [.prettyPrinted, .sortedKeys]
        )
        try traceData.write(to: outputURL.appendingPathComponent("myst-visible-evidence-probe.json"), options: [.atomic])
        let paintPNG = try #require(PNGEncoding.rgbaDataToPNG(layer.normalizedRGBAData, width: layer.width, height: layer.height))
        try paintPNG.write(to: outputURL.appendingPathComponent("myst-visible-evidence-paint-layer.png"), options: [.atomic])
    }

    private enum TestPNGError: Error {
        case creationFailed
    }
}
