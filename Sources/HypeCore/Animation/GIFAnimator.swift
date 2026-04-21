#if canImport(AppKit)
import AppKit
import ImageIO

// MARK: - GIFAnimationState

/// Runtime state for a single animated-GIF part.
///
/// All fields are mutable; the animator owns and mutates them
/// exclusively on the main thread via its `states` dictionary.
public struct GIFAnimationState: Sendable {
    public let partId: UUID
    public let frames: [CGImage]
    public let frameDelays: [Double]
    /// Number of times to play the animation. `0` means loop forever.
    public let loopCount: Int
    public var currentFrameIndex: Int
    public var currentLoopIteration: Int
    public var lastFrameTime: CFTimeInterval
    public var isRunning: Bool
}

// MARK: - GIFAnimator

/// Timer-driven GIF-playback engine for Image parts.
///
/// The singleton is driven by a 60 fps `RunLoop.main` timer (same
/// pattern as `PartAnimator`). `ensureState` is the decode trigger
/// and is safe to call on every draw — it returns immediately when
/// state already exists, or when the bytes are known to be non-GIF.
///
/// **Threading**: all methods must be called from the main thread.
/// The singleton is declared `nonisolated(unsafe)` to match the
/// established `PartAnimator` pattern.
public final class GIFAnimator: @unchecked Sendable {

    nonisolated(unsafe) public static let shared = GIFAnimator()

    // MARK: - Callbacks

    /// Fired after each frame advance for the given part.
    /// Wired by the view layer to `view.needsDisplay = true`.
    public var onFrameChanged: ((UUID) -> Void)?

    /// Fired once per `start` call when playback first begins.
    /// NOT fired on `resume`.
    public var onAnimationStart: ((UUID) -> Void)?

    /// Fired when a non-looping GIF reaches its final frame, or
    /// when `stop` / `set animated to false` is called explicitly.
    public var onAnimationEnd: ((UUID) -> Void)?

    // MARK: - Internal state

    /// Live animation states keyed by partId.
    private var states: [UUID: GIFAnimationState] = [:]

    /// Fast identity sentinels (keyed by partId) to avoid re-decoding
    /// the same bytes on every draw. Stores either:
    ///   - a `DataFingerprint` for a decoded or pending GIF, or
    ///   - a `DataFingerprint` tagged `isNonGIF = true` for JPEG/PNG/corrupt.
    private var fingerprints: [UUID: DataFingerprint] = [:]

    /// Tracks which parts are currently undergoing async decode so a
    /// second `ensureState` call (from the next draw frame) does not
    /// kick off a duplicate `Task.detached`.
    private var pendingDecode: Set<UUID> = []

    private var timer: Timer?

    // MARK: - DataFingerprint

    /// O(1) non-cryptographic identity check.
    ///
    /// Security Finding 4: use `(count, first, last)` — NOT
    /// `data.hashValue`, which uses a per-process randomised seed and
    /// is not a stable identity token.
    ///
    /// `isNonGIF` is a CLASSIFICATION tag, NOT part of the data
    /// identity. Two fingerprints with the same `(count, first, last)`
    /// but different `isNonGIF` values represent the SAME bytes — only
    /// the classification of those bytes differs. Equality must
    /// therefore compare bytes only. Synthesized `Equatable` would
    /// include `isNonGIF` and break the hot-path guard (Security
    /// Finding H-1, post-Builder code review): every static JPEG/PNG
    /// draw would fail the `existing == fp` fast-path check because
    /// the stored sentinel's `isNonGIF == true` never equals the
    /// incoming `isNonGIF == false`, causing `ensureState` to launch
    /// a new decode Task on every draw frame at 60 fps per image part.
    private struct DataFingerprint: Equatable {
        let count: Int
        let first: UInt8
        let last: UInt8
        let isNonGIF: Bool

        init(data: Data, isNonGIF: Bool = false) {
            count = data.count
            first = data.first ?? 0
            last = data.last ?? 0
            self.isNonGIF = isNonGIF
        }

        static func == (lhs: DataFingerprint, rhs: DataFingerprint) -> Bool {
            // Identity = bytes only. `isNonGIF` is metadata about the
            // bytes, not part of them.
            lhs.count == rhs.count
                && lhs.first == rhs.first
                && lhs.last == rhs.last
        }
    }

    // MARK: - Public API

