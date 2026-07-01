import SwiftUI
import HypeCore
import AppKit

/// Read-only preview of the card as it will appear on a specific device profile,
/// rendered using the same `LayoutResolver` projection that governs export.
///
/// This view is shown in place of the live `CardCanvasView` during emulation
/// when the layout policy is `.scaleToFit` or `.stretchToFill`. For `.fixed`
/// policy, the live editable canvas continues to be shown with an optional
/// overflow indicator.
///
/// **Coordinate-space safety**: this view does NOT use `scaleEffect`,
/// `transformEffect`, or any geometry transform on the live `CardCanvasView`.
/// It renders a static `NSImage` snapshot from `CardRenderer` using per-part
/// resolved geometry, so AppKit hit-testing and point-conversion are untouched.
/// The underlying `NSView` overrides `hitTest` to return `nil`, making the
/// preview completely non-interactive.
struct TargetPreviewCanvasView: View {
    let document: HypeDocument
    let cardId: UUID
    let profile: HypeDeviceProfile

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            TargetPreviewNSViewRepresentable(
                document: document,
                cardId: cardId,
                profile: profile
            )
            .frame(width: CGFloat(profile.width), height: CGFloat(profile.height))

            // Caption banner at the top indicating the preview is read-only.
            // Shown without animation — honors reduce-motion and is always static.
            VStack {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 10, weight: .semibold))
                    Text(captionText)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.88))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
                .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: CGFloat(profile.width), height: CGFloat(profile.height))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }

    private var captionText: String {
        let policyName = document.stack.deploymentTargets.layoutPolicy == .scaleToFit
            ? "scale-to-fit"
            : "stretch-to-fill"
        return "Previewing \(policyName) layout on \(profile.displayName) — turn off emulation to edit"
    }

    private var accessibilityLabel: String {
        let policyName = document.stack.deploymentTargets.layoutPolicy == .scaleToFit
            ? "scale-to-fit"
            : "stretch-to-fill"
        return "Read-only \(policyName) layout preview for \(profile.displayName). Authoring is paused during emulation."
    }
}

// MARK: - NSViewRepresentable wrapper

/// AppKit wrapper that renders the resolved card layout as a static image.
///
/// Overrides `hitTest` to return `nil` so the preview is fully non-interactive;
/// no mouse handlers are installed.
private struct TargetPreviewNSViewRepresentable: NSViewRepresentable {
    let document: HypeDocument
    let cardId: UUID
    let profile: HypeDeviceProfile

    func makeNSView(context: Context) -> TargetPreviewRenderView {
        let view = TargetPreviewRenderView()
        view.update(document: document, cardId: cardId, profile: profile)
        return view
    }

    func updateNSView(_ nsView: TargetPreviewRenderView, context: Context) {
        nsView.update(document: document, cardId: cardId, profile: profile)
    }
}

// MARK: - Render view

/// Non-interactive NSView that shows a single rendered snapshot of the card at
/// the resolved layout geometry.
///
/// Coordinate-space invariant: no `scaleBy`/`translateBy` transforms are applied
/// to the card canvas coordinate system. The renderer receives part copies whose
/// `.left`/`.top`/`.width`/`.height` are already in target-profile space
/// (produced by `LayoutResolver`), matching exactly the export path.
final class TargetPreviewRenderView: NSView {

    private var renderedImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    // MARK: - Public interface

    @MainActor
    func update(document: HypeDocument, cardId: UUID, profile: HypeDeviceProfile) {
        let size = NSSize(width: profile.width, height: profile.height)
        renderedImage = buildImage(document: document, cardId: cardId, profile: profile, size: size)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if let image = renderedImage, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cgImage, in: bounds)
        } else {
            // Empty card: white frame only.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(bounds)
        }
    }

    // MARK: - Hit testing (read-only)

    /// Return nil so no mouse events are delivered to this view or any subview.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Private helpers

    /// Build a snapshot image by:
    ///   1. Running `LayoutResolver` to get per-part resolved geometry in
    ///      target-profile space (same projection as the export path).
    ///   2. Creating temporary part copies with coordinates overridden to
    ///      resolved geometry.
    ///   3. Rendering those into a fresh `NSImage` via `CardRenderer`.
    @MainActor
    private func buildImage(
        document: HypeDocument,
        cardId: UUID,
        profile: HypeDeviceProfile,
        size: NSSize
    ) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let resolution = LayoutResolver().resolve(
            document: document,
            profile: profile,
            cardId: cardId
        )

        // Build a document copy whose parts are repositioned to resolved geometry.
        let resolvedDocument = documentWithResolvedGeometry(
            document: document,
            resolution: resolution
        )

        // The theme rides along inside `resolvedDocument` (a copy of `document`
        // with only geometry overridden), so the renderer resolves it correctly.
        let renderer = CardRenderer()
        return renderer.renderToImage(
            document: resolvedDocument,
            cardId: cardId,
            size: size,
            nativePartIds: []
        )
    }

    /// Returns a copy of `document` where every part's
    /// `left`/`top`/`width`/`height` is replaced by its resolved geometry.
    ///
    /// Parts with no resolved geometry entry (e.g., parts on other cards) are
    /// left unchanged. This does NOT mutate the source document.
    private func documentWithResolvedGeometry(
        document: HypeDocument,
        resolution: LayoutResolution
    ) -> HypeDocument {
        var copy = document
        // Remap every part in the copy.
        for i in copy.parts.indices {
            let id = copy.parts[i].id
            if let geo = resolution.geometries[id] {
                copy.parts[i].left = geo.left
                copy.parts[i].top = geo.top
                copy.parts[i].width = geo.width
                copy.parts[i].height = geo.height
            }
        }
        return copy
    }
}
