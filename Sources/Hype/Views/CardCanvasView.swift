import SwiftUI
import HypeCore
import AppKit

/// Convert a hex color string to NSColor.
private func nsColorFromHex(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return .black }
    return NSColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
        green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
        blue: CGFloat(rgb & 0xFF) / 255.0,
        alpha: 1.0
    )
}

/// AppKit-based dialog provider that shows real NSAlert/NSTextField dialogs.
final class AppKitDialogProvider: DialogProvider, @unchecked Sendable {
    func showAnswer(prompt: String) -> String {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return "OK"
    }

    func showAsk(prompt: String) -> String {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = ""
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return input.stringValue
        }
        return ""
    }
}
import WebKit
import AVKit

struct CardCanvasView: NSViewRepresentable {
    @Binding var document: HypeDocumentWrapper
    let currentCardId: UUID
    let currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    let editingBackground: Bool
    var paintColorHex: String = "#000000"

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CardCanvasNSView {
        let view = CardCanvasNSView()
        view.wantsLayer = true  // Layer-backed so subviews (NSTextField) composite properly
        view.document = document.document
        view.currentCardId = currentCardId
        view.currentTool = currentTool
        view.selectedPartIds = selectedPartIds
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
        nsView.selectedPartIds = selectedPartIds
        nsView.editingBackground = editingBackground
        // Sync paint color from SwiftUI Color hex to NSColor
        nsView.paintColor = nsColorFromHex(paintColorHex)
        nsView.coordinator = context.coordinator
        nsView.updateCursor()
        // Only redraw if not actively editing a field — constant redraws
        // during editing can interfere with the NSTextField overlay
        if nsView.isFieldEditing {
            nsView.setNeedsDisplay(nsView.bounds.insetBy(dx: -1, dy: -1))
        } else {
            nsView.needsDisplay = true
        }
    }

    /// Coordinator bridges NSView callbacks back to SwiftUI state.
    @MainActor
    final class Coordinator {
        var parent: CardCanvasView
        private let dispatcher = MessageDispatcher()

        init(parent: CardCanvasView) {
            self.parent = parent
        }

        /// Clear selection and select a single part (or none).
        func selectPart(_ id: UUID?) {
            if let id = id {
                parent.selectedPartIds = [id]
            } else {
                parent.selectedPartIds = []
            }
        }

        /// Add a part to the existing selection.
        func addToSelection(_ id: UUID) {
            parent.selectedPartIds.insert(id)
        }

        /// Remove a part from the existing selection.
        func removeFromSelection(_ id: UUID) {
            parent.selectedPartIds.remove(id)
        }

        /// Set the full selection to a specific set of IDs.
        func selectParts(_ ids: Set<UUID>) {
            parent.selectedPartIds = ids
        }