    /// Ensure that animation state exists for `partId`.
    ///
    /// Safe to call on every draw. O(1) dictionary lookup when state
    /// or a non-GIF sentinel already exists. When the bytes are new,
    /// kicks off an async decode via `Task.detached` and returns
    /// immediately; the renderer falls through to the static
    /// `NSImage` path during the decode window.
    ///
    /// Security Finding 7 (Non-GIF sentinel): stores a `KnownNonGIF`
    /// sentinel for JPEG/PNG/corrupt bytes so subsequent draws skip
    /// `CGImageSourceCreateWithData` entirely.
    ///
    /// Security Finding 2 (Async decode): decode never blocks the
    /// main thread. A pending-decode guard prevents concurrent decodes
    /// for the same part.
    public func ensureState(partId: UUID, imageData: Data, autoplay: Bool) {
        let fp = DataFingerprint(data: imageData)

        // Fast path: existing state (GIF or non-GIF sentinel) with
        // matching fingerprint — nothing to do.
        if let existing = fingerprints[partId], existing == fp {
            return
        }

        // Avoid re-launching a decode that's already in flight for
        // this partId. This guard MUST run BEFORE the stale-state
        // eviction below — otherwise a rapid sequence of image-data
        // changes can spawn multiple concurrent decode Tasks that
        // race to install state (Security Finding H-1, post-Builder
        // code review; the original ordering made this guard dead
        // code because it followed `pendingDecode.remove(partId)`).
        guard !pendingDecode.contains(partId) else { return }

        // Image data changed: evict stale state.
        states.removeValue(forKey: partId)

        // Record the new fingerprint and mark as pending decode.
        fingerprints[partId] = fp
        pendingDecode.insert(partId)

        // Kick off decode off the main thread.
        // Access the singleton directly inside `MainActor.run` rather
        // than capturing `self` across the actor boundary, which avoids
        // the Swift 6 "sending self risks data races" error.
        Task.detached(priority: .userInitiated) {
            let decoded = GIFDecoder.decode(imageData)
            await MainActor.run {
                let animator = GIFAnimator.shared
                // Verify the fingerprint still matches — the part
                // may have been deleted or its imageData changed
                // while the decode was in flight.
                guard let storedFP = animator.fingerprints[partId], storedFP == fp else {
                    animator.pendingDecode.remove(partId)
                    return
                }
                animator.pendingDecode.remove(partId)

                guard let gif = decoded else {
                    // Record non-GIF sentinel so future draws skip decode.
                    animator.fingerprints[partId] = DataFingerprint(data: imageData, isNonGIF: true)
                    return
                }

                let state = GIFAnimationState(
                    partId: partId,
                    frames: gif.frames,
                    frameDelays: gif.frameDelays,
                    loopCount: gif.loopCount,
                    currentFrameIndex: 0,
                    currentLoopIteration: 0,
                    lastFrameTime: CACurrentMediaTime(),
                    isRunning: autoplay
                )
                animator.states[partId] = state

                if autoplay {
                    animator.startTimerIfNeeded()
                    animator.onAnimationStart?(partId)
                }
            }
        }
    }

    /// Start or restart playback for a part, re-decoding from
    /// `imageData` if no state exists yet.
    ///
    /// Uses explicit var-out / write-back (matching `stop`) rather
    /// than optional-chained subscript mutation (`states[id]?.x = y`).
    /// The chained form SHOULD compile to the same get-mutate-set
    /// cycle, but when a GIF was stopped via `set the animated of X
    /// to false` and then restarted via `set the animated of X to
    /// true`, the chained form was observed to not re-enter playback:
    /// `isRunning` didn't flip back to true and the timer never
    /// tick()d forward. The explicit pattern avoids whatever write
    /// path was dropping the mutation.
    public func start(partId: UUID, imageData: Data) {
        if var state = states[partId] {
            // State exists — reset to beginning and resume.
            state.currentFrameIndex = 0
            state.currentLoopIteration = 0
            state.lastFrameTime = CACurrentMediaTime()
            state.isRunning = true
            states[partId] = state
            startTimerIfNeeded()
            onAnimationStart?(partId)
        } else {
            // No state — trigger decode with autoplay.
            ensureState(partId: partId, imageData: imageData, autoplay: true)
        }
    }

    /// Pause playback without resetting position.
    ///
    /// **Re-entrancy guard (Security Finding H-2, post-Builder code
    /// review):** `onAnimationEnd` dispatches an `animationEnd`
    /// HypeTalk message. A user handler like
    ///   `on animationEnd / stop the animation of me / end animationEnd`
    /// would otherwise recurse until stack overflow — `stop()` fires
    /// the callback, the callback dispatches to the script, the script
    /// calls `executeStopAnimation`, which calls `stop()` again. We
    /// break the cycle by checking `isRunning` up front: the second
    /// call sees `isRunning == false` and returns before firing the
    /// callback a second time. This also naturally fixes the double-
    /// fire case (Security Finding M-3) where two rapid `stop()` calls
    /// would have produced two `animationEnd` messages.
    public func stop(partId: UUID) {
        guard var state = states[partId], state.isRunning else { return }
        state.isRunning = false
        states[partId] = state
        stopTimerIfIdle()
        onAnimationEnd?(partId)
    }

