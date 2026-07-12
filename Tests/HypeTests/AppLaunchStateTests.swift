import Testing
import Foundation
import AppKit
@testable import Hype

/// SplitMix64 — small, fast, reproducible. Mirrors the PRNG convention used
/// by `Tests/HypeCoreTests/InterpreterFuzzTests.swift` so the seeded clamp
/// sweep below stays deterministic and replayable across runs.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }
}

@Suite("App launch state")
struct AppLaunchStateTests {

    @Test("existing last-opened file is restored")
    func existingLastOpenedFileIsRestored() throws {
        let defaults = makeDefaults()
        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("hype")
        try Data("{}".utf8).write(to: temporaryFile)

        defaults.set(temporaryFile.path, forKey: AppLaunchState.Key.lastOpenedFilePath)
        let state = AppLaunchState(defaults: defaults)

        #expect(state.lastOpenedFileURL == temporaryFile)
    }

    @Test("missing last-opened file is ignored")
    func missingLastOpenedFileIsIgnored() {
        let defaults = makeDefaults()
        defaults.set("/tmp/does-not-exist-\(UUID().uuidString).hype", forKey: AppLaunchState.Key.lastOpenedFilePath)

        let state = AppLaunchState(defaults: defaults)

        #expect(state.lastOpenedFileURL == nil)
    }

    @Test("saved window frame is validated and clamped to visible screens")
    func windowFrameValidationAndClamping() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        state.save(windowFrame: NSRect(x: 50, y: 60, width: 900, height: 700), forFileAt: nil)

        let visible = state.restorableWindowFrame(
            forFileAt: nil,
            visibleScreenFrames: [NSRect(x: 0, y: 0, width: 1600, height: 1000)]
        )
        // The saved frame (50,60,900,700) does not intersect a screen at
        // (2000,0,1200,900) at all. Rather than discard it, it must
        // relocate fully inside that screen (size preserved since it
        // fits): x = min(max(50,2000), 2000+1200-900) = 2000,
        // y = min(max(60,0), 0+900-700) = 60.
        let relocated = state.restorableWindowFrame(
            forFileAt: nil,
            visibleScreenFrames: [NSRect(x: 2000, y: 0, width: 1200, height: 900)]
        )