        func addPart(_ part: Part) {
            parent.document.document.addPart(part)
            // Dispatch creation message
            let message: String
            switch part.partType {
            case .button: message = "newButton"
            case .field:  message = "newField"
            default:      message = "newButton"
            }
            dispatchMessage(message, to: part.id)
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

        /// Select a radio button and deselect all other radio buttons in the same family.
        func selectRadioButton(id: UUID, family: Int) {
            // Clear hilite on all radio buttons in the same family on the current card
            let cardId = parent.currentCardId
            let parts = parent.document.document.partsForCard(cardId)
            for part in parts where part.partType == .button && part.buttonStyle == .radioButton && part.family == family {
                parent.document.document.updatePart(id: part.id) { $0.hilite = (part.id == id) }
            }
            // Also check background parts
            if let card = parent.document.document.cards.first(where: { $0.id == cardId }) {
                let bgParts = parent.document.document.partsForBackground(card.backgroundId)
                for part in bgParts where part.partType == .button && part.buttonStyle == .radioButton && part.family == family {
                    parent.document.document.updatePart(id: part.id) { $0.hilite = (part.id == id) }
                }
            }
        }

        func deletePart(id: UUID) {
            // Dispatch delete message before removing
            if let part = parent.document.document.parts.first(where: { $0.id == id }) {
                let message: String
                switch part.partType {
                case .button: message = "deleteButton"
                case .field:  message = "deleteField"
                default:      message = "deleteButton"
                }
                dispatchMessage(message, to: id)
            }
            // Remove constraints referencing this part
            parent.document.document.removeConstraintsForPart(id)
            parent.selectedPartIds.remove(id)
            parent.document.document.removePart(id: id)
        }

        /// Add a layout constraint to the document.
        func addConstraint(_ constraint: LayoutConstraint) {
            parent.document.document.addConstraint(constraint)
            resolveConstraints()
        }

        /// Resolve all layout constraints for the current card.
        func resolveConstraints() {
            let cardId = parent.currentCardId
            let doc = parent.document.document
            let cardParts = doc.partsForCard(cardId)
            let card = doc.cards.first(where: { $0.id == cardId })
            let bgParts = card.map { doc.partsForBackground($0.backgroundId) } ?? []
            let allParts = cardParts + bgParts
            let partIds = Set(allParts.map(\.id))
            let relevantConstraints = doc.constraints.filter { partIds.contains($0.sourcePartId) }
            guard !relevantConstraints.isEmpty else { return }

            let solver = ConstraintSolver()
            let updates = solver.solve(
                constraints: relevantConstraints,
                parts: allParts,
                canvasWidth: Double(doc.stack.width),
                canvasHeight: Double(doc.stack.height)
            )
            for (partId, geom) in updates {
                parent.document.document.updatePart(id: partId) {
                    $0.left = geom.left
                    $0.top = geom.top
                    $0.width = geom.width
                    $0.height = geom.height
                }
            }
        }

        /// Dispatch a HypeTalk message to the current card (for card-level events).
        private let dialogProvider = AppKitDialogProvider()

        func dispatchMessageToCard(_ message: String) {
            let cardId = parent.currentCardId
            let _ = dispatcher.dispatch(message: message, params: [], targetId: cardId, document: parent.document.document, currentCardId: cardId, dialogProvider: dialogProvider)
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
                currentCardId: cardId,
                dialogProvider: dialogProvider
            )

            // Handle execution results
            switch result.status {
            case .completed, .passed:
                // Apply document modifications from script
                if let modified = result.modifiedDocument {
                    parent.document.document = modified
                }
                // Handle "show all cards" — cycle through every card with a delay
                if result.showAllCards {
                    NotificationCenter.default.post(name: .showAllCards, object: nil)
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
    var selectedPartIds: Set<UUID> = []
    var editingBackground: Bool = false
    weak var coordinator: CardCanvasView.Coordinator?

    /// Eraser radius in pixels (adjustable with [ and ] keys).
    var eraserRadius: Int = 10
    /// Spray radius in pixels (adjustable with [ and ] keys when spray tool active).
    var sprayRadius: Int = 12
    /// Current paint color for spray, bucket, pencil (bitmap) tools.
    var paintColor: NSColor = .black

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

    // Active AVPlayerViews for video parts (keyed by part ID)
    private var videoPlayers: [UUID: AVPlayerView] = [:]
    // Track which video URLs are loaded to avoid redundant loads
    private var loadedVideoURLs: [UUID: String] = [:]

    // Active NSHostingViews for chart parts (keyed by part ID)
    private var chartViews: [UUID: NSView] = [:]
    // Track which chart data is loaded to avoid redundant recreations
    private var loadedChartData: [UUID: String] = [:]

    // Paint layers keyed by card ID
    private var paintLayers: [UUID: PaintLayer] = [:]

    // Drag state
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    private var draggedPartId: UUID?
    private var resizeHandle: ResizeHandle = .none

    // Constraint linking state
    private var isConstraintDragging = false
    private var constraintSourcePartId: UUID?
    private var constraintSourceEdge: ConstraintEdge?
    private var constraintDragEnd: CGPoint?

    // Pencil freeform points collected during drag
    private var pencilPoints: [PathPoint] = []

    // Marquee selection state
    private var isMarqueeSelecting = false

    // Mouse hover tracking for mouseEnter/mouseLeave messages
    private var hoveredPartId: UUID?

    // Original text when field editing starts (for closeField vs exitField)
    private var originalFieldText: String?

    // Alignment snap guides currently visible
    private var activeGuides: [SnapGuide] = []

    // Idle timer for dispatching idle messages in browse mode
    private var idleTimer: Timer?

    // Timer for mouseStillDown messages while mouse is held
    private var mouseStillDownTimer: Timer?
    private var mouseStillDownPartId: UUID?

    // Throttle mouseWithin dispatches
    private var lastMouseWithinTime: Date = .distantPast

    /// Which resize handle is being dragged.
    enum ResizeHandle {
        case none, topLeft, topCenter, topRight, rightCenter
        case bottomRight, bottomCenter, bottomLeft, leftCenter
    }

    /// The background ID for the current card, used when creating background parts.
    private var currentBackgroundId: UUID? {
        document.cards.first(where: { $0.id == currentCardId })?.backgroundId
    }

    /// Whether a field is currently being edited inline.
    var isFieldEditing: Bool { activeFieldEditor != nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Don't handle keys while editing a field inline
        if activeFieldEditor != nil {
            super.keyDown(with: event)
            return
        }

        // In browse mode, dispatch keyboard messages to the current card
        let browseToolCheck = ToolState(currentTool: currentTool.rawValue)
        if browseToolCheck.category == .browse {
            switch event.keyCode {
            case 36: // Return
                coordinator?.dispatchMessageToCard("returnKey")
            case 76: // Enter
                coordinator?.dispatchMessageToCard("enterKey")
            case 48: // Tab
                coordinator?.dispatchMessageToCard("tabKey")
            case 123, 124, 125, 126: // Arrow keys
                coordinator?.dispatchMessageToCard("arrowKey")
            default:
                if event.modifierFlags.contains(.command) {
                    coordinator?.dispatchMessageToCard("commandKeyDown")
                }
            }
        }

        // Delete or Backspace: delete all selected parts
        if event.keyCode == 51 || event.keyCode == 117 {
            if !selectedPartIds.isEmpty {
                for id in selectedPartIds {
                    coordinator?.deletePart(id: id)
                }
                needsDisplay = true
                return
            }
        }

        // [ and ] keys: resize eraser or spray
        if currentTool == .eraser || currentTool == .spray {
            if event.keyCode == 33 { // [ key — decrease
                if currentTool == .eraser {
                    eraserRadius = max(3, eraserRadius - 2)
                } else {
                    sprayRadius = max(3, sprayRadius - 2)
                }
                updateCursor()
                return
            } else if event.keyCode == 30 { // ] key — increase
                if currentTool == .eraser {
                    eraserRadius = min(50, eraserRadius + 2)
                } else {
                    sprayRadius = min(50, sprayRadius + 2)
                }
                updateCursor()
                return
            }
        }

        // Arrow keys: nudge selected parts (1px, or 5px with Shift)
        guard !selectedPartIds.isEmpty else {
            super.keyDown(with: event)
            return
        }
        let nudge: Double = event.modifierFlags.contains(.shift) ? 5 : 1
        switch event.keyCode {
        case 123: // Left arrow
            for id in selectedPartIds { coordinator?.movePart(id: id, dx: -nudge, dy: 0) }
            needsDisplay = true; return
        case 124: // Right arrow
            for id in selectedPartIds { coordinator?.movePart(id: id, dx: nudge, dy: 0) }
            needsDisplay = true; return
        case 125: // Down arrow
            for id in selectedPartIds { coordinator?.movePart(id: id, dx: 0, dy: nudge) }
            needsDisplay = true; return
        case 126: // Up arrow
            for id in selectedPartIds { coordinator?.movePart(id: id, dx: 0, dy: -nudge) }
            needsDisplay = true; return
        default: break
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Skip drawing the part being edited inline — the NSTextField overlay replaces it
        renderer.render(ctx: ctx, document: document, cardId: currentCardId, size: bounds.size, skipPartId: activeFieldPartId)

        // Render the paint layer on top of card content
        let paintLayer = paintLayerForCurrentCard()
        if !paintLayer.isEmpty {
            paintLayer.render(into: ctx)
        }

        // Draw selection overlay for all selected parts
        for selectedId in selectedPartIds {
            if let part = document.parts.first(where: { $0.id == selectedId }) {
                drawSelectionOverlay(ctx: ctx, part: part)
            }
        }

        // Draw alignment guides
        if !activeGuides.isEmpty {
            drawAlignmentGuides(ctx: ctx)
        }

        // Draw constraint rubber band during Option+drag
        if isConstraintDragging, let sourceId = constraintSourcePartId,
           let sourceEdge = constraintSourceEdge,
           let endPoint = constraintDragEnd,
           let sourcePart = document.parts.first(where: { $0.id == sourceId }) {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemOrange.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            let startPoint = constraintEdgePoint(sourceEdge, part: sourcePart)
            ctx.move(to: startPoint)
            ctx.addLine(to: endPoint)
            ctx.strokePath()
            // Draw circle at start
            ctx.setFillColor(NSColor.systemOrange.cgColor)
            ctx.fillEllipse(in: CGRect(x: startPoint.x - 4, y: startPoint.y - 4, width: 8, height: 8))
            ctx.restoreGState()
        }

        // Draw constraint indicators on selected parts
        for selectedId in selectedPartIds {
            let partConstraints = document.constraints.filter { $0.sourcePartId == selectedId }
            for constraint in partConstraints {
                if let part = document.parts.first(where: { $0.id == selectedId }) {
                    drawConstraintIndicator(ctx: ctx, part: part, constraint: constraint)
                }
            }
        }

        // Update web views for webpage parts
        updateWebViews()

        // Update video players for video parts
        updateVideoPlayers()

        // Update chart views for chart parts
        updateChartViews()

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

    /// Show a popup menu for a popup-style button.
    private func showPopupMenu(for part: Part, at point: CGPoint) {
        let menu = NSMenu()
        let items = part.popupItems.split(separator: "\n", omittingEmptySubsequences: true)
        if items.isEmpty {
            menu.addItem(NSMenuItem(title: "(No items defined)", action: nil, keyEquivalent: ""))
        } else {
            for item in items {
                let menuItem = NSMenuItem(title: String(item), action: #selector(popupMenuItemSelected(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = (part.id, String(item))
                // Check the currently selected item
                if part.textContent == String(item) {
                    menuItem.state = .on
                }
                menu.addItem(menuItem)
            }
        }
        let screenPoint = NSPoint(x: part.left, y: part.top + part.height)
        menu.popUp(positioning: nil, at: screenPoint, in: self)
    }

    @objc private func popupMenuItemSelected(_ sender: NSMenuItem) {
        guard let (partId, selectedText) = sender.representedObject as? (UUID, String) else { return }
        coordinator?.updatePartText(id: partId, text: selectedText)
        // Dispatch mouseUp so scripts can respond to the selection
        coordinator?.dispatchMessage("mouseUp", to: partId)
        needsDisplay = true
    }

    private func startFieldEditing(part: Part) {
        // Don't edit if locked
        guard part.partType == .field && !part.lockText else { return }

        // Remove existing editor
        endFieldEditing()

        // Store original text for closeField vs exitField determination
        originalFieldText = part.textContent

        // Dispatch openField lifecycle message
        coordinator?.dispatchMessage("openField", to: part.id)

        // Create the text field overlay, matching the part's position and style exactly
        let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
        let textField = NSTextField(frame: frame)
        textField.stringValue = part.textContent
        textField.font = NSFont(name: part.textFont, size: CGFloat(part.textSize)) ?? NSFont.systemFont(ofSize: CGFloat(part.textSize))
        textField.textColor = .black
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.backgroundColor = .white
        textField.focusRingType = .exterior
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self
        textField.alignment = part.textAlign == .center ? .center : part.textAlign == .right ? .right : .left
        textField.cell?.wraps = !part.dontWrap
        textField.cell?.isScrollable = true
        textField.wantsLayer = true
        textField.layer?.zPosition = 1000  // Ensure it's above all canvas drawing

        addSubview(textField, positioned: .above, relativeTo: nil)
        needsDisplay = true  // Redraw canvas to hide the underlying part

        // Delay makeFirstResponder to ensure the text field is fully in the view hierarchy
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(textField)
        }

        activeFieldEditor = textField
        activeFieldPartId = part.id
    }

    private func endFieldEditing() {
        if let editor = activeFieldEditor, let partId = activeFieldPartId {
            // Save the text back to the part
            let text = editor.stringValue
            coordinator?.updatePartText(id: partId, text: text)

            // Dispatch closeField (text changed) or exitField (text unchanged)
            if text != originalFieldText {
                coordinator?.dispatchMessage("closeField", to: partId)
            } else {
                coordinator?.dispatchMessage("exitField", to: partId)
            }

            editor.removeFromSuperview()
        }
        activeFieldEditor = nil
        activeFieldPartId = nil
        originalFieldText = nil
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
            switch currentTool {
            case .eraser:
                // Circle cursor matching eraser size
                let size = CGFloat(eraserRadius * 2)
                let image = NSImage(size: NSSize(width: size, height: size))
                image.lockFocus()
                NSColor.gray.withAlphaComponent(0.5).setStroke()
                NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1)).stroke()
                image.unlockFocus()
                NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2)).set()
            case .spray:
                // Circle cursor matching spray radius, tinted with paint color
                let size = CGFloat(sprayRadius * 2)
                let image = NSImage(size: NSSize(width: size, height: size))
                image.lockFocus()
                paintColor.withAlphaComponent(0.4).setStroke()
                let path = NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1))
                path.lineWidth = 1.5
                path.stroke()
                // Center dot showing color
                paintColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: size/2 - 2, y: size/2 - 2, width: 4, height: 4)).fill()
                image.unlockFocus()
                NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2)).set()
            default:
                NSCursor.crosshair.set()
            }
        }
    }

    // MARK: - Idle Timer

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let toolState = ToolState(currentTool: self.currentTool.rawValue)
            if toolState.category == .browse && self.activeFieldEditor == nil {
                self.coordinator?.dispatchMessageToCard("idle")
            }
        }
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopIdleTimer()
            mouseStillDownTimer?.invalidate()
            mouseStillDownTimer = nil
            // Remove frame change observer
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: self)
        } else {
            // Observe frame changes to resolve constraints on resize
            postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(viewFrameDidChange),
                name: NSView.frameDidChangeNotification,
                object: self
            )
        }
    }

    @objc private func viewFrameDidChange(_ notification: Notification) {
        // Resolve layout constraints whenever the view is resized
        coordinator?.resolveConstraints()
        needsDisplay = true
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // Final constraint resolution after user finishes resizing
        coordinator?.resolveConstraints()
        needsDisplay = true
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

    // MARK: - Tracking areas for mouseMoved

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .mouseEnteredAndExited],
            owner: self
        ))
        startIdleTimer()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = flippedPoint(for: event)
        let hitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)
        let newHoverId = hitPart?.id

        if newHoverId != hoveredPartId {
            // Leave old part
            if let oldId = hoveredPartId {
                coordinator?.dispatchMessage("mouseLeave", to: oldId)
            }
            hoveredPartId = newHoverId
            // Enter new part
            if let newId = newHoverId {
                coordinator?.dispatchMessage("mouseEnter", to: newId)
            }
        }

        // Dispatch mouseWithin (throttled to every 100ms)
        if let partId = hoveredPartId, Date().timeIntervalSince(lastMouseWithinTime) > 0.1 {
            lastMouseWithinTime = Date()
            let toolState = ToolState(currentTool: currentTool.rawValue)
            if toolState.category == .browse {
                coordinator?.dispatchMessage("mouseWithin", to: partId)
            }
        }
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
                pl.spray(cx: x, cy: y, radius: sprayRadius, density: max(10, sprayRadius * 2), color: paintColor)
            case .eraser:
                let pl = paintLayerForCurrentCard()
                pl.erase(cx: x, cy: y, radius: eraserRadius)
            case .bucket:
                let pl = paintLayerForCurrentCard()
                pl.floodFill(x: x, y: y, color: paintColor)
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

        // Option+click on a part in select/edit mode → start constraint drag
        if event.modifierFlags.contains(.option), let part = hitPart {
            isConstraintDragging = true
            constraintSourcePartId = part.id
            constraintSourceEdge = nearestEdge(of: part, to: point)
            constraintDragEnd = point
            dragStart = point
            needsDisplay = true
            return
        }

        // Double-click on a part in browse mode → dispatch message and open properties
        let toolCheck = ToolState(currentTool: currentTool.rawValue)
        if event.clickCount == 2 && toolCheck.category == .browse, let part = hitPart {
            coordinator?.dispatchMessage("mouseDoubleClick", to: part.id)
            NotificationCenter.default.post(name: .editPartProperties, object: part.id)
            return
        }

        var toolState = ToolState(currentTool: currentTool.rawValue)
        toolState.selectedPartId = selectedPartIds.first

        // Handle select tool directly for cleaner click-vs-marquee logic
        if currentTool == .select {
            // Check resize handle first (single selection only)
            if selectedPartIds.count == 1 {
                let handle = hitTestResizeHandle(point)
                if handle != .none {
                    resizeHandle = handle
                    dragStart = point
                    draggedPartId = selectedPartIds.first
                    return
                }
            }

            if let part = hitPart {
                // Clicked ON a part — select it and prepare for drag
                if event.modifierFlags.contains(.shift) {
                    if selectedPartIds.contains(part.id) {
                        coordinator?.removeFromSelection(part.id)
                    } else {
                        coordinator?.addToSelection(part.id)
                    }
                } else if !selectedPartIds.contains(part.id) {
                    // Only re-select if not already in the selection
                    // (avoids clearing multi-selection when dragging one of them)
                    coordinator?.selectPart(part.id)
                }
                resizeHandle = .none
                draggedPartId = part.id
                dragStart = point
            } else {
                // Clicked on EMPTY space — start marquee selection
                coordinator?.selectPart(nil)
                dragStart = point
                dragCurrent = point
                isDragging = true
                isMarqueeSelecting = true
                needsDisplay = true
            }
            return
        }

        let result = mouseHandler.handleMouseDown(tool: toolState, hitPart: hitPart, point: point)

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
                return
            }
            // Check if we clicked a popup button — show popup menu
            if let part = document.parts.first(where: { $0.id == partId }),
               part.partType == .button && part.buttonStyle == .popup {
                showPopupMenu(for: part, at: point)
                return
            }
            coordinator?.dispatchMessage(message, to: partId)
            // Start mouseStillDown timer for held clicks in browse mode
            mouseStillDownPartId = partId
            mouseStillDownTimer?.invalidate()
            mouseStillDownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let pid = self.mouseStillDownPartId else { return }
                self.coordinator?.dispatchMessage("mouseStillDown", to: pid)
            }
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

        // Handle constraint drag
        if isConstraintDragging {
            constraintDragEnd = point
            needsDisplay = true
            return
        }

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
                pl.spray(cx: x, cy: y, radius: sprayRadius, density: max(8, sprayRadius), color: paintColor)
            case .eraser:
                let pl = paintLayerForCurrentCard()
                pl.erase(cx: x, cy: y, radius: eraserRadius)
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
            } else if selectedPartIds.count > 1 && selectedPartIds.contains(partId) {
                // Move ALL selected parts by the same delta
                for id in selectedPartIds {
                    coordinator?.movePart(id: id, dx: dx, dy: dy)
                }
                activeGuides = []
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
        // Cancel mouseStillDown timer
        mouseStillDownTimer?.invalidate()
        mouseStillDownTimer = nil
        mouseStillDownPartId = nil

        let point = flippedPoint(for: event)

        // Handle constraint drag completion
        if isConstraintDragging {
            completeConstraintDrag(at: point)
            isConstraintDragging = false
            constraintSourcePartId = nil
            constraintSourceEdge = nil
            constraintDragEnd = nil
            needsDisplay = true
            return
        }

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

        // Complete marquee selection
        if isMarqueeSelecting, let start = dragStart, let current = dragCurrent {
            let marqueeRect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            let allParts = allVisibleParts()
            let selected = allParts.filter { part in
                let partRect = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
                return marqueeRect.intersects(partRect)
            }
            coordinator?.selectParts(Set(selected.map(\.id)))
            isMarqueeSelecting = false
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
                // Auto-hilite for buttons: checkboxes and toggles toggle on click,
                // radio buttons set hilite (and clear siblings in same family)
                if part.partType == .button {
                    switch part.buttonStyle {
                    case .checkBox, .toggle:
                        coordinator?.togglePartHilite(id: part.id)
                    case .radioButton:
                        // Set this radio button, clear others in the same family
                        coordinator?.selectRadioButton(id: part.id, family: part.family)
                    default:
                        // Standard buttons with autoHilite get a momentary flash
                        // (hilite is visual only during click, not persistent)
                        break
                    }
                }
                coordinator?.dispatchMessage("mouseUp", to: part.id)
            }
            return
        }

        guard isDragging else { return }

        let hitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)
        var toolState = ToolState(currentTool: currentTool.rawValue)
        toolState.selectedPartId = selectedPartIds.first

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
                wv.navigationDelegate = self
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

    // MARK: - Video Player Management

    /// Create, update, or remove AVPlayerViews for video parts on the current card.
    private func updateVideoPlayers() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseMode = toolState.category == .browse

        let cardParts = document.partsForCard(currentCardId)
        let bgParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            bgParts = document.partsForBackground(card.backgroundId)
        } else {
            bgParts = []
        }
        let allParts = cardParts + bgParts
        let videoParts = allParts.filter { $0.partType == .video && $0.visible }

        // In edit mode or no video parts, hide all players
        if !isBrowseMode || videoParts.isEmpty {
            for (_, player) in videoPlayers {
                player.player?.pause()
                player.removeFromSuperview()
            }
            videoPlayers.removeAll()
            loadedVideoURLs.removeAll()
            return
        }

        // Track which parts are still active
        var activeIds = Set<UUID>()

        for part in videoParts {
            activeIds.insert(part.id)
            let urlString = part.videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty else { continue }

            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = videoPlayers[part.id] {
                existing.frame = frame
                if loadedVideoURLs[part.id] != urlString {
                    // URL changed — reload
                    let url = URL(string: urlString) ?? URL(fileURLWithPath: urlString)
                    existing.player = AVPlayer(url: url)
                    loadedVideoURLs[part.id] = urlString
                }
            } else {
                let playerView = AVPlayerView(frame: frame)
                playerView.controlsStyle = .inline
                playerView.showsFullScreenToggleButton = true

                let url = URL(string: urlString) ?? URL(fileURLWithPath: urlString)
                playerView.player = AVPlayer(url: url)

                addSubview(playerView, positioned: .above, relativeTo: nil)
                videoPlayers[part.id] = playerView
                loadedVideoURLs[part.id] = urlString
            }
        }

        // Remove players for parts that no longer exist
        for id in videoPlayers.keys where !activeIds.contains(id) {
            videoPlayers[id]?.player?.pause()
            videoPlayers[id]?.removeFromSuperview()
            videoPlayers.removeValue(forKey: id)
            loadedVideoURLs.removeValue(forKey: id)
        }
    }

    // MARK: - Chart View Management

    /// Create, update, or remove NSHostingViews for chart parts on the current card.
    private func updateChartViews() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseMode = toolState.category == .browse

        let cardParts = document.partsForCard(currentCardId)
        let bgParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            bgParts = document.partsForBackground(card.backgroundId)
        } else {
            bgParts = []
        }
        let allParts = cardParts + bgParts
        let chartParts = allParts.filter { $0.partType == .chart && $0.visible }

        // In edit mode or no chart parts, hide all chart views
        if !isBrowseMode || chartParts.isEmpty {
            for (_, view) in chartViews {
                view.removeFromSuperview()
            }
            chartViews.removeAll()
            loadedChartData.removeAll()
            return
        }

        // Track which parts are still active
        var activeIds = Set<UUID>()

        for part in chartParts {
            activeIds.insert(part.id)
            guard !part.chartData.isEmpty else { continue }

            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = chartViews[part.id] {
                existing.frame = frame
                if loadedChartData[part.id] != part.chartData {
                    // Data changed — recreate the hosting view
                    existing.removeFromSuperview()
                    chartViews.removeValue(forKey: part.id)
                    loadedChartData.removeValue(forKey: part.id)
                    // Fall through to creation below
                } else {
                    continue
                }
            }

            if let config = ChartConfig.fromJSON(part.chartData) {
                let chartView = ChartHostView(config: config)
                let hostingView = NSHostingView(rootView: chartView)
                hostingView.frame = frame
                addSubview(hostingView, positioned: .above, relativeTo: nil)
                chartViews[part.id] = hostingView
                loadedChartData[part.id] = part.chartData
            }
        }

        // Remove views for parts that no longer exist
        for id in chartViews.keys where !activeIds.contains(id) {
            chartViews[id]?.removeFromSuperview()
            chartViews.removeValue(forKey: id)
            loadedChartData.removeValue(forKey: id)
        }
    }

    // MARK: - Resize Handle Hit Testing

    /// Check if a point hits a resize handle on the selected part.
    private func hitTestResizeHandle(_ point: CGPoint) -> ResizeHandle {
        guard selectedPartIds.count == 1,
              let selectedId = selectedPartIds.first,
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

    /// Get all visible parts on the current card/background (respects editing mode).
    private func allVisibleParts() -> [Part] {
        let cardParts = document.partsForCard(currentCardId)
        let bgParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            bgParts = document.partsForBackground(card.backgroundId)
        } else {
            bgParts = []
        }
        if editingBackground {
            return bgParts.filter { $0.visible }
        } else {
            return (cardParts + bgParts).filter { $0.visible }
        }
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

    // MARK: - Constraint Helpers

    /// Determine which edge of a part is nearest to a point.
    private func nearestEdge(of part: Part, to point: CGPoint) -> ConstraintEdge {
        let distances: [(ConstraintEdge, Double)] = [
            (.left, abs(point.x - part.left)),
            (.right, abs(point.x - (part.left + part.width))),
            (.top, abs(point.y - part.top)),
            (.bottom, abs(point.y - (part.top + part.height))),
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }

    /// Get the position of a constraint edge on a part.
    private func edgePosition(_ edge: ConstraintEdge, part: Part) -> Double {
        switch edge {
        case .left: return part.left
        case .right: return part.left + part.width
        case .top: return part.top
        case .bottom: return part.top + part.height
        case .centerX: return part.left + part.width / 2
        case .centerY: return part.top + part.height / 2
        }
    }

    /// Get the CGPoint on a part for a given constraint edge (for drawing).
    private func constraintEdgePoint(_ edge: ConstraintEdge, part: Part) -> CGPoint {
        switch edge {
        case .left: return CGPoint(x: part.left, y: part.top + part.height / 2)
        case .right: return CGPoint(x: part.left + part.width, y: part.top + part.height / 2)
        case .top: return CGPoint(x: part.left + part.width / 2, y: part.top)
        case .bottom: return CGPoint(x: part.left + part.width / 2, y: part.top + part.height)
        case .centerX: return CGPoint(x: part.left + part.width / 2, y: part.top + part.height / 2)
        case .centerY: return CGPoint(x: part.left + part.width / 2, y: part.top + part.height / 2)
        }
    }

    /// Complete the constraint drag — determine target and show distance dialog.
    private func completeConstraintDrag(at point: CGPoint) {
        guard let sourceId = constraintSourcePartId,
              let sourceEdge = constraintSourceEdge else { return }

        let canvasW = Double(bounds.width)
        let canvasH = Double(bounds.height)

        // Determine target: hit another part, or near canvas edge
        let hitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)

        var targetType: ConstraintTargetType
        var targetPartId: UUID?
        var targetEdge: ConstraintEdge
        var currentDistance: Double

        if let target = hitPart, target.id != sourceId {
            // Part-to-part constraint
            targetType = .part
            targetPartId = target.id
            targetEdge = nearestEdge(of: target, to: point)
            let sourcePos = edgePosition(sourceEdge, part: document.parts.first(where: { $0.id == sourceId })!)
            let targetPos = edgePosition(targetEdge, part: target)
            currentDistance = abs(sourcePos - targetPos)
        } else {
            // Canvas edge constraint — determine nearest canvas edge
            targetType = .canvas
            targetPartId = nil
            let edgeDists: [(ConstraintEdge, Double)] = [
                (.left, abs(point.x)),
                (.right, abs(point.x - canvasW)),
                (.top, abs(point.y)),
                (.bottom, abs(point.y - canvasH)),
            ]
            targetEdge = edgeDists.min(by: { $0.1 < $1.1 })!.0
            // Ensure horizontal matches horizontal
            if sourceEdge.isHorizontal != targetEdge.isHorizontal {
                targetEdge = sourceEdge.isHorizontal ? .right : .bottom
            }
            let sourcePos = edgePosition(sourceEdge, part: document.parts.first(where: { $0.id == sourceId })!)
            let canvasPos: Double
            switch targetEdge {
            case .left: canvasPos = 0
            case .right: canvasPos = canvasW
            case .top: canvasPos = 0
            case .bottom: canvasPos = canvasH
            case .centerX: canvasPos = canvasW / 2
            case .centerY: canvasPos = canvasH / 2
            }
            currentDistance = abs(sourcePos - canvasPos)
        }

        // Validate: horizontal-to-horizontal, vertical-to-vertical
        if sourceEdge.isHorizontal != targetEdge.isHorizontal { return }

        // Show distance dialog — always show positive value
        let alert = NSAlert()
        alert.messageText = "Set Constraint Distance"
        alert.informativeText = "Distance from \(sourceEdge.rawValue) to \(targetType == .canvas ? "canvas " : "")\(targetEdge.rawValue) (pixels)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = String(Int(round(currentDistance)))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let userDistance = abs(Double(input.stringValue) ?? currentDistance)

        // Compute the signed distance for the solver:
        // The solver computes: desiredSourcePos = targetPos + distance
        // So distance = sourcePos - targetPos (with correct sign)
        let sourcePart = document.parts.first(where: { $0.id == sourceId })!
        let sourcePos = edgePosition(sourceEdge, part: sourcePart)
        let targetPos: Double
        if targetType == .canvas {
            switch targetEdge {
            case .left: targetPos = 0
            case .right: targetPos = canvasW
            case .top: targetPos = 0
            case .bottom: targetPos = canvasH
            case .centerX: targetPos = canvasW / 2
            case .centerY: targetPos = canvasH / 2
            }
        } else if let tid = targetPartId, let tp = document.parts.first(where: { $0.id == tid }) {
            targetPos = edgePosition(targetEdge, part: tp)
        } else {
            targetPos = 0
        }
        // Preserve the direction but use the user's magnitude
        let signedDistance = sourcePos >= targetPos ? userDistance : -userDistance

        let constraint = LayoutConstraint(
            sourcePartId: sourceId,
            sourceEdge: sourceEdge,
            targetType: targetType,
            targetPartId: targetPartId,
            targetEdge: targetEdge,
            distance: signedDistance
        )
        coordinator?.addConstraint(constraint)
    }

    /// Draw a small orange diamond indicator at a constraint's source edge.
    private func drawConstraintIndicator(ctx: CGContext, part: Part, constraint: LayoutConstraint) {
        let point = constraintEdgePoint(constraint.sourceEdge, part: part)
        ctx.saveGState()
        ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(0.8).cgColor)
        let size: CGFloat = 6
        ctx.move(to: CGPoint(x: point.x, y: point.y - size))
        ctx.addLine(to: CGPoint(x: point.x + size, y: point.y))
        ctx.addLine(to: CGPoint(x: point.x, y: point.y + size))
        ctx.addLine(to: CGPoint(x: point.x - size, y: point.y))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
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

// MARK: - WKNavigationDelegate (web view error handling)

extension CardCanvasNSView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleWebViewError(webView: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleWebViewError(webView: webView, error: error)
    }

    private func handleWebViewError(webView: WKWebView, error: Error) {
        // Find the part ID for this webview and show the error as placeholder text
        if let partId = webViews.first(where: { $0.value === webView })?.key {
            webView.removeFromSuperview()
            webViews.removeValue(forKey: partId)
            loadedURLs.removeValue(forKey: partId)
            coordinator?.updatePartText(id: partId, text: "Error: \(error.localizedDescription)")
            needsDisplay = true
        }
    }
}
