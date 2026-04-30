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
/// Drawing provider that draws to a PaintLayer from script commands.
final class PaintLayerDrawingProvider: DrawingProvider, @unchecked Sendable {
    private let paintLayer: PaintLayer

    init(paintLayer: PaintLayer) {
        self.paintLayer = paintLayer
    }

    func drawLine(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String) {
        let color = nsColorFromHex(colorHex)
        paintLayer.drawThickLine(x0: from.0, y0: from.1, x1: to.0, y1: to.1, radius: radius, color: color)
    }
}

import WebKit
import AVKit
import SpriteKit

struct CardCanvasView: NSViewRepresentable {
    @Binding var document: HypeDocumentWrapper
    let currentCardId: UUID
    let currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    let editingBackground: Bool
    var paintColorHex: String = "#000000"
    var pencilRadius: Int = 2

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
        context.coordinator.nsView = view

        // Wire the part animator's property-change callback so
        // animations modify the live document and trigger redraws.
        PartAnimator.shared.onPropertyChange = { [weak view] partId, property, value in
            guard let nsView = view else { return }
            guard let coord = nsView.coordinator else { return }
            coord.applyAnimatedPropertyChange(partId: partId, property: property, value: value)
            nsView.needsDisplay = true
        }

        // Wire the GIF animator callbacks.
        // onFrameChanged: trigger a redraw whenever any GIF advances.
        GIFAnimator.shared.onFrameChanged = { [weak view] _ in
            view?.needsDisplay = true
        }
        // onAnimationStart / onAnimationEnd: dispatch HypeTalk events.
        GIFAnimator.shared.onAnimationStart = { [weak view] partId in
            view?.coordinator?.dispatchMessage("animationStart", to: partId)
        }
        GIFAnimator.shared.onAnimationEnd = { [weak view] partId in
            view?.coordinator?.dispatchMessage("animationEnd", to: partId)
        }

