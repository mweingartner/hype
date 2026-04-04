import SwiftUI
import HypeCore

struct CardCanvasView: NSViewRepresentable {
    let document: HypeDocument
    let currentCardId: UUID
    let currentTool: ToolName
    let selectedPartId: UUID?
    let onPartSelected: (UUID?) -> Void

    func makeNSView(context: Context) -> CardCanvasNSView {
        let view = CardCanvasNSView()
        view.document = document
        view.currentCardId = currentCardId
        view.onPartSelected = onPartSelected
        return view
    }

    func updateNSView(_ nsView: CardCanvasNSView, context: Context) {
        nsView.document = document
        nsView.currentCardId = currentCardId
        nsView.selectedPartId = selectedPartId
        nsView.needsDisplay = true
    }
}

class CardCanvasNSView: NSView {
    var document: HypeDocument = HypeDocument()
    var currentCardId: UUID = UUID()
    var selectedPartId: UUID?
    var onPartSelected: ((UUID?) -> Void)?

    private let renderer = CardRenderer()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Flip context for top-left origin drawing
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        renderer.render(ctx: ctx, document: document, cardId: currentCardId, size: bounds.size)

        // Draw selection overlay
        if let selectedId = selectedPartId,
           let part = document.parts.first(where: { $0.id == selectedId }) {
            drawSelectionOverlay(ctx: ctx, part: part)
        }

        ctx.restoreGState()
    }

    private func drawSelectionOverlay(ctx: CGContext, part: Part) {
        let rect = CGRect(x: part.left - 1, y: part.top - 1, width: part.width + 2, height: part.height + 2)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.stroke(rect)
        ctx.setLineDash(phase: 0, lengths: [])

        // Resize handles
        let handleSize: CGFloat = 6
        let handles = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
        ]
        ctx.setFillColor(NSColor.controlAccentColor.cgColor)
        for h in handles {
            ctx.fill(CGRect(x: h.x - handleSize / 2, y: h.y - handleSize / 2, width: handleSize, height: handleSize))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Flip Y for our coordinate system
        let flippedPoint = CGPoint(x: point.x, y: bounds.height - point.y)
        let hitPart = renderer.partAtPoint(flippedPoint, document: document, cardId: currentCardId)
        onPartSelected?(hitPart?.id)
    }
}
