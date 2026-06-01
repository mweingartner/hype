import Foundation
import Testing
@testable import HypeCore

@Suite("HyperCard import and XCMD/XFCN emulation")
struct HyperCardImportTests {

    @Test("block parser accepts a minimal HyperCard stack")
    func blockParserAcceptsMinimalStack() throws {
        let data = makeSyntheticHyperCardStack()
        let blocks = try HyperCardBlockParser().parse(data: data)

        #expect(blocks.map(\.type).contains("STAK"))
        #expect(blocks.map(\.type).contains("BKGD"))
        #expect(blocks.map(\.type).contains("CARD"))
        #expect(blocks.last?.type == "TAIL")
    }

    @Test("converter imports cards, backgrounds, parts, scripts, and original fork metadata")
    func converterImportsSyntheticStack() throws {
        let data = makeSyntheticHyperCardStack()
        let result = try HyperCardToHypeConverter().convert(data: data)
        let document = result.document

        #expect(document.stack.width == 640)
        #expect(document.stack.height == 480)
        #expect(document.stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(document.stack.deploymentTargets.selectionPromptAcknowledged)
        #expect(document.backgrounds.count == 1)
        #expect(document.cards.count == 1)
        #expect(document.parts.count == 2)
        #expect(document.stack.script.contains("on openStack"))
        #expect(document.cards[0].script.contains("on openCard"))
        #expect(document.parts.contains { $0.name == "Card Field" && $0.textContent == "hello from card" })
        #expect(document.parts.contains { $0.name == "BG Button" && $0.script.contains("on mouseUp") })
        #expect(try parsedHandlerCount(document.stack.script) == 1)
        #expect(try parsedHandlerCount(document.cards[0].script) == 1)
        #expect(document.legacyImport?.embeddedDataFork == data)
        #expect(result.report.importedScripts >= 3)
    }

    @Test("resource fork parser discovers XCMD resources")
    func resourceForkParserDiscoversXCMD() throws {
        let fork = makeSyntheticResourceFork()
        let resources = try MacResourceForkReader().parse(fork)

        let xcmd = try #require(resources.first(where: { $0.type == "XCMD" }))
        #expect(xcmd.name == "AddColor")
        #expect(xcmd.id == 128)
        #expect(xcmd.data == Data([1, 2, 3]))
    }

    @Test("converter imports snd resources as playable audio assets in asset repository")
    func converterImportsSoundResourcesAsAudioAssets() throws {
        let data = makeSyntheticHyperCardStack()
        let fork = makeResourceForkWithSound()
        let result = try HyperCardToHypeConverter().convert(
            data: data,
            resourceFork: fork
        )

        let audioAssets = result.document.assetRepository.assets.filter { $0.kind == .audioClip }
        if StackImportRuntime.isAvailable {
            let asset = try #require(audioAssets.first)
            #expect(audioAssets.count == 1)
            #expect(asset.name == "Sound 128")
            #expect(asset.mimeType == "audio/wav")
            #expect(asset.data.count >= 44)
            #expect(asset.data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]))
        } else {
            #expect(audioAssets.isEmpty)
            #expect(result.report.warnings.contains { $0.contains("StackImport.framework") })
        }
    }

