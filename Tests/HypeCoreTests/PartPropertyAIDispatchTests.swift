import Testing
import Foundation
@testable import HypeCore

// AI-surface halves of the dispatch tests (`control-property-consistency`
// P2, design.md test plan items 3–8, 10; mock acceptance criteria
// 3–8). `PartPropertyDispatchTests.swift` drives the identical
// scenarios through HypeTalk's `MessageDispatcher`; these tests drive
// the SAME registry gate through `HypeToolExecutor.execute` to prove
// the AI tool surface honors the shared `PartPropertyRegistry`
// identically (mock §3: "one shared registry drives both").

// MARK: - Test helpers

/// Builds a fresh single-card document (no output field needed — the
/// AI tools return their result as a plain `String`, unlike HypeTalk
/// scripts which write into a field).
private func aiFreshDoc() -> (HypeDocument, UUID) {
    let doc = HypeDocument.newDocument(name: "Test")
    let cardId = doc.cards[0].id
    return (doc, cardId)
}

private func aiSet(_ doc: inout HypeDocument, cardId: UUID, part: String, property: String, value: String) async -> String {
    await HypeToolExecutor().execute(
        toolName: "set_part_property",
        arguments: ["part_name": part, "property": property, "value": value],
        document: &doc, currentCardId: cardId
    )
}

private func aiGet(_ doc: inout HypeDocument, cardId: UUID, part: String, property: String) async -> String {
    await HypeToolExecutor().execute(
        toolName: "get_part_property",
        arguments: ["part_name": part, "property": property],
        document: &doc, currentCardId: cardId
    )
}

// MARK: - size pair law (AI half of mock §3.2, criterion 4)

@Suite("AI size pair law", .serialized)
struct AISizePairLawTests {
    @Test("SET \"width,height\" then GET returns the same pair")
    func sizeRoundTrips() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 10, height: 10)
        doc.addPart(shape)
        let setResult = await aiSet(&doc, cardId: cardId, part: "s", property: "size", value: "200,150")
        #expect(setResult.contains("Set"), "unexpected: \(setResult)")
        #expect(doc.parts.first { $0.name == "s" }?.width == 200)
        #expect(doc.parts.first { $0.name == "s" }?.height == 150)
        let got = await aiGet(&doc, cardId: cardId, part: "s", property: "size")
        #expect(got == "200,150")
    }

    @Test("SET of a single number errors with the exact mock copy naming textSize")
    func sizeSingleNumberErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 10, height: 10)
        doc.addPart(shape)
        let result = await aiSet(&doc, cardId: cardId, part: "s", property: "size", value: "24")
        #expect(result == "size expects \"width,height\" — use textSize to set the text size.")
    }

    @Test("textSize is unaffected by the size split — still sets the text point size")
    func textSizeStillWorks() async {
        var (doc, cardId) = aiFreshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        _ = await aiSet(&doc, cardId: cardId, part: "f", property: "textsize", value: "24")
        #expect(doc.parts.first { $0.name == "f" }?.textSize == 24)
        let got = await aiGet(&doc, cardId: cardId, part: "f", property: "textsize")
        #expect(got == "24.0")
    }
}

// MARK: - Video playback family (task 2.1, mock §3.3)

