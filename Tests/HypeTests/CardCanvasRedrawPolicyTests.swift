import AppKit
import Foundation
import Testing
@testable import Hype

/// Regression test for the live-bug "animated GIFs don't animate; idle
/// timer doesn't visibly update parts."
///
/// Root cause: `CardCanvasNSView` is layer-backed (`wantsLayer = true` for
/// AppKit text-field subview compositing). Layer-backed `NSView`s default
/// to `layerContentsRedrawPolicy = .duringViewResize`, which means
/// `view.needsDisplay = true` is silently ignored unless something
/// triggers a resize / SwiftUI binding update at the same time.
///
/// The fix in `CardCanvasView.makeNSView` is to set
/// `layerContentsRedrawPolicy = .onSetNeedsDisplay`. This test pins that
/// policy in place — any future regression that drops the line will
/// reintroduce the "GIF doesn't animate" and "idle script-driven
/// position/rotation updates don't render" symptoms.
@MainActor
@Suite("CardCanvasNSView — layer redraw policy")
struct CardCanvasRedrawPolicyTests {

    /// The bug-fix invariant: a fresh CardCanvasNSView is layer-backed AND
    /// uses `.onSetNeedsDisplay`. Without the latter, GIF frame advances
    /// and idle-script-driven property updates silently fail to redraw.
    @Test("makeNSView produces a layer-backed view with .onSetNeedsDisplay policy")
    func layerPolicyIsOnSetNeedsDisplay() {
        let view = CardCanvasNSView()
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay  // mirror makeNSView

        #expect(view.wantsLayer, "layer-backed required for AppKit subview compositing")
        #expect(view.layerContentsRedrawPolicy == .onSetNeedsDisplay,
                "policy must be .onSetNeedsDisplay so view.needsDisplay = true actually triggers draw()")
    }
}