    @Test("C importer converts snd resources through resource payload streaming")
    func cImporterConvertsSoundResourcesThroughStreaming() throws {
        let fixture = URL(fileURLWithPath: "../stackimport/Resources.stak").standardizedFileURL
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            return
        }
        guard StackImportRuntime.isAvailable else {
            return
        }
        HypeLogger.shared.clear()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-c-import-sound-\(UUID().uuidString).stak")
        try FileManager.default.copyItem(at: fixture, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try makeResourceForkWithSound().write(to: URL(fileURLWithPath: tempURL.path + "/..namedfork/rsrc"))

        let result = try StackImportCImporter().importStack(at: tempURL)
        let audioAssets = result.document.assetRepository.assets.filter { $0.kind == .audioClip }

        #expect(audioAssets.count == 1)
        for asset in audioAssets {
            #expect(asset.mimeType == "audio/wav")
            #expect(asset.data.count >= 44)
            #expect(asset.data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]))
        }
        #expect(HypeLogger.shared.entries.contains {
            $0.source == "StackImport" &&
            $0.level == .info &&
            $0.message.contains("Status: Wrote snd #128 as WAV.")
        })
    }

    @Test("converter records XCMD resources as non-native emulation targets")
    func converterRecordsExternalResources() throws {
        let result = try HyperCardToHypeConverter().convert(
            data: makeSyntheticHyperCardStack(),
            resourceFork: makeSyntheticResourceFork()
        )

        let external = try #require(result.report.externalResources.first)
        #expect(external.kind == .xcmd)
        #expect(external.name == "AddColor")
        #expect(external.emulationStatus == .knownUnsupported)
        #expect(result.report.unsupportedFeatures.contains { $0.contains("XCMD/XFCN") })
    }

    @Test("legacy route-only translator preserves state gated cross-stack movie clicks")
    func legacyRouteOnlyTranslatorPreservesStateGatedCrossStackMovieClicks() throws {
        let script = """
        on mouseDownInMovie which
        global MY_Selenitic
        if which is "SeleniticBook.MooV" then
        if MY_Selenitic is not "true" then
        put "true" into MY_Selenitic
        set the currTime of window which to "5,50"
        repeat with x = 1 to
        else
        put "false" into MY_Selenitic
        go to card "black"
        go to card "black" of stack "Selenitic Age"
        go to card id 45136 of stack "Selenitic Age"
        end if
        end if
        end mouseDownInMovie
        """

        let translated = LegacyHyperTalkScript.preparedForHypeTalkRuntime(script)

        #expect(!LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(translated))
        #expect(translated.contains("route compatibility script"))
        #expect(translated.contains("if MY_Selenitic is \"true\" then"))
        #expect(translated.contains("go to card id 45136 of stack \"Selenitic Age\""))
        #expect(try parsedHandlerCount(translated) == 1)
    }

    @Test("legacy translator keeps Myst keyboard pushKey handler live")
    func legacyTranslatorKeepsMystKeyboardPushKeyHandlerLive() throws {
        let script = """
        on openCard
        global keyCounter
        put 0 into keyCounter
        pass opencard
        end openCard

        on pushKey theKey
        global keyCounter,MY_SpacePower
        add 1 to keyCounter
        get the Loc of the target
        set the loc of card button mask to 0,0
        xCIcon3 it,1000 + theKey
        play stop
        if MY_SpacePower = 59 then play "MU Organ" tempo 1 48 + theKey
        repeat until the mouse is up
        put the mouseloc into ml
        if  ml is not within the rect of the target then
        if keyCounter > 10 then exit repeat
        set the loc of card button mask to it
        --play stop
        if ml is within the rect of card button keyboard then click at ml
        else play stop
        exit pushKey
        end if
        end repeat
        set the loc of card button mask to it
        if keyCounter > 10 then
        put 0 into keycounter
        play stop
        exit to hypercard
        end if
        put 0 into keyCounter
        play stop
        end pushKey
        """

        do {
            _ = try parse(script)
        } catch {
            Issue.record("Myst pushKey source did not parse: \(error.localizedDescription)")
        }
        let translated = LegacyHyperTalkScript.preparedForHypeTalkRuntime(script)

        #expect(!LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(translated))
        #expect(translated.contains("on pushKey theKey"))
        #expect(try parsedHandlerCount(translated) == 2)
    }

    @Test("Myst environment externals are registered as emulated")
    func mystEnvironmentExternalsAreRegisteredAsEmulated() {
        let registry = HyperCardExternalRegistry.default
        #expect(registry.status(for: "HTLock", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "HTVisual", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "DeCurse", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "moveCursor", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "xWindowFrame", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "xAbout", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "xMemory", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "xMemory", kind: .xfcn) == .emulated)
        #expect(registry.status(for: "xVirtual", kind: .xfcn) == .emulated)
        #expect(registry.status(for: "xDepth", kind: .xfcn) == .emulated)
        #expect(registry.status(for: "variant", kind: .xfcn) == .emulated)
        #expect(registry.status(for: "movieInfo", kind: .xfcn) == .emulated)
        #expect(registry.status(for: "playQT", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "Movie", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "Buzzer", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "dplay", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "closemoovs", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "vd", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "vs", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "arrow", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "slideKnob", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "doValveI", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "doValveL", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "doValveR", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "showPillar", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "pillarClick", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "pushKey", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "fadein", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "fadeout", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "xSetSoundVol", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "xSetSoundVol", kind: .xfcn) == .emulated)
        #expect(registry.status(for: "xGetSoundVol", kind: .xfcn) == .emulated)
        #expect(registry.status(for: "SetMode", kind: .xcmd) == .emulated)
        #expect(registry.status(for: "GetMode", kind: .xfcn) == .emulated)
    }

    @Test("stackimport C importer converts a real stackimport fixture")
    func stackimportCImporterConvertsFixture() throws {
        let fixture = URL(fileURLWithPath: "../stackimport/Resources.stak").standardizedFileURL
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            return
        }
        guard StackImportRuntime.isAvailable else {
            return
        }

        let result = try StackImportCImporter().importStack(at: fixture)
        let document = result.document

        #expect(document.stack.name == "Resources.stak")
        #expect(document.stack.width == 480)
        #expect(document.stack.height == 296)
        #expect(document.backgrounds.count == 1)
        #expect(document.cards.count == 10)
        #expect(document.parts.contains { $0.partType == .image && $0.imageData != nil })
        #expect(document.parts.contains { $0.partType == .button && $0.script.contains("goTopic") })
        let importedScripts = [document.stack.script] + document.backgrounds.map(\.script) + document.cards.map(\.script) + document.parts.map(\.script)
        for script in importedScripts where !script.isEmpty {
            if scriptIsDisabledLegacyReference(script) {
                #expect(try parsedHandlerCount(script) == 0)
            } else {
                #expect(try parsedHandlerCount(script) > 0)
            }
        }
        #expect(document.legacyImport?.embeddedDataFork?.isEmpty == false)
    }

    @Test("stackimport package keeps unnamed graphical buttons unlabeled")
    func stackimportPackageKeepsUnnamedGraphicalButtonsUnlabeled() throws {
        let packageFiles: [String: Data] = [
            "project.json": Data("""
            {"sourceFileName":"Squirt Sample","stackFile":"stack_-1.json","blocks":[],"fonts":[]}
            """.utf8),
            "stack_-1.json": Data("""
            {"name":"Squirt Sample","cardWidth":512,"cardHeight":342,"script":"","pages":[{"cardIds":[100]}],"layers":[{"kind":"card","id":100,"file":"card_100.json"}]}
            """.utf8),
            "card_100.json": Data("""
            {"id":100,"bitmap":null,"name":"Frame","script":"","parts":[{"id":1,"type":"button","style":"transparent","showName":true,"autoHighlight":false,"rect":{"left":0,"top":0,"right":512,"bottom":342},"name":"","script":"on mouseUp\\rgo next\\rend mouseUp"}],"contents":[]}
            """.utf8),
        ]

        let result = try StackImportPackageConverter().convert(packageFiles: packageFiles)
        let button = try #require(result.document.parts.first { $0.partType == .button })

        #expect(result.document.stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(result.document.stack.deploymentTargets.selectionPromptAcknowledged)
        #expect(button.name == "Button 1")
        #expect(button.showName == false)
        #expect(button.buttonStyle == .transparent)
        #expect(button.script.contains("go next"))
        #expect(!scriptIsDisabledLegacyReference(button.script))
        #expect(try parsedHandlerCount(button.script) == 1)
    }

    @Test("stackimport package normalizes legacy gonext shorthand before enabling runnable scripts")
    func stackimportPackageNormalizesGoNextShorthand() throws {
        let packageFiles: [String: Data] = [
            "project.json": Data("""
            {"sourceFileName":"Squirt Sample","stackFile":"stack_-1.json","blocks":[],"fonts":[]}
            """.utf8),
            "stack_-1.json": Data("""
            {"name":"Squirt Sample","cardWidth":512,"cardHeight":342,"script":"","pages":[{"cardIds":[100]}],"layers":[{"kind":"card","id":100,"file":"card_100.json"}]}
            """.utf8),
            "card_100.json": Data("""
            {"id":100,"bitmap":null,"name":"Frame","script":"","parts":[{"id":1,"type":"button","style":"transparent","showName":true,"autoHighlight":false,"rect":{"left":0,"top":0,"right":512,"bottom":342},"name":"","script":"on mouseUp\\r  gonext\\rend mouseUp"}],"contents":[]}
            """.utf8),
        ]

        let result = try StackImportPackageConverter().convert(packageFiles: packageFiles)
        let button = try #require(result.document.parts.first { $0.partType == .button })

        #expect(button.script.contains("  go next"))
        #expect(!button.script.contains("gonext"))
        #expect(!scriptIsDisabledLegacyReference(button.script))
        #expect(try parsedHandlerCount(button.script) == 1)
    }

    @Test("stackimport package imports converted sounds as playable audio assets")
    func stackimportPackageImportsConvertedSoundsAsAudioAssets() throws {
        let wav = Data("RIFF----WAVEfmt ".utf8)
        let packageFiles: [String: Data] = [
            "project.json": Data("""
            {"sourceFileName":"Squirt Sample","stackFile":"stack_-1.json","blocks":[],"fonts":[]}
            """.utf8),
            "stack_-1.json": Data("""
            {"name":"Squirt Sample","cardWidth":512,"cardHeight":342,"script":"","pages":[{"cardIds":[100]}],"layers":[{"kind":"card","id":100,"file":"card_100.json"}]}
            """.utf8),
            "card_100.json": Data("""
            {"id":100,"bitmap":null,"name":"Frame","script":"","parts":[],"contents":[]}
            """.utf8),
            "sounds/Squirt%203.1_snd_128_MachineHum.wav": wav,
            "sounds/Squirt%203.1_snd_129_Red%20Alert.wav": wav,
        ]

        let result = try StackImportPackageConverter().convert(packageFiles: packageFiles)
        let assets = result.document.assetRepository.assets.filter { $0.kind == .audioClip }

        #expect(assets.count == 2)
        #expect(result.document.assetRepository.asset(byName: "MachineHum")?.mimeType == "audio/wav")
        #expect(result.document.assetRepository.asset(byName: "Red Alert")?.data == wav)
    }

    @Test("stackimport package registers card and background bitmaps as image assets")
    func stackimportPackageRegistersLayerBitmapsAsImageAssets() throws {
        let pbm = Data([UInt8]("P4\n2 1\n".utf8) + [0b1000_0000])
        let packageFiles: [String: Data] = [
            "project.json": Data("""
            {"sourceFileName":"Bitmap Sample","stackFile":"stack_-1.json","blocks":[],"fonts":[]}
            """.utf8),
            "stack_-1.json": Data("""
            {"name":"Bitmap Sample","cardWidth":2,"cardHeight":1,"script":"","pages":[{"cardIds":[100]}],"layers":[{"kind":"background","id":10,"file":"background_10.json","name":"Shared Art"},{"kind":"card","id":100,"owner":10,"file":"card_100.json","name":"Card Art"}]}
            """.utf8),
            "background_10.json": Data("""
            {"id":10,"bitmap":"background_10.pbm","name":"Shared Art","script":"","parts":[],"contents":[]}
            """.utf8),
            "card_100.json": Data("""
            {"id":100,"bitmap":"card_100.pbm","name":"Card Art","script":"","parts":[],"contents":[]}
            """.utf8),
            "background_10.pbm": pbm,
            "card_100.pbm": pbm,
        ]

        let result = try StackImportPackageConverter().convert(packageFiles: packageFiles)
        let assets = result.document.assetRepository.assets

        let backgroundAsset = try #require(assets.first { $0.name == "Shared Art Paint Layer" })
        #expect(backgroundAsset.kind == .imageTexture)
        #expect(backgroundAsset.mimeType == "image/png")
        #expect(backgroundAsset.width == 2)
        #expect(backgroundAsset.height == 1)
        #expect(backgroundAsset.tags.contains("background-paint-layer"))

        let cardAsset = try #require(assets.first { $0.name == "Card Art Paint Layer" })
        #expect(cardAsset.kind == .imageTexture)
        #expect(cardAsset.mimeType == "image/png")
        #expect(cardAsset.tags.contains("card-paint-layer"))
        #expect(result.document.parts.filter { $0.partType == .image && $0.imageData != nil }.count == 2)
    }

    @Test("stackimport package imports converted resource images and metadata")
    func stackimportPackageImportsConvertedResourceImagesAndMetadata() throws {
        HypeLogger.shared.clear()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/luz9XwAAAABJRU5ErkJggg==")!
        let metadata = Data(#"{"hotspotX":4,"hotspotY":8}"#.utf8)
        let text = Data("Héllo".utf8)
        let packageFiles: [String: Data] = [
            "project.json": Data("""
            {"sourceFileName":"Resource Sample","stackFile":"stack_-1.json","blocks":[],"fonts":[]}
            """.utf8),
            "stack_-1.json": Data("""
            {"name":"Resource Sample","cardWidth":512,"cardHeight":342,"script":"","pages":[{"cardIds":[100]}],"layers":[{"kind":"card","id":100,"file":"card_100.json"}]}
            """.utf8),
            "card_100.json": Data("""
            {"id":100,"bitmap":null,"name":"Frame","script":"","parts":[],"contents":[]}
            """.utf8),
            "source-manifest.json": Data("""
            {
              "resourceFork": {
                "resources": [
                  {
                    "type": "CURS",
                    "id": 24,
                    "flags": 0,
                    "name": "Pointer",
                    "bytes": 68,
                    "status": "exported",
                    "outputArtifacts": [
                      {"path": "CURS_24.png", "format": "png", "mediaType": "image/png", "description": "decoded cursor image", "variantIndex": 0},
                      {"path": "CURS_24.json", "format": "json", "mediaType": "application/json", "description": "cursor metadata", "variantIndex": 0}
                    ]
                  },
                  {
                    "type": "STR ",
                    "id": 12,
                    "flags": 0,
                    "name": "Greeting",
                    "bytes": 6,
                    "status": "exported",
                    "outputArtifacts": [
                      {"path": "resource-text/Stack_STR%20_12.txt", "format": "text", "mediaType": "text/plain", "description": "decoded text", "variantIndex": 0}
                    ]
                  },
                  {
                    "type": "ICON",
                    "id": 99,
                    "flags": 0,
                    "name": "Unsafe",
                    "bytes": 128,
                    "status": "exported",
                    "outputArtifacts": [
                      {"path": "../escape.png", "format": "png", "mediaType": "image/png", "description": "bad path", "variantIndex": 0}
                    ]
                  }
                ]
              }
            }
            """.utf8),
            "CURS_24.png": png,
            "CURS_24.json": metadata,
            "resource-text/Stack_STR%20_12.txt": text,
            "../escape.png": png,
        ]

        let result = try StackImportPackageConverter().convert(packageFiles: packageFiles)
        let assets = result.document.assetRepository.assets

        let cursor = try #require(assets.first { $0.name == "CURS_24" })
        #expect(cursor.kind == .imageTexture)
        #expect(cursor.mimeType == "image/png")
        #expect(cursor.tags.contains("resource-curs"))
        #expect(cursor.metadata.contains { $0.key == "CURS_24.json" && $0.value.contains("hotspotX") })

        let textAsset = try #require(assets.first { $0.name == "Stack_STR _12" })
        #expect(textAsset.kind == .placeholderAsset)
        #expect(textAsset.metadata.contains { $0.value == "Héllo" })
        #expect(result.report.resourceSummary.contains { $0.type == "CURS" && $0.count == 1 && $0.totalBytes == 68 })
        #expect(!assets.contains { $0.name == "escape" || $0.name == "Unsafe" })
        #expect(HypeLogger.shared.entries.contains {
            $0.source == "HyperCardImport" &&
            $0.message.contains("Skipping unsafe stackimport artifact path '../escape.png'")
        })
        #expect(HypeLogger.shared.entries.contains {
            $0.source == "HyperCardImport" &&
            $0.message.contains("Importing unhandled resource artifact as metadata placeholder: resource STR  12")
        })
    }

    @Test("parser accepts classic XCMD command syntax")
    func parserAcceptsExternalCommandSyntax() throws {
        let script = try parse("""
        on mouseUp
          SetCursor "watch"
          AddColor "card", "indexed"
          xWindowFrame
          xAbout
          xSetSoundVol true
        end mouseUp
        """)

        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].body.count == 5)
        guard case .externalCommand(let name, let arguments) = script.handlers[0].body[0] else {
            Issue.record("Expected external command statement")
            return
        }
        #expect(name == "SetCursor")
        #expect(arguments.count == 1)
        guard case .externalCommand(let bareName, let bareArguments) = script.handlers[0].body[2] else {
            Issue.record("Expected bare external command statement")
            return
        }
        #expect(bareName == "xWindowFrame")
        #expect(bareArguments.isEmpty)
    }

    @Test("interpreter routes emulated XFCN function calls through registry")
    func interpreterRoutesEmulatedXFCN() async throws {
        var document = HypeDocument.newDocument(name: "External Test")
        let cardId = try #require(document.cards.first?.id)
        document.addPart(Part(partType: .field, cardId: cardId, name: "out"))
        let handler = try parse("""
        on mouseUp
          put HypeVersion() into field "out"
        end mouseUp
        """).handlers[0]

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        let out = try #require(modified.parts.first(where: { $0.name == "out" }))
        #expect(out.textContent == "Hype HyperCard compatibility layer")
    }

    @Test("unknown XCMD does not crash and sets the result diagnostic")
    func unknownXCMDDegradesToDiagnostic() async throws {
        var document = HypeDocument.newDocument(name: "External Test")
        let cardId = try #require(document.cards.first?.id)
        document.addPart(Part(partType: .field, cardId: cardId, name: "out"))
        let handler = try parse("""
        on mouseUp
          MissingClassicExternal "x"
          put the result into field "out"
        end mouseUp
        """).handlers[0]

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        let out = try #require(modified.parts.first(where: { $0.name == "out" }))
        #expect(out.textContent.contains("Can't Load External"))
        #expect(out.textContent.contains("MissingClassicExternal"))
    }

    @Test("Myst environment externals update runtime globals")
    func mystEnvironmentExternalsUpdateRuntimeGlobals() async throws {
        var document = HypeDocument.newDocument(name: "External Test")
        let cardId = try #require(document.cards.first?.id)
        document.addPart(Part(partType: .field, cardId: cardId, name: "out"))
        let handler = try parse("""
        on mouseUp
          HTLock "unlock"
          HTVisual "dissolve", 30
          DeCurse "remove", 128, "CURS"
          moveCursor 11, 22
          xWindowFrame
          xAbout
          xMemory 1
          SetMode c,8
          put xDepth() & return & GetMode() & return & xSetSoundVol(128) & return & xGetSoundVol() & return & variant() into field "out"
        end mouseUp
        """).handlers[0]

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        let out = try #require(modified.parts.first(where: { $0.name == "out" }))
        #expect(out.textContent == "8\rc,8\r128\r128\r2.1")
        #expect(modified.scriptGlobals["hypercard.htlock.mode"] == "unlock")
        #expect(modified.scriptGlobals["hypercard.htvisual.effect"] == "dissolve")
        #expect(modified.scriptGlobals["hypercard.decurse.mode"] == "remove")
        #expect(modified.scriptGlobals["hypercard.movecursor.loc"] == "11,22")
        #expect(modified.scriptGlobals["hypercard.window.frame.exists"] == "true")
        #expect(modified.scriptGlobals["hypercard.xabout.invoked"] == "true")
        #expect(modified.scriptGlobals["hypercard.display.value"] == "c,8")
        #expect(modified.scriptGlobals["hypercard.sound.volume"] == "128")
    }

    private func parse(_ source: String) throws -> Script {
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        return try parser.parse()
    }

    private func parsedHandlerCount(_ source: String) throws -> Int {
        try parse(source).handlers.count
    }

    private func scriptIsDisabledLegacyReference(_ source: String) -> Bool {
        source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-- Imported HyperCard script preserved for reference.")
    }
}