        #expect(visible == NSRect(x: 50, y: 60, width: 900, height: 700))
        #expect(relocated == NSRect(x: 2000, y: 60, width: 900, height: 700))
    }

    @Test("first-ever launch has no saved frame to restore")
    func firstEverLaunchHasNoSavedFrame() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)

        #expect(state.storedWindowFrame == nil)
        #expect(state.storedWindowFrame(forFileAt: makeStackURL()) == nil)
        #expect(state.restorableWindowFrame(forFileAt: nil, visibleScreenFrames: [NSRect(x: 0, y: 0, width: 1600, height: 1000)]) == nil)
    }

    // MARK: - Per-stack storage identity

    @Test("per-path save/lookup round-trips the exact saved frame")
    func perPathRoundTrip() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let url = makeStackURL()
        let frame = NSRect(x: 120, y: 80, width: 1024, height: 768)

        state.save(windowFrame: frame, forFileAt: url)

        #expect(state.storedWindowFrame(forFileAt: url) == frame)
    }

    @Test("two stacks never share a saved per-path frame")
    func twoStacksDoNotShareASavedFrame() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let stackA = makeStackURL()
        let stackB = makeStackURL()
        let frameA = NSRect(x: 0, y: 0, width: 1400, height: 900)
        let frameB = NSRect(x: 200, y: 150, width: 640, height: 480)

        state.save(windowFrame: frameA, forFileAt: stackA)
        state.save(windowFrame: frameB, forFileAt: stackB)

        #expect(state.storedWindowFrame(forFileAt: stackA) == frameA)
        #expect(state.storedWindowFrame(forFileAt: stackB) == frameB)
    }

    // MARK: - Regression: an auxiliary window's save must not poison another stack's frame
    //
    // The reported bug: an auxiliary window (or a second stack) saved a
    // small, off-center frame that clobbered the one global frame every
    // stack fell back to, so reopening stack A landed at that tiny
    // geometry instead of its own. Per-path storage fixes this by giving
    // every stack its own entry; these tests pin that a save under one
    // identity can never overwrite another's.

    @Test("saving a small frame under a different stack's URL does not overwrite an existing stack's own per-path entry")
    func savingADifferentStacksFrameDoesNotOverwriteAnExistingStacksEntry() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let stackA = makeStackURL()
        let largeFrameA = NSRect(x: 80, y: 120, width: 1800, height: 1100)
        state.save(windowFrame: largeFrameA, forFileAt: stackA)

        // Simulates the reported bug's trigger: another stack (or an
        // auxiliary window standing in for one) saves a small, off-center
        // frame under a DIFFERENT identity after stack A's frame is
        // already stored.
        let stackB = makeStackURL()
        let smallFrameB = NSRect(x: 5, y: 5, width: 320, height: 240)
        state.save(windowFrame: smallFrameB, forFileAt: stackB)

        #expect(state.storedWindowFrame(forFileAt: stackA) == largeFrameA)
        #expect(state.storedWindowFrame(forFileAt: stackB) == smallFrameB)
    }

    @Test("saving the untitled/global frame does not alter any existing stack's per-path entry")
    func savingTheUntitledGlobalFrameDoesNotAlterAnExistingStacksEntry() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let stackA = makeStackURL()
        let largeFrameA = NSRect(x: 80, y: 120, width: 1800, height: 1100)
        state.save(windowFrame: largeFrameA, forFileAt: stackA)

        // The untitled/global fallback save (url == nil) is exactly what
        // an auxiliary window with no associated file writes. It must
        // update only the legacy scalar keys, never stack A's per-path
        // entry.
        let smallGlobalFrame = NSRect(x: 5, y: 5, width: 320, height: 240)
        state.save(windowFrame: smallGlobalFrame, forFileAt: nil)

        #expect(state.storedWindowFrame(forFileAt: stackA) == largeFrameA)
        #expect(state.storedWindowFrame(forFileAt: nil) == smallGlobalFrame)
    }

    @Test("frameKey canonicalizes symlinks and relative components to the same identity")
    func frameKeyCanonicalization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLaunchStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let realFile = directory.appendingPathComponent("Stack.hype")
        try Data("{}".utf8).write(to: realFile)

        let symlink = directory.appendingPathComponent("Alias.hype")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)

        // Lexically collapses to `directory/Stack.hype` regardless of
        // whether "ignored" exists on disk — `.standardizedFileURL`
        // removes ".." components without needing a filesystem round trip.
        let dotPath = directory
            .appendingPathComponent("ignored", isDirectory: true)
            .appendingPathComponent("..")
            .appendingPathComponent("Stack.hype")

        let canonical = AppLaunchState.frameKey(forFileAt: realFile)

        #expect(AppLaunchState.frameKey(forFileAt: symlink) == canonical)
        #expect(AppLaunchState.frameKey(forFileAt: dotPath) == canonical)
    }

    @Test("per-path lookup falls back to the legacy global frame when no entry exists for that path")
    func perPathLookupFallsBackToLegacyWhenNoEntryExists() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let legacyFrame = NSRect(x: 40, y: 40, width: 900, height: 650)
        state.save(windowFrame: legacyFrame, forFileAt: nil)

        let neverOpenedStack = makeStackURL()

        #expect(state.storedWindowFrame(forFileAt: neverOpenedStack) == legacyFrame)
    }

    @Test("an untitled (nil URL) lookup reads only the legacy scalar keys, never the per-path dictionary")
    func nilURLAlwaysUsesTheLegacyGlobalFrame() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let legacyFrame = NSRect(x: 15, y: 25, width: 800, height: 600)
        state.save(windowFrame: legacyFrame, forFileAt: nil)

        // Seed a per-path entry directly (bypassing `save`, which would
        // otherwise keep the legacy scalars in sync) so the legacy keys
        // stay at `legacyFrame` while a DIFFERENT frame exists in the
        // per-path dictionary. If the nil-URL lookup ever consulted that
        // dictionary, it would see this instead.
        let otherStack = makeStackURL()
        defaults.set(
            [AppLaunchState.frameKey(forFileAt: otherStack): [500.0, 500.0, 1200.0, 900.0, 1_700_000_000.0]],
            forKey: AppLaunchState.Key.windowFramesByPath
        )

        #expect(state.storedWindowFrame(forFileAt: nil) == legacyFrame)
    }

    @Test("a non-dictionary windowFramesByPath value is treated as no per-path data at all")
    func topLevelNonDictionaryFallsBackToLegacyForEveryPath() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let legacyFrame = NSRect(x: 5, y: 5, width: 850, height: 620)
        state.save(windowFrame: legacyFrame, forFileAt: nil)
        defaults.set("not-a-dictionary", forKey: AppLaunchState.Key.windowFramesByPath)

        #expect(state.storedWindowFrame(forFileAt: makeStackURL()) == legacyFrame)
    }

    @Test("restorableWindowFrame looks up the per-path frame, then clamps it")
    func restorableWindowFrameAppliesPerPathLookupThenClamps() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let url = makeStackURL()
        state.save(windowFrame: NSRect(x: 50, y: 60, width: 900, height: 700), forFileAt: url)

        let restored = state.restorableWindowFrame(
            forFileAt: url,
            visibleScreenFrames: [NSRect(x: 2000, y: 0, width: 1200, height: 900)]
        )

        #expect(restored == NSRect(x: 2000, y: 60, width: 900, height: 700))
    }

    // MARK: - Malformed / untrusted stored data

    @Test("a present but non-array per-path entry is rejected, not silently replaced by the legacy frame")
    func malformedNonArrayPerPathEntryIsRejected() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let legacyFrame = NSRect(x: 10, y: 10, width: 900, height: 700)
        state.save(windowFrame: legacyFrame, forFileAt: nil)

        let url = makeStackURL()
        defaults.set(
            [AppLaunchState.frameKey(forFileAt: url): "not-an-array"],
            forKey: AppLaunchState.Key.windowFramesByPath
        )

        #expect(state.storedWindowFrame(forFileAt: url) == nil)
    }

    @Test("a per-path entry with the wrong number of elements is rejected")
    func malformedArityPerPathEntryIsRejected() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let legacyFrame = NSRect(x: 10, y: 10, width: 900, height: 700)
        state.save(windowFrame: legacyFrame, forFileAt: nil)

        let url = makeStackURL()
        defaults.set(
            [AppLaunchState.frameKey(forFileAt: url): [10.0, 20.0, 640.0, 480.0]], // missing lastUsed
            forKey: AppLaunchState.Key.windowFramesByPath
        )

        #expect(state.storedWindowFrame(forFileAt: url) == nil)
    }

    @Test(
        "a per-path entry with any non-finite component (including the lastUsed timestamp) is rejected",
        arguments: [0, 1, 2, 3, 4]
    )
    func nonFinitePerPathEntryIsRejected(nonFiniteIndex: Int) {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let url = makeStackURL()

        var components: [Double] = [100, 100, 900, 700, 1_700_000_000]
        components[nonFiniteIndex] = .nan
        defaults.set(
            [AppLaunchState.frameKey(forFileAt: url): components],
            forKey: AppLaunchState.Key.windowFramesByPath
        )

        #expect(state.storedWindowFrame(forFileAt: url) == nil)
    }

    @Test("a non-finite legacy scalar is treated as no saved frame")
    func legacyScalarNaNIsTreatedAsAbsent() {
        let defaults = makeDefaults()
        defaults.set(Double.nan, forKey: AppLaunchState.Key.lastWindowX)
        defaults.set(100.0, forKey: AppLaunchState.Key.lastWindowY)
        defaults.set(900.0, forKey: AppLaunchState.Key.lastWindowWidth)
        defaults.set(700.0, forKey: AppLaunchState.Key.lastWindowHeight)

        let state = AppLaunchState(defaults: defaults)

        #expect(state.storedWindowFrame == nil)
    }

    // MARK: - Pure clamp() geometry

    @Test("a frame fully contained by a screen is returned unchanged")
    func clampPreservesFullyVisibleFrameUnchanged() {
        let frame = NSRect(x: 100, y: 100, width: 900, height: 700)
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)

        #expect(AppLaunchState.clamped(frame, toVisibleScreenFrames: [screen]) == frame)
    }

    @Test("a partially off-screen frame is translated fully onto the screen, preserving size")
    func clampTranslatesPartiallyOffScreenFrameOntoScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let frame = NSRect(x: 1400, y: 900, width: 900, height: 700) // hangs off the right + top

        let result = AppLaunchState.clamped(frame, toVisibleScreenFrames: [screen])

        // x = min(max(1400,0), 1600-900) = 700; y = min(max(900,0), 1000-700) = 300
        #expect(result == NSRect(x: 700, y: 300, width: 900, height: 700))
    }

    @Test("a frame larger than every screen is capped to the target screen's size")
    func clampCapsOversizedFrameToScreenSize() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: -200, y: -100, width: 2000, height: 1500)

        let result = AppLaunchState.clamped(frame, toVisibleScreenFrames: [screen])

        // width = min(2000,1440) = 1440; height = min(1500,900) = 900;
        // origin clamps to the screen's own origin since the capped size
        // exactly fills it.
        #expect(result == NSRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @Test("a frame disconnected from every screen relocates onto the first screen")
    func clampRelocatesFullyDisconnectedFrameToFirstScreen() {
        let mainScreen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let secondScreen = NSRect(x: 1600, y: 0, width: 1600, height: 1000)
        let frame = NSRect(x: -3000, y: -3000, width: 900, height: 700) // touches neither

        let result = AppLaunchState.clamped(frame, toVisibleScreenFrames: [mainScreen, secondScreen])

        // Neither screen intersects the frame; falls back to screens[0]
        // (the main screen), size preserved since it fits.
        #expect(result == NSRect(x: 0, y: 0, width: 900, height: 700))
    }

    @Test("an empty screen list clamps to nil")
    func clampReturnsNilForEmptyScreenList() {
        let frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        #expect(AppLaunchState.clamped(frame, toVisibleScreenFrames: []) == nil)
    }

    @Test("degenerate screen rects are dropped before a clamp target is chosen")
    func clampDropsNonPositiveScreenRectsBeforeChoosingATarget() throws {
        let degenerate = NSRect(x: 0, y: 0, width: 0, height: 900)
        let valid = NSRect(x: 3000, y: 3000, width: 1200, height: 800)
        let frame = NSRect(x: -500, y: -500, width: 900, height: 700)

        // The degenerate rect is first in the array; it must never be
        // chosen as the "screens[0]" disconnected-display fallback just
        // because of its position.
        let result = try #require(AppLaunchState.clamped(frame, toVisibleScreenFrames: [degenerate, valid]))
        #expect(valid.contains(result))

        // A second, differently-degenerate rect (zero height rather than
        // zero width) so a screen list where EVERY entry is degenerate
        // falls through to "empty screens" and returns nil.
        let onlyDegenerateScreens = AppLaunchState.clamped(
            frame,
            toVisibleScreenFrames: [degenerate, NSRect(x: 100, y: 100, width: 500, height: 0)]
        )
        #expect(onlyDegenerateScreens == nil)
    }

    @Test("a non-finite or degenerately small frame is rejected before any screen is considered")
    func clampRejectsNonFiniteOrDegenerateFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let nanFrame = NSRect(x: Double.nan, y: 0, width: 900, height: 700)
        let tinyFrame = NSRect(x: 0, y: 0, width: 50, height: 50)

        #expect(AppLaunchState.clamped(nanFrame, toVisibleScreenFrames: [screen]) == nil)
        #expect(AppLaunchState.clamped(tinyFrame, toVisibleScreenFrames: [screen]) == nil)
    }

    @Test("clamping an already-clamped frame returns it unchanged")
    func clampIsIdempotent() {
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let frame = NSRect(x: 1400, y: 900, width: 900, height: 700)

        let once = AppLaunchState.clamped(frame, toVisibleScreenFrames: [screen])
        let twice = once.flatMap { AppLaunchState.clamped($0, toVisibleScreenFrames: [screen]) }

        #expect(once != nil)
        #expect(once == twice)
    }

    // MARK: - Read-path purity and bounded storage

    @Test("reading the stored/restorable frame never writes to UserDefaults")
    func readPathPerformsNoWrites() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let url = makeStackURL()
        state.save(windowFrame: NSRect(x: 10, y: 20, width: 640, height: 480), forFileAt: url)

        let before = defaults.dictionaryRepresentation() as NSDictionary

        _ = state.storedWindowFrame
        _ = state.storedWindowFrame(forFileAt: url)
        _ = state.storedWindowFrame(forFileAt: nil)
        _ = state.restorableWindowFrame(forFileAt: url, visibleScreenFrames: [NSRect(x: 0, y: 0, width: 1600, height: 1000)])
        _ = AppLaunchState.clamped(NSRect(x: 10, y: 20, width: 640, height: 480), toVisibleScreenFrames: [NSRect(x: 0, y: 0, width: 1600, height: 1000)])

        let after = defaults.dictionaryRepresentation() as NSDictionary
        #expect(before == after)
    }

    @Test("the least-recently-used per-path entry is evicted once storage exceeds the cap")
    func lruEvictionAtCap() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let urls = (0...AppLaunchState.maxStoredFrameEntries).map { index in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("Stack-\(index)-\(UUID().uuidString)")
                .appendingPathExtension("hype")
        }

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, url) in urls.enumerated() {
            state.save(
                windowFrame: NSRect(x: 0, y: 0, width: 640, height: 480),
                forFileAt: url,
                now: baseDate.addingTimeInterval(Double(index))
            )
        }

        let storedFrames = defaults.dictionary(forKey: AppLaunchState.Key.windowFramesByPath) ?? [:]
        let survivingKeys = Set(storedFrames.keys)
        // `urls` has maxStoredFrameEntries + 1 entries; the very first
        // (oldest `now`) must be the one evicted, leaving exactly the
        // rest.
        let expectedSurvivingKeys = Set(urls.dropFirst().map(AppLaunchState.frameKey(forFileAt:)))

        #expect(storedFrames.count == AppLaunchState.maxStoredFrameEntries)
        #expect(survivingKeys == expectedSurvivingKeys)
    }

    // MARK: - Stress: a bloated/corrupted store degrades gracefully and self-heals
    //
    // Security (code) flagged a Low CWE-400 (uncontrolled resource
    // consumption) on the read path: `perPathFrames` decodes the entire
    // `windowFramesByPath` dictionary on every read, with no assumption
    // that it is bounded. `save` is the only thing that enforces the
    // 32-entry cap, so a store that grew (or was corrupted/merged) before
    // that cap applied must still be read safely, and must be pruned back
    // down the next time anything is saved.

    @Test("a store seeded with far more entries than the cap still resolves a known key without crashing, and self-heals to the cap on the next save")
    func bloatedStoreResolvesAKnownEntryAndSelfHealsOnNextSave() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let knownURL = makeStackURL()
        let knownFrame = NSRect(x: 321, y: 654, width: 1000, height: 800)

        // Seed 1000 entries directly into UserDefaults, bypassing `save`'s
        // eviction entirely.
        let bloatedEntries = makeBloatedPerPathEntries(count: 1000, knownURL: knownURL, knownFrame: knownFrame)
        defaults.set(bloatedEntries, forKey: AppLaunchState.Key.windowFramesByPath)

        #expect(bloatedEntries.count == 1001)
        #expect(state.storedWindowFrame(forFileAt: knownURL) == knownFrame)

        // A subsequent save must prune the bloated store back to the cap
        // rather than simply adding one more entry on top of it — the
        // store self-heals on the very next write, regardless of how it
        // became oversized.
        state.save(windowFrame: NSRect(x: 0, y: 0, width: 640, height: 480), forFileAt: makeStackURL())

        let storedFrames = defaults.dictionary(forKey: AppLaunchState.Key.windowFramesByPath) ?? [:]
        #expect(storedFrames.count == AppLaunchState.maxStoredFrameEntries)
    }

    @Test("repeated reads against a bloated store stay fast — no quadratic blowup on the read path")
    func repeatedReadsAgainstABloatedStoreStayFast() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        let knownURL = makeStackURL()
        let knownFrame = NSRect(x: 321, y: 654, width: 1000, height: 800)
        let bloatedEntries = makeBloatedPerPathEntries(count: 1000, knownURL: knownURL, knownFrame: knownFrame)
        defaults.set(bloatedEntries, forKey: AppLaunchState.Key.windowFramesByPath)

        let clock = ContinuousClock()
        var lastResult: NSRect?
        let elapsed = clock.measure {
            for _ in 0..<500 {
                lastResult = state.storedWindowFrame(forFileAt: knownURL)
            }
        }

        #expect(lastResult == knownFrame)
        // `storedWindowFrame(forFileAt:)` fully redecodes `perPathFrames`
        // on every call — an O(entry count) cost by design, confirmed by
        // measurement to run ~0.7-0.9s for 500 reads against 1000 entries
        // on development hardware. That's the exact CWE-400 behavior the
        // eviction cap exists to bound (32 entries in real use is
        // effectively free); this budget is generous enough to absorb CI
        // variance while still catching a much worse regression — e.g. an
        // accidental O(n²) decode, or an unbounded per-call allocation —
        // which would blow far past 5s.
        #expect(elapsed < .seconds(5), "500 reads against a bloated store took \(elapsed), exceeding the 5s budget")
    }

    // MARK: - Seeded clamp sweep

    @Test(
        "clamp sweep: containment, size preservation, and idempotence hold across ~200 seeded frames × 3 screen configs",
        arguments: 0..<200
    )
    func clampSweepAcrossScreenConfigs(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &* 0x100000001B3 &+ 51)

        // Three representative screen layouts: one large single screen,
        // two screens side by side, and a negative-origin layout (an
        // external monitor above/left of the main screen).
        let screenConfigs: [[NSRect]] = [
            [NSRect(x: 0, y: 0, width: 1920, height: 1080)],
            [NSRect(x: 0, y: 0, width: 1920, height: 1080), NSRect(x: 1920, y: 0, width: 1920, height: 1080)],
            [NSRect(x: -1440, y: -900, width: 1440, height: 900)],
        ]
        let smallestScreenWidth = 1440.0
        let smallestScreenHeight = 900.0
        let largestScreenWidth = 1920.0
        let largestScreenHeight = 1080.0

        for screens in screenConfigs {
            let originX = rng.double(-4000...5000)
            let originY = rng.double(-4000...5000)
            // Alternate between sizes guaranteed to fit on every screen in
            // every config above, and sizes guaranteed to be oversized on
            // all of them, so both branches of the clamp algorithm are
            // exercised by the sweep.
            let fitsEveryScreen = rng.next() & 1 == 0
            let width = fitsEveryScreen
                ? rng.double(101...(smallestScreenWidth - 1))
                : rng.double((largestScreenWidth + 1)...4000)
            let height = fitsEveryScreen
                ? rng.double(101...(smallestScreenHeight - 1))
                : rng.double((largestScreenHeight + 1)...4000)
            let frame = NSRect(x: originX, y: originY, width: width, height: height)

            guard let result = AppLaunchState.clamped(frame, toVisibleScreenFrames: screens) else {
                Issue.record("seed \(seed): expected a clamped result for frame \(frame) against \(screens)")
                continue
            }

            // Property 1 — containment: the result always lies fully
            // within some (positive-area) screen in the config.
            let containingScreen = screens.first { $0.width > 0 && $0.height > 0 && $0.contains(result) }
            #expect(containingScreen != nil, "seed \(seed): \(result) is not contained in any screen of \(screens)")

            // Property 2 — size preserved when it fits: sizes chosen
            // smaller than every screen in every config must come back
            // unchanged (only the origin may move).
            if fitsEveryScreen {
                #expect(
                    result.width == frame.width && result.height == frame.height,
                    "seed \(seed): size not preserved for \(frame) -> \(result)"
                )
            }

            // Property 3 — idempotence: clamping an already-clamped frame
            // is a no-op.
            let reclamped = AppLaunchState.clamped(result, toVisibleScreenFrames: screens)
            #expect(reclamped == result, "seed \(seed): clamp not idempotent for \(result) -> \(String(describing: reclamped))")
        }
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suite = "AppLaunchStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStackURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("hype")
    }

    /// A per-path dictionary with `count` synthetic entries plus one more,
    /// distinguishable entry for `knownURL`/`knownFrame` — used to seed a
    /// bloated/corrupted store directly, bypassing `save`'s eviction, for
    /// the stress tests above.
    private func makeBloatedPerPathEntries(count: Int, knownURL: URL, knownFrame: NSRect) -> [String: [Double]] {
        var entries: [String: [Double]] = [:]
        for index in 0..<count {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Bloat-\(index)-\(UUID().uuidString)")
                .appendingPathExtension("hype")
            entries[AppLaunchState.frameKey(forFileAt: url)] = [
                Double(index), Double(index), 640, 480, 1_700_000_000 + Double(index),
            ]
        }
        entries[AppLaunchState.frameKey(forFileAt: knownURL)] = [
            knownFrame.origin.x, knownFrame.origin.y, knownFrame.width, knownFrame.height, 1_750_000_000,
        ]
        return entries
    }
}
