import AppKit
import Foundation
import Testing
@testable import Hype
@testable import HypeCore

/// Regression tests for the live-bug "animated GIFs don't animate; idle
/// timer doesn't visibly update parts."
///
/// Root cause: `CardCanvasNSView` is layer-backed (`wantsLayer = true` for
/// AppKit text-field subview compositing). Layer-backed `NSView`s default
/// to `layerContentsRedrawPolicy = .duringViewResize`, which means
/// `view.needsDisplay = true` is silently ignored unless something
/// triggers a resize / SwiftUI binding update at the same time.
///
/// Two specific paths break under that default:
///   1. `GIFAnimator.onFrameChanged` callback sets `view.needsDisplay = true`
///      per frame — the chick GIF in `teststack.hype` displayed as a
///      static image because the per-frame redraw was dropped.
///   2. `on idle` handlers whose `set the loc of me` / `set the rotation
///      of me` writes flow through a runtime writeback path that also
///      only sets `view.needsDisplay = true` — position/rotation changes
///      never appeared on screen even though the document was updated
///      (proven by `set the fillColor of me` working via a different
///      SwiftUI binding-refresh path that also triggered re-layout).
///
/// The core fix is `view.layerContentsRedrawPolicy = .onSetNeedsDisplay`
/// inside `CardCanvasNSView.configureForCardCanvasRendering()`. The active
/// canvas also refreshes the singleton animation callbacks from both
/// `makeNSView` and `updateNSView` so frame ticks cannot target a stale view.
/// The tests below pin these invariants from BOTH angles:
///
///   - **Structural**: calling the production setup method actually sets
///     both `wantsLayer` and `.onSetNeedsDisplay`. Catches any future
///     refactor that drops the policy line.
///   - **Behavioural**: with the policy in place, `needsDisplay = true`
///     queues a real `draw(_:)` invocation when the runloop spins.
///     Catches the case where the property is set but, e.g., the layer
///     contents are still cached and the draw is short-circuited.
@MainActor
@Suite("CardCanvasNSView — layer redraw policy")
struct CardCanvasRedrawPolicyTests {

    /// Structural invariant: production's `makeNSView` calls
    /// `configureForCardCanvasRendering()`, which must set both
    /// `wantsLayer = true` and `layerContentsRedrawPolicy =
    /// .onSetNeedsDisplay`. If either drops, GIF frame advances and
    /// idle-script-driven property updates silently fail to redraw.
    @Test("configureForCardCanvasRendering sets wantsLayer + .onSetNeedsDisplay")
    func configureSetsLayerAndPolicy() {
        let view = CardCanvasNSView()
        // Confirm the *default* on a fresh view is the WRONG-for-Hype
        // policy. This is what causes the regression: if anyone ever
        // forgets to call configureForCardCanvasRendering (or drops
        // the policy line from it), the view falls back to
        // `.duringViewResize` and on-demand redraws are silently
        // dropped. AppKit's default is `.duringViewResize` (rawValue 2).
        #expect(view.layerContentsRedrawPolicy != .onSetNeedsDisplay,
                "pre-condition: bare CardCanvasNSView must NOT already use .onSetNeedsDisplay (else this test is vacuous)")

        view.configureForCardCanvasRendering()

        #expect(view.wantsLayer, "configureForCardCanvasRendering must enable layer-backing")
        #expect(view.layerContentsRedrawPolicy == .onSetNeedsDisplay,
                "configureForCardCanvasRendering must set .onSetNeedsDisplay so needsDisplay = true triggers draw()")
    }

    /// Behavioural invariant: with the configured policy, setting
    /// `needsDisplay = true` queues a real `draw(_:)` invocation.
    ///
    /// We use a subclass that counts draw calls because we can't easily
    /// observe `setNeedsDisplay` propagation without an actual draw
    /// happening. The subclass is wrapped in an `NSWindow` because
    /// detached views do not get scheduled into the display cycle —
    /// the runloop only services views inside a window tree.
    @Test("needsDisplay = true on a configured view triggers draw() when the runloop spins")
    func needsDisplayTriggersDrawWhenConfigured() async throws {
        let view = DrawCountingCanvas()
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.configureForCardCanvasRendering()

        // Host in a window so the view enters the display cycle.
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        // makeKeyAndOrderFront forces the window to lay out; the initial
        // draw counts as the "baseline" before the test triggers another.
        window.orderFront(nil)
        window.displayIfNeeded()
        let baselineDraws = view.drawCount

        // Request a redraw without any other state change.
        view.needsDisplay = true

        // Spin the runloop briefly so AppKit drains the display queue.
        // 200ms is generous; a configured view usually draws within
        // one or two runloop turns (~16ms each on a 60Hz display link).
        try await Task.sleep(nanoseconds: 200_000_000)

        // Force any pending draw to complete before we read the count.
        view.displayIfNeeded()

        #expect(view.drawCount > baselineDraws,
                "needsDisplay = true did not trigger draw() — layer policy regression. baseline=\(baselineDraws) after=\(view.drawCount)")

        // Cleanup.
        window.orderOut(nil)
        window.contentView = nil
    }
}

/// Minimal CardCanvasNSView subclass that counts draw() invocations.
/// Used by the behavioural redraw-policy test to detect dropped draws.
@MainActor
private final class DrawCountingCanvas: CardCanvasNSView {
    private(set) var drawCount: Int = 0

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        // Don't call super — we don't have a real document/coordinator
        // wired up here, and super's draw expects a renderer context
        // backed by live model state. The test only cares whether
        // draw was scheduled and entered, not what it painted.
    }
}

/// Integration-level regression: a configured `CardCanvasNSView` whose
/// production `GIFAnimator.onFrameChanged` callback fires actually triggers
/// `draw()`.
///
/// This is the EXACT shape of the user-reported chick-GIF bug. Before
/// the fix, the callback ran, the view invalidation returned, and no draw was
/// scheduled — frames never advanced visibly. The test uses the production
/// callback installer with a counter so stale-callback or policy regressions
/// resurface here too.
@MainActor
@Suite("CardCanvasNSView — animator-callback redraw integration")
struct CardCanvasAnimatorCallbackTests {

    @Test("active canvas GIF callback triggers draw on configured view")
    func activeCanvasGIFCallbackTriggersDraw() async throws {
        let view = DrawCountingCanvas()
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.configureForCardCanvasRendering()
        view.installRuntimeAnimatorCallbacks()
        defer {
            GIFAnimator.shared.onFrameChanged = nil
            GIFAnimator.shared.onAnimationStart = nil
            GIFAnimator.shared.onAnimationEnd = nil
            PartAnimator.shared.onPropertyChange = nil
        }

        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        window.displayIfNeeded()
        let baselineDraws = view.drawCount

        // Fire the "frame advanced" callback three times, runloop-spun
        // between each, exactly as the GIF tick path does.
        for _ in 0..<3 {
            GIFAnimator.shared.onFrameChanged?(UUID())
            try await Task.sleep(nanoseconds: 50_000_000)
            view.displayIfNeeded()
        }

        // Each callback should produce at least one draw after the
        // policy fix; before the fix every one would be silently
        // dropped and drawCount would equal baselineDraws.
        #expect(view.drawCount > baselineDraws,
                "animator-style needsDisplay callback dropped — layer policy regression. baseline=\(baselineDraws) after=\(view.drawCount)")

        window.orderOut(nil)
        window.contentView = nil
    }
}