private func makeSyntheticHyperCardStack() -> Data {
    var data = Data()
    data.append(hcBlock(type: "STAK", id: 1, payload: makeStackPayload()))
    data.append(hcBlock(type: "BKGD", id: 100, payload: makeBackgroundPayload()))
    data.append(hcBlock(type: "CARD", id: 200, payload: makeCardPayload()))
    data.append(hcBlock(type: "TAIL", id: 0, payload: Data()))
    return data
}

private func makeStackPayload() -> Data {
    var payload = Data(repeating: 0, count: 0x620)
    payload.setInt32BE(2, at: 0)
    payload.setUInt16BE(480, at: 0x1A8)
    payload.setUInt16BE(640, at: 0x1AA)
    payload.writeCString("on openStack\n  pass openStack\nend openStack", at: 0x5F0)
    return payload
}

private func makeBackgroundPayload() -> Data {
    let part = makePartRecord(id: 1, rawType: 1, name: "BG Button", text: "", script: "on mouseUp\n  answer \"hi\"\nend mouseUp", rect: (20, 20, 120, 60))
    let content = makePartContent(partId: 1, text: "")
    var payload = Data(repeating: 0, count: 34)
    payload.setUInt16BE(1, at: 20)
    payload.setUInt32BE(UInt32(part.count), at: 24)
    payload.setUInt16BE(1, at: 28)
    payload.setUInt32BE(UInt32(content.count), at: 30)
    payload.append(part)
    payload.append(content)
    payload.appendMacRomanCString("Main Background")
    payload.appendMacRomanCString("on openBackground\n  pass openBackground\nend openBackground")
    return payload
}