        return view
    }

    static func dismantleNSView(_ nsView: CardCanvasNSView, coordinator: Coordinator) {
        // Stop the GIF timer and release all CGImage frame buffers.
        // Security Finding 6: required to prevent a process-lifetime
        // accumulation of CGImage arrays and a dangling timer across
        // document open/close cycles.
        GIFAnimator.shared.removeAll()
    }

    func updateNSView(_ nsView: CardCanvasNSView, context: Context) {
        // Keep coordinator's parent in sync so it reads current state
        context.coordinator.parent = self
        nsView.document = document.document
        nsView.currentCardId = currentCardId
        nsView.currentTool = currentTool
        nsView.selectedPartIds = selectedPartIds
        nsView.editingBackground = editingBackground
        // Sync paint color and pencil radius from SwiftUI
        nsView.paintColor = nsColorFromHex(paintColorHex)
        nsView.pencilRadius = pencilRadius
        nsView.coordinator = context.coordinator
        nsView.updateCursor()
        // Suppress redraws while a SpriteKit card transition is
        // playing. The SKView is on top showing the animated
        // transition between two card-texture scenes — if we
        // call needsDisplay here, the parent NSView's draw()
        // repaints the CGContext card content into its CALayer,
        // which composites OVER the SKView animation and makes
        // the transition appear instant. The transition's
        // completion handler clears isTransitioning and calls
        // needsDisplay itself to update to the new card.
        guard !nsView.isTransitioning else { return }
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
        weak var nsView: CardCanvasNSView?

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
            var p = part
            // Apply the stack's default font to newly created parts
            // that still carry the generic init default. This ensures
            // buttons and fields dropped from tools pick up whatever
            // the user (or a script) has set as the stack-level font.
            let stackFont = parent.document.document.stack.defaultFont
            if !stackFont.isEmpty {
                p.textFont = stackFont
            }
            parent.document.document.addPart(p)
            // Dispatch creation message
            let message: String
            switch p.partType {
            case .button: message = "newButton"
            case .field:  message = "newField"
            default:      message = "newButton"
            }
            dispatchMessage(message, to: p.id)
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

        /// Force the hilite state of a part to a specific value.
        /// Used by the transient mouseDown→mouseUp "pressed" state
        /// for autoHilite buttons (e.g. shadow-style buttons whose
        /// drop-shadow snaps to the opposite corner while held).
        func setPartHilite(id: UUID, to value: Bool) {
            parent.document.document.updatePart(id: id) { $0.hilite = value }
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
                // Release GIF state for image parts before the part
                // is removed from the document.
                if part.partType == .image {
                    GIFAnimator.shared.remove(partId: id)
                }
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

            // Use the actual canvas bounds so constraints resolve
            // to the live window dimensions, not the fixed stack
            // model size. The stack width/height is a minimum, not
            // a hard cap on where parts can be positioned.
            let cw = Double(nsView?.bounds.width ?? CGFloat(doc.stack.width))
            let ch = Double(nsView?.bounds.height ?? CGFloat(doc.stack.height))
            let solver = ConstraintSolver()
            let updates = solver.solve(
                constraints: relevantConstraints,
                parts: allParts,
                canvasWidth: cw,
                canvasHeight: ch
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

        /// Apply a single animated property change to the document.
        /// Called by PartAnimator's tick callback at ~60fps during
        /// active animations. Mirrors the property assignments in
        /// property-set handling but operates on the SwiftUI document
        /// binding directly.
        func applyAnimatedPropertyChange(partId: UUID, property: String, value: String) {
            parent.document.document.updatePart(id: partId) { part in
                switch property.lowercased() {
                case "left":     part.left = Double(value) ?? part.left
                case "top":      part.top = Double(value) ?? part.top
                case "width":    part.width = Double(value) ?? part.width
                case "height":   part.height = Double(value) ?? part.height
                case "rotation": part.rotation = Double(value) ?? part.rotation
                case "loc", "location":
                    let comps = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                    if comps.count >= 2 {
                        part.left = comps[0] - part.width / 2
                        part.top = comps[1] - part.height / 2
                    }
                default: break
                }
            }
        }

        /// Dispatch a HypeTalk message to the current card (for card-level events).
        private let dialogProvider = AppKitDialogProvider()
        private let aiProvider = OllamaAIScriptingProvider()

        private var drawingProvider: DrawingProvider {
            if let view = nsView {
                return PaintLayerDrawingProvider(paintLayer: view.paintLayerForCurrentCard())
            }
            return StubDrawingProvider()
        }

        /// App-level ("Hype") script stored in UserDefaults.
        private var appScript: String {
            UserDefaults.standard.string(forKey: "hypeAppScript") ?? ""
        }

        /// Dispatch a HypeTalk message to the current card and apply
        /// any document mutations / navigation / visual effects that
        /// the handler produced.
        ///
        /// NOTE: the earlier implementation of this function threw
        /// away the `ExecutionResult` entirely (`let _ = dispatcher
        /// .dispatch(...)`). Because `buildHierarchy` routes
        /// card-targeted messages through card → background →
        /// stack → Hype, every handler at any of those levels ran
        /// but none of their state mutations ever made it back into
        /// `parent.document.document`. That silently broke `idle`,
        /// `enterKey`, `returnKey`, `tabKey`, `arrowKey`,
        /// `commandKeyDown`, and card-level `keyDown` — the user
        /// reported "the idle event is not firing" because scripts
        /// like `on idle / set the loc of sprite "ball" to ... / end
        /// idle` appeared to do nothing. The fix is to share the
        /// same result-handling path that part-targeted messages
        /// already use (see `applyDispatchResult`).
        func dispatchMessageToCard(_ message: String, mouseX: Double = 0, mouseY: Double = 0) {
            dispatchMessageToCard(message, params: [], mouseX: mouseX, mouseY: mouseY)
        }

        func dispatchMessageToCard(_ message: String, params: [Value], mouseX: Double = 0, mouseY: Double = 0) {
            let cardId = parent.currentCardId
            dispatchThroughRuntime(
                message: message,
                params: params,
                targetId: cardId,
                currentCardId: cardId,
                mouseX: mouseX,
                mouseY: mouseY,
                scriptContext: nil
            )
        }

        /// Dispatch a HypeTalk message through the object hierarchy.
        /// This is the runtime — when you click a button in browse mode,
        /// its mouseUp handler fires, which can navigate, modify parts, etc.
        func dispatchMessage(_ message: String, to partId: UUID, mouseX: Double = 0, mouseY: Double = 0) {
            dispatchMessage(message, to: partId, params: [], mouseX: mouseX, mouseY: mouseY, scriptContext: nil)
        }

        func dispatchMessage(
            _ message: String,
            to partId: UUID,
            params: [Value],
            mouseX: Double = 0,
            mouseY: Double = 0,
            scriptContext: ScriptDispatchContext? = nil
        ) {
            let cardId = parent.currentCardId
            dispatchThroughRuntime(
                message: message,
                params: params,
                targetId: partId,
                currentCardId: cardId,
                mouseX: mouseX,
                mouseY: mouseY,
                scriptContext: scriptContext
            )
        }

        func dispatchIdleBurst(cardTargetId: UUID, partTargetIds: [UUID]) {
            let snapshot = parent.document.document
            let config = runtimeConfiguration()
            Task {
                let runtime = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: config)
                await runtime.dispatchIdleBurst(
                    cardTargetID: cardTargetId,
                    partTargetIDs: partTargetIds,
                    currentCardId: cardTargetId
                )
            }
        }

        /// Shared result-handling for both part-targeted
        /// (`dispatchMessage(_:to:)`) and card-targeted
        /// (`dispatchMessageToCard(_:)`) dispatches. Walks every
        /// side-effect surface an ExecutionResult can carry and
        /// applies it to SwiftUI state, AppKit, and the notification
        /// center.
        private func applyDispatchResult(_ result: ExecutionResult) {
            switch result.status {
            case .completed, .passed:
                // Apply document modifications from script. This is
                // the line whose absence caused the idle bug: every
                // card/bg/stack/app-level handler runs against a
                // document snapshot and returns a mutated copy in
                // `result.modifiedDocument`; writing it back is what
                // makes the mutation actually visible.
                if let modified = result.modifiedDocument {
                    parent.document.document = modified
                }
                // Handle "show all cards" — cycle through every card with a delay
                if result.showAllCards {
                    NotificationCenter.default.post(name: .showAllCards, object: nil)
                }
                // Handle navigation (e.g., go next card)
                if let navTarget = result.navigationTarget {
                    HypeLogger.shared.info("navigate to \(navTarget.uuidString.prefix(8))… effect=\(result.visualEffect ?? "nil") dur=\(result.visualEffectDuration ?? -1) nsView=\(nsView != nil ? "ok" : "NIL")", source: "Navigation")
                    if let effectName = result.visualEffect, !effectName.isEmpty {
                        let effect = HypeCore.VisualEffect.fromName(effectName)
                        if effect != .none {
                            let dur = result.visualEffectDuration ?? CardCanvasNSView.defaultTransitionDuration
                            nsView?.performCardTransition(to: navTarget, effect: effect, duration: dur)
                            // Post the navigation after the transition
                            // duration so the CGContext redraw happens
                            // AFTER the SK animation finishes.
                            DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
                                NotificationCenter.default.post(
                                    name: .navigateToCard,
                                    object: navTarget
                                )
                            }
                            return
                        }
                    }
                    // No visual effect (or .none) — navigate immediately
                    NotificationCenter.default.post(
                        name: .navigateToCard,
                        object: navTarget
                    )
                }
            case .error:
                if let err = result.error {
                    postScriptErrorNotification(err)
                }
            }
        }

        /// Translate a `ScriptError` into a `.showScriptError`
        /// notification carrying enough context for `MainContentView`
        /// to open the script editor for the offending object and
        /// highlight the error line. Called from `applyDispatchResult`
        /// whenever a dispatch returns `status == .error`.
        ///
        /// The notification is deliberately fire-and-forget — we
        /// don't block the dispatch path waiting for the UI to
        /// acknowledge. If no script editor is listening, the error
        /// is still logged to stderr via the dispatcher's printing
        /// path, so nothing is lost.
        private func postScriptErrorNotification(_ err: ScriptError) {
            var userInfo: [AnyHashable: Any] = [
                "line": err.line,
                "message": err.message,
                "handler": err.handler,
            ]
            // Resolve the target from err.objectId: could be a part,
            // card, background, stack, or the Hype (app) sentinel.
            // Fall back to .stack if we can't classify it — better
            // than dropping the error.
            let doc = parent.document.document
            if let objectId = err.objectId {
                if doc.parts.contains(where: { $0.id == objectId }) {
                    userInfo["target"] = ScriptTarget.part(objectId)
                    userInfo["partId"] = objectId
                } else if doc.cards.contains(where: { $0.id == objectId }) {
                    userInfo["target"] = ScriptTarget.card(objectId)
                } else if doc.backgrounds.contains(where: { $0.id == objectId }) {
                    userInfo["target"] = ScriptTarget.background(objectId)
                } else if doc.stack.id == objectId {
                    userInfo["target"] = ScriptTarget.stack
                } else if objectId == MessageDispatcher.hypeScriptSentinel {
                    userInfo["target"] = ScriptTarget.hype
                } else if let spriteTarget = resolveSpriteScriptTarget(objectId: objectId, in: doc) {
                    userInfo["target"] = spriteTarget.target
                    userInfo["partId"] = spriteTarget.partId
                } else {
                    userInfo["target"] = ScriptTarget.stack
                }
            } else {
                userInfo["target"] = ScriptTarget.stack
            }
            NotificationCenter.default.post(
                name: .showScriptError,
                object: nil,
                userInfo: userInfo
            )
        }

        private func dispatchThroughRuntime(
            message: String,
            params: [Value],
            targetId: UUID,
            currentCardId: UUID,
            mouseX: Double,
            mouseY: Double,
            scriptContext: ScriptDispatchContext?
        ) {
            let snapshot = parent.document.document
            let config = runtimeConfiguration()
            Task {
                let runtime = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: config)
                let result = await runtime.dispatchAndWait(
                    message,
                    params: params,
                    targetId: targetId,
                    currentCardId: currentCardId,
                    mouseX: mouseX,
                    mouseY: mouseY,
                    scriptContext: scriptContext
                )
                await MainActor.run {
                    self.applyDispatchResult(result)
                }
            }
        }

        private func runtimeConfiguration() -> StackRuntimeConfiguration {
            StackRuntimeConfiguration(
                dialogProvider: dialogProvider,
                drawingProvider: drawingProvider,
                aiProvider: aiProvider,
                appScript: appScript
            )
        }

        private func resolveSpriteScriptTarget(
            objectId: UUID,
            in document: HypeDocument
        ) -> (target: ScriptTarget, partId: UUID)? {
            for part in document.parts where part.partType == .spriteArea {
                guard let areaSpec = part.spriteAreaSpecModel else { continue }
                if areaSpec.scenes.contains(where: { $0.id == objectId }) {
                    return (.scene(partId: part.id, sceneId: objectId), part.id)
                }
                for scene in areaSpec.scenes where scene.scene.node(id: objectId) != nil {
                    return (.node(partId: part.id, nodeId: objectId), part.id)
                }
            }
            return nil
        }
    }
}

