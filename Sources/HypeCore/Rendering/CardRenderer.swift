import Foundation
#if canImport(AppKit)
import AppKit

/// Renders a card and its parts onto a CGContext.
public final class CardRenderer: Sendable {

    public init() {}

    /// Render a complete card state to an NSImage.
    ///
    /// The render() method expects a flipped (top-left origin) CGContext,
    /// matching the coordinate system of an NSView with isFlipped=true.
    /// NSImage.lockFocus() provides a bottom-left origin context by default,
    /// so we use an NSBitmapImageRep with an explicit flip transform.
    @MainActor
    public func renderToImage(
        document: HypeDocument,
        cardId: UUID,
        size: NSSize,
        skipPartId: UUID? = nil,
        nativePartIds: Set<UUID> = []
    ) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        guard let gfxContext = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: size)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gfxContext
        let ctx = gfxContext.cgContext
        // Flip to match the flipped NSView coordinate system (top-left origin)
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        render(ctx: ctx, document: document, cardId: cardId, size: size, skipPartId: skipPartId, nativePartIds: nativePartIds)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Render onto an existing CGContext.
    ///
    /// - Parameters:
    ///   - nativePartIds: Parts whose IDs appear in this set are skipped during
    ///     CGContext rendering, because they are rendered natively via SpriteKit nodes.
    public func render(
        ctx: CGContext,
        document: HypeDocument,
        cardId: UUID,
        size: NSSize,
        skipPartId: UUID? = nil,
        nativePartIds: Set<UUID> = [],
        theme: HypeTheme? = nil
    ) {
        // Layer 1: Card surface — theme.cardBackground when a
        // theme is supplied, else NSColor.white to preserve the
        // pre-theme rendering for any caller that hasn't migrated.
        let resolved = theme ?? document.effectiveTheme(forCard: cardId)
        let surfaceColor = resolved.cardBackground.nsColor
        ctx.setFillColor(surfaceColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        guard let card = document.cards.first(where: { $0.id == cardId }),
              let bg = document.backgroundForCard(card) else {
            drawEmptyState(ctx: ctx, size: size)
            return
        }

        // Layer 2: Background parts
        let bgParts = document.partsForBackground(bg.id)
        for part in bgParts where part.visible && part.id != skipPartId && !nativePartIds.contains(part.id) {
            drawPart(ctx: ctx, part: part, canvasHeight: Double(size.height), theme: resolved)
        }

        // Layer 3: Card paint layer (future — bitmap overlay)

        // Layer 4: Card parts
        let cardParts = document.partsForCard(cardId)
        for part in cardParts where part.visible && part.id != skipPartId && !nativePartIds.contains(part.id) {
            drawPart(ctx: ctx, part: part, canvasHeight: Double(size.height), theme: resolved)
        }
    }

    private func drawEmptyState(ctx: CGContext, size: NSSize) {
        let text = "No stack open" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            // secondaryLabelColor is dark-mode aware (lighter on
            // dark themes, darker on light themes).
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let textSize = text.size(withAttributes: attrs)
        let x = (size.width - textSize.width) / 2
        let y = (size.height - textSize.height) / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        text.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Dispatch part rendering based on type. The optional `theme`
    /// is forwarded to every per-part renderer that supports
    /// theme-aware drawing — currently the new "Liquid Glass"
    /// branch in `ButtonRenderer` / `FieldRenderer` / `ShapeRenderer`
    /// and any future material-aware code path. Renderers ignore
    /// `nil` and fall back to their pre-theme rendering, so adding
    /// new renderers to the dispatch is safe without per-renderer
    /// theme work.
    public func drawPart(ctx: CGContext, part: Part, canvasHeight: Double, theme: HypeTheme? = nil) {
        // View is flipped (top-left origin), use part coordinates directly
        let rect = CGRect(
            x: part.left,
            y: part.top,
            width: part.width,
            height: part.height
        )

        switch part.partType {
        case .button:
            ButtonRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
        case .field:
            FieldRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
        case .shape:
            ShapeRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
        case .webpage:
            WebPageRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .image:
            ImageRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .video:
            VideoRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .chart:
            ChartRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .spriteArea:
            SpriteAreaRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .calendar:
            CalendarRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .pdf:
            PDFRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .map:
            MapRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .colorWell:
            ColorWellRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .stepper, .slider, .segmented:
            FormControlsRenderer.draw(part.partType, ctx: ctx, part: part, rect: rect, theme: theme)
        case .audioRecorder:
            AudioRecorderRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .scene3D:
            Scene3DRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .progressView:
            ProgressViewRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
        case .gauge:
            GaugeRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
        case .divider:
            DividerRenderer.draw(ctx: ctx, part: part, rect: rect, theme: theme)
        case .toggle, .link, .menu, .searchField:
            // Migrated to button/field with appropriate style at decode
            // time — these PartTypes are unreachable in normal flow.
            // Empty branch keeps the switch exhaustive.
            break
        case .unknown:
            // Unknown types are filtered out at load time; if one slips
            // through, render nothing.
            break
        }
    }

    /// Hit test: find topmost visible part at a point.
    public func partAtPoint(
        _ point: CGPoint,
        document: HypeDocument,
        cardId: UUID
    ) -> Part? {
        let cardParts = document.partsForCard(cardId)
        // Check card parts first (on top), then bg parts
        for part in cardParts.reversed() where part.visible {
            if partContainsPoint(part, point: point) {
                return part
            }
        }

        if let card = document.cards.first(where: { $0.id == cardId }) {
            let bgParts = document.partsForBackground(card.backgroundId)
            for part in bgParts.reversed() where part.visible {
                if partContainsPoint(part, point: point) {
                    return part
                }
            }
        }
        return nil
    }

    private func partContainsPoint(_ part: Part, point: CGPoint) -> Bool {
        point.x >= part.left && point.x <= part.left + part.width &&
        point.y >= part.top && point.y <= part.top + part.height
    }
}
#endif