private func makeCardPayload() -> Data {
    let part = makePartRecord(id: 2, rawType: 2, name: "Card Field", text: "hello from card", script: "", rect: (40, 60, 260, 100))
    let content = makePartContent(partId: -2, text: "hello from card")
    var payload = Data(repeating: 0, count: 38)
    payload.setInt32BE(100, at: 20)
    payload.setUInt16BE(1, at: 24)
    payload.setUInt32BE(UInt32(part.count), at: 28)
    payload.setUInt16BE(1, at: 32)
    payload.setUInt32BE(UInt32(content.count), at: 34)
    payload.append(part)
    payload.append(content)
    payload.appendMacRomanCString("First Card")
    payload.appendMacRomanCString("on openCard\n  put \"opened\" into field \"Card Field\"\nend openCard")
    return payload
}

private func makePartRecord(
    id: Int,
    rawType: UInt8,
    name: String,
    text: String,
    script: String,
    rect: (left: Int16, top: Int16, right: Int16, bottom: Int16)
) -> Data {
    var record = Data(repeating: 0, count: 30)
    record.setInt16BE(Int16(id), at: 2)
    record[record.startIndex + 4] = rawType
    record.setInt16BE(rect.top, at: 6)
    record.setInt16BE(rect.left, at: 8)
    record.setInt16BE(rect.bottom, at: 10)
    record.setInt16BE(rect.right, at: 12)
    record[record.startIndex + 15] = rawType == 2 ? 2 : 3
    record.setInt16BE(-1, at: 22)
    record.setInt16BE(12, at: 24)
    record.appendMacRomanCString(name)
    record.append(0)
    record.appendMacRomanCString(script)
    record.setUInt16BE(UInt16(record.count), at: 0)
    _ = text
    return record
}