/// SKView subclass that passes through all mouse events to its superview.
/// Used for the card-level SpriteKit view so that CardCanvasNSView continues
/// to receive and handle all mouse/keyboard events.
private class PassthroughSKView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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

    // Active SKViews for spriteArea parts (keyed by part ID)
    private var spriteViews: [UUID: SKView] = [:]
    private var spriteScenes: [UUID: HypeSKScene] = [:]
    private var spriteBridges: [UUID: SceneBridge] = [:]
    private var loadedSceneSpecs: [UUID: String] = [:]
    private var loadedActiveSceneIDs: [UUID: UUID] = [:]
    private var pendingSceneLoadIds: Set<UUID> = []

    /// Last-known cursor position within each sprite scene, in Hype
    /// scene-local top-left-origin coordinates (the same system
    /// `the loc of sprite` returns). Updated on every mouseWithin /
    /// mouseDown / mouseUp / mouseDragged forwarded from the scene.
    /// Used to populate the `mouseLoc` / `mouseH` / `mouseV`
    /// properties for `frameUpdate` (and any other handler) so
    /// scripts that cross-reference mouse vs. sprite positions
    /// every frame — like "accelerate the ball when the cursor
    /// touches it" — see the real cursor instead of (0,0).
    /// Cleared when the scene tears down.
    private var lastSceneMousePosition: [UUID: PointSpec] = [:]

    // Card-level SpriteKit view for transitions (Phase A)
    private var cardSKView: PassthroughSKView?
    private var cardScene: CardSKScene?
    /// True while a card-to-card SpriteKit transition is playing.
    /// While set, `updateNSView` suppresses `needsDisplay = true`
    /// so the parent NSView's `draw()` doesn't repaint the
    /// CGContext card content on top of the animating SKView.
    /// Cleared in `performCardTransition`'s completion handler
    /// after the SKView is hidden.
    var isTransitioning = false

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

    // Pencil bitmap drawing state
    private var lastPencilPoint: CGPoint? = nil
    var pencilRadius: Int = 2

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

    /// The part ID currently auto-hilited by a held mouseDown.
    /// Cleared on mouseUp (or if the mouse drags off the part).
    /// Distinct from `hoveredPartId` — this only fires when the
    /// user is actively pressing, and only on parts whose
    /// `autoHilite` flag is true. Used by the renderer to switch
    /// shadow-style buttons into their "pressed" appearance.
    private var pressedButtonId: UUID?

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
                if focusFirstEditableField(reverse: event.modifierFlags.contains(.shift)) {
                    return
                }
                coordinator?.dispatchMessageToCard("tabKey")
            case 123, 124, 125, 126: // Arrow keys
                coordinator?.dispatchMessageToCard("arrowKey")
            default:
                if event.modifierFlags.contains(.command) {
                    coordinator?.dispatchMessageToCard("commandKeyDown")
                }
            }

            // Forward key events to active sprite scenes
            for (_, skView) in spriteViews {
                if let scene = skView.scene as? HypeSKScene {
                    scene.keyDown(with: event)
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

    override func keyUp(with event: NSEvent) {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        if toolState.category == .browse {
            // Forward key-up events to active sprite scenes
            for (_, skView) in spriteViews {
                if let scene = skView.scene as? HypeSKScene {
                    scene.keyUp(with: event)
                }
            }
        }
        super.keyUp(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        // While a SpriteKit card transition is playing, don't
        // repaint the CGContext content — it would composite over
        // the animating SKView and make the transition invisible.
        if isTransitioning {
            return
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Ensure idle timer is running (may not start from updateTrackingAreas alone)
        if idleTimer == nil { startIdleTimer() }

        // Skip drawing the part being edited inline — the NSTextField overlay replaces it.
        //
        // Pass `nativePartIds` so CardRenderer skips CG-rendering for parts that
        // already have a live AppKit/SpriteKit overlay (sprite areas, charts, web
        // pages, videos). Without this the SpriteAreaRenderer placeholder (teal
        // dashed border + scene-name label) would draw INTO the parent NSView's
        // CALayer and then show through any sprite-area SKView whose
        // `allowsTransparency` is on — making a transparent sprite scene look
        // "as if it's in edit mode" in browse. Same logic applies to chart /
        // video / web overlay parts: their native subview already paints the
        // pixels, so the CG placeholder is wasted work at best and visible
        // chrome at worst.
        //
        // We derive the set from the DOCUMENT (not the live `spriteViews` /
        // `chartViews` etc. dictionaries) and only in browse mode, because
        // (a) on a card-return, the dictionaries lag by one frame —
        // `updateSpriteViews()` runs LATER in this same draw, so the SKView
        // for a returning sprite area isn't in `spriteViews` yet — which
        // would let the placeholder flash through for one frame; and
        // (b) in edit mode we WANT the placeholder visible, since the SKView
        // is intentionally torn down in edit mode and the placeholder is
        // the authoring affordance.
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseModeForRender = toolState.category == .browse
        let nativePartIds: Set<UUID>
        if isBrowseModeForRender {
            let renderCardParts = document.partsForCard(currentCardId)
            let renderBgParts: [Part]
            if let renderCard = document.cards.first(where: { $0.id == currentCardId }) {
                renderBgParts = document.partsForBackground(renderCard.backgroundId)
            } else {
                renderBgParts = []
            }
            let nativeKinds: Set<PartType> = [.spriteArea, .chart, .webpage, .video]
            nativePartIds = Set(
                (renderCardParts + renderBgParts)
                    .filter { $0.visible && nativeKinds.contains($0.partType) }
                    .map(\.id)
            )
        } else {
            nativePartIds = []
        }
        renderer.render(
            ctx: ctx,
            document: document,
            cardId: currentCardId,
            size: bounds.size,
            skipPartId: activeFieldPartId,
            nativePartIds: nativePartIds
        )

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

        // Update sprite views for spriteArea parts
        updateSpriteViews()

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

    /// The cascade-resolved theme for the currently-displayed card,
    /// used to color selection chrome (resize handles, dashed
    /// outline, rubber-band marquee). Changes live as the user
    /// switches themes.
    private var resolvedTheme: HypeTheme {
        document.effectiveTheme(forCard: currentCardId)
    }

    private func drawSelectionOverlay(ctx: CGContext, part: Part) {
        let theme = resolvedTheme
        let strokeNS = theme.selectionStroke.nsColor
        let rect = CGRect(x: part.left - 1, y: part.top - 1, width: part.width + 2, height: part.height + 2)
        ctx.setStrokeColor(strokeNS.cgColor)
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
        ctx.setFillColor(strokeNS.cgColor)
        for h in handles {
            ctx.fill(CGRect(x: h.x - handleSize / 2, y: h.y - handleSize / 2, width: handleSize, height: handleSize))
        }
    }

    private func drawRubberBand(start: CGPoint, current: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let theme = resolvedTheme
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        ctx.setStrokeColor(theme.selectionStroke.nsColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.stroke(rect)
        ctx.setLineDash(phase: 0, lengths: [])

        // Semi-transparent fill from the theme's selectionFill.
        ctx.setFillColor(theme.selectionFill.nsColor.cgColor)
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

    static func editableFieldTabOrder(in document: HypeDocument, currentCardId: UUID) -> [Part] {
        document.effectivePartsForCard(currentCardId)
            .filter {
                $0.partType == .field
                    && $0.visible
                    && $0.enabled
                    && !$0.lockText
            }
            .sorted { lhs, rhs in
                if abs(lhs.top - rhs.top) > 6 {
                    return lhs.top < rhs.top
                }
                if abs(lhs.left - rhs.left) > 2 {
                    return lhs.left < rhs.left
                }
                if lhs.sortKey != rhs.sortKey {
                    return lhs.sortKey < rhs.sortKey
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    @discardableResult
    private func focusFirstEditableField(reverse: Bool = false) -> Bool {
        let fields = Self.editableFieldTabOrder(in: document, currentCardId: currentCardId)
        guard let part = reverse ? fields.last : fields.first else { return false }
        startFieldEditing(part: part, selectText: true)
        return true
    }

    @discardableResult
    private func moveFieldEditingFocus(reverse: Bool) -> Bool {
        guard let activeFieldPartId else { return false }
        let fields = Self.editableFieldTabOrder(in: document, currentCardId: currentCardId)
        guard !fields.isEmpty else { return false }

        let nextPart: Part
        if let currentIndex = fields.firstIndex(where: { $0.id == activeFieldPartId }) {
            guard fields.count > 1 else { return true }
            let nextIndex = reverse
                ? (currentIndex - 1 + fields.count) % fields.count
                : (currentIndex + 1) % fields.count
            nextPart = fields[nextIndex]
        } else {
            nextPart = reverse ? fields[fields.count - 1] : fields[0]
        }

        endFieldEditing()
        startFieldEditing(part: nextPart, selectText: true)
        return true
    }

    private func startFieldEditing(part: Part, selectText: Bool = false) {
        // Don't edit if locked
        guard part.partType == .field && !part.lockText else { return }

        // Remove existing editor
        endFieldEditing()

        // Store original text for closeField vs exitField determination
        originalFieldText = part.textContent

        // Dispatch openField lifecycle message
        coordinator?.dispatchMessage("openField", to: part.id)

        // Create the text field overlay, matching the part's position and style exactly.
        //
        // The frame is the FULL part rect; the custom cell
        // (`HypeFieldEditorCell`) handles the inner padding so the
        // editor's text rect matches `FieldRenderer`'s
        // `rect.insetBy(dx: padding, dy: padding)` exactly. Without
        // the custom cell, characters jumped 2-6pt when entering
        // edit mode (NSTextField's default ~2pt cell inset + 5pt
        // lineFragmentPadding + vertical centering).
        let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
        let textField = NSTextField(frame: frame)

        // Swap in our custom cell BEFORE setting any cell-derived
        // properties (font, alignment, etc.) — those flow onto the
        // current cell, and replacing the cell after would lose them.
        let cell = HypeFieldEditorCell(textCell: "")
        cell.hypePadding = part.wideMargins ? 8 : 4
        cell.rightScrollbarReserve = part.fieldStyle == .scrolling ? 16 : 0
        // Top-align (no vertical centering). NSTextField centers
        // single-line text vertically when `wraps == false`; we set
        // wraps=true so the layout matches FieldRenderer regardless
        // of `dontWrap` (we control wrap behavior via lineBreakMode
        // separately).
        cell.wraps = true
        cell.isScrollable = true
        cell.lineBreakMode = part.dontWrap ? .byClipping : .byWordWrapping
        cell.usesSingleLineMode = false
        textField.cell = cell

        textField.stringValue = part.textContent
        textField.font = NSFont(name: part.textFont, size: CGFloat(part.textSize)) ?? NSFont.systemFont(ofSize: CGFloat(part.textSize))
        textField.textColor = .black
        textField.isBordered = false
        textField.drawsBackground = part.fieldStyle != .transparent
        textField.backgroundColor = nsColorFromHex(part.fillColor)
        textField.focusRingType = .exterior
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self
        textField.alignment = part.textAlign == .center ? .center : part.textAlign == .right ? .right : .left
        textField.wantsLayer = true
        textField.layer?.borderColor = nsColorFromHex(part.strokeColor).cgColor
        textField.layer?.borderWidth = max(0, CGFloat(part.strokeWidth))
        textField.layer?.backgroundColor = (part.fieldStyle == .transparent ? NSColor.clear : nsColorFromHex(part.fillColor)).cgColor
        textField.layer?.zPosition = 1000  // Ensure it's above all canvas drawing

        addSubview(textField, positioned: .above, relativeTo: nil)
        needsDisplay = true  // Redraw canvas to hide the underlying part

        // Delay makeFirstResponder to ensure the text field is fully in the view hierarchy
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(textField)
            if selectText {
                textField.selectText(nil)
            }
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

    /// True if the given script source declares `on idle`.
    ///
    /// Accepts `on idle` at the start of any line (ignoring leading
    /// whitespace). Stricter than `.contains("on idle")`, which would
    /// false-positive on comments like `-- on idle does X` and on
    /// handlers whose names happen to start with "idle" (e.g.
    /// `on idleState`), wastefully dispatching idle to parts that
    /// have no actual idle handler.
    private static func scriptHasIdleHandler(_ script: String) -> Bool {
        guard !script.isEmpty else { return false }
        for rawLine in script.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            if line.hasPrefix("on idle") {
                // Next char after "on idle" must be whitespace or
                // end-of-line — so "on idleState" doesn't count.
                let afterIdle = line.dropFirst("on idle".count)
                if afterIdle.isEmpty || afterIdle.first?.isWhitespace == true {
                    return true
                }
            }
        }
        return false
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let toolState = ToolState(currentTool: self.currentTool.rawValue)
            guard toolState.category == .browse, self.activeFieldEditor == nil else { return }

            let cardParts = self.document.partsForCard(self.currentCardId)
            let card = self.document.cards.first(where: { $0.id == self.currentCardId })
            let bgParts = card.map { self.document.partsForBackground($0.backgroundId) } ?? []
            let idlePartIDs = (cardParts + bgParts)
                .filter { CardCanvasNSView.scriptHasIdleHandler($0.script) }
                .map(\.id)
            self.coordinator?.dispatchIdleBurst(cardTargetId: self.currentCardId, partTargetIds: idlePartIDs)
        }
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - Card-Level SpriteKit Transition

    /// Lazily create the card-level SKView used for transitions.
    private func ensureCardSKView() {
        guard cardSKView == nil else { return }
        let skView = PassthroughSKView(frame: bounds)
        skView.allowsTransparency = false
        skView.autoresizingMask = [.width, .height]
        skView.isHidden = true
        addSubview(skView, positioned: .above, relativeTo: nil)
        self.cardSKView = skView
    }

    /// Default transition duration when none is specified in the script.
    static let defaultTransitionDuration: TimeInterval = 1.0

    /// Hide all embedded NSView subviews (web views, video
    /// players, chart hosting views, and sprite area SKViews)
    /// so they don't float on top of the SpriteKit card
    /// transition. Called after capturing the current card's
    /// bitmap but before the transition animation starts.
    /// The subviews are recreated by updateNSView → draw()
    /// after the transition completes.
    private func hideAllEmbeddedSubviews() {
        for (_, wv) in webViews { wv.isHidden = true }
        for (_, vp) in videoPlayers { vp.isHidden = true }
        for (_, cv) in chartViews { cv.isHidden = true }
        for (_, sv) in spriteViews { sv.isHidden = true }
    }

    /// Perform a card transition using SpriteKit.
    ///
    /// Captures the current card as a texture, presents it in an SKView,
    /// transitions to the new card's texture, then hides the SKView so
    /// normal CGContext rendering resumes.
    ///
    /// `duration` overrides the default transition length (1.0s) when the
    /// user writes `visual effect dissolve 2` in a script.
    func performCardTransition(to newCardId: UUID, effect: HypeCore.VisualEffect, duration: TimeInterval? = nil) {
        guard effect != .none else {
            HypeLogger.shared.debug("Transition skipped: effect is .none", source: "Transition")
            return
        }
        ensureCardSKView()
        guard let skView = cardSKView else {
            HypeLogger.shared.error("Transition failed: cardSKView is nil", source: "Transition")
            return
        }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            HypeLogger.shared.error("Transition failed: bounds are zero", source: "Transition")
            return
        }

        let dur = duration ?? Self.defaultTransitionDuration
        HypeLogger.shared.info("Starting \(effect) transition, duration=\(dur)s, size=\(Int(size.width))×\(Int(size.height))", source: "Transition")

        isTransitioning = true

        // Render the current card as a texture BEFORE hiding
        // embedded subviews — renderToImage only captures the
        // CGContext-drawn content (buttons, fields, shapes, text),
        // not the NSView overlays. The texture is a complete-enough
        // representation of the card for the transition.
        let currentImage = renderer.renderToImage(document: document, cardId: currentCardId, size: size)
        HypeLogger.shared.debug("Current card rendered: \(Int(currentImage.size.width))×\(Int(currentImage.size.height))", source: "Transition")

        // Hide all embedded NSView subviews (charts, sprite
        // SKViews, video players, web views) so they don't float
        // on top of the SpriteKit transition animation. Without
        // this, these views remain visible in their old-card
        // positions while the transition texture slides/fades
        // underneath them — the "floating controls" bug.
        hideAllEmbeddedSubviews()
        HypeLogger.shared.debug("Embedded subviews hidden", source: "Transition")

        skView.isHidden = false
        skView.frame = bounds
        skView.isPaused = false

        HypeLogger.shared.debug("SKView frame=\(skView.frame), superview=\(skView.superview != nil), window=\(skView.window != nil)", source: "Transition")

        let currentScene = CardSKScene(cardSize: size)
        currentScene.updateCardTexture(currentImage)
        skView.presentScene(currentScene)
        HypeLogger.shared.debug("Presented currentScene, skView.scene=\(skView.scene != nil)", source: "Transition")

        // Pre-render the new card texture
        let newImage = renderer.renderToImage(document: document, cardId: newCardId, size: size)
        HypeLogger.shared.debug("New card rendered: \(Int(newImage.size.width))×\(Int(newImage.size.height))", source: "Transition")

        let newScene = CardSKScene(cardSize: size)
        newScene.updateCardTexture(newImage)
        let transition = Self.skTransition(for: effect, duration: dur)

        // Delay the transition presentation so currentScene renders at least one frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak skView] in
            guard let self = self, let skView = skView else {
                HypeLogger.shared.error("Transition delayed block: weak refs gone", source: "Transition")
                return
            }
            HypeLogger.shared.info("Presenting transition now: skView.hidden=\(skView.isHidden), scene=\(skView.scene != nil)", source: "Transition")
            skView.presentScene(newScene, transition: transition)
        }

        // Cleanup after transition
        DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.2) { [weak self] in
            HypeLogger.shared.info("Transition complete — hiding SKView, resuming draw()", source: "Transition")
            self?.isTransitioning = false
            self?.cardSKView?.isHidden = true
            self?.cardScene = nil
            self?.needsDisplay = true
        }
    }

    /// Convert a HyperCard-style VisualEffect into an SKTransition.
    private static func skTransition(for effect: HypeCore.VisualEffect, duration: TimeInterval) -> SKTransition {
        switch effect {
        case .dissolve:
            return SKTransition.crossFade(withDuration: duration)
        case .wipeLeft:
            return SKTransition.push(with: .left, duration: duration)
        case .wipeRight:
            return SKTransition.push(with: .right, duration: duration)
        case .wipeUp:
            return SKTransition.push(with: .up, duration: duration)
        case .wipeDown:
            return SKTransition.push(with: .down, duration: duration)
        case .irisOpen:
            return SKTransition.doorway(withDuration: duration)
        case .irisClose:
            return SKTransition.doorway(withDuration: duration)
        case .scrollLeft:
            return SKTransition.moveIn(with: .left, duration: duration)
        case .scrollRight:
            return SKTransition.moveIn(with: .right, duration: duration)
        case .none:
            return SKTransition.crossFade(withDuration: 0)
        }
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

        // Dispatch mouseWithin (throttled to every 100ms) with mouse coordinates
        if let partId = hoveredPartId, Date().timeIntervalSince(lastMouseWithinTime) > 0.1 {
            lastMouseWithinTime = Date()
            let toolState = ToolState(currentTool: currentTool.rawValue)
            if toolState.category == .browse {
                coordinator?.dispatchMessage("mouseWithin", to: partId,
                                             mouseX: Double(point.x), mouseY: Double(point.y))
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
                let pl = paintLayerForCurrentCard()
                pl.drawCircle(cx: x, cy: y, radius: pencilRadius, color: paintColor)
                lastPencilPoint = point
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

        // Cmd+click in browse mode: open script editor for the
        // topmost part under the cursor, regardless of editing
        // mode. Uses rawHitPart (not the editing-mode-filtered
        // hitPart) so background parts are reachable even when
        // not in background-edit mode. If no part is hit, opens
        // the card's script editor.
        if toolCheck.category == .browse && event.modifierFlags.contains(.command) {
            if let part = rawHitPart {
                NotificationCenter.default.post(
                    name: .openPartScriptEditor,
                    object: nil,
                    userInfo: ["partId": part.id]
                )
            } else {
                NotificationCenter.default.post(
                    name: .openPartScriptEditor,
                    object: nil,
                    userInfo: ["cardId": currentCardId]
                )
            }
            return
        }

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
            // Auto-hilite for buttons whose `autoHilite` flag is on:
            // toggle hilite=true while the mouse is held so the
            // renderer can paint the "pressed" state (e.g. shadow-
            // style buttons snap their drop-shadow to the opposite
            // corner). Stable-toggle styles (checkBox, toggle) are
            // handled in mouseUp instead — they want a sticky
            // hilite, not a transient one.
            if let part = document.parts.first(where: { $0.id == partId }),
               part.partType == .button,
               part.autoHilite,
               part.buttonStyle != .checkBox,
               part.buttonStyle != .toggle {
                coordinator?.setPartHilite(id: partId, to: true)
                pressedButtonId = partId
                needsDisplay = true
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
                if let last = lastPencilPoint {
                    let pl = paintLayerForCurrentCard()
                    pl.drawThickLine(x0: Int(last.x), y0: Int(last.y), x1: x, y1: y, radius: pencilRadius, color: paintColor)
                }
                lastPencilPoint = point
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
                        // Theme-aware defaults: pull stroke + fill
                        // from the active theme so newly drawn shapes
                        // visibly match the cardstack's chosen look.
                        // The cascade-resolver always returns a theme.
                        let rectTheme = document.effectiveTheme(forCard: currentCardId)
                        newPart.strokeColor = rectTheme.shapeStrokeDefault.rawDescription.hasPrefix("#")
                            ? rectTheme.shapeStrokeDefault.rawDescription : "#000000"
                        newPart.fillColor = rectTheme.shapeFillDefault.rawDescription.hasPrefix("#")
                            ? rectTheme.shapeFillDefault.rawDescription : "#FFFFFF"
                        newPart.strokeWidth = max(1.0, rectTheme.strokeWidthThin)
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
                        let ovalTheme = document.effectiveTheme(forCard: currentCardId)
                        newPart.strokeColor = ovalTheme.shapeStrokeDefault.rawDescription.hasPrefix("#")
                            ? ovalTheme.shapeStrokeDefault.rawDescription : "#000000"
                        newPart.fillColor = ovalTheme.shapeFillDefault.rawDescription.hasPrefix("#")
                            ? ovalTheme.shapeFillDefault.rawDescription : "#FFFFFF"
                        newPart.strokeWidth = max(1.0, ovalTheme.strokeWidthThin)
                        coordinator?.addPart(newPart)
                    }

                case .pencil:
                    // Pencil draws to PaintLayer bitmap — no Part created
                    lastPencilPoint = nil

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
                    newField.strokeWidth = 0
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

            // Cmd+click is handled in mouseDown (line 1340) so it
            // responds immediately. Skip all mouseUp processing
            // when Cmd is held to avoid double-opening the editor
            // or dispatching mouseUp to the part.
            if event.modifierFlags.contains(.command) {
                // Even on a Cmd+click skip, release any transient
                // press state so a stuck pressed-button doesn't
                // outlive the mouseDown.
                if let pressedId = pressedButtonId {
                    coordinator?.setPartHilite(id: pressedId, to: false)
                    pressedButtonId = nil
                    needsDisplay = true
                }
                return
            }

            if let part = hitPart {
                // Handle image invert-on-click
                if part.partType == .image && part.invertOnClick {
                    coordinator?.togglePartHilite(id: part.id)
                }
                // Auto-hilite for buttons: checkboxes and toggles toggle on click
                if part.partType == .button {
                    switch part.buttonStyle {
                    case .checkBox, .toggle:
                        coordinator?.togglePartHilite(id: part.id)
                    default:
                        break
                    }
                }
                coordinator?.dispatchMessage("mouseUp", to: part.id)
            }
            // Release the transient mouseDown hilite for any
            // autoHilite button that got pressed (whether the user
            // released INSIDE the button or dragged off — either
            // way the visual press state ends here).
            if let pressedId = pressedButtonId {
                coordinator?.setPartHilite(id: pressedId, to: false)
                pressedButtonId = nil
                needsDisplay = true
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
            // Set default SceneSpec for new spriteArea parts
            if partType == .spriteArea {
                let defaultAreaSpec = SpriteAreaSpec(
                    defaultSceneNamed: "main",
                    fallbackSize: SizeSpec(width: Double(newPart.width), height: Double(newPart.height))
                )
                newPart.setSpriteAreaSpec(defaultAreaSpec)
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

    // MARK: - Sprite View Management

    /// Create, update, or remove SKViews for spriteArea parts on the current card.
    private func updateSpriteViews() {
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
        let spriteParts = allParts.filter { $0.partType == .spriteArea && $0.visible }

        // In edit mode or no sprite parts, remove all SKViews (show placeholder only)
        if !isBrowseMode || spriteParts.isEmpty {
            // Dispatch closeScene for all active sprite scenes before removing
            for id in spriteViews.keys {
                if let sceneId = loadedActiveSceneIDs[id],
                   let payload = spriteDispatchContext(for: id, sceneId: sceneId) {
                    coordinator?.dispatchMessage(
                        "closeScene",
                        to: payload.targetId,
                        params: [],
                        scriptContext: payload.context
                    )
                } else {
                    coordinator?.dispatchMessage("closeScene", to: id)
                }
            }
            for (_, sv) in spriteViews {
                sv.removeFromSuperview()
            }
            spriteViews.removeAll()
            spriteScenes.removeAll()
            spriteBridges.removeAll()
            loadedSceneSpecs.removeAll()
            loadedActiveSceneIDs.removeAll()
            return
        }

        // Track which parts are still active
        var activeIds = Set<UUID>()

        for part in spriteParts {
            activeIds.insert(part.id)

            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existingSKView = spriteViews[part.id] {
                // Update position/size
                existingSKView.frame = frame
                // Defensive un-hide: hideAllEmbeddedSubviews() (called
                // during card-level SpriteKit transitions) sets
                // `isHidden = true` on every embedded SKView so it
                // doesn't float over the transition. After the
                // transition completes we just call needsDisplay,
                // which routes back through here — but for a sprite
                // area shared via a background, the same SKView
                // instance survives the transition and would stay
                // hidden without this. New-SKView creation defaults
                // to visible so it doesn't need this.
                existingSKView.isHidden = false
                // Sync transparency flags every pass so toggling
                // `Part.transparentBackground` at runtime (via the
                // inspector toggle, HypeTalk, or AI) takes effect
                // on the existing SKView without a scene rebuild.
                applyTransparency(part: part, to: existingSKView)

                // Only update scene if the sceneSpec JSON changed
                if loadedSceneSpecs[part.id] != part.sceneSpec {
                    let currentSceneId = part.activeSceneID
                    let previousSceneId = loadedActiveSceneIDs[part.id]
                    if let previousSceneId,
                       let currentSceneId,
                       previousSceneId != currentSceneId,
                       let payload = spriteDispatchContext(for: part.id, sceneId: previousSceneId) {
                        coordinator?.dispatchMessage(
                            "closeScene",
                            to: payload.targetId,
                            params: [],
                            scriptContext: payload.context
                        )
                    }
                    // Try live update first (no rebuild needed for property-only changes)
                    if let bridge = spriteBridges[part.id],
                       let scene = spriteScenes[part.id],
                       let spec = part.activeSceneSpec {
                        let needsRebuild = bridge.applyLiveUpdates(spec: spec, to: scene, repository: document.spriteRepository)
                        if needsRebuild {
                            rebuildSpriteScene(for: part, in: existingSKView)
                        } else {
                            // applyLiveUpdates writes scene.backgroundColor
                            // from spec on every call — re-apply
                            // transparency so a sceneSpec edit (or any
                            // path that triggers live update) on a
                            // transparent sprite area doesn't flip the
                            // scene back to opaque on the next frame.
                            applyTransparency(part: part, to: existingSKView)
                            loadedActiveSceneIDs[part.id] = currentSceneId
                        }
                        loadedSceneSpecs[part.id] = part.sceneSpec
                        if let previousSceneId,
                           let currentSceneId,
                           previousSceneId != currentSceneId {
                            dispatchSpriteLifecycleMessages(partId: part.id, sceneId: currentSceneId)
                        }
                    } else {
                        rebuildSpriteScene(for: part, in: existingSKView)
                    }
                }
            } else {
                // Create new SKView
                let skView = SKView(frame: frame)
                skView.ignoresSiblingOrder = false
                // Honor Part.transparentBackground: when true, the
                // SKView composites against the underlying card so a
                // bg-image part beneath shows through. When false,
                // the scene's solid backgroundColor paints over
                // anything beneath. Helper sets matching flags on
                // both the SKView (allowsTransparency, isOpaque)
                // and the live SKScene (backgroundColor).
                applyTransparency(part: part, to: skView)

                // Add tracking area for mouse moved events within the SKView
                let trackingArea = NSTrackingArea(
                    rect: skView.bounds,
                    options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                    owner: skView,
                    userInfo: nil
                )
                skView.addTrackingArea(trackingArea)

                addSubview(skView, positioned: .above, relativeTo: nil)
                spriteViews[part.id] = skView

                rebuildSpriteScene(for: part, in: skView)
            }
        }

        // Remove SKViews for parts that no longer exist
        for id in spriteViews.keys where !activeIds.contains(id) {
            if let sceneId = loadedActiveSceneIDs[id],
               let payload = spriteDispatchContext(for: id, sceneId: sceneId) {
                coordinator?.dispatchMessage(
                    "closeScene",
                    to: payload.targetId,
                    params: [],
                    scriptContext: payload.context
                )
            } else {
                coordinator?.dispatchMessage("closeScene", to: id)
            }
            spriteViews[id]?.removeFromSuperview()
            spriteViews.removeValue(forKey: id)
            spriteScenes.removeValue(forKey: id)
            spriteBridges.removeValue(forKey: id)
            loadedSceneSpecs.removeValue(forKey: id)
            lastSceneMousePosition.removeValue(forKey: id)
            loadedActiveSceneIDs.removeValue(forKey: id)
        }
    }

    /// Parse the sceneSpec and present a new HypeSKScene in the given SKView.
    /// Apply `Part.transparentBackground` to a sprite-area's
    /// SKView and its currently-presented SKScene.
    ///
    /// When `true`:
    /// - `SKView.allowsTransparency = true` so the view's drawable
    ///   composites with a non-opaque clear color
    /// - `SKScene.backgroundColor = .clear` so the scene's per-
    ///   frame clear no longer paints over what's beneath
    ///
    /// When `false` (default), restore the spec's backgroundColor
    /// so the user-authored color is honored (e.g. Sunset's beige
    /// game card stays beige when transparency is off).
    ///
    /// Note: NSView's `isOpaque` is a read-only computed property
    /// in Swift (it reflects whether the view fully covers its
    /// rect), so we don't set it here — the `allowsTransparency`
    /// flag plus a clear scene bg is sufficient for SKView to
    /// composite correctly against the underlying card content.
    private func applyTransparency(part: Part, to skView: SKView) {
        let transparent = part.transparentBackground
        skView.allowsTransparency = transparent
        if let scene = skView.scene {
            if transparent {
                scene.backgroundColor = .clear
            } else if let spec = part.activeSceneSpec {
                scene.backgroundColor = NSColor(hexString: spec.backgroundColor)
                    ?? .darkGray
            }
        }
    }

    private func rebuildSpriteScene(for part: Part, in skView: SKView) {
        guard let areaSpec = part.spriteAreaSpecModel,
              let sceneEntry = areaSpec.activeSceneEntry,
              let spec = areaSpec.activeScene else {
            // No valid scene — present an empty scene
            let emptyScene = SKScene(size: CGSize(width: part.width, height: part.height))
            emptyScene.backgroundColor = part.transparentBackground ? .clear : .darkGray
            skView.allowsTransparency = part.transparentBackground
            skView.presentScene(emptyScene)
            loadedSceneSpecs[part.id] = part.sceneSpec
            return
        }

        let sceneSize = CGSize(width: spec.size.width, height: spec.size.height)
        let bridge = SceneBridge(sceneHeight: spec.size.height)
        bridge.eventDelegate = self
        let scene = HypeSKScene(size: sceneSize, sceneHeight: spec.size.height)
        scene.registry = bridge.registry
        scene.eventDelegate = self

        // Configure debug overlays
        skView.showsFPS = spec.showsFPS
        skView.showsNodeCount = spec.showsNodeCount
        skView.showsPhysics = spec.showsPhysics

        // Store references BEFORE presenting — didMove(to:) fires during presentScene()
        // and the SpriteEventDelegate needs spriteScenes[partId] to resolve events
        spriteScenes[part.id] = scene
        spriteBridges[part.id] = bridge
        loadedActiveSceneIDs[part.id] = sceneEntry.id

        // Build the scene from spec
        let repository = document.spriteRepository
        bridge.apply(spec: spec, to: scene, repository: repository)

        // Apply transparency BEFORE presentScene so the very first
        // frame painted by SpriteKit already has the correct clear
        // backgroundColor — otherwise on card-return we briefly
        // (and sometimes persistently, depending on render timing)
        // see the spec's solid color paint over the underlying
        // card. `bridge.apply` just set scene.backgroundColor from
        // the spec; if the part is transparent we override to
        // `.clear` here. We also set `skView.allowsTransparency`
        // here directly since `applyTransparency`'s scene-level
        // override only fires when `skView.scene` is non-nil and
        // we haven't called presentScene yet.
        if part.transparentBackground {
            scene.backgroundColor = .clear
            skView.allowsTransparency = true
        } else {
            skView.allowsTransparency = false
        }

        // Present the scene
        skView.presentScene(scene)

        // Belt-and-suspenders: re-run the helper after presentScene
        // so any code path that mutates scene.backgroundColor
        // between the override above and the first frame (e.g. a
        // didMove that resets the clear color) is corrected on the
        // very next runloop tick.
        applyTransparency(part: part, to: skView)

        loadedSceneSpecs[part.id] = part.sceneSpec

        // Dispatch lifecycle events after a short delay — must be outside the draw() cycle
        // to avoid re-entrant document mutations during rendering
        let partId = part.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            guard self.spriteScenes[partId] != nil else { return }  // scene still exists
            self.dispatchSpriteLifecycleMessages(partId: partId, sceneId: sceneEntry.id)
        }
    }

    private func spriteDispatchContext(
        for partId: UUID,
        sceneId: UUID? = nil,
        nodeId: UUID? = nil
    ) -> (targetId: UUID, context: ScriptDispatchContext)? {
        guard let part = document.parts.first(where: { $0.id == partId }),
              let areaSpec = part.spriteAreaSpecModel else {
            return nil
        }
        let resolvedSceneId = sceneId ?? areaSpec.activeSceneEntry?.id
        guard let resolvedSceneId,
              let scene = areaSpec.scene(id: resolvedSceneId) else {
            return nil
        }

        var hierarchyPrefix: [UUID] = []
        var objectScripts: [UUID: String] = [:]
        var objectDescriptions: [UUID: String] = [:]

        if let nodeId {
            let path = scene.ancestorPath(for: nodeId)
            if !path.isEmpty {
                for node in path {
                    hierarchyPrefix.append(node.id)
                    objectScripts[node.id] = node.script
                    objectDescriptions[node.id] = "\(node.nodeType.rawValue) \"\(node.name)\""
                }
            }
        }

        hierarchyPrefix.append(resolvedSceneId)
        objectScripts[resolvedSceneId] = scene.script
        objectDescriptions[resolvedSceneId] = "scene \"\(scene.name)\""
        hierarchyPrefix.append(part.id)

        let targetId = hierarchyPrefix.first ?? resolvedSceneId
        let context = ScriptDispatchContext(
            hierarchyPrefix: hierarchyPrefix,
            objectScripts: objectScripts,
            objectDescriptions: objectDescriptions
        )
        return (targetId, context)
    }

    private func dispatchSpriteLifecycleMessages(partId: UUID, sceneId: UUID) {
        guard let payload = spriteDispatchContext(for: partId, sceneId: sceneId) else {
            coordinator?.dispatchMessage("sceneDidLoad", to: partId)
            coordinator?.dispatchMessage("openScene", to: partId)
            return
        }
        coordinator?.dispatchMessage(
            "sceneDidLoad",
            to: payload.targetId,
            params: [],
            scriptContext: payload.context
        )
        coordinator?.dispatchMessage(
            "openScene",
            to: payload.targetId,
            params: [],
            scriptContext: payload.context
        )
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
    func paintLayerForCurrentCard() -> PaintLayer {
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

        // Use the actual view bounds so constraints target the
        // live window edges, not the fixed stack model dimensions.
        // The stack width/height is a minimum content area, not a
        // hard boundary — parts and constraints should be able to
        // reach the full window extent.
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
        guard let field = obj.object as? NSTextField,
              field === activeFieldEditor else { return }
        endFieldEditing()
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertTab(_:)) {
            needsDisplay = true
            return moveFieldEditingFocus(reverse: false)
        }
        if commandSelector == #selector(insertBacktab(_:)) {
            needsDisplay = true
            return moveFieldEditingFocus(reverse: true)
        }
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
                originalFieldText = nil
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
            originalFieldText = nil
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

// MARK: - SpriteEventDelegate (SpriteKit event forwarding)

extension CardCanvasNSView: SpriteEventDelegate {
    func spriteScene(_ scene: HypeSKScene, didReceiveEvent event: SpriteEvent) {
        // Find the spriteArea part ID that owns this scene
        guard let partId = spriteScenes.first(where: { $0.value === scene })?.key else { return }

        // Record scene-local mouse position for any pointer-carrying
        // event. The stored position backs `the mouseLoc` during the
        // frameUpdate dispatch below (and any other handler that needs
        // to read the cursor without a fresh mouse event).
        switch event {
        case .mouseDown(_, let pos),
             .mouseUp(_, let pos),
             .mouseDragged(_, let pos),
             .mouseWithin(_, let pos):
            lastSceneMousePosition[partId] = pos
        default:
            break
        }

        switch event {
        case .mouseDown(let nodeId, let pos):
            if let payload = spriteDispatchContext(for: partId, nodeId: nodeId) {
                coordinator?.dispatchMessage("mouseDown", to: payload.targetId, params: [], mouseX: pos.x, mouseY: pos.y, scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("mouseDown", to: partId, mouseX: pos.x, mouseY: pos.y)
            }
        case .mouseUp(let nodeId, let pos):
            if let payload = spriteDispatchContext(for: partId, nodeId: nodeId) {
                coordinator?.dispatchMessage("mouseUp", to: payload.targetId, params: [], mouseX: pos.x, mouseY: pos.y, scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("mouseUp", to: partId, mouseX: pos.x, mouseY: pos.y)
            }
        case .mouseDragged(let nodeId, let pos):
            if let payload = spriteDispatchContext(for: partId, nodeId: nodeId) {
                coordinator?.dispatchMessage("mouseDragged", to: payload.targetId, params: [], mouseX: pos.x, mouseY: pos.y, scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("mouseDragged", to: partId, mouseX: pos.x, mouseY: pos.y)
            }
        case .mouseWithin(let nodeId, let pos):
            // Publish the hovered-sprite name so scripts can check
            // `the hoveredSprite is "blue_ball"` without having to
            // write a hit-test loop themselves. When the cursor is
            // over the scene background (nodeId == nil) or over a
            // node with no name, the published name is "".
            if let nodeId,
               let part = document.parts.first(where: { $0.id == partId }),
               let scene = part.activeSceneSpec,
               let node = scene.node(id: nodeId) {
                SpriteSceneMouseState.shared.hoveredSprite = node.name
            } else {
                SpriteSceneMouseState.shared.hoveredSprite = ""
            }
            if let payload = spriteDispatchContext(for: partId, nodeId: nodeId) {
                coordinator?.dispatchMessage("mouseWithin", to: payload.targetId, params: [], mouseX: pos.x, mouseY: pos.y, scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("mouseWithin", to: partId, mouseX: pos.x, mouseY: pos.y)
            }
        case .keyDown(let characters, _):
            if let payload = spriteDispatchContext(for: partId) {
                coordinator?.dispatchMessage("keyDown", to: payload.targetId, params: [characters], scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("keyDown", to: partId, params: [characters])
            }
            if !characters.isEmpty {
                coordinator?.dispatchMessageToCard("keyDown")
            }
        case .keyUp(_, _):
            if let payload = spriteDispatchContext(for: partId) {
                coordinator?.dispatchMessage("keyUp", to: payload.targetId, params: [], scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("keyUp", to: partId)
            }
        case .contactBegan(let nodeA, let nodeB):
            let nodeNames: [UUID: String] = {
                guard let part = document.parts.first(where: { $0.id == partId }),
                      let scene = part.activeSceneSpec else { return [:] }
                return [
                    nodeA: scene.node(id: nodeA)?.name ?? "",
                    nodeB: scene.node(id: nodeB)?.name ?? "",
                ]
            }()
            if let payload = spriteDispatchContext(for: partId, nodeId: nodeA) {
                coordinator?.dispatchMessage("beginContact", to: payload.targetId, params: [nodeNames[nodeB] ?? ""], scriptContext: payload.context)
            }
            if nodeB != nodeA, let payload = spriteDispatchContext(for: partId, nodeId: nodeB) {
                coordinator?.dispatchMessage("beginContact", to: payload.targetId, params: [nodeNames[nodeA] ?? ""], scriptContext: payload.context)
            }
        case .contactEnded(let nodeA, let nodeB):
            let nodeNames: [UUID: String] = {
                guard let part = document.parts.first(where: { $0.id == partId }),
                      let scene = part.activeSceneSpec else { return [:] }
                return [
                    nodeA: scene.node(id: nodeA)?.name ?? "",
                    nodeB: scene.node(id: nodeB)?.name ?? "",
                ]
            }()
            if let payload = spriteDispatchContext(for: partId, nodeId: nodeA) {
                coordinator?.dispatchMessage("endContact", to: payload.targetId, params: [nodeNames[nodeB] ?? ""], scriptContext: payload.context)
            }
            if nodeB != nodeA, let payload = spriteDispatchContext(for: partId, nodeId: nodeB) {
                coordinator?.dispatchMessage("endContact", to: payload.targetId, params: [nodeNames[nodeA] ?? ""], scriptContext: payload.context)
            }
        case .frameUpdate(let deltaTime):
            // Plumb the last-known mouse position so `the mouseLoc` /
            // `the mouseH` / `the mouseV` return real cursor coords
            // inside `on frameUpdate` handlers. Without this the
            // dispatch defaults to (0, 0) and scripts that compute
            // cursor-vs-sprite distance every frame silently compare
            // against the scene origin — e.g. the AI-generated
            // "accelerate the ball when the cursor touches it"
            // pattern appeared completely dead because the condition
            // `sqrt(dx*dx + dy*dy) < 20` measured the distance from
            // the ball to (0,0), not to the cursor.
            let mousePos = lastSceneMousePosition[partId]
            let mouseX = mousePos?.x ?? 0
            let mouseY = mousePos?.y ?? 0
            if let payload = spriteDispatchContext(for: partId) {
                coordinator?.dispatchMessage("frameUpdate", to: payload.targetId, params: [String(deltaTime)], mouseX: mouseX, mouseY: mouseY, scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("frameUpdate", to: partId, params: [String(deltaTime)], mouseX: mouseX, mouseY: mouseY)
            }
        case .sceneDidLoad:
            // Lifecycle events are now dispatched directly from rebuildSpriteScene()
            // This case is kept for completeness but should not fire in normal flow
            if let sceneId = loadedActiveSceneIDs[partId] {
                dispatchSpriteLifecycleMessages(partId: partId, sceneId: sceneId)
            } else {
                coordinator?.dispatchMessage("sceneDidLoad", to: partId)
                coordinator?.dispatchMessage("openScene", to: partId)
            }
        case .actionFinished(let name, let nodeId):
            if let payload = spriteDispatchContext(for: partId, nodeId: nodeId) {
                coordinator?.dispatchMessage("actionFinished", to: payload.targetId, params: [name], scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("actionFinished", to: partId, params: [name])
            }
        }
    }
}
