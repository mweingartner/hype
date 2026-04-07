import SwiftUI
import HypeCore
import WebKit

struct CardCanvasView: NSViewRepresentable {
    @Binding var document: HypeDocumentWrapper
    let currentCardId: UUID
    let currentTool: ToolName
    @Binding var selectedPartId: UUID?
    let editingBackground: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CardCanvasNSView {
        let view = CardCanvasNSView()
        view.document = document.document
        view.currentCardId = currentCardId
        view.currentTool = currentTool
        view.selectedPartId = selectedPartId
        view.editingBackground = editingBackground
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CardCanvasNSView, context: Context) {
        // Keep coordinator's parent in sync so it reads current state
        context.coordinator.parent = self
        nsView.document = document.document
        nsView.currentCardId = currentCardId
        nsView.currentTool = currentTool
        nsView.selectedPartId = selectedPartId
        nsView.editingBackground = editingBackground
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

        func resizePart(id: UUID, handle: CardCanvasNSView.ResizeHandle, dx: Double, dy: Double) {
            parent.document.document.updatePart(id: id) { part in
                let minSize: Double = 10
                switch handle {
                case .topLeft:
                    let newW = max(minSize, part.width - dx)
                    let newH = max(minSize, part.height - dy)
                    part.left += part.width - newW
                    part.top += part.height - newH
                    part.width = newW
                    part.height = newH
                case .topCenter:
                    let newH = max(minSize, part.height - dy)
                    part.top += part.height - newH
                    part.height = newH
                case .topRight:
                    part.width = max(minSize, part.width + dx)
                    let newH = max(minSize, part.height - dy)
                    part.top += part.height - newH
                    part.height = newH
                case .rightCenter:
                    part.width = max(minSize, part.width + dx)
                case .bottomRight:
                    part.width = max(minSize, part.width + dx)
                    part.height = max(minSize, part.height + dy)
                case .bottomCenter:
                    part.height = max(minSize, part.height + dy)
                case .bottomLeft:
                    let newW = max(minSize, part.width - dx)
                    part.left += part.width - newW
                    part.width = newW
                    part.height = max(minSize, part.height + dy)
                case .leftCenter:
                    let newW = max(minSize, part.width - dx)
                    part.left += part.width - newW
                    part.width = newW
                case .none:
                    break
                }
            }
        }

        /// Update a part's text content (used by inline field editor).
        func updatePartText(id: UUID, text: String) {
            parent.document.document.updatePart(id: id) { $0.textContent = text }
        }

        /// Toggle the hilite state of a part (used for image invert-on-click).
        func togglePartHilite(id: UUID) {
            parent.document.document.updatePart(id: id) { $0.hilite.toggle() }
        }

        func deletePart(id: UUID) {
            parent.selectedPartId = nil
            parent.document.document.removePart(id: id)
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
                    print("[HypeTalk] Navigating to card \(navTarget)")
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
    var editingBackground: Bool = false
    weak var coordinator: CardCanvasView.Coordinator?

    private let renderer = CardRenderer()
    private let mouseHandler = MouseHandler()
    private let alignmentEngine = AlignmentEngine()

    // Inline field editing
    private var activeFieldEditor: NSTextField?
    private var activeFieldPartId: UUID?

    // Active WKWebViews for webpage parts (keyed by part ID)
    private var webViews: [UUID: WKWebView] = [:]
    // Track which URLs are loaded to avoid redundant loads
    private var loadedURLs: [UUID: String] = [:]

    // Paint layers keyed by card ID
    private var paintLayers: [UUID: PaintLayer] = [:]

    // Drag state
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    private var draggedPartId: UUID?
    private var resizeHandle: ResizeHandle = .none

    // Pencil freeform points collected during drag
    private var pencilPoints: [PathPoint] = []

    // Alignment snap guides currently visible
    private var activeGuides: [SnapGuide] = []

    /// Which resize handle is being dragged.
    enum ResizeHandle {
        case none, topLeft, topCenter, topRight, rightCenter
        case bottomRight, bottomCenter, bottomLeft, leftCenter
    }

    /// The background ID for the current card, used when creating background parts.
    private var currentBackgroundId: UUID? {
        document.cards.first(where: { $0.id == currentCardId })?.backgroundId
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Don't handle keys while editing a field inline
        if activeFieldEditor != nil {
            super.keyDown(with: event)
            return
        }

        // Delete or Backspace: delete the selected part
        if event.keyCode == 51 || event.keyCode == 117 {  // 51 = Backspace, 117 = Forward Delete
            if let partId = selectedPartId {
                coordinator?.deletePart(id: partId)
                needsDisplay = true
                return
            }
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        renderer.render(ctx: ctx, document: document, cardId: currentCardId, size: bounds.size)

        // Render the paint layer on top of card content
        let paintLayer = paintLayerForCurrentCard()
        if !paintLayer.isEmpty {
            paintLayer.render(into: ctx)
        }

        // Draw selection overlay
        if let selectedId = selectedPartId,
           let part = document.parts.first(where: { $0.id == selectedId }) {
            drawSelectionOverlay(ctx: ctx, part: part)
        }

        // Draw alignment guides
        if !activeGuides.isEmpty {
            drawAlignmentGuides(ctx: ctx)
        }

        // Update web views for webpage parts
        updateWebViews()

        // Dim card parts and draw border when editing background
        if editingBackground {
            // Dim all card-specific parts with a semi-transparent overlay
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            for part in document.partsForCard(currentCardId) where part.visible {
                ctx.fill(CGRect(x: part.left, y: part.top, width: part.width, height: part.height))
            }
            // Draw a border to indicate background editing mode
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(bounds.insetBy(dx: 1.5, dy: 1.5))
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

    // MARK: - Inline Field Editing

    private func startFieldEditing(part: Part) {
        // Don't edit if locked
        guard part.partType == .field && !part.lockText else { return }

        // Remove existing editor
        endFieldEditing()

        let textField = NSTextField(frame: CGRect(x: part.left, y: part.top, width: part.width, height: part.height))
        textField.stringValue = part.textContent
        textField.font = NSFont(name: part.textFont, size: CGFloat(part.textSize)) ?? NSFont.systemFont(ofSize: CGFloat(part.textSize))
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self
        textField.alignment = part.textAlign == .center ? .center : part.textAlign == .right ? .right : .left

        addSubview(textField)
        window?.makeFirstResponder(textField)

        activeFieldEditor = textField
        activeFieldPartId = part.id
    }

    private func endFieldEditing() {
        if let editor = activeFieldEditor, let partId = activeFieldPartId {
            // Save the text back to the part
            let text = editor.stringValue
            coordinator?.updatePartText(id: partId, text: text)
            editor.removeFromSuperview()
        }
        activeFieldEditor = nil
        activeFieldPartId = nil
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
        // End any active field editing when clicking elsewhere
        if activeFieldEditor != nil {
            endFieldEditing()
            needsDisplay = true
        }

        let point = flippedPoint(for: event)

        // Handle paint tools directly
        let paintToolCheck = ToolState(currentTool: currentTool.rawValue)
        if paintToolCheck.category == .paint {
            let x = Int(point.x)
            let y = Int(point.y)

            switch currentTool {
            case .pencil:
                // Collect freeform points (no bitmap drawing)
                pencilPoints = [PathPoint(x: Double(x), y: Double(y))]
            case .spray:
                let pl = paintLayerForCurrentCard()
                pl.spray(cx: x, cy: y, radius: 12, density: 20, color: NSColor.black)
            case .eraser:
                let pl = paintLayerForCurrentCard()
                pl.erase(cx: x, cy: y, radius: 10)
            case .bucket:
                let pl = paintLayerForCurrentCard()
                pl.floodFill(x: x, y: y, color: NSColor.black)
            case .line, .rect, .oval, .text:
                // These use drag -- just record start point
                break
            default:
                break
            }

            dragStart = point
            isDragging = true
            needsDisplay = true
            return
        }

        let rawHitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)

        // Filter hit part based on editing mode: only allow selecting parts
        // on the layer being edited.
        let hitPart: Part?
        if let part = rawHitPart {
            if editingBackground && part.cardId != nil {
                hitPart = nil  // Can't select card parts when editing background
            } else if !editingBackground && part.backgroundId != nil && part.cardId == nil {
                hitPart = nil  // Can't select background parts when editing card
            } else {
                hitPart = part
            }
        } else {
            hitPart = nil
        }

        // Double-click on a part in browse mode → open properties for editing
        let toolCheck = ToolState(currentTool: currentTool.rawValue)
        if event.clickCount == 2 && toolCheck.category == .browse, let part = hitPart {
            NotificationCenter.default.post(name: .editPartProperties, object: part.id)
            return
        }

        var toolState = ToolState(currentTool: currentTool.rawValue)
        toolState.selectedPartId = selectedPartId

        let result = mouseHandler.handleMouseDown(tool: toolState, hitPart: hitPart, point: point)

        // Before handling the tool result, check if we're clicking a resize handle
        // on the already-selected part
        if currentTool == .select, let _ = selectedPartId {
            let handle = hitTestResizeHandle(point)
            if handle != .none {
                resizeHandle = handle
                dragStart = point
                draggedPartId = selectedPartId
                return
            }
        }

        switch result {
        case .selectPart(let id):
            coordinator?.selectPart(id)
            resizeHandle = .none
            draggedPartId = id
            dragStart = point
        case .deselectAll:
            coordinator?.selectPart(nil)
        case .sendMessage(let partId, let message):
            // Check if we clicked a field in browse mode — start editing
            if let part = document.parts.first(where: { $0.id == partId }),
               part.partType == .field && !part.lockText {
                startFieldEditing(part: part)
                return  // Don't dispatch mouseDown for field editing
            }
            // For buttons and other parts, dispatch the message
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

        // Handle paint tool dragging
        if isDragging && ToolState(currentTool: currentTool.rawValue).category == .paint {
            let x = Int(point.x)
            let y = Int(point.y)

            switch currentTool {
            case .pencil:
                // Collect freeform points (no bitmap drawing)
                pencilPoints.append(PathPoint(x: Double(point.x), y: Double(point.y)))
                dragCurrent = point  // For visual preview
            case .spray:
                let pl = paintLayerForCurrentCard()
                pl.spray(cx: x, cy: y, radius: 12, density: 15, color: NSColor.black)
            case .eraser:
                let pl = paintLayerForCurrentCard()
                pl.erase(cx: x, cy: y, radius: 10)
            case .line, .rect, .oval, .text:
                // Rubber-band preview -- update drag current
                dragCurrent = point
            default:
                break
            }

            needsDisplay = true
            return
        }

        if let partId = draggedPartId, let start = dragStart {
            let dx = Double(point.x - start.x)
            let dy = Double(point.y - start.y)
            if resizeHandle != .none {
                // Resize the part using the handle, with size-matching snap
                let otherParts = allOtherParts(excluding: partId)
                var proposedPart = document.parts.first(where: { $0.id == partId })!
                // Apply raw resize to get proposed dimensions
                proposedPart.width += dx
                proposedPart.height += dy
                let snap = alignmentEngine.computeResizeSnap(
                    resizingPart: proposedPart,
                    otherParts: otherParts,
                    canvasWidth: Double(bounds.width),
                    canvasHeight: Double(bounds.height)
                )
                activeGuides = snap.guides
                coordinator?.resizePart(id: partId, handle: resizeHandle, dx: dx, dy: dy)
            } else {
                // Move the part with alignment snapping
                let otherParts = allOtherParts(excluding: partId)
                var proposedPart = document.parts.first(where: { $0.id == partId })!
                proposedPart.left += dx
                proposedPart.top += dy
                let snap = alignmentEngine.computeMoveSnap(
                    movingPart: proposedPart,
                    otherParts: otherParts,
                    canvasWidth: Double(bounds.width),
                    canvasHeight: Double(bounds.height)
                )
                activeGuides = snap.guides
                coordinator?.movePart(id: partId, dx: dx + snap.dx, dy: dy + snap.dy)
            }
            dragStart = point
            needsDisplay = true
        } else if isDragging {
            dragCurrent = point
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = flippedPoint(for: event)

        // Handle paint tool mouseUp (shape tools create Parts, bitmap tools use PaintLayer)
        if isDragging && ToolState(currentTool: currentTool.rawValue).category == .paint {
            if let start = dragStart {
                let x0 = Int(start.x), y0 = Int(start.y)
                let x1 = Int(point.x), y1 = Int(point.y)

                switch currentTool {
                case .line:
                    let points = [PathPoint(x: Double(x0), y: Double(y0)), PathPoint(x: Double(x1), y: Double(y1))]
                    let minX = min(Double(x0), Double(x1))
                    let minY = min(Double(y0), Double(y1))
                    var newPart = Part(
                        partType: .shape,
                        cardId: editingBackground ? nil : currentCardId,
                        backgroundId: editingBackground ? currentBackgroundId : nil,
                        name: "Line \(document.parts.count + 1)",
                        left: minX, top: minY,
                        width: max(1, abs(Double(x1 - x0))), height: max(1, abs(Double(y1 - y0)))
                    )
                    newPart.shapeType = .line
                    newPart.pathData = points
                    newPart.strokeColor = "#000000"
                    newPart.strokeWidth = 2
                    coordinator?.addPart(newPart)

                case .rect:
                    let rx = min(Double(x0), Double(x1)), ry = min(Double(y0), Double(y1))
                    let rw = abs(Double(x1 - x0)), rh = abs(Double(y1 - y0))
                    if rw > 3 && rh > 3 {
                        var newPart = Part(
                            partType: .shape,
                            cardId: editingBackground ? nil : currentCardId,
                            backgroundId: editingBackground ? currentBackgroundId : nil,
                            name: "Rectangle \(document.parts.count + 1)",
                            left: rx, top: ry, width: rw, height: rh
                        )
                        newPart.shapeType = .rectangle
                        newPart.strokeColor = "#000000"
                        newPart.fillColor = "#FFFFFF"
                        newPart.strokeWidth = 1
                        coordinator?.addPart(newPart)
                    }

                case .oval:
                    let rx = min(Double(x0), Double(x1)), ry = min(Double(y0), Double(y1))
                    let rw = abs(Double(x1 - x0)), rh = abs(Double(y1 - y0))
                    if rw > 3 && rh > 3 {
                        var newPart = Part(
                            partType: .shape,
                            cardId: editingBackground ? nil : currentCardId,
                            backgroundId: editingBackground ? currentBackgroundId : nil,
                            name: "Oval \(document.parts.count + 1)",
                            left: rx, top: ry, width: rw, height: rh
                        )
                        newPart.shapeType = .oval
                        newPart.strokeColor = "#000000"
                        newPart.fillColor = "#FFFFFF"
                        newPart.strokeWidth = 1
                        coordinator?.addPart(newPart)
                    }

                case .pencil:
                    if pencilPoints.count >= 2 {
                        // Calculate bounding box
                        let minX = pencilPoints.map(\.x).min()!
                        let minY = pencilPoints.map(\.y).min()!
                        let maxX = pencilPoints.map(\.x).max()!
                        let maxY = pencilPoints.map(\.y).max()!
                        var newPart = Part(
                            partType: .shape,
                            cardId: editingBackground ? nil : currentCardId,
                            backgroundId: editingBackground ? currentBackgroundId : nil,
                            name: "Freeform \(document.partsForCard(currentCardId).count + 1)",
                            left: minX, top: minY,
                            width: max(1, maxX - minX), height: max(1, maxY - minY)
                        )
                        newPart.shapeType = .freeform
                        newPart.pathData = pencilPoints
                        newPart.strokeColor = "#000000"
                        newPart.fillColor = "#FFFFFF"
                        newPart.strokeWidth = 2
                        coordinator?.addPart(newPart)
                        coordinator?.selectPart(newPart.id)
                    }
                    pencilPoints = []

                case .text:
                    // Create a transparent field at the click location
                    var newField = Part(
                        partType: .field,
                        cardId: editingBackground ? nil : currentCardId,
                        backgroundId: editingBackground ? currentBackgroundId : nil,
                        name: "Text \(document.partsForCard(currentCardId).count + 1)",
                        left: Double(x1),
                        top: Double(y1),
                        width: 200,
                        height: 30
                    )
                    newField.fieldStyle = .transparent
                    newField.lockText = false
                    coordinator?.addPart(newField)
                    coordinator?.selectPart(newField.id)

                default:
                    break
                }
            }

            isDragging = false
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
            return
        }

        if draggedPartId != nil {
            draggedPartId = nil
            dragStart = nil
            resizeHandle = .none
            activeGuides = []
            needsDisplay = true
            return
        }

        // In browse mode, dispatch mouseUp even without a drag
        let toolCheck = ToolState(currentTool: currentTool.rawValue)
        if toolCheck.category == .browse {
            let hitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)
            if let part = hitPart {
                // Handle image invert-on-click
                if part.partType == .image && part.invertOnClick {
                    coordinator?.togglePartHilite(id: part.id)
                }
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
                cardId: editingBackground ? nil : currentCardId,
                backgroundId: editingBackground ? currentBackgroundId : nil,
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

    // MARK: - Web View Management

    /// Create, update, or remove WKWebViews for webpage parts on the current card.
    private func updateWebViews() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseMode = toolState.category == .browse

        // Get all webpage parts on the current card
        let cardParts = document.partsForCard(currentCardId)
        let bgParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            bgParts = document.partsForBackground(card.backgroundId)
        } else {
            bgParts = []
        }
        let allParts = cardParts + bgParts
        let webParts = allParts.filter { $0.partType == .webpage && $0.visible }

        // In edit mode or no webpage parts, hide all webviews
        if !isBrowseMode || webParts.isEmpty {
            for (_, wv) in webViews {
                wv.removeFromSuperview()
            }
            webViews.removeAll()
            loadedURLs.removeAll()
            return
        }

        // Track which parts are still active
        var activeIds = Set<UUID>()

        for part in webParts {
            activeIds.insert(part.id)

            // Resolve URL — check linked field first, then static URL
            let urlString: String
            if let linkedId = part.urlSourceFieldId,
               let linkedField = allParts.first(where: { $0.id == linkedId }) {
                urlString = linkedField.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                urlString = part.url.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Validate URL
            guard !urlString.isEmpty,
                  let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "https" || scheme == "http") else {
                // Invalid URL — remove webview if exists, show placeholder
                if let wv = webViews.removeValue(forKey: part.id) {
                    wv.removeFromSuperview()
                    loadedURLs.removeValue(forKey: part.id)
                }
                continue
            }

            // Position the webview to match the part's rect
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existingWV = webViews[part.id] {
                // Update position/size
                existingWV.frame = frame
                // Reload only if URL changed
                if loadedURLs[part.id] != urlString {
                    existingWV.load(URLRequest(url: url))
                    loadedURLs[part.id] = urlString
                }
            } else {
                // Create new webview
                let config = WKWebViewConfiguration()
                config.preferences.isElementFullscreenEnabled = false
                let wv = WKWebView(frame: frame, configuration: config)
                wv.allowsBackForwardNavigationGestures = false
                wv.load(URLRequest(url: url))
                addSubview(wv)
                webViews[part.id] = wv
                loadedURLs[part.id] = urlString
            }
        }

        // Remove webviews for parts that no longer exist
        for id in webViews.keys {
            if !activeIds.contains(id) {
                webViews[id]?.removeFromSuperview()
                webViews.removeValue(forKey: id)
                loadedURLs.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Resize Handle Hit Testing

    /// Check if a point hits a resize handle on the selected part.
    private func hitTestResizeHandle(_ point: CGPoint) -> ResizeHandle {
        guard let selectedId = selectedPartId,
              let part = document.parts.first(where: { $0.id == selectedId }) else {
            return .none
        }

        let handleSize: CGFloat = 10 // slightly larger hit area than visual
        let rect = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

        let handles: [(ResizeHandle, CGPoint)] = [
            (.topLeft,      CGPoint(x: rect.minX, y: rect.minY)),
            (.topCenter,    CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight,     CGPoint(x: rect.maxX, y: rect.minY)),
            (.rightCenter,  CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight,  CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottomCenter, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft,   CGPoint(x: rect.minX, y: rect.maxY)),
            (.leftCenter,   CGPoint(x: rect.minX, y: rect.midY)),
        ]

        for (handle, center) in handles {
            let handleRect = CGRect(
                x: center.x - handleSize / 2,
                y: center.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            if handleRect.contains(point) {
                return handle
            }
        }

        return .none
    }

    // MARK: - Helpers

    /// Convert window coordinates to flipped (top-left origin) view coordinates.
    private func flippedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        // View is already flipped (isFlipped = true), so no additional transform needed
        return point
    }

    /// Get all parts on the current card/background except the one being manipulated.
    private func allOtherParts(excluding partId: UUID) -> [Part] {
        let cardParts = document.partsForCard(currentCardId)
        let bgParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            bgParts = document.partsForBackground(card.backgroundId)
        } else {
            bgParts = []
        }
        return (cardParts + bgParts).filter { $0.id != partId }
    }

    /// Get or create the paint layer for the current card.
    private func paintLayerForCurrentCard() -> PaintLayer {
        if let existing = paintLayers[currentCardId] {
            return existing
        }
        let layer = PaintLayer(width: max(1, Int(bounds.width)), height: max(1, Int(bounds.height)))
        paintLayers[currentCardId] = layer
        return layer
    }

    /// Draw alignment snap guides on the canvas.
    private func drawAlignmentGuides(ctx: CGContext) {
        for guide in activeGuides {
            ctx.saveGState()

            let color: NSColor
            switch guide.kind {
            case .edge:    color = NSColor.systemBlue.withAlphaComponent(0.6)
            case .center:  color = NSColor.systemPurple.withAlphaComponent(0.6)
            case .canvas:  color = NSColor.systemRed.withAlphaComponent(0.4)
            case .spacing: color = NSColor.systemGreen.withAlphaComponent(0.5)
            }

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(0.5)
            ctx.setLineDash(phase: 0, lengths: [3, 3])

            switch guide.orientation {
            case .vertical:
                ctx.move(to: CGPoint(x: guide.position, y: 0))
                ctx.addLine(to: CGPoint(x: guide.position, y: Double(bounds.height)))
            case .horizontal:
                ctx.move(to: CGPoint(x: 0, y: guide.position))
                ctx.addLine(to: CGPoint(x: Double(bounds.width), y: guide.position))
            }
            ctx.strokePath()

            ctx.restoreGState()
        }
    }
}

// MARK: - NSTextFieldDelegate (inline field editing)

extension CardCanvasNSView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        endFieldEditing()
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            // Enter key pressed
            if let partId = activeFieldPartId,
               let part = document.parts.first(where: { $0.id == partId }),
               part.enterKeyEnabled {
                // Save text first
                let text = activeFieldEditor?.stringValue ?? ""
                coordinator?.updatePartText(id: partId, text: text)
                // End editing
                let savedPartId = partId
                activeFieldEditor?.removeFromSuperview()
                activeFieldEditor = nil
                activeFieldPartId = nil
                needsDisplay = true
                // Dispatch enterKey message
                coordinator?.dispatchMessage("enterKey", to: savedPartId)
                return true
            }
            // If enterKey not enabled, just end editing normally
            endFieldEditing()
            needsDisplay = true
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            // Escape: cancel editing without saving
            activeFieldEditor?.removeFromSuperview()
            activeFieldEditor = nil
            activeFieldPartId = nil
            needsDisplay = true
            return true
        }
        return false
    }
}