private func makePartContent(partId: Int, text: String) -> Data {
    var content = Data()
    let textData = text.data(using: .macOSRoman) ?? Data()
    let size = UInt16(4 + 1 + textData.count)
    content.appendUInt16BE(size)
    content.appendInt16BE(Int16(partId))
    content.append(0)
    content.append(textData)
    return content
}

private func hcBlock(type: String, id: Int32, payload: Data) -> Data {
    var data = Data()
    data.appendInt32BE(Int32(payload.count + 16))
    data.append(type.data(using: .macOSRoman)!)
    data.appendInt32BE(id)
    data.append(contentsOf: [0, 0, 0, 0])
    data.append(payload)
    return data
}

private func makeResourceForkWithSound() -> Data {
    // Build a minimal valid snd resource (format 1, 8-bit mono PCM, 1 sample)
    var snd = Data()
    snd.appendUInt16BE(1) // version
    snd.appendUInt16BE(1) // number of data types
    snd.appendUInt16BE(5) // type: sampled sound
    snd.appendUInt32BE(0) // options
    snd.appendUInt16BE(1) // number of commands
    // Null command; the converter defaults the sample buffer to the bytes after the command list.
    snd.appendUInt16BE(0)
    snd.appendUInt16BE(1)
    snd.appendUInt32BE(0)
    // Sample data follows: data pointer (0 = at end of commands)
    snd.appendUInt32BE(0) // data pointer
    snd.appendUInt32BE(1) // sample byte count
    let sampleRate: UInt32 = 22050
    snd.appendUInt32BE(sampleRate << 16) // sample rate (16.16 fixed point)
    snd.appendUInt32BE(0) // reserved
    snd.appendUInt32BE(0) // reserved
    snd.appendUInt8(0) // encoding: 0 = uncompressed signed 8-bit
    snd.appendUInt8(60) // base frequency
    // Raw sample: one byte of PCM data
    snd.appendUInt8(128)

    // Build resource fork containing the snd resource.
    let dataOffset = 0x100
    let mapOffset = 0x200
    let typeListOffset = 28
    let refListOffset = 10
    let nameListOffset = typeListOffset + refListOffset + 12
    let dataLength = 4 + snd.count
    let mapLength = nameListOffset
    var fork = Data(repeating: 0, count: mapOffset + mapLength)

    fork.setUInt32BE(UInt32(dataOffset), at: 0)
    fork.setUInt32BE(UInt32(mapOffset), at: 4)
    fork.setUInt32BE(UInt32(dataLength), at: 8)
    fork.setUInt32BE(UInt32(mapLength), at: 12)
    fork.setUInt32BE(UInt32(snd.count), at: dataOffset)
    fork.replaceSubrange((dataOffset + 4)..<(dataOffset + 4 + snd.count), with: snd)

    fork.setUInt16BE(UInt16(typeListOffset), at: mapOffset + 24)
    fork.setUInt16BE(UInt16(nameListOffset), at: mapOffset + 26)
    let typeListStart = mapOffset + typeListOffset
    fork.setInt16BE(0, at: typeListStart)
    fork.replaceSubrange((typeListStart + 2)..<(typeListStart + 6), with: "snd ".data(using: .ascii)!)
    fork.setInt16BE(0, at: typeListStart + 6)
    fork.setUInt16BE(UInt16(refListOffset), at: typeListStart + 8)

    let refStart = typeListStart + refListOffset
    fork.setInt16BE(128, at: refStart)
    fork.setInt16BE(-1, at: refStart + 2)
    fork[refStart + 4] = 0
    fork[refStart + 5] = 0
    fork[refStart + 6] = 0
    fork[refStart + 7] = 0

    return fork
}