    /// Resume playback from the current frame without firing
    /// `onAnimationStart` (contrast with `start` which resets
    /// to frame 0 and fires the start event).
    public func resume(partId: UUID) {
        guard var state = states[partId] else { return }
        state.isRunning = true
        // Advance lastFrameTime to now so the tick doesn't try to
        // "catch up" the time the animation was paused.
        state.lastFrameTime = CACurrentMediaTime()
        states[partId] = state
        startTimerIfNeeded()
        // Note: `onAnimationStart` is NOT fired on resume per spec §12.
    }

    /// Remove all state for a part (used when a part is deleted).
    public func remove(partId: UUID) {
        states.removeValue(forKey: partId)
        fingerprints.removeValue(forKey: partId)
        pendingDecode.remove(partId)
        stopTimerIfIdle()
    }

    /// Remove all state for all parts.
    ///
    /// Security Finding 6: MUST be called from `dismantleNSView`
    /// (or equivalent teardown) to stop the Timer and release all
    /// frame backing stores. Without this the singleton accumulates
    /// CGImage arrays across document open/close cycles.
    public func removeAll() {
        states.removeAll()
        fingerprints.removeAll()
        pendingDecode.removeAll()
        timer?.invalidate()
        timer = nil
    }

    /// Return the current CGImage frame for a part, or `nil` when
    /// no state exists (decode pending, non-GIF, or removed).
    public func currentFrame(partId: UUID) -> CGImage? {
        guard let state = states[partId], !state.frames.isEmpty else { return nil }
        return state.frames[state.currentFrameIndex]
    }

    /// Whether this part has a running (non-paused) GIF animation.
    public func isAnimating(partId: UUID) -> Bool {
        states[partId]?.isRunning == true
    }

    /// Whether any state (running or paused) exists for this part.
    public func hasState(partId: UUID) -> Bool {
        states[partId] != nil
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func stopTimerIfIdle() {
        let anyRunning = states.values.contains { $0.isRunning }
        guard !anyRunning else { return }
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Tick

    /// Advance all running animations by the elapsed wall-clock time.
    ///
    /// Security Finding 3 (Bounded catch-up): the inner loop is
    /// capped at `frames.count` iterations per animation per tick.
    /// If the app was suspended (sleep/wake) and more frames would
    /// have played than one full pass, we resync `lastFrameTime = now`
    /// and break, preventing a main-thread freeze.
    ///
    /// Security Finding 5 (Buffered callbacks): `onFrameChanged` and
    /// `onAnimationEnd` are collected into local arrays during the
    /// mutation pass and fired AFTER the loop completes.  This
    /// prevents re-entrant mutation of `states` from callback handlers
    /// (e.g. an `animationEnd` handler calling `start the animation
    /// of` would otherwise corrupt the iterator).
    private func tick() {
        let now = CACurrentMediaTime()
        var frameChangedIds: [UUID] = []
        var animationEndIds: [UUID] = []

        for partId in states.keys {
            guard var state = states[partId], state.isRunning else { continue }
            guard !state.frames.isEmpty else { continue }

            let currentDelay = state.frameDelays[state.currentFrameIndex]
            guard now - state.lastFrameTime >= currentDelay else { continue }

            // Catch-up pass, bounded at one full frame-array pass.
            let maxSkip = state.frames.count
            var iterationsThisTick = 0
            var naturalEnd = false

            repeat {
                let previousIndex = state.currentFrameIndex
                state.currentFrameIndex += 1
                iterationsThisTick += 1

                if state.currentFrameIndex >= state.frames.count {
                    state.currentLoopIteration += 1
                    if state.loopCount > 0 && state.currentLoopIteration >= state.loopCount {
                        // Park on the final frame; mark as ended.
                        state.currentFrameIndex = state.frames.count - 1
                        state.isRunning = false
                        naturalEnd = true
                        state.lastFrameTime += state.frameDelays[previousIndex]
                        break
                    } else {
                        state.currentFrameIndex = 0
                    }
                }

                state.lastFrameTime += state.frameDelays[previousIndex]

                if iterationsThisTick >= maxSkip {
                    // Resync to prevent spinning on the next tick.
                    state.lastFrameTime = now
                    break
                }
            } while now - state.lastFrameTime >= state.frameDelays[state.currentFrameIndex]

            states[partId] = state
            frameChangedIds.append(partId)
            if naturalEnd {
                animationEndIds.append(partId)
            }
        }

        // Fire callbacks AFTER the mutation pass to prevent re-entrant
        // mutation of `states` during iteration.
        for id in frameChangedIds { onFrameChanged?(id) }
        for id in animationEndIds { onAnimationEnd?(id) }

        stopTimerIfIdle()
    }
}
#endif