@Suite("AI video playback family", .serialized)
struct AIVideoPlaybackFamilyTests {
    @Test("videoLoop/videoAutoplay/videoVolume/currentTime/playRate round-trip")
    func videoFamilyRoundTrips() async {
        var (doc, cardId) = aiFreshDoc()
        let video = Part(partType: .video, cardId: cardId, name: "v", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(video)
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "videoloop", value: "true")
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "videoautoplay", value: "yes")
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "videovolume", value: "0.5")
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "currenttime", value: "12.5")
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "playrate", value: "2")
        let part = doc.parts.first { $0.name == "v" }
        #expect(part?.videoLoop == true)
        #expect(part?.videoAutoplay == true)
        #expect(part?.videoVolume == 0.5)
        #expect(part?.videoCurrentTime == 12.5)
        #expect(part?.videoPlayRate == 2)
        let loopGet = await aiGet(&doc, cardId: cardId, part: "v", property: "videoloop")
        #expect(loopGet == "true")
        let volumeGet = await aiGet(&doc, cardId: cardId, part: "v", property: "videovolume")
        #expect(volumeGet == "0.5")
    }

    @Test("videoVolume clamps to 0...1")
    func videoVolumeClamps() async {
        var (doc, cardId) = aiFreshDoc()
        let video = Part(partType: .video, cardId: cardId, name: "v", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(video)
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "videovolume", value: "5")
        #expect(doc.parts.first { $0.name == "v" }?.videoVolume == 1)
    }

    @Test("videoDuration is read-only: GET works, SET errors")
    func videoDurationReadOnly() async {
        var (doc, cardId) = aiFreshDoc()
        var video = Part(partType: .video, cardId: cardId, name: "v", left: 0, top: 0, width: 100, height: 40)
        video.videoDuration = 9.5
        doc.addPart(video)
        let got = await aiGet(&doc, cardId: cardId, part: "v", property: "videoduration")
        #expect(got == "9.5")
        let setResult = await aiSet(&doc, cardId: cardId, part: "v", property: "videoduration", value: "99")
        #expect(setResult == "\"videoduration\" of video \"v\" is read-only.")
    }

    @Test("loop/volume bare words route per type: video vs music family (H7)")
    func loopVolumeBareWordsRoutePerType() async {
        var (doc, cardId) = aiFreshDoc()
        let video = Part(partType: .video, cardId: cardId, name: "v", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(video)
        let music = Part(partType: .musicPlayer, cardId: cardId, name: "m", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(music)
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "loop", value: "true")
        _ = await aiSet(&doc, cardId: cardId, part: "v", property: "volume", value: "0.25")
        _ = await aiSet(&doc, cardId: cardId, part: "m", property: "loop", value: "true")
        _ = await aiSet(&doc, cardId: cardId, part: "m", property: "volume", value: "0.75")
        #expect(doc.parts.first { $0.name == "v" }?.videoLoop == true)
        #expect(doc.parts.first { $0.name == "v" }?.videoVolume == 0.25)
        #expect(doc.parts.first { $0.name == "m" }?.musicLoop == true)
        #expect(doc.parts.first { $0.name == "m" }?.musicVolume == 0.75)
    }

    @Test("autoplay bare word applies to video only — errors on a gauge")
    func autoplayVideoOnlyErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let result = await aiSet(&doc, cardId: cardId, part: "g", property: "autoplay", value: "true")
        #expect(result.contains("does not apply"), "unexpected: \(result)")
    }
}

// MARK: - popupItems, field flags, showsUserLocation, invertOnClick, animated, icon (task 2.1, mock A5)

@Suite("AI curated new getters/setters (A5)", .serialized)
struct AINewCuratedPropertyTests {
    @Test("popupItems round-trips on a button; errors on a non-button")
    func popupItemsRoundTrip() async {
        var (doc, cardId) = aiFreshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        _ = await aiSet(&doc, cardId: cardId, part: "b", property: "popupitems", value: "One\nTwo")
        #expect(doc.parts.first { $0.name == "b" }?.popupItems == "One\nTwo")
        let got = await aiGet(&doc, cardId: cardId, part: "b", property: "popupitems")
        #expect(got == "One\nTwo")

        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let errorResult = await aiSet(&doc, cardId: cardId, part: "f", property: "popupitems", value: "One\nTwo")
        #expect(errorResult.contains("does not apply"), "unexpected: \(errorResult)")
    }

