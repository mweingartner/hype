import SwiftUI
import HypeCore
import WebKit

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
        // Keep coordinator's parent in sync so it reads current state
        context.coordinator.parent = self
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

    // Drag state
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    private var draggedPartId: UUID?
    private var resizeHandle: ResizeHandle = .none

    // Alignment snap guides currently visible
    private var activeGuides: [SnapGuide] = []

    /// Which resize handle is being dragged.
    enum ResizeHandle {
        case none, topLeft, topCenter, topRight, rightCenter
        case bottomRight, bottomCenter, bottomLeft, leftCenter
    }

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

        // Draw alignment guides
        if !activeGuides.isEmpty {
            drawAlignmentGuides(ctx: ctx)
        }

        // Update web views for webpage parts
        updateWebViews()

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