private func makeSyntheticResourceFork() -> Data {
    let resourcePayload = Data([1, 2, 3])
    let dataOffset = 0x100
    let mapOffset = 0x200
    let typeListOffset = 28
    let refListOffset = 10
    let nameListOffset = typeListOffset + refListOffset + 12
    let mapLength = nameListOffset + 1 + "AddColor".count
    let dataLength = 4 + resourcePayload.count

    var fork = Data(repeating: 0, count: mapOffset + mapLength)
    fork.setUInt32BE(UInt32(dataOffset), at: 0)
    fork.setUInt32BE(UInt32(mapOffset), at: 4)
    fork.setUInt32BE(UInt32(dataLength), at: 8)
    fork.setUInt32BE(UInt32(mapLength), at: 12)
    fork.setUInt32BE(UInt32(resourcePayload.count), at: dataOffset)
    fork.replaceSubrange((dataOffset + 4)..<(dataOffset + 4 + resourcePayload.count), with: resourcePayload)

    fork.setUInt16BE(UInt16(typeListOffset), at: mapOffset + 24)
    fork.setUInt16BE(UInt16(nameListOffset), at: mapOffset + 26)
    let typeListStart = mapOffset + typeListOffset
    fork.setInt16BE(0, at: typeListStart)
    fork.replaceSubrange((typeListStart + 2)..<(typeListStart + 6), with: "XCMD".data(using: .macOSRoman)!)
    fork.setInt16BE(0, at: typeListStart + 6)
    fork.setUInt16BE(UInt16(refListOffset), at: typeListStart + 8)
    let refStart = typeListStart + refListOffset
    fork.setInt16BE(128, at: refStart)
    fork.setInt16BE(0, at: refStart + 2)
    fork[refStart + 4] = 0
    fork[refStart + 5] = 0
    fork[refStart + 6] = 0
    fork[refStart + 7] = 0
    let nameStart = mapOffset + nameListOffset
    fork[nameStart] = UInt8("AddColor".count)
    fork.replaceSubrange((nameStart + 1)..<(nameStart + 1 + "AddColor".count), with: "AddColor".data(using: .macOSRoman)!)
    return fork
}

private extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendInt16BE(_ value: Int16) {
        appendUInt16BE(UInt16(bitPattern: value))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendInt32BE(_ value: Int32) {
        appendUInt32BE(UInt32(bitPattern: value))
    }

    mutating func setUInt16BE(_ value: UInt16, at offset: Int) {
        self[startIndex + offset] = UInt8((value >> 8) & 0xFF)
        self[startIndex + offset + 1] = UInt8(value & 0xFF)
    }

    mutating func setInt16BE(_ value: Int16, at offset: Int) {
        setUInt16BE(UInt16(bitPattern: value), at: offset)
    }

    mutating func setUInt32BE(_ value: UInt32, at offset: Int) {
        self[startIndex + offset] = UInt8((value >> 24) & 0xFF)
        self[startIndex + offset + 1] = UInt8((value >> 16) & 0xFF)
        self[startIndex + offset + 2] = UInt8((value >> 8) & 0xFF)
        self[startIndex + offset + 3] = UInt8(value & 0xFF)
    }

    mutating func setInt32BE(_ value: Int32, at offset: Int) {
        setUInt32BE(UInt32(bitPattern: value), at: offset)
    }

    mutating func appendMacRomanCString(_ value: String) {
        append(value.data(using: .macOSRoman) ?? Data())
        append(0)
    }

    mutating func writeCString(_ value: String, at offset: Int) {
        let bytes = value.data(using: .macOSRoman) ?? Data()
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        self[offset + bytes.count] = 0
    }
}