    @Test("field flags (dontWrap/wideMargins/richText/enterKeyEnabled) round-trip on a field")
    func fieldFlagsRoundTrip() async {
        var (doc, cardId) = aiFreshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        for flag in ["dontwrap", "widemargins", "richtext", "enterkeyenabled"] {
            _ = await aiSet(&doc, cardId: cardId, part: "f", property: flag, value: "true")
            let got = await aiGet(&doc, cardId: cardId, part: "f", property: flag)
            #expect(got == "true", "\(flag) did not round-trip: got '\(got)'")
        }
        let part = doc.parts.first { $0.name == "f" }
        #expect(part?.dontWrap == true)
        #expect(part?.wideMargins == true)
        #expect(part?.richText == true)
        #expect(part?.enterKeyEnabled == true)
    }

    @Test("showsUserLocation round-trips on a map; errors on a non-map")
    func showsUserLocationRoundTrip() async {
        var (doc, cardId) = aiFreshDoc()
        let map = Part(partType: .map, cardId: cardId, name: "m", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(map)
        _ = await aiSet(&doc, cardId: cardId, part: "m", property: "showsuserlocation", value: "true")
        #expect(doc.parts.first { $0.name == "m" }?.mapShowsUserLocation == true)
        let got = await aiGet(&doc, cardId: cardId, part: "m", property: "showsuserlocation")
        #expect(got == "true")

        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let errorResult = await aiSet(&doc, cardId: cardId, part: "s", property: "showsuserlocation", value: "true")
        #expect(errorResult.contains("does not apply"), "unexpected: \(errorResult)")
    }

    @Test("invertOnClick and animated round-trip on an image")
    func invertOnClickAndAnimatedRoundTrip() async {
        var (doc, cardId) = aiFreshDoc()
        let image = Part(partType: .image, cardId: cardId, name: "i", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(image)
        _ = await aiSet(&doc, cardId: cardId, part: "i", property: "invertonclick", value: "true")
        _ = await aiSet(&doc, cardId: cardId, part: "i", property: "animated", value: "false")
        #expect(doc.parts.first { $0.name == "i" }?.invertOnClick == true)
        #expect(doc.parts.first { $0.name == "i" }?.animated == false)
        let invertGet = await aiGet(&doc, cardId: cardId, part: "i", property: "invertonclick")
        #expect(invertGet == "true")
        let animatedGet = await aiGet(&doc, cardId: cardId, part: "i", property: "animated")
        #expect(animatedGet == "false")
    }

    @Test("icon: GET is empty when unset (H8); SET \"\" or \"0\" clears a bound icon")
    func iconEmptySentinelAndClear() async {
        var (doc, cardId) = aiFreshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let emptyGet = await aiGet(&doc, cardId: cardId, part: "b", property: "icon")
        #expect(emptyGet == "")

        doc.parts[doc.parts.firstIndex { $0.name == "b" }!].iconId = UUID()
        _ = await aiSet(&doc, cardId: cardId, part: "b", property: "icon", value: "0")
        #expect(doc.parts.first { $0.name == "b" }?.iconId == nil)

        let uuid = UUID()
        _ = await aiSet(&doc, cardId: cardId, part: "b", property: "icon", value: uuid.uuidString)
        #expect(doc.parts.first { $0.name == "b" }?.iconId == uuid)
    }
}

// MARK: - `location` unified to geometry/map semantics (task 2.1)

@Suite("AI location unification", .serialized)
struct AILocationUnificationTests {
    @Test("a coordinate pair moves the geometric center of ANY part")
    func coordinatePairMovesAnyPart() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 10, height: 10)
        doc.addPart(shape)
        _ = await aiSet(&doc, cardId: cardId, part: "s", property: "location", value: "100,50")
        let part = doc.parts.first { $0.name == "s" }
        #expect(part?.left == 95)
        #expect(part?.top == 45)
    }

