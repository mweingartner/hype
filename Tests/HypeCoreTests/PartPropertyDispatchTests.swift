import Testing
import Foundation
@testable import HypeCore

// End-to-end HypeTalk dispatch tests for `control-property-consistency`
// P1 (design.md test plan items 3–7, 9–10; mock acceptance criteria
// 3–7, 9). `PartPropertyRegistryConformanceTests.swift` covers the
// registry's own data shape; these tests drive real scripts through
// `MessageDispatcher` to prove the interpreter's GET/SET switches
// honor the registry gate end to end.

// MARK: - Test helpers

/// Runs `script` as the `test` handler of a fresh card and returns the
/// execution result.
private func run(_ script: String, cardId: UUID, doc: HypeDocument) async -> ExecutionResult {
    var doc = doc
    doc.cards[0].script = script
    return await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
        message: "openCard", params: [], targetId: cardId,
        document: doc, currentCardId: cardId
    ) }
}

/// Builds a fresh single-card document with an output field named "out".
private func freshDoc() -> (HypeDocument, UUID) {
    var doc = HypeDocument.newDocument(name: "Test")
    let cardId = doc.cards[0].id
    let out = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 60, width: 100, height: 40)
    doc.addPart(out)
    return (doc, cardId)
}

// MARK: - Bare polymorphic dispatch cells (design.md §3.1/§3.3)

@Suite("Dispatch cells — bare polymorphic words route per part type", .serialized)
struct PolymorphicDispatchCellTests {

    @Test("`value` on a gauge writes gaugeValue (clamped/rounded via setGaugeValue)")
    func valueOnGauge() async {
        var (doc, cardId) = freshDoc()
        var gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        gauge.gaugeMin = 0
        gauge.gaugeMax = 10
        doc.addPart(gauge)
        let result = await run("""
        on openCard
          set the value of gauge "g" to 5
          put the gaugevalue of gauge "g" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "5")
    }

    @Test("`value` on a progress view writes progressValue")
    func valueOnProgressView() async {
        var (doc, cardId) = freshDoc()
        var progress = Part(partType: .progressView, cardId: cardId, name: "p", left: 0, top: 0, width: 100, height: 40)
        progress.progressTotal = 100
        doc.addPart(progress)
        let result = await run("""
        on openCard
          set the value of progressview "p" to 42
          put the progressvalue of progressview "p" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "42")
    }

