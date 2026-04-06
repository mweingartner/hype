import Foundation
#if canImport(AppKit)
import AppKit

/// Renders a card and its parts onto a CGContext.
public final class CardRenderer: Sendable {

    public init() {}

    /// Render a complete card state to an NSImage.
    @MainActor
    public func renderToImage(
        document: HypeDocument,
        cardId: UUID,
        size: NSSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        render(ctx: ctx, document: document, cardId: cardId, size: size)
        image.unlockFocus()
        return image
    }

    /// Render onto an existing CGContext.
    public func render(
        ctx: CGContext,
        document: HypeDocument,
        cardId: UUID,
        size: NSSize
    ) {
        // Layer 1: Background (white)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        guard let card = document.cards.first(where: { $0.id == cardId }),
              let bg = document.backgroundForCard(card) else {
            drawEmptyState(ctx: ctx, size: size)
            return
        }

        // Layer 2: Background parts
        let bgParts = document.partsForBackground(bg.id)
        for part in bgParts where part.visible {
            drawPart(ctx: ctx, part: part, canvasHeight: Double(size.height))
        }

        // Layer 3: Card paint layer (future — bitmap overlay)

        // Layer 4: Card parts
        let cardParts = document.partsForCard(cardId)
        for part in cardParts where part.visible {
            drawPart(ctx: ctx, part: part, canvasHeight: Double(size.height))
        }
    }

    private func drawEmptyState(ctx: CGContext, size: NSSize) {
        let text = "No stack open" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.gray,
        ]
        let textSize = text.size(withAttributes: attrs)
        let x = (size.width - textSize.width) / 2
        let y = (size.height - textSize.height) / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        text.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Dispatch part rendering based on type.
    public func drawPart(ctx: CGContext, part: Part, canvasHeight: Double) {
        // View is flipped (top-left origin), use part coordinates directly
        let rect = CGRect(
            x: part.left,
            y: part.top,
            width: part.width,
            height: part.height
        )

        switch part.partType {
        case .button:
            ButtonRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .field:
            FieldRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .shape:
            ShapeRenderer.draw(ctx: ctx, part: part, rect: rect)
        case .webpage:
            WebPageRenderer.draw(ctx: ctx, part: part, rect: rect)
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