    @Test("a non-pair value on a map part geocodes into mapLocation")
    func nonPairOnMapWritesPlaceName() async {
        var (doc, cardId) = aiFreshDoc()
        let map = Part(partType: .map, cardId: cardId, name: "m", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(map)
        _ = await aiSet(&doc, cardId: cardId, part: "m", property: "location", value: "97537")
        #expect(doc.parts.first { $0.name == "m" }?.mapLocation == "97537")
        let got = await aiGet(&doc, cardId: cardId, part: "m", property: "location")
        #expect(got == "97537")
    }

    @Test("a non-pair value on a non-map part now errors instead of silently doing nothing")
    func nonPairOnNonMapErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 10, height: 10)
        doc.addPart(shape)
        let result = await aiSet(&doc, cardId: cardId, part: "s", property: "location", value: "not a pair")
        #expect(result.contains("is not a coordinate pair"), "unexpected: \(result)")
    }

    @Test("GET of location returns the geometric center when no place name is set")
    func getLocationDefaultsToGeometry() async {
        var (doc, cardId) = aiFreshDoc()
        let map = Part(partType: .map, cardId: cardId, name: "m", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(map)
        let got = await aiGet(&doc, cardId: cardId, part: "m", property: "location")
        #expect(got == "50,20")
    }
}

// MARK: - Chart single-path — chart keys error on non-chart parts (task 2.1, A4)

@Suite("AI chart single path", .serialized)
struct AIChartSinglePathTests {
    @Test("chart title/interactive work through the chart intercept")
    func chartTitleAndInteractiveWork() async {
        var (doc, cardId) = aiFreshDoc()
        var chart = Part(partType: .chart, cardId: cardId, name: "Sales", left: 0, top: 0, width: 200, height: 200)
        chart.chartData = ChartConfig().toJSON()
        doc.addPart(chart)
        _ = await aiSet(&doc, cardId: cardId, part: "Sales", property: "title", value: "Q3 Revenue")
        _ = await aiSet(&doc, cardId: cardId, part: "Sales", property: "interactive", value: "true")
        let titleGet = await aiGet(&doc, cardId: cardId, part: "Sales", property: "title")
        #expect(titleGet == "Q3 Revenue")
        let interactiveGet = await aiGet(&doc, cardId: cardId, part: "Sales", property: "interactive")
        #expect(interactiveGet == "true")
    }

    @Test("chart-only keys (e.g. charttype) error on a non-chart part instead of silently no-op'ing")
    func chartKeyOnNonChartPartErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let result = await aiSet(&doc, cardId: cardId, part: "s", property: "charttype", value: "bar")
        #expect(result.contains("no such property"), "unexpected: \(result)")
    }

    @Test("bare interactive on a shape (neither chart nor colorWell) errors")
    func interactiveOnShapeErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let result = await aiSet(&doc, cardId: cardId, part: "s", property: "interactive", value: "true")
        #expect(result.contains("does not apply"), "unexpected: \(result)")
    }
}

// MARK: - Boolean parser fuzz (A3; mock §3.8, criterion 8)

@Suite("AI boolean parser", .serialized)
struct AIBooleanParserTests {
    private static let truthyTokens = ["true", "TRUE", " True ", "yes", "YES", "y", "Y", "1", "on", "ON"]
    private static let falsyTokens = ["false", "FALSE", " False ", "no", "NO", "n", "N", "0", "off", "OFF"]

    @Test("every accepted truthy token sets a boolean property to true", arguments: AIBooleanParserTests.truthyTokens)
    func truthyTokensParse(token: String) async {
        var (doc, cardId) = aiFreshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let result = await aiSet(&doc, cardId: cardId, part: "f", property: "visible", value: token)
        #expect(result.contains("Set"), "token '\(token)' unexpectedly errored: \(result)")
        #expect(doc.parts.first { $0.name == "f" }?.visible == true, "token '\(token)' did not set true")
    }