    @Test("`value` on a segmented control writes selectedSegment")
    func valueOnSegmented() async {
        var (doc, cardId) = freshDoc()
        let segmented = Part(partType: .segmented, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(segmented)
        let result = await run("""
        on openCard
          set the value of segmented "s" to 2
          put the selectedsegment of segmented "s" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "2")
    }

    @Test("`value` on a text field writes textContent (Security condition 1: through the masked cell)")
    func valueOnField() async {
        var (doc, cardId) = freshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let result = await run("""
        on openCard
          set the value of field "f" to "typed text"
          put the value of field "f" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "typed text")
    }

    @Test("`value` on a button (no value concept) errors on SET (A2) but GET keeps the permissive controlValue read")
    func valueOnButtonErrorsOnSetOnly() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let setResult = await run("""
        on openCard
          set the value of button "b" to "5"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(setResult.status == .error)
        #expect(setResult.error?.message.contains("does not apply") == true)

        let getResult = await run("""
        on openCard
          put the value of button "b" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(getResult.status == .completed, "Script error: \(getResult.error?.message ?? "")")
        #expect(getResult.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "0")
    }

    @Test("`on` applies only to toggle; errors elsewhere on both verbs")
    func onOnlyOnToggle() async {
        var (doc, cardId) = freshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let result = await run("""
        on openCard
          set the on of field "f" to true
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.error?.message.contains("\"on\"") == true)
    }

    @Test("`min`/`max` on a gauge route to gaugeMin/gaugeMax (H3)")
    func minMaxOnGauge() async {
        var (doc, cardId) = freshDoc()
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let result = await run("""
        on openCard
          set the min of gauge "g" to 2
          set the max of gauge "g" to 20
          put the gaugemin of gauge "g" & "," & the gaugemax of gauge "g" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "2,20")
    }

    @Test("`min`/`max` on a calendar route to minDate/maxDate (H3)")
    func minMaxOnCalendar() async {
        var (doc, cardId) = freshDoc()
        let calendar = Part(partType: .calendar, cardId: cardId, name: "c", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(calendar)
        let result = await run("""
        on openCard
          set the min of calendar "c" to "2024-01-01"
          set the max of calendar "c" to "2024-12-31"
          put the mindate of calendar "c" & "," & the maxdate of calendar "c" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "2024-01-01,2024-12-31")
    }

    @Test("`min` on a progress view: GET is always \"0\"; SET accepts only 0, else errors with the exact copy")
    func minOnProgressView() async {
        var (doc, cardId) = freshDoc()
        let progress = Part(partType: .progressView, cardId: cardId, name: "p", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(progress)
        let getResult = await run("""
        on openCard
          put the min of progressview "p" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(getResult.status == .completed, "Script error: \(getResult.error?.message ?? "")")
        #expect(getResult.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "0")

        let setZero = await run("""
        on openCard
          set the min of progressview "p" to 0
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(setZero.status == .completed, "Script error: \(setZero.error?.message ?? "")")

        let setNonZero = await run("""
        on openCard
          set the min of progressview "p" to 5
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(setNonZero.status == .error)
        #expect(setNonZero.error?.message == "progress always starts at 0 — set the max instead.")
    }

    @Test("`min`/`max`/`step` error on an unlisted type (e.g. button)")
    func minMaxStepErrorOnButton() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        for bareName in ["min", "max", "step"] {
            let result = await run("""
            on openCard
              set the \(bareName) of button "b" to 5
            end openCard
            """, cardId: cardId, doc: doc)
            #expect(result.status == .error, "\(bareName) should error on button")
        }
    }

    @Test("`loop`/`volume` route per type: video→video*, music family→music* (H7)")
    func loopVolumeVideoVsMusic() async {
        var (doc, cardId) = freshDoc()
        let video = Part(partType: .video, cardId: cardId, name: "v", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(video)
        let music = Part(partType: .musicPlayer, cardId: cardId, name: "m", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(music)
        let result = await run("""
        on openCard
          set the loop of video "v" to true
          set the volume of video "v" to 0.5
          set the loop of musicplayer "m" to true
          set the volume of musicplayer "m" to 0.25
          put the videoloop of video "v" & "," & the videovolume of video "v" & "," & the musicloop of musicplayer "m" & "," & the musicvolume of musicplayer "m" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "true,0.5,true,0.25")
    }

    @Test("`autoplay` applies to video only")
    func autoplayVideoOnly() async {
        var (doc, cardId) = freshDoc()
        let video = Part(partType: .video, cardId: cardId, name: "v", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(video)
        let result = await run("""
        on openCard
          set the autoplay of video "v" to true
          put the videoautoplay of video "v" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "true")

        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        var doc2 = result.modifiedDocument ?? doc
        doc2.addPart(gauge)
        let errorResult = await run("""
        on openCard
          set the autoplay of gauge "g" to true
        end openCard
        """, cardId: cardId, doc: doc2)
        #expect(errorResult.status == .error)
    }

    @Test("`duration` routes: video→videoDuration (RO), music family→musicDuration (RW), audioRecorder→audioDuration (RO)")
    func durationDispatch() async {
        var (doc, cardId) = freshDoc()
        var video = Part(partType: .video, cardId: cardId, name: "v", left: 0, top: 0, width: 100, height: 40)
        video.videoDuration = 12.5
        doc.addPart(video)
        var recorder = Part(partType: .audioRecorder, cardId: cardId, name: "r", left: 0, top: 0, width: 100, height: 40)
        recorder.audioDuration = 3.2
        doc.addPart(recorder)
        // musicDuration's GET case only surfaces the real value for
        // .appleMusicBrowser (or when a musicSourceID is bound) — a
        // pre-existing, unrelated quirk this change preserves
        // verbatim, so the music-family fixture here uses that type.
        let music = Part(partType: .appleMusicBrowser, cardId: cardId, name: "m", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(music)

        let getResult = await run("""
        on openCard
          put the duration of video "v" & "," & the duration of recorder "r" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(getResult.status == .completed, "Script error: \(getResult.error?.message ?? "")")
        #expect(getResult.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "12.5,3.2")

        let videoSetResult = await run("""
        on openCard
          set the duration of video "v" to 99
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(videoSetResult.status == .error, "video duration is read-only")

        let musicSetResult = await run("""
        on openCard
          set the duration of applemusicbrowser "m" to 30
          put the musicduration of applemusicbrowser "m" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(musicSetResult.status == .completed, "Script error: \(musicSetResult.error?.message ?? "")")
        #expect(musicSetResult.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "30")
    }

    @Test("`tint` routes: gauge→gaugeTint, progressView→progressTint (H6 alias symmetry: GET now has it too)")
    func tintDispatch() async {
        var (doc, cardId) = freshDoc()
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let progress = Part(partType: .progressView, cardId: cardId, name: "p", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(progress)
        let result = await run("""
        on openCard
          set the tint of gauge "g" to "#AABBCC"
          set the tint of progressview "p" to "#112233"
          put the tint of gauge "g" & "," & the tint of progressview "p" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "#AABBCC,#112233")
    }

    @Test("`total` is a compat alias of progressTotal (progress \"Total\" retirement, mock §1.2)")
    func totalAliasOfProgressTotal() async {
        var (doc, cardId) = freshDoc()
        let progress = Part(partType: .progressView, cardId: cardId, name: "p", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(progress)
        let result = await run("""
        on openCard
          set the total of progressview "p" to 500
          put the progresstotal of progressview "p" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "500")
    }

    @Test("`items` routes: button→popupItems, menu→menuItems")
    func itemsDispatch() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let menu = Part(partType: .menu, cardId: cardId, name: "m", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(menu)
        let result = await run("""
        on openCard
          set the items of button "b" to "One" & return & "Two"
          set the items of menu "m" to "Alpha" & return & "Beta"
          put the popupitems of button "b" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        // HypeTalk's `return` constant is "\r" (classic HyperCard line
        // delimiter), not "\n".
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "One\rTwo")
        let menuPart = result.modifiedDocument?.parts.first { $0.name == "m" }
        #expect(menuPart?.menuItems == "Alpha\rBeta")
    }

    @Test("`decimals` routes: gauge→gaugeDecimals, progressView→progressDecimals")
    func decimalsDispatch() async {
        var (doc, cardId) = freshDoc()
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let result = await run("""
        on openCard
          set the decimals of gauge "g" to 3
          put the gaugedecimals of gauge "g" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "3")
    }

    @Test("`decimals` errors on an unlisted type")
    func decimalsErrorsOnField() async {
        var (doc, cardId) = freshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let result = await run("""
        on openCard
          set the decimals of field "f" to 3
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
    }

    @Test("`color` routes: colorWell→colorWellHex, divider→dividerColor (fixes bare color→colorWellHex on every type)")
    func colorDispatch() async {
        var (doc, cardId) = freshDoc()
        let colorWell = Part(partType: .colorWell, cardId: cardId, name: "cw", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(colorWell)
        let divider = Part(partType: .divider, cardId: cardId, name: "d", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(divider)
        let result = await run("""
        on openCard
          set the color of colorwell "cw" to "#010203"
          set the color of divider "d" to "#040506"
          put the colorwellhex of colorwell "cw" & "," & the dividercolor of divider "d" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "#010203,#040506")

        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        var doc2 = result.modifiedDocument ?? doc
        doc2.addPart(button)
        let errorResult = await run("""
        on openCard
          set the color of button "b" to "#010203"
        end openCard
        """, cardId: cardId, doc: doc2)
        #expect(errorResult.status == .error, "bare color must no longer write colorWellHex on every type")
    }

    @Test("`background` routes to scene3D's background3D only (short form)")
    func backgroundDispatch() async {
        var (doc, cardId) = freshDoc()
        let scene = Part(partType: .scene3D, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(scene)
        let result = await run("""
        on openCard
          set the background of scene3d "s" to "#0000FF"
          put the scenebackground of scene3d "s" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "#0000FF")
    }
}

// MARK: - `size` pair law (fixes H2, A6; mock §3.2, criterion 4)

@Suite("size pair law", .serialized)
struct SizePairLawTests {
    @Test("GET returns \"width,height\"")
    func sizeGetReturnsPair() async {
        var (doc, cardId) = freshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 33, height: 77)
        doc.addPart(shape)
        let result = await run("""
        on openCard
          put the size of shape "s" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "33,77")
    }

    @Test("SET of \"width,height\" writes both dimensions")
    func sizeSetWritesPair() async {
        var (doc, cardId) = freshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 10, height: 10)
        doc.addPart(shape)
        let result = await run("""
        on openCard
          set the size of shape "s" to "150,90"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let shape2 = result.modifiedDocument?.parts.first { $0.name == "s" }
        #expect(shape2?.width == 150)
        #expect(shape2?.height == 90)
    }

    @Test("SET of a single number errors with the exact mock copy naming textSize")
    func sizeSetSingleNumberErrors() async {
        var (doc, cardId) = freshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 10, height: 10)
        doc.addPart(shape)
        let result = await run("""
        on openCard
          set the size of shape "s" to 24
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.error?.message == "size expects \"width,height\" — use textSize to set the text size.")
    }

    @Test("textSize is unaffected by the size split — still sets the text point size")
    func textSizeStillWorks() async {
        var (doc, cardId) = freshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let result = await run("""
        on openCard
          set the textsize of field "f" to 24
          put the textsize of field "f" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "24")
    }
}

// MARK: - Strict-SET law (fixes H10, A2; mock §3.7, criterion 5)

@Suite("Strict-SET law — unknown property errors, no variable created", .serialized)
struct StrictSetLawTests {
    @Test("SET of an unrecognized property on an object target errors, with the property name in the message")
    func unknownPropertyErrors() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let result = await run("""
        on openCard
          set the totallyBogusProperty of button "b" to "x"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.error?.message.contains("totallyBogusProperty") == true)
        #expect(result.error?.message.contains("no such property") == true)
    }

    @Test("a near-miss typo produces a did-you-mean hint")
    func typoProducesHint() async {
        var (doc, cardId) = freshDoc()
        let gauge = Part(partType: .gauge, cardId: cardId, name: "g", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(gauge)
        let result = await run("""
        on openCard
          set the gaugvalue of gauge "g" to 5
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.error?.message.contains("did you mean") == true, "message: \(result.error?.message ?? "")")
    }

    @Test("the typo never creates a script variable of that name (H10 fix)")
    func typoDoesNotCreateVariable() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        // The old behavior: an unrecognized `set the X of <object> to V`
        // silently ran `env.setVariable(X, V)`. If that still happened,
        // a SUBSEQUENT read of the bare variable `nonexistentProp` would
        // see "leaked" — but since the statement now throws before
        // completing, the handler never reaches the `put` line at all,
        // and the overall result is an error (not a completed run that
        // silently populated a variable).
        let result = await run("""
        on openCard
          set the nonexistentProp of button "b" to "leaked"
          put nonexistentProp into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent.isEmpty != false)
    }

    @Test("plain `set <var> to <expr>` with no object target is untouched (Condition 2)")
    func plainVariableSetUnaffected() async {
        var (doc, cardId) = freshDoc()
        let result = await run("""
        on openCard
          set myVariable to "still works"
          put myVariable into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "still works")
    }

    @Test("all 12 classic no-op stubs (11 field props + scroll) accept SET silently, never erroring")
    func noOpStubsNeverError() async {
        var (doc, cardId) = freshDoc()
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let stubs = [
            "scroll", "scrollpos", "sharedtext", "sharedhilite", "showlines", "showpict",
            "fixedlineheight", "multiplelines", "dontsearch", "autoselect", "autotab",
            "cantdelete", "cantmodify",
        ]
        for stub in stubs {
            let result = await run("""
            on openCard
              set the \(stub) of field "f" to "5"
            end openCard
            """, cardId: cardId, doc: doc)
            #expect(result.status == .completed, "\(stub) should be a silent no-op, got: \(result.error?.message ?? "")")
        }
    }
}

// MARK: - Wrong-type write law (mock criterion 6)

@Suite("Wrong-type write law — type-scoped keys error on non-applicable types", .serialized)
struct WrongTypeWriteLawTests {
    @Test("gaugeValue on a button errors instead of mutating a never-rendered field")
    func gaugeValueOnButtonErrors() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let result = await run("""
        on openCard
          set the gaugevalue of button "b" to 999
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.error?.message.contains("gaugevalue") == true)
        #expect(result.error?.message.contains("gauge") == true)
    }

    @Test("progressTotal on a shape errors")
    func progressTotalOnShapeErrors() async {
        var (doc, cardId) = freshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let result = await run("""
        on openCard
          set the progresstotal of shape "s" to 100
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
    }

    @Test("read-only law: duration of video errors on SET with the exact copy shape")
    func videoDurationReadOnly() async {
        var (doc, cardId) = freshDoc()
        var video = Part(partType: .video, cardId: cardId, name: "Clip", left: 0, top: 0, width: 100, height: 40)
        video.videoDuration = 5
        doc.addPart(video)
        let result = await run("""
        on openCard
          set the videoduration of video "Clip" to 999
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.error?.message == "\"videoduration\" of video \"Clip\" is read-only.")
    }
}

// MARK: - H-regression tests (mock criterion 7)

@Suite("H-bug regression tests", .serialized)
struct HBugRegressionTests {
    @Test("H1: GET style of a shape now mirrors SET (shapeType), not fieldStyle garbage")
    func h1ShapeStyleGetMirrorsSet() async {
        var (doc, cardId) = freshDoc()
        var shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        shape.shapeType = .oval
        doc.addPart(shape)
        let result = await run("""
        on openCard
          put the style of shape "s" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "oval")
    }

    @Test("H4: `marked` targeting a part errors on both GET and SET")
    func h4MarkedOnPartErrors() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let getResult = await run("""
        on openCard
          put the marked of button "b" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(getResult.status == .error)
        #expect(getResult.error?.message == "\"marked\" is a card property — try the marked of this card.")

        let setResult = await run("""
        on openCard
          set the marked of button "b" to true
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(setResult.status == .error)
        #expect(setResult.error?.message == "\"marked\" is a card property — try the marked of this card.")
    }

    @Test("H4: `marked` targeting the CARD itself still works")
    func h4MarkedOnCardStillWorks() async {
        let (doc, cardId) = freshDoc()
        // `HypeDocument.newDocument` names the first card "Card 1" —
        // the stack itself is named "Test" (see `freshDoc()`), which
        // is a different object entirely.
        let result = await run("""
        on openCard
          set the marked of card "Card 1" to true
          put the marked of card "Card 1" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "true")
    }

    @Test("H5: `set the user level` accepts the spaced \"user level\" form (parity with GET), exercised at the AST level")
    func h5SpacedUserLevelSet() {
        // The HypeTalk parser does not currently tokenize a bare,
        // spaced two-word property name like "user level" in the
        // `set the <property> of <target> to <value>` grammar (it
        // special-cases only a short, fixed list of name-adjective
        // pairs like "short name"/"long name" — "user"+"level" isn't
        // among them). This is a pre-existing, out-of-scope parser
        // gap that pre-dates this change and affects the GET side
        // identically (flagged separately in the Builder's report).
        // The fix this change makes is at the INTERPRETER level (the
        // stack SET switch now accepts the "user level" spelling,
        // matching what GET already accepted) — exercised here by
        // constructing the AST directly, bypassing the parser.
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let handler = Handler(
            name: "test",
            handlerType: .message,
            params: [],
            body: [
                .set(
                    property: "user level",
                    of: .objectRef(ObjectRefExpr(objectType: "stack", identifier: .literal("stack"))),
                    to: .literal("5")
                ),
            ],
            line: 1
        )
        let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
        let result = Interpreter().execute(handler: handler, params: [], context: context)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.stack.userLevel == HypeUserLevel.scripting.rawValue)
    }

    @Test("H8: GET icon of a button with no icon `is empty` (was \"0\")")
    func h8IconEmptySentinel() async {
        var (doc, cardId) = freshDoc()
        let button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let result = await run("""
        on openCard
          if the icon of button "b" is empty then
            put "yes" into field "out"
          else
            put "no" into field "out"
          end if
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "yes")
    }

    @Test("H8: SET icon of \"\" or \"0\" clears the bound icon")
    func h8IconClearedByEmptyOrZero() async {
        var (doc, cardId) = freshDoc()
        var button = Part(partType: .button, cardId: cardId, name: "b", left: 0, top: 0, width: 100, height: 40)
        button.iconId = UUID()
        doc.addPart(button)
        let result = await run("""
        on openCard
          set the icon of button "b" to "0"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "b" }?.iconId == nil)
    }

    @Test("H9: background gains short/long/abbreviated name variants")
    func h9BackgroundNameVariants() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let bg = doc.addBackground(name: "Menu Background")
        doc.cards[0].backgroundId = bg.id
        let out = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 60, width: 100, height: 40)
        doc.addPart(out)
        let result = await run("""
        on openCard
          put the short name of background "Menu Background" & "|" & the long name of background "Menu Background" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let text = result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent ?? ""
        #expect(text == "Menu Background|bkgnd \"Menu Background\"")
    }
}

// MARK: - Hex color validation (Decision 4, Condition 6)

@Suite("Color validation — HexColor vs ChartConfig.normalizedHex parity", .serialized)
struct ColorValidationTests {
    @Test("garbage hex on a HexColor-validated property errors with the exact copy")
    func garbageHexErrorsOnFillColor() async {
        var (doc, cardId) = freshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let result = await run("""
        on openCard
          set the fillcolor of shape "s" to "reddish"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
        #expect(result.error?.message == "\"reddish\" is not a color — use \"#RRGGBB\" or \"#RRGGBBAA\" (empty clears).")
    }

    @Test("empty string clears a color (auto)")
    func emptyStringClearsColor() async {
        var (doc, cardId) = freshDoc()
        var shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        shape.fontColor = "#123456"
        doc.addPart(shape)
        let result = await run("""
        on openCard
          set the fontcolor of shape "s" to ""
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "s" }?.fontColor == "")
    }

    @Test("8-digit hex (with alpha) normalizes to #UPPER")
    func eightDigitHexNormalizes() async {
        var (doc, cardId) = freshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let result = await run("""
        on openCard
          set the strokecolor of shape "s" to "aabbccdd"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "s" }?.strokeColor == "#AABBCCDD")
    }

    /// Design-Review Condition C3 / Condition 6: chart spider colors are
    /// DELIBERATELY not routed through `HexColor` — they keep using
    /// `ChartConfig.normalizedHex`'s fallback-on-invalid behavior so
    /// every existing chart path stays byte-identical. This test pins
    /// the parity BETWEEN the two validators by contrasting them
    /// directly: a garbage color on a HexColor-gated property errors
    /// (proven above), while the identical garbage string written to a
    /// chart's spider grid color does NOT error — it silently keeps the
    /// prior value, exactly as `ChartConfig.normalizedHex` already did
    /// before this change. (A literal "chart spider-color write errors"
    /// test is not implementable without violating Condition 6, which
    /// requires chart color paths to stay byte-identical; flagged for
    /// Design/Security to confirm this reconciliation.)
    @Test("chart spider grid color keeps its silent fallback-on-invalid behavior (\"reddish\" does not error)")
    func chartSpiderColorGarbageDoesNotError() async {
        var (doc, cardId) = freshDoc()
        var chart = Part(partType: .chart, cardId: cardId, name: "Sales", left: 0, top: 0, width: 200, height: 200)
        var config = ChartConfig()
        config.chartType = .spider
        config.spiderGridColor = "#C9CDD3"
        chart.chartData = config.toJSON()
        doc.addPart(chart)
        let result = await run("""
        on openCard
          set the spidergridcolor of chart "Sales" to "reddish"
          put the spidergridcolor of chart "Sales" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "chart spider color write must not error (Condition 6): \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "#C9CDD3", "garbage must fall back to the prior color, unchanged")
    }
}

// MARK: - Chart single-path (A4; mock criterion 9)

@Suite("Chart single-path — title/interactive stay chart-scoped", .serialized)
struct ChartSinglePathTests {
    @Test("chart `title`/`interactive` work; `interactive` on a non-chart, non-colorWell type errors")
    func chartTitleAndInteractive() async {
        var (doc, cardId) = freshDoc()
        var chart = Part(partType: .chart, cardId: cardId, name: "Sales", left: 0, top: 0, width: 200, height: 200)
        chart.chartData = ChartConfig().toJSON()
        doc.addPart(chart)
        let result = await run("""
        on openCard
          set the title of chart "Sales" to "Q3 Revenue"
          set the interactive of chart "Sales" to true
          put the title of chart "Sales" & "," & the interactive of chart "Sales" into field "out"
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent == "Q3 Revenue,true")
    }

    @Test("bare `interactive` on a shape (neither chart nor colorWell) errors")
    func interactiveOnShapeErrors() async {
        var (doc, cardId) = freshDoc()
        let shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(shape)
        let result = await run("""
        on openCard
          set the interactive of shape "s" to true
        end openCard
        """, cardId: cardId, doc: doc)
        #expect(result.status == .error)
    }
}
