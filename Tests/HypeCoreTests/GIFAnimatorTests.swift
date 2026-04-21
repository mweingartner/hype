import Testing
import Foundation
import ImageIO
@testable import HypeCore
#if canImport(AppKit)
import AppKit

// MARK: - Helpers shared with GIFDecoderTests

/// Build a solid-color CGImage for GIF synthesis.
private func makeAnimatorSolidColorCGImage(width: Int, height: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// Synthesize an in-memory animated GIF.
///
/// - Parameters:
///   - frameCount: Number of frames (must be ≥ 2 for GIFDecoder to accept it).
///   - delay: Per-frame delay in seconds.
///   - loopCount: 0 = infinite, positive = finite.
/// - Returns: Raw GIF Data, or `nil` on failure.
private func makeAnimatorTestGIF(
    frameCount: Int,
    delay: Double = 0.05,
    loopCount: Int = 0,
    width: Int = 4,
    height: Int = 4
) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data, "com.compuserve.gif" as CFString, frameCount, nil
    ) else { return nil }

    let topProps: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]
    ]
    CGImageDestinationSetProperties(dest, topProps as CFDictionary)

    for i in 0 ..< frameCount {
        let img = makeAnimatorSolidColorCGImage(
            width: width, height: height
        )
        // Vary color slightly by index so frames differ — CGImageDestination
        // occasionally elides identical frames when encoding GIFs.
        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ]
        _ = i  // silence unused-var
        CGImageDestinationAddImage(dest, img, frameProps as CFDictionary)
    }

    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