    @Test("every accepted falsy token sets a boolean property to false", arguments: AIBooleanParserTests.falsyTokens)
    func falsyTokensParse(token: String) async {
        var (doc, cardId) = aiFreshDoc()
        var field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        field.visible = true
        doc.addPart(field)
        let result = await aiSet(&doc, cardId: cardId, part: "f", property: "visible", value: token)
        #expect(result.contains("Set"), "token '\(token)' unexpectedly errored: \(result)")
        #expect(doc.parts.first { $0.name == "f" }?.visible == false, "token '\(token)' did not set false")
    }

    @Test("garbage boolean input errors with the exact AI copy")
    func garbageBooleanErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let result = await aiSet(&doc, cardId: cardId, part: "f", property: "visible", value: "maybe")
        #expect(result == "\"maybe\" is not a boolean — use true/false, yes/no, on/off, or 1/0.")
    }
}

// MARK: - Unknown-property / wrong-type errors (mock §3.7/criterion 6)

@Suite("AI strict-SET and wrong-type laws", .serialized)
struct AIStrictSetAndWrongTypeTests {
    @Test("SET of an unrecognized property errors, with the property name in the message")
    func unknownPropertyErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let result = await aiSet(&doc, cardId: cardId, part: "b", property: "totallyBogusProperty", value: "x")
        #expect(result.contains("no such property"))
        #expect(result.contains("totallyBogusProperty"))
    }

    @Test("a near-miss typo produces a did-you-mean hint")
    func typoProducesHint() async {
        var (doc, cardId) = aiFreshDoc()
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let result = await aiSet(&doc, cardId: cardId, part: "g", property: "gaugvalue", value: "5")
        #expect(result.contains("did you mean"), "unexpected: \(result)")
    }

    @Test("gaugeValue on a button errors instead of mutating a never-rendered field")
    func gaugeValueOnButtonErrors() async {
        var (doc, cardId) = aiFreshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let result = await aiSet(&doc, cardId: cardId, part: "b", property: "gaugevalue", value: "999")
        #expect(result.contains("gaugevalue"))
        #expect(result.contains("gauge"))
    }

    @Test("read-only law: videoDuration on a video errors with the exact copy shape")
    func readOnlyExactCopy() async {
        var (doc, cardId) = aiFreshDoc()
        let video = Part(partType: .video, cardId: cardId, name: "Clip", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(video)
        let result = await aiSet(&doc, cardId: cardId, part: "Clip", property: "videoduration", value: "999")
        #expect(result == "\"videoduration\" of video \"Clip\" is read-only.")
    }

    @Test("color error: garbage hex errors with the exact copy")
    func colorErrorExactCopy() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let result = await aiSet(&doc, cardId: cardId, part: "s", property: "fillcolor", value: "reddish")
        #expect(result == "\"reddish\" is not a color — use \"#RRGGBB\" or \"#RRGGBBAA\" (empty clears).")
    }

    @Test("color kind normalizes to #UPPER on round-trip")
    func colorNormalizesToUpper() async {
        var (doc, cardId) = aiFreshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        _ = await aiSet(&doc, cardId: cardId, part: "s", property: "fillcolor", value: "#ff00aa")
        #expect(doc.parts.first { $0.name == "s" }?.fillColor == "#FF00AA")
    }
}

// MARK: - progressMin dispatch (mock §3.1, Condition 8)

