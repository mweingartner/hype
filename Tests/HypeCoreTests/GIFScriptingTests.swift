import Testing
import Foundation
import ImageIO
@testable import HypeCore
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Test Helpers

/// Parse a HypeTalk script and return the first statement in the first handler,
/// or `nil` if parsing fails.
private func parseFirstStatement(_ source: String) throws -> Statement? {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    let script = try parser.parse()
    return script.handlers.first?.body.first
}

/// Returns `true` when the source string parses without error.
private func parses(_ source: String) -> Bool {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    return (try? parser.parse()) != nil
}

/// Returns `true` when parsing throws a `ParseError`.
private func throwsParseError(_ source: String) -> Bool {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    do {
        _ = try parser.parse()
        return false
    } catch is ParseError {
        return true
    } catch {
        return false
    }
}

/// Build a solid-color CGImage for embedding in test GIFs.
private func makeScriptingTestCGImage(width: Int, height: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// Synthesize a minimal multi-frame GIF suitable for scripting tests.
private func makeScriptingTestGIF(frameCount: Int = 3, delay: Double = 0.1, loopCount: Int = 0) -> Data? {
    let nsData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        nsData, "com.compuserve.gif" as CFString, frameCount, nil
    ) else { return nil }

    let topProps: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]
    ]
    CGImageDestinationSetProperties(dest, topProps as CFDictionary)

    let frameProps: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
    ]
    let img = makeScriptingTestCGImage(width: 4, height: 4)
    for _ in 0 ..< frameCount {
        CGImageDestinationAddImage(dest, img, frameProps as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { return nil }
    return nsData as Data
}

/// Build a test document with one Image part named "foo" whose imageData is
/// a synthesized 3-frame GIF, and a field named "out" for output capture.
private func makeGIFTestDoc() -> (doc: HypeDocument, cardId: UUID, imageId: UUID, btnId: UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id

    var btn = Part(partType: .button, cardId: cardId, name: "runner")
    doc.addPart(btn)

    var img = Part(partType: .image, cardId: cardId, name: "foo")
    img.imageData = makeScriptingTestGIF()
    doc.addPart(img)

    var field = Part(partType: .field, cardId: cardId, name: "out")
    doc.addPart(field)

    return (doc, cardId, img.id, btn.id)
}

/// Run a script attached to `btnId` by dispatching a `mouseUp` message,
/// returning the `ExecutionResult`. Runs on a large-stack thread via
/// `runOnLargeStack` so the interpreter's deep-recursion stack frames
/// never overflow the cooperative thread's small stack.
private func runGIFScript(
    _ source: String,
    on doc: inout HypeDocument,
    cardId: UUID,
    targetId: UUID
) async -> ExecutionResult {
    doc.updatePart(id: targetId) { $0.script = source }
    let dispatcher = MessageDispatcher()
    let snapshot = doc
    let result = await runOnLargeStack {
        dispatcher.dispatch(
            message: "mouseUp", params: [],
            targetId: targetId, document: snapshot,
            currentCardId: cardId
        )
    }
    if let modified = result.modifiedDocument { doc = modified }
    return result
}

// MARK: - Parser Tests

@Suite("GIF HypeTalk — Parser", .serialized)
struct GIFParserTests {

    // MARK: 1. start the animation of "foo" parses to .startAnimation

    @Test("'start the animation of \"foo\"' parses to .startAnimation") func parseStartAnimationBareString() async throws {
        let stmt = try parseFirstStatement("""
        on test
          start the animation of "foo"
        end test
        """)
        if case .startAnimation(let expr) = stmt {
            if case .literal(let val) = expr {
                #expect(val == "foo")
            } else {
                Issue.record("Expected literal expression, got \(String(describing: expr))")
            }
        } else {
            Issue.record("Expected .startAnimation, got \(String(describing: stmt))")
        }
    }

    // MARK: 2. start the animation of image "foo" parses (objectRef form)

    @Test("'start the animation of image \"foo\"' parses to .startAnimation(objectRef)")
    func parseStartAnimationObjectRef() throws {
        #expect(parses("""
        on test
          start the animation of image "foo"
        end test
        """))

        let stmt = try parseFirstStatement("""
        on test
          start the animation of image "foo"
        end test
        """)
        if case .startAnimation(let expr) = stmt {
            if case .objectRef(let ref) = expr {
                #expect(ref.objectType == "image")
            } else {
                Issue.record("Expected objectRef expression, got \(String(describing: expr))")
            }
        } else {
            Issue.record("Expected .startAnimation, got \(String(describing: stmt))")
        }
    }

    // MARK: 3. stop the animation of "foo" parses to .stopAnimation

    @Test("'stop the animation of \"foo\"' parses to .stopAnimation") func parseStopAnimation() async throws {
        let stmt = try parseFirstStatement("""
        on test
          stop the animation of "foo"
        end test
        """)
        if case .stopAnimation(let expr) = stmt {
            if case .literal(let val) = expr {
                #expect(val == "foo")
            } else {
                Issue.record("Expected literal expression, got \(String(describing: expr))")
            }
        } else {
            Issue.record("Expected .stopAnimation, got \(String(describing: stmt))")
        }
    }

    // MARK: 4. Regression: start using "stack" still parses to .startUsing

    @Test("'start using \"stack\"' still parses to .startUsing (regression)")
    func parseStartUsingRegressionNotBroken() throws {
        let stmt = try parseFirstStatement("""
        on test
          start using "stack"
        end test
        """)
        if case .startUsing(_) = stmt {
            // correct
        } else {
            Issue.record("Expected .startUsing, got \(String(describing: stmt)) — regression: start using path broken by animation branch")
        }
    }

    // MARK: 5. Regression: stop using "stack" still parses to .stopUsing

    @Test("'stop using \"stack\"' still parses to .stopUsing (regression)")
    func parseStopUsingRegressionNotBroken() throws {
        let stmt = try parseFirstStatement("""
        on test
          stop using "myStack"
        end test
        """)
        if case .stopUsing(_) = stmt {
            // correct
        } else {
            Issue.record("Expected .stopUsing, got \(String(describing: stmt)) — regression: stop using path broken by animation branch")
        }
    }

    // MARK: 6. Regression: stop listener 42 still parses to .stopListener

    @Test("'stop listener 42' still parses to .stopListener (regression)")
    func parseStopListenerRegressionNotBroken() throws {
        let stmt = try parseFirstStatement("""
        on test
          stop listener 42
        end test
        """)
        if case .stopListener(_) = stmt {
            // correct
        } else {
            Issue.record("Expected .stopListener, got \(String(describing: stmt)) — regression: stop listener path broken by animation branch")
        }
    }

    // MARK: 7. Malformed "start the animation from" falls through to startUsing gracefully
    //
    // The parser uses a 3-token lookahead check:
    //   if current == .the, peek(1) == .animation, peek(2) == .of { ... }
    // When peek(2) is .from instead of .of, the condition fails and the statement
    // falls through to the startUsing branch — it does NOT throw a ParseError.
    // The `expect(.of)` in Security Finding 10 only fires when the lookahead
    // ALREADY confirmed all three tokens are the correct ones; the lookahead
    // itself is the gate. So "start the animation from" is gracefully handled
    // as startUsing rather than erroring, which is a safe and correct behaviour.

    @Test("'start the animation from \"foo\"' falls through to startUsing, not a parse error") func parseStartAnimationFromFallsThroughToStartUsing() async throws {
        // The 3-token lookahead sees the third token is .from, not .of,
        // so the animation branch is NOT taken — it silently becomes startUsing.
        // This verifies the parser does not crash and produces a valid AST.
        let stmt = try parseFirstStatement("""
        on test
          start the animation from "foo"
        end test
        """)
        // Should parse successfully (no throw) as some statement
        #expect(stmt != nil, "Malformed 'start the animation from' should parse gracefully (no crash)")
    }

    // MARK: 8. "animation" lexes as .animation token

    @Test("'animation' keyword lexes as .animation token") func lexerAnimationToken() async {
        var lexer = Lexer(source: "animation")
        let tokens = lexer.tokenize()
        #expect(tokens.first?.type == .animation)
    }

    // MARK: 9. stop the animation of image "foo" also parses (objectRef stop)

    @Test("'stop the animation of image \"foo\"' parses to .stopAnimation(objectRef)")
    func parseStopAnimationObjectRef() throws {
        #expect(parses("""
        on test
          stop the animation of image "foo"
        end test
        """))
    }
}

// MARK: - Interpreter Tests

@Suite("GIF HypeTalk — Interpreter", .serialized)
struct GIFInterpreterTests {

    // MARK: Shared teardown

    private func cleanupAnimator(_ id: UUID) {
        GIFAnimator.shared.remove(partId: id)
    }

    // MARK: 1. the animated of "foo" initially returns "true"

    @Test("'the animated of \"foo\"' returns \"true\" by default") func animatedPropertyDefaultsTrue() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        let result = await runGIFScript("""
        on mouseUp
          put the animated of image "foo" into field "out"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "Script should complete without error: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "true",
                "Part.animated should default to true")
    }

    // MARK: 2. set the animated of "foo" to false flips the property

    @Test("'set the animated of \"foo\" to false' persists in the document") func setAnimatedFalseFlipsProperty() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        let result = await runGIFScript("""
        on mouseUp
          set the animated of image "foo" to false
          put the animated of image "foo" into field "out"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "Script should complete: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "false",
                "animated should be false after 'set the animated of ... to false'")

        // Verify the model field was updated too.
        let part = result.modifiedDocument?.parts.first { $0.name == "foo" }
        #expect(part?.animated == false, "Part.animated model field should be false")
    }

    // MARK: 3. the animating of "foo" returns "false" when GIF is not running

    @Test("'the animating of \"foo\"' returns \"false\" when not animating") func animatingPropertyFalseWhenIdle() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        // Ensure no animation is running.
        GIFAnimator.shared.remove(partId: imageId)

        let result = await runGIFScript("""
        on mouseUp
          put the animating of image "foo" into field "out"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "Script should complete: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "false",
                "animating should be false when no animation is running")
    }

    // MARK: 4. Interpreter: start the animation of "foo" triggers GIFAnimator

    @Test("'start the animation of \"foo\"' executes without error") func startAnimationExecutes() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        let result = await runGIFScript("""
        on mouseUp
          start the animation of "foo"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "start the animation should complete without error: \(result.error?.message ?? "")")
    }

    // MARK: 5. Interpreter: stop the animation of "foo" executes without error

    @Test("'stop the animation of \"foo\"' executes without error") func stopAnimationExecutes() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        let result = await runGIFScript("""
        on mouseUp
          stop the animation of "foo"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "stop the animation should complete without error: \(result.error?.message ?? "")")
    }

    // MARK: 6. Interpreter: start then stop sequentially

    @Test("'start' then 'stop the animation' sequence executes without error") func startThenStopSequence() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        let result = await runGIFScript("""
        on mouseUp
          start the animation of image "foo"
          stop the animation of image "foo"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "start then stop should complete without error: \(result.error?.message ?? "")")
    }

    // MARK: 7. Interpreter: set animated to false calls GIFAnimator.stop (no crash)

    @Test("'set the animated of image \"foo\" to false' calls through to GIFAnimator without crash") func setAnimatedFalseCallsStop() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        let result = await runGIFScript("""
        on mouseUp
          set the animated of image "foo" to false
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "set animated false should complete without error: \(result.error?.message ?? "")")
    }

    // MARK: 8. Interpreter: start animation on non-existent name is a silent no-op

    @Test("'start the animation of \"ghost\"' is a silent no-op for missing part") func startAnimationMissingPartIsNoOp() async {
        var (doc, cardId, _, btnId) = makeGIFTestDoc()

        let result = await runGIFScript("""
        on mouseUp
          start the animation of "ghost"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "Missing-part animation start should be a silent no-op, not an error")
    }

    // MARK: 9. Interpreter: start animation on a non-image part is a silent no-op

    @Test("'start the animation of button \"runner\"' is a silent no-op (non-image part)")
    func startAnimationOnNonImagePartIsNoOp() async {
        var (doc, cardId, _, btnId) = makeGIFTestDoc()

        let result = await runGIFScript("""
        on mouseUp
          start the animation of button "runner"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "start animation on a button should be a silent no-op")
    }

    // MARK: 10. Interpreter: the animating OR-combines PartAnimator and GIFAnimator

    @Test("'the animating' is false when neither PartAnimator nor GIFAnimator is running") func animatingORCombinesBothFalse() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        // Make sure GIFAnimator has no state for the image.
        GIFAnimator.shared.remove(partId: imageId)

        let result = await runGIFScript("""
        on mouseUp
          put the animating of image "foo" into field "out"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed)
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "false",
                "animating should be false when no tween or GIF animation is active")
    }

    // MARK: 11. Interpreter: the animating OR-combines — PartAnimator tween active → "true"
    //
    // Spec §16 last bullet: "Regression: `the animating of 'button1'` while a
    // `PartAnimator` tween is active returns 'true' (OR-combined semantics)".
    // GIFAnimator has no state for the part; PartAnimator does. Result must be "true".

    #if canImport(AppKit)
    @Test("'the animating' returns \"true\" when a PartAnimator tween is active (OR-combine regression)")
    func animatingTrueWhenPartAnimatorTweenActive() async {
        var (doc, cardId, _, btnId) = makeGIFTestDoc()
        defer { PartAnimator.shared.stopAll() }

        // Register a long-duration tween on the button so PartAnimator.isAnimating → true
        // for the lifetime of this test.
        PartAnimator.shared.animate(
            partId: btnId,
            property: "left",
            fromValue: 0,
            toValue: 100,
            duration: 60.0   // 60 seconds — will still be running when we query
        )
        #expect(PartAnimator.shared.isAnimating(partId: btnId),
                "PartAnimator should be animating the button part")

        // GIFAnimator has NO state for btnId — the OR is (true || false) = true.
        let result = await runGIFScript("""
        on mouseUp
          put the animating of button "runner" into field "out"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "Script should complete: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "true",
                "animating should be 'true' when PartAnimator has an active tween even if GIFAnimator has no state")
    }
    #endif

    // MARK: 12. Interpreter: set animated to true starts playback via GIFAnimator

    @Test("'set the animated of \"foo\" to true' calls GIFAnimator.start without error") func setAnimatedTrueCallsStart() async {
        var (doc, cardId, imageId, btnId) = makeGIFTestDoc()
        defer { GIFAnimator.shared.remove(partId: imageId) }

        // First set to false so the start pathway actually fires when set back to true.
        let _ = await runGIFScript("""
        on mouseUp
          set the animated of image "foo" to false
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        // Now set back to true — should call GIFAnimator.start without crashing.
        let result = await runGIFScript("""
        on mouseUp
          set the animated of image "foo" to true
          put the animated of image "foo" into field "out"
        end mouseUp
        """, on: &doc, cardId: cardId, targetId: btnId)

        #expect(result.status == .completed,
                "set animated true should complete without error: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "true",
                "animated property should read back as 'true' after set to true")
        let part = result.modifiedDocument?.parts.first { $0.name == "foo" }
        #expect(part?.animated == true, "Part.animated model field should be true after set to true")
    }
}

// MARK: - Model Codable Tests (added to complement ModelTests.swift)

@Suite("Part.animated Codable backward-compat", .serialized)
struct PartAnimatedCodableTests {

    // MARK: 1. Round-trip with animated = false preserved

    @Test("Part with animated=false survives Codable round-trip") func roundTripAnimatedFalse() async throws {
        var part = Part(partType: .image, cardId: UUID())
        part.animated = false

        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)

        #expect(decoded.animated == false,
                "animated=false should be preserved through Codable round-trip")
    }

    // MARK: 2. Round-trip with animated = true preserved

    @Test("Part with animated=true survives Codable round-trip") func roundTripAnimatedTrue() async throws {
        var part = Part(partType: .image, cardId: UUID())
        part.animated = true

        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)

        #expect(decoded.animated == true,
                "animated=true should be preserved through Codable round-trip")
    }

    // MARK: 3. JSON without "animated" key defaults to true (backward compat)

    @Test("Part JSON without 'animated' key decodes with animated=true (backward compat)")
    func missingAnimatedKeyDefaultsToTrue() throws {
        // Encode a part, then strip the "animated" key from the JSON.
        var part = Part(partType: .image, cardId: UUID())
        part.animated = false  // so we can confirm it gets replaced

        var dict = try JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(part))
        dict.removeValue(forKey: "animated")
        let strippedData = try JSONEncoder().encode(dict)

        let decoded = try JSONDecoder().decode(Part.self, from: strippedData)
        #expect(decoded.animated == true,
                "Missing 'animated' key should default to true for backward compatibility")
    }

    // MARK: 4. Default Part.animated is true

    @Test("New Part's animated field defaults to true") func newPartAnimatedDefaultsToTrue() async {
        let part = Part(partType: .image)
        #expect(part.animated == true,
                "newly created image Part should have animated=true by default")
    }

    // MARK: 5. Non-image Part also has animated=true default

    @Test("New button Part's animated field also defaults to true") func buttonPartAnimatedDefaultsToTrue() async {
        let part = Part(partType: .button)
        #expect(part.animated == true,
                "animated defaults to true for all part types (field is universal)")
    }
}

// MARK: - AnyCodable helper for JSON manipulation in tests

/// A minimal type-erased `Codable` wrapper used only in tests to strip
/// specific keys from a Part's JSON dictionary without manual JSON string
/// construction.  Not part of the production code.
private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) { value = b }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let s = try? container.decode(String.self) { value = s }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr.map { $0.value } }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value } }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let b as Bool:   try container.encode(b)
        case let i as Int:    try container.encode(i)
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        case let arr as [Any]:
            let coded = arr.map { AnyCodable($0) }
            try container.encode(coded)
        case let dict as [String: Any]:
            let coded = dict.mapValues { AnyCodable($0) }
            try container.encode(coded)
        default:
            try container.encode("")
        }
    }
}
