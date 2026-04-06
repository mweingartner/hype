import SwiftUI
import HypeCore

struct CardCanvasView: NSViewRepresentable {
    @Binding var document: HypeDocumentWrapper
    let currentCardId: UUID
    let currentTool: ToolName
    @Binding var selectedPartId: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CardCanvasNSView {
        let view = CardCanvasNSView()
        view.document = document.document
        view.currentCardId = currentCardId
        view.currentTool = currentTool
        view.selectedPartId = selectedPartId
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CardCanvasNSView, context: Context) {
        nsView.document = document.document
        nsView.currentCardId = currentCardId
        nsView.currentTool = currentTool
        nsView.selectedPartId = selectedPartId
        nsView.coordinator = context.coordinator
        nsView.updateCursor()
        nsView.needsDisplay = true
    }

    /// Coordinator bridges NSView callbacks back to SwiftUI state.
    @MainActor
    final class Coordinator {
        var parent: CardCanvasView
        private let dispatcher = MessageDispatcher()

        init(parent: CardCanvasView) {
            self.parent = parent
        }

        func selectPart(_ id: UUID?) {
            parent.selectedPartId = id
        }

        func addPart(_ part: Part) {
            parent.document.document.addPart(part)
        }

        func movePart(id: UUID, dx: Double, dy: Double) {
            parent.document.document.updatePart(id: id) { part in
                part.left += dx
                part.top += dy
            }
        }

        /// Dispatch a HypeTalk message through the object hierarchy.
        /// This is the runtime — when you click a button in browse mode,
        /// its mouseUp handler fires, which can navigate, modify parts, etc.
        func dispatchMessage(_ message: String, to partId: UUID) {
            let cardId = parent.currentCardId
            let result = dispatcher.dispatch(
                message: message,
                params: [],
                targetId: partId,
                document: parent.document.document,
                currentCardId: cardId
            )

            // Handle execution results
            switch result.status {
            case .completed, .passed:
                // Apply document modifications from script (e.g., put "x" into field 1)
                if let modified = result.modifiedDocument {
                    parent.document.document = modified
                }
                // Handle navigation (e.g., go next card)
                if let navTarget = result.navigationTarget {
                    NotificationCenter.default.post(
                        name: .navigateToCard,
                        object: navTarget
                    )
                }
            case .error:
                if let err = result.error {
                    print("[HypeTalk Error] \(err.handler) line \(err.line): \(err.message)")
                }
            }
        }
    }
}

class CardCanvasNSView: NSView {
    var document: HypeDocument = HypeDocument()
    var currentCardId: UUID = UUID()
    var currentTool: ToolName = .browse
    var selectedPartId: UUID?
    weak var coordinator: CardCanvasView.Coordinator?

    private let renderer = CardRenderer()
    private let mouseHandler = MouseHandler()

    // Drag state
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    private var draggedPartId: UUID?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        renderer.render(ctx: ctx, document: document, cardId: currentCardId, size: bounds.size)

        // Draw selection overlay
        if let selectedId = selectedPartId,
           let part = document.parts.first(where: { $0.id == selectedId }) {
            drawSelectionOverlay(ctx: ctx, part: part)
        }

        // Draw rubber-band rectangle
        if isDragging, let start = dragStart, let current = dragCurrent {
            drawRubberBand(start: start, current: current)
        }
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

    private func drawRubberBand(start: CGPoint, current: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.stroke(rect)
        ctx.setLineDash(phase: 0, lengths: [])

        // Semi-transparent fill
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor)
        ctx.fill(rect)
    }

    // MARK: - Cursor

    func updateCursor() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        switch toolState.category {
        case .browse:
            NSCursor.pointingHand.set()
        case .edit:
            if currentTool == .select {
                NSCursor.arrow.set()
            } else {
                NSCursor.crosshair.set()
            }
        case .paint:
            NSCursor.crosshair.set()
        }
    }

    override func resetCursorRects() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let cursor: NSCursor
        switch toolState.category {
        case .browse: cursor = .pointingHand
        case .edit: cursor = currentTool == .select ? .arrow : .crosshair
        case .paint: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let point = flippedPoint(for: event)
        let hitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)

        // Double-click on a part in browse mode → open properties for editing
        let toolCheck = ToolState(currentTool: currentTool.rawValue)
        if event.clickCount == 2 && toolCheck.category == .browse, let part = hitPart {
            NotificationCenter.default.post(name: .editPartProperties, object: part.id)
            return
        }

        var toolState = ToolState(currentTool: currentTool.rawValue)
        toolState.selectedPartId = selectedPartId

        let result = mouseHandler.handleMouseDown(tool: toolState, hitPart: hitPart, point: point)

        switch result {
        case .selectPart(let id):
            coordinator?.selectPart(id)
            draggedPartId = id
            dragStart = point
        case .deselectAll:
            coordinator?.selectPart(nil)
        case .sendMessage(let partId, let message):
            // In browse mode, dispatch the message through the script hierarchy
            coordinator?.dispatchMessage(message, to: partId)
        case .beginDrag(let startX, let startY):
            dragStart = CGPoint(x: startX, y: startY)
            dragCurrent = dragStart
            isDragging = true
            needsDisplay = true
        case .none, .createPart, .movePart:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = flippedPoint(for: event)

        if let partId = draggedPartId, let start = dragStart {
            // Move selected part
            let dx = Double(point.x - start.x)
            let dy = Double(point.y - start.y)
            coordinator?.movePart(id: partId, dx: dx, dy: dy)
            dragStart = point
            needsDisplay = true
        } else if isDragging {
            dragCurrent = point
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = flippedPoint(for: event)

        if draggedPartId != nil {
            draggedPartId = nil
            dragStart = nil
            return
        }

        // In browse mode, dispatch mouseUp even without a drag
        let toolCheck = ToolState(currentTool: currentTool.rawValue)
        if toolCheck.category == .browse {
            let hitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)
            if let part = hitPart {
                coordinator?.dispatchMessage("mouseUp", to: part.id)
            }
            return
        }

        guard isDragging else { return }

        let hitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)
        var toolState = ToolState(currentTool: currentTool.rawValue)
        toolState.selectedPartId = selectedPartId

        let cgDragStart: CGPoint? = dragStart
        let result = mouseHandler.handleMouseUp(tool: toolState, hitPart: hitPart, dragStart: cgDragStart, point: point)

        switch result {
        case .createPart(let partType, let rect, let extras):
            var newPart = Part(
                partType: partType,
                cardId: currentCardId,
                left: rect.origin.x,
                top: rect.origin.y,
                width: rect.size.width,
                height: rect.size.height
            )
            newPart.name = "\(partType.rawValue.capitalized) \(document.partsForCard(currentCardId).count + 1)"
            if let shapeTypeStr = extras["shapeType"], let shapeType = ShapeType(rawValue: shapeTypeStr) {
                newPart.shapeType = shapeType
            }
            coordinator?.addPart(newPart)
            coordinator?.selectPart(newPart.id)
        case .sendMessage(let partId, let message):
            coordinator?.dispatchMessage(message, to: partId)
        default:
            break
        }

        // Reset drag state
        isDragging = false
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
    }

    // MARK: - Helpers

    /// Convert window coordinates to flipped (top-left origin) view coordinates.
    private func flippedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        // View is already flipped (isFlipped = true), so no additional transform needed
        return point
    }
}