@Suite("AI progressMin dispatch", .serialized)
struct AIProgressMinDispatchTests {
    @Test("GET is always \"0\"; SET accepts only 0, else errors with the exact copy")
    func progressMinDispatch() async {
        var (doc, cardId) = aiFreshDoc()
        let progress = Part(partType: .progressView, cardId: cardId, name: "p", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(progress)
        let got = await aiGet(&doc, cardId: cardId, part: "p", property: "min")
        #expect(got == "0")
        let setZero = await aiSet(&doc, cardId: cardId, part: "p", property: "min", value: "0")
        #expect(setZero.contains("Set"), "unexpected: \(setZero)")
        let setNonZero = await aiSet(&doc, cardId: cardId, part: "p", property: "min", value: "5")
        #expect(setNonZero == "progress always starts at 0 — set the max instead.")
    }
}

// MARK: - tint dispatch (H6 alias symmetry)

@Suite("AI tint dispatch", .serialized)
struct AITintDispatchTests {
    @Test("tint routes: gauge→gaugeTint, progressView→progressTint")
    func tintDispatch() async {
        var (doc, cardId) = aiFreshDoc()
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let progress = Part(partType: .progressView, cardId: cardId, name: "p", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(progress)
        _ = await aiSet(&doc, cardId: cardId, part: "g", property: "tint", value: "#AABBCC")
        _ = await aiSet(&doc, cardId: cardId, part: "p", property: "tint", value: "#112233")
        #expect(doc.parts.first { $0.name == "g" }?.gaugeTint == "#AABBCC")
        #expect(doc.parts.first { $0.name == "p" }?.progressTint == "#112233")
        let gaugeGet = await aiGet(&doc, cardId: cardId, part: "g", property: "tint")
        #expect(gaugeGet == "#AABBCC")
    }
}

// MARK: - Masking law extended to the AI getter (Security condition 1)

@Suite("AI masking law — value/htmlContent/searchText on a secure field", .serialized)
struct AIMaskingLawTests {
    @Test("`value` of a .secure field masks (the exact bypass this change closes)")
    func valueMasksOnSecureField() async {
        var (doc, cardId) = aiFreshDoc()
        var field = Part(partType: .field, cardId: cardId, name: "pwd", left: 0, top: 0, width: 100, height: 40)
        field.fieldStyle = .secure
        field.textContent = "s3cr3t-value"
        doc.addPart(field)
        let got = await aiGet(&doc, cardId: cardId, part: "pwd", property: "value")
        #expect(got == "(masked)")
        #expect(!got.contains("s3cr3t-value"))
    }

    @Test("`htmlContent` of a .secure field masks")
    func htmlContentMasksOnSecureField() async {
        var (doc, cardId) = aiFreshDoc()
        var field = Part(partType: .field, cardId: cardId, name: "pwd", left: 0, top: 0, width: 100, height: 40)
        field.fieldStyle = .secure
        field.htmlContent = "s3cr3t-html"
        doc.addPart(field)
        let got = await aiGet(&doc, cardId: cardId, part: "pwd", property: "htmlcontent")
        #expect(got == "(masked)")
        #expect(!got.contains("s3cr3t-html"))
    }

    @Test("`searchText` of a .secure field masks")
    func searchTextMasksOnSecureField() async {
        var (doc, cardId) = aiFreshDoc()
        var field = Part(partType: .field, cardId: cardId, name: "pwd", left: 0, top: 0, width: 100, height: 40)
        field.fieldStyle = .secure
        field.searchText = "s3cr3t-search"
        doc.addPart(field)
        let got = await aiGet(&doc, cardId: cardId, part: "pwd", property: "searchtext")
        #expect(got == "(masked)")
        #expect(!got.contains("s3cr3t-search"))
    }

    @Test("a non-secure (rectangle) field still reads plaintext through value/htmlContent/searchText")
    func nonSecureFieldStaysPlaintext() async {
        var (doc, cardId) = aiFreshDoc()
        var field = Part(partType: .field, cardId: cardId, name: "notes", left: 0, top: 0, width: 100, height: 40)
        field.fieldStyle = .rectangle
        field.textContent = "hello"
        field.htmlContent = "<b>hi</b>"
        field.searchText = "term"
        doc.addPart(field)
        let value = await aiGet(&doc, cardId: cardId, part: "notes", property: "value")
        let html = await aiGet(&doc, cardId: cardId, part: "notes", property: "htmlcontent")
        let search = await aiGet(&doc, cardId: cardId, part: "notes", property: "searchtext")
        #expect(value == "hello")
        #expect(html == "<b>hi</b>")
        #expect(search == "term")
    }
}