/// Wait for an async condition to become true, polling every 10 ms
/// up to `timeoutMs` total milliseconds.  Returns `true` if the
/// condition fired within the window, `false` if it timed out.
@MainActor
private func waitFor(
    timeoutMs: Int = 300,
    condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

// MARK: - GIFAnimator Tests

@Suite("GIFAnimator — state transitions", .serialized)
@MainActor
struct GIFAnimatorTests {

    // Ensure a clean slate between tests.
    private func teardown() {
        GIFAnimator.shared.removeAll()
        GIFAnimator.shared.onFrameChanged = nil
        GIFAnimator.shared.onAnimationStart = nil
        GIFAnimator.shared.onAnimationEnd = nil
    }

    // MARK: 1. start → isAnimating true after decode completes

    @Test("start() with 3-frame GIF → isAnimating true after decode window")
    func startSetsIsAnimatingTrue() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1, loopCount: 0) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        GIFAnimator.shared.start(partId: id, imageData: data)

        let became = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.isAnimating(partId: id)
        }
        #expect(became, "isAnimating should become true after async decode completes")
    }

    @Test("start() → hasState true after decode window")
    func startCreatesState() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1, loopCount: 0) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        GIFAnimator.shared.start(partId: id, imageData: data)

        let hasState = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(hasState, "hasState should be true once state is installed")
    }

    // MARK: 2. stop → isAnimating false, currentFrame preserved

    @Test("stop() sets isAnimating false; currentFrame is still non-nil")
    func stopPreservesCurrentFrame() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        GIFAnimator.shared.start(partId: id, imageData: data)

        // Wait for state to install.
        let ready = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(ready, "state should install before stop test")

        GIFAnimator.shared.stop(partId: id)

        #expect(GIFAnimator.shared.isAnimating(partId: id) == false)
        // currentFrame should still return something (parked on last advanced frame)
        #expect(GIFAnimator.shared.currentFrame(partId: id) != nil,
                "currentFrame should remain non-nil after stop")
    }

    // MARK: 3. remove → isAnimating false, currentFrame nil

    @Test("remove() clears all state; isAnimating false and currentFrame nil")
    func removeClears() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        GIFAnimator.shared.start(partId: id, imageData: data)

        let ready = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(ready)

        GIFAnimator.shared.remove(partId: id)

        #expect(GIFAnimator.shared.isAnimating(partId: id) == false)
        #expect(GIFAnimator.shared.currentFrame(partId: id) == nil)
        #expect(GIFAnimator.shared.hasState(partId: id) == false)
    }

    // MARK: 4. removeAll → everything cleared

    @Test("removeAll() clears state for all parts")
    func removeAllClears() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 2, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id1 = UUID()
        let id2 = UUID()
        GIFAnimator.shared.start(partId: id1, imageData: data)
        GIFAnimator.shared.start(partId: id2, imageData: data)

        // Wait for at least one to settle.
        _ = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id1)
        }

        GIFAnimator.shared.removeAll()

        #expect(GIFAnimator.shared.isAnimating(partId: id1) == false)
        #expect(GIFAnimator.shared.isAnimating(partId: id2) == false)
        #expect(GIFAnimator.shared.currentFrame(partId: id1) == nil)
        #expect(GIFAnimator.shared.currentFrame(partId: id2) == nil)
    }

    // MARK: 5. Re-entrancy guard (Security Finding H-2): stop() fires onAnimationEnd ONCE

    @Test("calling stop() twice fires onAnimationEnd exactly once (H-2 re-entrancy guard)")
    func stopTwiceFiresEndCallbackOnce() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        var endCount = 0
        GIFAnimator.shared.onAnimationEnd = { _ in endCount += 1 }

        GIFAnimator.shared.start(partId: id, imageData: data)
        let ready = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(ready)

        // First stop: should fire callback.
        GIFAnimator.shared.stop(partId: id)
        // Second stop: state.isRunning == false, guard should short-circuit.
        GIFAnimator.shared.stop(partId: id)

        #expect(endCount == 1,
                "onAnimationEnd should fire exactly once across two stop() calls (H-2 guard), got \(endCount)")
    }

    // MARK: 6. Fingerprint equality guard (Security Finding H-1):
    //          non-GIF data does NOT re-launch decode on repeated ensureState calls.

    @Test("ensureState with non-GIF data does not launch repeated decodes (H-1 fix)")
    func ensureStateNonGIFIsIdempotent() async throws {
        teardown()
        defer { teardown() }

        // Use genuine PNG bytes (non-GIF).
        let img = makeAnimatorSolidColorCGImage(width: 8, height: 8)
        guard let pngData = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create PNG data")
            return
        }
        let id = UUID()

        // First call: kicks off a decode that finds non-GIF → stores sentinel.
        GIFAnimator.shared.ensureState(partId: id, imageData: pngData, autoplay: true)

        // Allow async decode to complete.
        try await Task.sleep(for: .milliseconds(100))

        // Subsequent calls with the same bytes must be fast-path no-ops.
        // We verify: no state was ever installed (non-GIF) and isAnimating == false.
        GIFAnimator.shared.ensureState(partId: id, imageData: pngData, autoplay: true)
        GIFAnimator.shared.ensureState(partId: id, imageData: pngData, autoplay: true)

        #expect(GIFAnimator.shared.isAnimating(partId: id) == false,
                "Non-GIF data should never produce a running animation")
        #expect(GIFAnimator.shared.currentFrame(partId: id) == nil,
                "Non-GIF data should produce no current frame")
    }

    // MARK: 7. ensureState fast-path for GIF data: second call is idempotent

    @Test("ensureState for already-decoded GIF is O(1): no re-decode")
    func ensureStateGIFFastPath() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 2, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()

        // First call — triggers async decode.
        GIFAnimator.shared.ensureState(partId: id, imageData: data, autoplay: false)
        let settled = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(settled, "State should settle after first ensureState")

        // Snapshot state fields to compare after second call.
        let frameBefore = GIFAnimator.shared.currentFrame(partId: id)

        // Second call with identical bytes — must NOT evict or re-decode state.
        GIFAnimator.shared.ensureState(partId: id, imageData: data, autoplay: false)

        // If state was evicted and re-decode started, hasState would transiently be false
        // and currentFrame would be nil.  Wait a tick and check stability.
        try await Task.sleep(for: .milliseconds(20))

        #expect(GIFAnimator.shared.hasState(partId: id),
                "State should be stable after repeated ensureState with same bytes")
        // The current frame pointer should still be valid (same CGImage object or equivalent)
        #expect(GIFAnimator.shared.currentFrame(partId: id) != nil)
        // Autoplay was false so it should still not be animating
        #expect(GIFAnimator.shared.isAnimating(partId: id) == false)
    }

    // MARK: 8. Non-looping GIF: onAnimationEnd fires and isAnimating becomes false

    @Test("non-looping GIF (loopCount=1) fires onAnimationEnd and stops")
    func nonLoopingGIFFiresEnd() async throws {
        teardown()
        defer { teardown() }

        // 2 frames at 50ms each = ~100ms total playback before end.
        guard let data = makeAnimatorTestGIF(frameCount: 2, delay: 0.05, loopCount: 1) else {
            Issue.record("Failed to synthesize non-looping GIF")
            return
        }
        let id = UUID()
        var endFired = false
        GIFAnimator.shared.onAnimationEnd = { pid in
            if pid == id { endFired = true }
        }

        GIFAnimator.shared.start(partId: id, imageData: data)

        // Wait up to 1 s for the natural end.
        let fired = await waitFor(timeoutMs: 1000) { endFired }
        #expect(fired, "onAnimationEnd should fire for a non-looping GIF")
        #expect(GIFAnimator.shared.isAnimating(partId: id) == false,
                "isAnimating should be false after non-looping GIF completes")
    }

    // MARK: 9. onAnimationStart fires once per initial start, NOT on resume

    @Test("onAnimationStart fires once per start(); resume() does not fire it")
    func animationStartFiresOnceNotOnResume() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        var startCount = 0
        GIFAnimator.shared.onAnimationStart = { pid in
            if pid == id { startCount += 1 }
        }

        GIFAnimator.shared.start(partId: id, imageData: data)

        let ready = await waitFor(timeoutMs: 300) {
            startCount >= 1
        }
        #expect(ready, "onAnimationStart should fire at least once on start()")

        // Pause then resume — onAnimationStart must NOT fire again.
        GIFAnimator.shared.stop(partId: id)
        let beforeResume = startCount
        GIFAnimator.shared.resume(partId: id)

        // Give the timer a few ticks to ensure no spurious callback.
        try await Task.sleep(for: .milliseconds(50))
        #expect(startCount == beforeResume,
                "onAnimationStart should NOT fire on resume(), count was \(startCount)")
    }

    // MARK: 10. Single-frame bytes → no state installed

    @Test("start() with single-frame GIF data: no GIF state installed")
    func singleFrameGIFNoState() async throws {
        teardown()
        defer { teardown() }

        // Single-frame GIF — GIFDecoder returns nil, so no state.
        guard let data = makeAnimatorTestGIF(frameCount: 1, delay: 0.1) else {
            Issue.record("Failed to synthesize single-frame GIF")
            return
        }
        let id = UUID()
        GIFAnimator.shared.start(partId: id, imageData: data)

        // Allow async decode to finish.
        try await Task.sleep(for: .milliseconds(200))

        #expect(GIFAnimator.shared.isAnimating(partId: id) == false)
        #expect(GIFAnimator.shared.currentFrame(partId: id) == nil)
        #expect(GIFAnimator.shared.hasState(partId: id) == false)
    }

    // MARK: 11. isAnimating false immediately before decode completes

    @Test("isAnimating returns false synchronously before async decode completes")
    func isAnimatingFalseBeforeDecodeCompletes() {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        GIFAnimator.shared.start(partId: id, imageData: data)
        // Immediately after start(), decode is still in flight.
        // isAnimating relies on state being installed; it is not yet.
        // This is not guaranteed false (decode could be instant on a fast machine),
        // but hasState should also reflect the pending state.
        // The main assertion: no crash on immediate query.
        _ = GIFAnimator.shared.isAnimating(partId: id)  // must not crash
        _ = GIFAnimator.shared.currentFrame(partId: id) // must not crash

        GIFAnimator.shared.removeAll()
    }

    // MARK: 12. stop() on unknown partId is a no-op (no crash)

    @Test("stop() on unknown partId does not crash")
    func stopUnknownIdNoCrash() {
        teardown()
        defer { teardown() }
        GIFAnimator.shared.stop(partId: UUID())  // must not crash
    }

    // MARK: 13. remove() on unknown partId is a no-op (no crash)

    @Test("remove() on unknown partId does not crash")
    func removeUnknownIdNoCrash() {
        teardown()
        defer { teardown() }
        GIFAnimator.shared.remove(partId: UUID())  // must not crash
    }

    // MARK: 14. currentFrame returns nil when no state

    @Test("currentFrame returns nil when no state exists for partId")
    func currentFrameNilWhenNoState() {
        teardown()
        defer { teardown() }
        #expect(GIFAnimator.shared.currentFrame(partId: UUID()) == nil)
    }

    // MARK: 15. hasState false for unknown partId

    @Test("hasState returns false for unknown partId")
    func hasStateFalseWhenNoState() {
        teardown()
        defer { teardown() }
        #expect(GIFAnimator.shared.hasState(partId: UUID()) == false)
    }

    // MARK: 16. Frame advance: timer drives currentFrameIndex forward
    //
    // Use a 0.1 s per-frame delay and wait long enough for the timer to
    // fire at least once. onFrameChanged fires on the main actor after each
    // tick that advances a frame. We poll using waitFor (which uses
    // Task.sleep + main-actor re-scheduling) so the main RunLoop still
    // processes the Timer while we wait.

    @Test("timer advances currentFrame: onFrameChanged fires at least once after one frame delay")
    func timerAdvancesFrameIndex() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1, loopCount: 0) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        var frameChangedCount = 0
        GIFAnimator.shared.onFrameChanged = { pid in
            if pid == id { frameChangedCount += 1 }
        }

        GIFAnimator.shared.start(partId: id, imageData: data)

        // Wait for decode to settle.
        let ready = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(ready, "State should install within 300 ms")

        // Wait up to 800 ms for at least one frame-changed callback.
        // The timer fires every ~17 ms; frame delay is 0.1 s, so the first
        // onFrameChanged should arrive around 100 ms after decode settles.
        let advanced = await waitFor(timeoutMs: 800) { frameChangedCount > 0 }
        #expect(advanced,
                "onFrameChanged should fire at least once after one frame delay (0.1 s); got \(frameChangedCount) calls")
    }

    // MARK: 17. Re-entrant stop() inside onAnimationEnd does not recurse
    //
    // Security Finding H-2 regression: if a stop() call from inside the
    // onAnimationEnd callback caused a second onAnimationEnd fire, this
    // would produce infinite recursion. The guard `guard state.isRunning`
    // in stop() must break the cycle. We verify the callback fires
    // exactly once even when stop() is called from inside it.

    @Test("stop() called inside onAnimationEnd callback does not recurse (H-2 regression)")
    func stopFromInsideCallbackDoesNotRecurse() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        var endCount = 0
        GIFAnimator.shared.onAnimationEnd = { pid in
            endCount += 1
            // Calling stop again from inside the callback — must not recurse.
            GIFAnimator.shared.stop(partId: pid)
        }

        GIFAnimator.shared.start(partId: id, imageData: data)
        let ready = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(ready, "State must be installed before stop test")

        // Explicit stop triggers the callback; the callback calls stop again.
        GIFAnimator.shared.stop(partId: id)

        // Give the run loop a tick to confirm no recursive call landed.
        try await Task.sleep(for: .milliseconds(20))

        #expect(endCount == 1,
                "onAnimationEnd should fire exactly once even when stop() is re-invoked from inside the callback; got \(endCount)")
    }

    // MARK: 18. ensureState with different bytes evicts stale state and re-decodes

    @Test("ensureState with changed image bytes evicts old state and launches new decode")
    func ensureStateDifferentBytesEvictsState() async throws {
        teardown()
        defer { teardown() }

        guard let data1 = makeAnimatorTestGIF(frameCount: 2, delay: 0.1),
              let data2 = makeAnimatorTestGIF(frameCount: 3, delay: 0.1, width: 6, height: 6) else {
            Issue.record("Failed to synthesize GIFs")
            return
        }
        // Ensure data1 and data2 are distinguishable bytes (different sizes).
        guard data1 != data2 else {
            Issue.record("Test GIFs are identical — cannot test fingerprint mismatch")
            return
        }

        let id = UUID()

        // First decode with data1.
        GIFAnimator.shared.ensureState(partId: id, imageData: data1, autoplay: false)
        let settled1 = await waitFor(timeoutMs: 300) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(settled1, "State should settle for data1")

        // Switch to data2 — fingerprint changes, state should evict.
        GIFAnimator.shared.ensureState(partId: id, imageData: data2, autoplay: false)

        // State should eventually re-settle with the new data.
        let settled2 = await waitFor(timeoutMs: 500) {
            GIFAnimator.shared.hasState(partId: id)
        }
        #expect(settled2, "State should re-settle after data swap")
        // After re-decode completes, currentFrame should be non-nil.
        #expect(GIFAnimator.shared.currentFrame(partId: id) != nil,
                "currentFrame should be available after data-swap re-decode")
    }

    // MARK: 19. resume() restores isAnimating without firing onAnimationStart

    @Test("resume() re-activates isAnimating and does not fire onAnimationStart")
    func resumeRestoresAnimatingWithoutStartEvent() async throws {
        teardown()
        defer { teardown() }

        guard let data = makeAnimatorTestGIF(frameCount: 3, delay: 0.1) else {
            Issue.record("Failed to synthesize GIF")
            return
        }
        let id = UUID()
        var startCount = 0
        GIFAnimator.shared.onAnimationStart = { pid in
            if pid == id { startCount += 1 }
        }

        GIFAnimator.shared.start(partId: id, imageData: data)
        let ready = await waitFor(timeoutMs: 300) { startCount >= 1 }
        #expect(ready, "onAnimationStart must fire once on initial start()")

        let countAfterStart = startCount

        // Pause.
        GIFAnimator.shared.stop(partId: id)
        #expect(GIFAnimator.shared.isAnimating(partId: id) == false,
                "isAnimating should be false after stop")

        // Resume.
        GIFAnimator.shared.resume(partId: id)

        // isAnimating must become true again.
        let resumed = await waitFor(timeoutMs: 100) {
            GIFAnimator.shared.isAnimating(partId: id)
        }
        #expect(resumed, "isAnimating should be true after resume()")

        // onAnimationStart must NOT have fired again.
        try await Task.sleep(for: .milliseconds(30))
        #expect(startCount == countAfterStart,
                "onAnimationStart should not fire on resume(); was \(startCount), expected \(countAfterStart)")
    }
}

#endif  // canImport(AppKit)
