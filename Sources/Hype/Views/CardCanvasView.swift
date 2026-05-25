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

private final class AccessibilityHitTestResult: @unchecked Sendable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}

/// AppKit-based dialog provider that shows real NSAlert/NSTextField dialogs.
final class AppKitDialogProvider: DialogProvider, @unchecked Sendable {
    func showAnswer(prompt: String) -> String {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return "OK"
        }
    }

    func showAsk(prompt: String) -> String {
        MainActor.assumeIsolated {
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
}
/// Drawing provider that draws to a PaintLayer from script commands.
final class PaintLayerDrawingProvider: DrawingProvider, @unchecked Sendable {
    private let paintLayer: PaintLayer
    private let onChange: () -> Void

    init(paintLayer: PaintLayer, onChange: @escaping () -> Void = {}) {
        self.paintLayer = paintLayer
        self.onChange = onChange
    }

    func drawLine(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String) {
        let color = nsColorFromHex(colorHex)
        paintLayer.drawThickLine(x0: from.0, y0: from.1, x1: to.0, y1: to.1, radius: radius, color: color)
        onChange()
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
        // Layer-backing + .onSetNeedsDisplay redraw policy. Both are
        // mandatory; see `configureForCardCanvasRendering` doc comment
        // for the failure modes if either is missing. Centralised on
        // the view itself so the regression test exercises the exact
        // same code path production uses.
        view.configureForCardCanvasRendering()
        view.document = document.document
        view.currentCardId = currentCardId
        view.currentTool = currentTool
        view.selectedPartIds = selectedPartIds
        view.editingBackground = editingBackground
        view.coordinator = context.coordinator
        context.coordinator.nsView = view

        view.installRuntimeAnimatorCallbacks()

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
        context.coordinator.nsView = nsView
        nsView.installRuntimeAnimatorCallbacks()
        nsView.updateCursor()
        // Reconcile map-part `mapLocation` changes through the
        // shared geocoder. This runs in BOTH browse and edit mode
        // (the inspector lives in either), so any path that mutates
        // `mapLocation` triggers the resolve and writes back coords
        // — fixing the prior bug where setting Location twice in
        // edit mode never moved the map (the live MapKit host that
        // used to own the geocode logic is destroyed in edit mode).
        context.coordinator.reconcileMapLocations()
        nsView.refreshAccessibilityTreeIfNeeded()
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

        /// Per-part snapshot of `mapLocation` from the last
        /// updateNSView pass. We compare incoming `mapLocation`
        /// values to these to detect changes from any source —
        /// inspector typing, HypeTalk `set the location of map "X"
        /// to "..."`, AI `set_part_property property=location`,
        /// or `create_map`'s initial seed — and route them through
        /// `MapLocationGeocoder.shared` so the resolved coords land
        /// in the doc regardless of whether a live `MKMapView` is
        /// on screen. Previously the geocode lived inside
        /// `MapHostNSView`, which is destroyed in edit mode, so
        /// edits made via the inspector never re-geocoded.
        var lastMapLocations: [UUID: String] = [:]

        private var activeCanvasCoalescingKey: String {
            "canvas-\(parent.currentCardId.uuidString)"
        }

        init(parent: CardCanvasView) {
            self.parent = parent
        }

        func setPaintLayer(_ layer: CardPaintLayer) {
            parent.document.document.setPaintLayer(layer)
        }

        func removePaintLayer(cardId: UUID) {
            parent.document.document.removePaintLayer(forCardId: cardId)
        }

        /// Clear selection and select a single part (or none).
        func selectPart(_ id: UUID?) {
            if let id = id {
                parent.selectedPartIds = parent.document.document.expandedGroupSelection([id])
            } else {
                parent.selectedPartIds = []
            }
        }

        /// Add a part to the existing selection.
        func addToSelection(_ id: UUID) {
            parent.selectedPartIds.formUnion(parent.document.document.expandedGroupSelection([id]))
        }

        /// Remove a part from the existing selection.
        func removeFromSelection(_ id: UUID) {
            parent.selectedPartIds.subtract(parent.document.document.expandedGroupSelection([id]))
        }

        /// Set the full selection to a specific set of IDs.
        func selectParts(_ ids: Set<UUID>) {
            parent.selectedPartIds = parent.document.document.expandedGroupSelection(ids)
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

        func moveParts(ids: Set<UUID>, dx: Double, dy: Double) {
            parent.document.document.moveParts(ids: ids, dx: dx, dy: dy)
            parent.selectedPartIds = parent.document.document.expandedGroupSelection(parent.selectedPartIds)
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

        func resizeParts(ids: Set<UUID>, from oldBounds: PartBounds, to newBounds: PartBounds) {
            parent.document.document.resizeParts(ids: ids, from: oldBounds, to: newBounds)
            parent.selectedPartIds = parent.document.document.expandedGroupSelection(parent.selectedPartIds)
        }

        func beginCoalescedCanvasMutation(actionName: String) {
            HypeDocumentMutationCoordinator.shared.beginCoalescedUndo(
                key: activeCanvasCoalescingKey,
                binding: parent.$document
            )
        }

        func performContinuousCanvasMutation(_ mutation: () -> Void) {
            HypeDocumentMutationCoordinator.shared.performWithoutUndo(mutation)
        }

        func endCoalescedCanvasMutation(actionName: String) {
            HypeDocumentMutationCoordinator.shared.endCoalescedUndo(
                key: activeCanvasCoalescingKey,
                binding: parent.$document,
                undoManager: nsView?.window?.undoManager,
                actionName: actionName
            )
        }

        /// Update a part's text content (used by inline field editor).
        func updatePartText(id: UUID, text: String) {
            parent.document.document.updatePart(id: id) { $0.textContent = text }
        }

        /// Accessibility writeback for button labels and authored part text.
        func setPartText(id: UUID, text: String) {
            parent.document.document.updatePart(id: id) { $0.textContent = text }
        }

        /// Accessibility writeback for non-text parts. Automation clients use
        /// the AX value setter as a broad "rename selected object" affordance
        /// when the part does not expose editable text.
        func setPartName(id: UUID, name: String) {
            parent.document.document.updatePart(id: id) { $0.name = name }
        }

        /// Accessibility resize action. Keeps the model mutation on the same
        /// coordinator path as other canvas edits so undo/autosave still see it.
        func resizeAccessibilityPart(id: UUID, dw: Double, dh: Double) {
            parent.document.document.updatePart(id: id) { part in
                part.width = max(10, part.width + dw)
                part.height = max(10, part.height + dh)
            }
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

        /// Write the user's interactive date selection back to the
        /// document so HypeTalk reads of `the selectedDate of
        /// calendar "X"` reflect what's on screen. Called from
        /// `CalendarHostNSView.onDateChange` via the NSView's
        /// `coordinator?` pointer. Also dispatches the
        /// `dateChanged` message so script handlers can react.
        func setPartCalendarDate(id: UUID, isoDate: String) {
            parent.document.document.updatePart(id: id) { $0.selectedDate = isoDate }
            dispatchMessage("dateChanged", to: id)
        }

        /// Write the user's interactive color pick back into the
        /// document. Same writeback pattern as
        /// `setPartCalendarDate`. Dispatches `colorChanged` on the
        /// part so HypeTalk handlers can react.
        func setPartColorWellHex(id: UUID, hex: String) {
            parent.document.document.updatePart(id: id) { $0.colorWellHex = hex }
            dispatchMessage("colorChanged", to: id)
        }

        /// Write the geocoder-resolved coordinate back into the
        /// document so HypeTalk reads + save/load see the new
        /// lat/lon as authoritative. Mirrors setPartColorWellHex
        /// and setPartCalendarDate. Dispatches `locationResolved`
        /// so HypeTalk authors can react.
        func setPartMapCoordinate(id: UUID, lat: Double, lon: Double) {
            parent.document.document.updatePart(id: id) { part in
                part.mapCenterLat = lat
                part.mapCenterLon = lon
            }
            dispatchMessage("locationResolved", to: id)
        }

        /// Diff the current document's map parts against the last
        /// snapshot in `lastMapLocations` and dispatch each changed
        /// `mapLocation` through `MapLocationGeocoder.shared`. Runs
        /// on every `updateNSView` cycle so any path that mutates
        /// `mapLocation` — inspector typing, HypeTalk setter, AI
        /// tool, AI `create_map`, document open — gets the same
        /// resolve treatment regardless of whether the live
        /// `MKMapView` host is on screen.
        ///
        /// We also retire entries for parts that are no longer in
        /// the document so a stale `Timer` / `MKLocalSearch` doesn't
        /// keep firing for a deleted part.
        @MainActor
        func reconcileMapLocations() {
            let parts = parent.document.document.parts
            var seenIds = Set<UUID>()
            for part in parts where part.partType == .map {
                seenIds.insert(part.id)
                let current = part.mapLocation
                let previous = lastMapLocations[part.id]
                lastMapLocations[part.id] = current

                // Skip the very first observation of a part that
                // already has resolved coordinates: the doc was
                // loaded from disk with `mapLocation` and matching
                // `mapCenterLat/Lon`, no resolve needed. Detect by:
                // previous == nil AND current matches what the geocode
                // cache holds (or the lat/lon look intentional, i.e.
                // not the default 0,0). Conservative heuristic — if
                // the part already has non-zero lat/lon AND a
                // matching cache entry, skip the resolve. Otherwise
                // resolve so a freshly opened doc with a typo'd
                // address still settles.
                let isFirstSeen = previous == nil
                let coordsAlreadyValid = abs(part.mapCenterLat) > 1e-6 || abs(part.mapCenterLon) > 1e-6
                if isFirstSeen && coordsAlreadyValid && current.isEmpty {
                    continue
                }

                // Skip when the value didn't change since last pass
                // — `MapLocationGeocoder.scheduleResolve` already
                // suppresses redundant work on a per-query basis,
                // but bailing here avoids touching the service at
                // all on the common no-op redraw.
                if previous == current { continue }

                // Empty value: nothing to resolve, but we still
                // record the empty so the next non-empty edit
                // detects the transition.
                if current.isEmpty { continue }

                // Capture parent in a way that's safe across the
                // async callback. `parent` is a value-type
                // CardCanvasView (NSViewRepresentable), but the
                // coordinator lives across re-renders and the
                // closure mutates the document via
                // `setPartMapCoordinate` which itself uses
                // `parent.document.document.updatePart`.
                let partId = part.id
                MapLocationGeocoder.shared.scheduleResolve(
                    partId: partId,
                    query: current
                ) { [weak self] coord in
                    // The service hops to MainActor before
                    // invoking the callback, but the closure type
                    // is non-isolated `@Sendable` so we hop again
                    // explicitly to call the MainActor-isolated
                    // `setPartMapCoordinate`.
                    Task { @MainActor [weak self] in
                        self?.setPartMapCoordinate(
                            id: partId,
                            lat: coord.latitude,
                            lon: coord.longitude
                        )
                    }
                }
            }

            // Retire entries for deleted map parts so the service
            // doesn't keep them around.
            for staleId in lastMapLocations.keys where !seenIds.contains(staleId) {
                MapLocationGeocoder.shared.forget(partId: staleId)
                lastMapLocations.removeValue(forKey: staleId)
            }
        }

        /// Shared writeback for stepper / slider / toggle /
        /// segmented control changes. The `message` parameter
        /// chooses which HypeTalk handler the part gets:
        /// `valueChanged` for stepper/slider/toggle,
        /// `selectionChanged` for segmented.
        func setPartControlValue(id: UUID, value: Double, message: String) {
            parent.document.document.updatePart(id: id) { $0.controlValue = value }
            dispatchMessage(message, to: id)
        }

        /// Writeback for the gauge host's interactive scrub gesture.
        /// Gauge uses `gaugeValue` (not `controlValue` — the form
        /// controls own that field). Fires `valueChanged` on every
        /// drag tick so HypeTalk authors get the same lifecycle as
        /// stepper / slider / toggle.
        func setPartGaugeValue(id: UUID, value: Double) {
            parent.document.document.updatePart(id: id) { $0.gaugeValue = value }
            dispatchMessage("valueChanged", to: id)
        }

        /// Writeback for the audio-recorder host. State changes
        /// update recorder state atomically. Dispatches
        /// `recordingStarted` or `recordingStopped` on transitions so
        /// HypeTalk handlers can react.
        func setPartAudioRecorderState(id: UUID, recording: Bool, playing: Bool, duration: Double, outputPath: String, embeddedData: Data?) {
            let prior = parent.document.document.parts.first(where: { $0.id == id })
            let priorRecording = prior?.audioRecording ?? false
            let priorPlaying = prior?.audioPlaying ?? false
            parent.document.document.updatePart(id: id) {
                $0.audioRecording = recording
                $0.audioPlaying = playing
                $0.audioDuration = duration
                if !outputPath.isEmpty { $0.audioOutputPath = outputPath }
                if recording && embeddedData == nil && $0.audioEmbedInStack == false {
                    $0.audioData = nil
                }
                if let embeddedData {
                    $0.audioData = embeddedData
                    $0.audioEmbedInStack = true
                }
            }
            if recording != priorRecording {
                dispatchMessage(recording ? "recordingStarted" : "recordingStopped", to: id)
            }
            if playing != priorPlaying {
                dispatchMessage(playing ? "playbackStarted" : "playbackStopped", to: id)
            }
        }

        func setPartAppleMusicSearchConfiguration(
            id: UUID,
            term: String,
            scope: AppleMusicSearchScope,
            itemType: AppleMusicItemKind
        ) {
            parent.document.document.updatePart(id: id) { part in
                part.musicSearchTerm = term
                part.musicSearchScope = scope.rawValue
                part.musicSourceType = itemType.rawValue
                part.musicSourceKind = scope == .library
                    ? MusicSourceKind.appleMusicLibrary.rawValue
                    : MusicSourceKind.appleMusicCatalog.rawValue
            }
        }

        func setPartAppleMusicSelection(id: UUID, item: AppleMusicItemRef) {
            parent.document.document.musicLibrary.upsertAppleMusicItem(item)
            parent.document.document.updatePart(id: id) { part in
                part.musicSourceKind = item.source.rawValue
                part.musicSourceType = item.kind.rawValue
                part.musicSourceID = item.id
                part.musicSourceTitle = item.titleSnapshot
                part.musicSourceArtist = item.artistSnapshot
                part.musicSourceAlbum = item.albumSnapshot
                part.musicArtworkURL = item.artworkURLSnapshot
                part.musicDuration = max(0, item.durationSnapshot ?? 0)
                part.musicPosition = 0
            }
        }

        func setPartAppleMusicPosition(id: UUID, position: Double) {
            parent.document.document.updatePart(id: id) {
                $0.musicPosition = max(0, position)
            }
        }

        func setPartMusicInstrumentName(id: UUID, instrument: String) {
            parent.document.document.updatePart(id: id) {
                $0.musicInstrumentName = MusicInstrumentCatalog.resolve(instrument).name
            }
            dispatchMessage("instrumentChanged", to: id, params: [instrument])
        }

        func dispatchAppleMusicBrowserEvent(id: UUID, message: String, params: [String] = []) {
            dispatchMessage(message, to: id, params: params)
        }

        /// Dispatch `modelLoadFailed` to the scene3D part so HypeTalk
        /// handlers can react (e.g. `on modelLoadFailed reason ...`).
        /// Called from `Scene3DHostNSView.onLoadFailed`.
        func dispatchScene3DLoadFailed(id: UUID, reason: String) {
            dispatchMessage("modelLoadFailed", to: id, params: [reason])
        }

        // MARK: - Phase 3 control writebacks

        /// Writeback for progressView: fires `progressFinished` once
        /// when value first crosses total. Mutation happens before the
        /// dispatch so HypeTalk reads inside the handler see the final value.
        func setPartProgressFinished(id: UUID) {
            dispatchMessage("progressFinished", to: id)
        }

        /// Writeback for searchField: fires `searchChanged` or `searchSubmitted`.
        func setPartSearchText(id: UUID, text: String, message: String) {
            parent.document.document.updatePart(id: id) {
                $0.searchText = String(text.prefix(1024))
            }
            dispatchMessage(message, to: id, params: [text])
        }

        /// Writeback for menu: fires `menuItemSelected` with the chosen label.
        func setPartMenuItemSelected(id: UUID, label: String) {
            dispatchMessage("menuItemSelected", to: id, params: [label])
        }

        /// Writeback for link: dispatches `linkOpened` before the URL opens.
        func setPartLinkOpened(id: UUID) {
            dispatchMessage("linkOpened", to: id)
        }

        func deletePart(id: UUID) {
            deleteParts(ids: [id])
        }

        func deleteParts(ids: Set<UUID>) {
            let expanded = parent.document.document.expandedGroupSelection(ids)
            let orderedIds = parent.document.document.parts
                .filter { expanded.contains($0.id) }
                .map(\.id)
            guard !orderedIds.isEmpty else { return }

            // Drop inspector/canvas selection immediately, but keep the
            // document objects alive until their delete handlers have run.
            parent.selectedPartIds.subtract(expanded)
            nsView?.selectedPartIds.subtract(expanded)
            dispatchDeleteMessagesThenRemove(orderedIds, index: 0)
        }

        private func dispatchDeleteMessagesThenRemove(_ orderedIds: [UUID], index: Int) {
            guard index < orderedIds.count else {
                removeDeletedParts(orderedIds)
                return
            }

            let id = orderedIds[index]
            guard let part = parent.document.document.parts.first(where: { $0.id == id }) else {
                dispatchDeleteMessagesThenRemove(orderedIds, index: index + 1)
                return
            }

            dispatchMessage(
                Self.deleteMessageName(for: part.partType),
                to: id,
                params: [],
                completion: { [weak self] in
                    self?.dispatchDeleteMessagesThenRemove(orderedIds, index: index + 1)
                }
            )
        }

        private func removeDeletedParts(_ ids: [UUID]) {
            let idSet = Set(ids)
            for id in idSet {
                nsView?.releasePartRuntimeResources(partId: id)
            }

            var wrapper = parent.document
            for id in ids {
                wrapper.document.deletePart(id: id)
            }
            parent.document = wrapper
            parent.selectedPartIds.subtract(idSet)
            nsView?.selectedPartIds.subtract(idSet)
            nsView?.needsDisplay = true
        }

        private static func deleteMessageName(for partType: PartType) -> String {
            switch partType {
            case .button: return "deleteButton"
            case .field: return "deleteField"
            default: return "deletePart"
            }
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
            HypeDocumentMutationCoordinator.shared.performWithoutUndo {
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
        }

        /// Dispatch a HypeTalk message to the current card (for card-level events).
        private let dialogProvider = AppKitDialogProvider()
        private let systemProvider = AppKitSystemProvider()
        private let aiProvider = SelectedAIScriptingProvider()

        private var drawingProvider: DrawingProvider {
            if let view = nsView {
                return PaintLayerDrawingProvider(paintLayer: view.paintLayerForCurrentCard()) { [weak view] in
                    Task { @MainActor in
                        view?.persistPaintLayerForCurrentCard()
                    }
                }
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
            scriptContext: ScriptDispatchContext? = nil,
            completion: (@MainActor () -> Void)? = nil
        ) {
            let cardId = parent.currentCardId
            dispatchThroughRuntime(
                message: message,
                params: params,
                targetId: partId,
                currentCardId: cardId,
                mouseX: mouseX,
                mouseY: mouseY,
                scriptContext: scriptContext,
                completion: completion
            )
        }

        func dispatchIdleBurst(cardTargetId: UUID, includeCardTarget: Bool, partTargetIds: [UUID]) {
            let snapshot = parent.document.document
            let config = runtimeConfiguration()
            Task {
                let runtime = await StackRuntimeRegistry.shared.runtime(for: snapshot, configuration: config)
                await runtime.dispatchIdleBurst(
                    cardTargetID: cardTargetId,
                    partTargetIDs: partTargetIds,
                    currentCardId: cardTargetId,
                    includeCardTarget: includeCardTarget
                )
            }
        }

        func appScriptHasHandler(_ handlerName: String) -> Bool {
            CardCanvasNSView.scriptHasHandler(appScript, named: handlerName)
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
                    nsView?.document = modified
                    nsView?.needsDisplay = true
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
                            let didStart = nsView?.performCardTransition(
                                to: navTarget,
                                effect: effect,
                                duration: result.visualEffectDuration
                            ) ?? false
                            if didStart {
                                let dur = CardCanvasNSView.normalizedTransitionDuration(result.visualEffectDuration)
                                // Post the navigation after the SpriteKit
                                // transition has actually had a priming
                                // frame and then completed, so CGContext
                                // redraw resumes on the destination card
                                // rather than cutting the animation short.
                                DispatchQueue.main.asyncAfter(deadline: .now() + CardCanvasNSView.navigationDelay(forTransitionDuration: dur)) {
                                    NotificationCenter.default.post(
                                        name: .navigateToCard,
                                        object: navTarget
                                    )
                                }
                                return
                            }
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
                    nsView?.blockSpriteDispatch(after: err)
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
            let actionURL = scriptErrorActionURL(
                target: userInfo["target"] as? ScriptTarget,
                err: err,
                document: doc
            )
            if let actionURL {
                userInfo["url"] = actionURL
            }
            HypeLogger.shared.scriptError(
                err,
                source: "Script",
                context: scriptErrorContext(target: userInfo["target"] as? ScriptTarget, document: doc),
                actionURL: actionURL
            )
            NotificationCenter.default.post(
                name: .showScriptError,
                object: nil,
                userInfo: userInfo
            )
        }

        private func scriptErrorContext(target: ScriptTarget?, document: HypeDocument) -> String {
            guard let target else { return document.stack.name }
            switch target {
            case .part(let id):
                if let part = document.parts.first(where: { $0.id == id }) {
                    return "\(part.partType.rawValue) \"\(part.name)\""
                }
            case .card(let id):
                if let card = document.cards.first(where: { $0.id == id }) {
                    return "card \"\(card.name)\""
                }
            case .background(let id):
                if let background = document.backgrounds.first(where: { $0.id == id }) {
                    return "background \"\(background.name)\""
                }
            case .scene:
                return "SpriteKit scene script"
            case .node:
                return "SpriteKit node script"
            case .stack:
                return "stack \"\(document.stack.name)\""
            case .hype:
                return "Hype app script"
            }
            return document.stack.name
        }

        private func scriptErrorActionURL(target: ScriptTarget?, err: ScriptError, document: HypeDocument) -> URL? {
            guard let target else { return nil }
            var items = [
                URLQueryItem(name: "stack", value: document.stack.id.uuidString),
                URLQueryItem(name: "line", value: "\(err.line)"),
                URLQueryItem(name: "message", value: err.message),
            ]
            switch target {
            case .part(let id):
                items.append(URLQueryItem(name: "target", value: "part"))
                items.append(URLQueryItem(name: "id", value: id.uuidString))
            case .card(let id):
                items.append(URLQueryItem(name: "target", value: "card"))
                items.append(URLQueryItem(name: "id", value: id.uuidString))
            case .background(let id):
                items.append(URLQueryItem(name: "target", value: "background"))
                items.append(URLQueryItem(name: "id", value: id.uuidString))
            case .scene(let partId, let sceneId):
                items.append(URLQueryItem(name: "target", value: "scene"))
                items.append(URLQueryItem(name: "partId", value: partId.uuidString))
                items.append(URLQueryItem(name: "id", value: sceneId.uuidString))
            case .node(let partId, let nodeId):
                items.append(URLQueryItem(name: "target", value: "node"))
                items.append(URLQueryItem(name: "partId", value: partId.uuidString))
                items.append(URLQueryItem(name: "id", value: nodeId.uuidString))
            case .stack:
                items.append(URLQueryItem(name: "target", value: "stack"))
            case .hype:
                items.append(URLQueryItem(name: "target", value: "hype"))
            }
            var components = URLComponents()
            components.scheme = "hype"
            components.host = "script-error"
            components.queryItems = items
            return components.url
        }

        private func dispatchThroughRuntime(
            message: String,
            params: [Value],
            targetId: UUID,
            currentCardId: UUID,
            mouseX: Double,
            mouseY: Double,
            scriptContext: ScriptDispatchContext?,
            completion: (@MainActor () -> Void)? = nil
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
                    completion?()
                }
            }
        }

        private func runtimeConfiguration() -> StackRuntimeConfiguration {
            StackRuntimeConfiguration(
                dialogProvider: dialogProvider,
                drawingProvider: drawingProvider,
                systemProvider: systemProvider,
                aiProvider: aiProvider,
                speechOutputProvider: OpenAISpeechOutputProvider.shared,
                speechListenerProvider: RuntimeSpeechListenerProvider.shared,
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
    private static let objectToolPasteboardType = NSPasteboard.PasteboardType(ObjectToolCatalog.dragPasteboardTypeRaw)
    private static let objectToolPasteboardTypes: [NSPasteboard.PasteboardType] = [
        objectToolPasteboardType,
        .string,
    ]

    struct ToolTipDescriptor: Equatable {
        let partId: UUID
        let rect: NSRect
    }

    private enum CursorDescriptor: Hashable {
        case arrow
        case pointingHand
        case crosshair
        case eraser(radius: Int)
        case spray(radius: Int, colorToken: String)
    }

    enum CreationCommitMode: Equatable {
        case replaceSelectionAndSelectTool
        case appendSelectionKeepPlacementTool
    }

    var document: HypeDocument = HypeDocument()
    var currentCardId: UUID = UUID()
    var currentTool: ToolName = .browse
    var selectedPartIds: Set<UUID> = []
    var editingBackground: Bool = false
    weak var coordinator: CardCanvasView.Coordinator?
    var musicControlPlaybackHandler: ((MusicControlPlaybackRequest, HypeDocument) -> Void)?
    var musicControlSustainStopHandler: ((MusicSustainedNoteSpec, HypeDocument) -> Void)?

    /// Configure the layer-backing and redraw policy required for the
    /// card canvas to behave correctly. Both `wantsLayer = true` (so
    /// AppKit text-field subviews composite atop the CG-drawn card) and
    /// `layerContentsRedrawPolicy = .onSetNeedsDisplay` (so
    /// `view.needsDisplay = true` actually queues a draw) are
    /// REQUIRED. Layer-backed `NSView`s default the policy to
    /// `.duringViewResize`, which silently drops on-demand redraws —
    /// the user-visible symptom is animated GIFs that never advance
    /// and `on idle` scripts whose `set the loc of me` / `set the
    /// rotation of me` writes never appear on screen. Single seam
    /// owned by `CardCanvasNSView` itself so production wiring
    /// (`CardCanvasView.makeNSView`) and the regression test live
    /// against the same code path.
    func configureForCardCanvasRendering() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        registerForDraggedTypes(Self.objectToolPasteboardTypes)
    }

    /// Keep process-wide animation callbacks pointed at the active canvas.
    ///
    /// `GIFAnimator` and `PartAnimator` are runtime singletons, while
    /// SwiftUI may rebuild or update the representable around the same
    /// document window. Wiring only in `makeNSView` can leave the callbacks
    /// captured to a stale view; refreshing here from both `makeNSView` and
    /// `updateNSView` keeps frame ticks invalidating the visible canvas.
    func installRuntimeAnimatorCallbacks() {
        PartAnimator.shared.onPropertyChange = { [weak self] partId, property, value in
            guard let self else { return }
            guard let coord = self.coordinator else { return }
            coord.applyAnimatedPropertyChange(partId: partId, property: property, value: value)
            self.requestRuntimeAnimationRedraw()
        }

        GIFAnimator.shared.onFrameChanged = { [weak self] _ in
            self?.requestRuntimeAnimationRedraw()
        }

        GIFAnimator.shared.onAnimationStart = { [weak self] partId in
            self?.coordinator?.dispatchMessage("animationStart", to: partId)
        }

        GIFAnimator.shared.onAnimationEnd = { [weak self] partId in
            self?.coordinator?.dispatchMessage("animationEnd", to: partId)
        }
    }

    func requestRuntimeAnimationRedraw() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.requestRuntimeAnimationRedraw()
            }
            return
        }
        needsDisplay = true
        setNeedsDisplay(bounds)
    }

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

    // Active NSDatePicker hosts for calendar parts (keyed by part ID).
    // Mirrors chart/sprite pattern — the live picker shows in browse
    // mode, the CG placeholder shows in edit mode.
    private var calendarViews: [UUID: CalendarHostNSView] = [:]
    // Live PDFView, MKMapView, NSColorWell hosts. Same lifecycle.
    private var pdfViews: [UUID: PDFHostNSView] = [:]
    private var loadedPDFURLs: [UUID: String] = [:]
    private var mapViews: [UUID: MapHostNSView] = [:]
    private var colorWellViews: [UUID: ColorWellHostNSView] = [:]
    // Live form-control hosts.
    private var stepperViews: [UUID: StepperHostNSView] = [:]
    private var sliderViews: [UUID: SliderHostNSView] = [:]
    private var segmentedViews: [UUID: SegmentedHostNSView] = [:]
    private var appleMusicBrowserViews: [UUID: AppleMusicBrowserHostNSView] = [:]
    private var musicInstrumentPopupViews: [UUID: MusicInstrumentPopupHostNSView] = [:]
    private var audioRecorderViews: [UUID: AudioRecorderHostNSView] = [:]
    private var scene3DViews: [UUID: Scene3DHostNSView] = [:]
    // Phase 3 framework controls.
    private var progressViewHosts: [UUID: ProgressViewHostNSView] = [:]
    private var gaugeHosts: [UUID: GaugeHostNSView] = [:]
    // toggleViews / linkHosts / menuHosts / searchFieldHosts removed
    // in dedup — those PartTypes migrate to button / field with
    // appropriate style at decode time.

    /// Per-part tooltip registration. We use the system
    /// `NSView.addToolTip(_:owner:userData:)` mechanism — the same
    /// thing every native macOS app uses for hover help — to give
    /// each card / background part its own help bubble. The bubble
    /// content is `Part.helpText`. Empty `helpText` means no
    /// bubble for that part.
    ///
    /// We keep a `tag → partId` map so the
    /// `view(_:stringForToolTip:point:userData:)` callback (which
    /// receives only the tag, not the part) can look the part up
    /// fresh every time the system needs the tooltip string. This
    /// makes the bubble content always current — if the user edits
    /// `helpText` while the bubble is showing, the next render
    /// uses the new text.
    ///
    /// Tooltips are registered/cleared in `updatePartToolTips()`
    /// during browse mode only. Edit mode disables them so they
    /// don't confuse authors who are clicking parts to select them.
    private var toolTipTagToPartId: [NSView.ToolTipTag: UUID] = [:]
    private var registeredToolTipDescriptors: [ToolTipDescriptor] = []
    private var mouseMovedTrackingArea: NSTrackingArea?
    private var activeCursorDescriptor: CursorDescriptor?
    private var cursorCache: [CursorDescriptor: NSCursor] = [:]
    var accessibilitySignature: String = ""

    // Active SKViews for spriteArea parts (keyed by part ID)
    private var spriteViews: [UUID: SKView] = [:]
    private var spriteScenes: [UUID: HypeSKScene] = [:]
    private var spriteBridges: [UUID: SceneBridge] = [:]
    private var loadedSceneSpecs: [UUID: String] = [:]
    private var loadedActiveSceneIDs: [UUID: UUID] = [:]
    private var dispatchedLifecycleSceneIDs: [UUID: UUID] = [:]
    private struct SpriteLifecycleDispatchKey: Hashable {
        var partId: UUID
        var sceneId: UUID
    }
    private var pendingSceneLoads: Set<SpriteLifecycleDispatchKey> = []
    private var frameUpdateDispatchInFlight: Set<UUID> = []
    private var frameUpdateDispatchPayloads: [UUID: (targetId: UUID, context: ScriptDispatchContext, hasHandler: Bool)] = [:]
    private var frameUpdateDispatchSignatures: [UUID: String] = [:]
    /// Circuit-breaks a sprite area after a script runtime error until
    /// its scene/script signature changes. This prevents a bad
    /// frameUpdate/openScene loop from repeatedly reopening the Script
    /// Editor and stealing Browse-mode gameplay focus.
    private var blockedSpriteDispatchSignatures: [UUID: String] = [:]

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
    private var dragInitialBounds: PartBounds?
    private var appliedDragTranslation = CGSize.zero
    private var paletteDragTool: ToolName?
    private var paletteDragPoint: CGPoint?

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
    private static let idleTimerInterval: TimeInterval = 1.0 / 60.0
    private var idleDispatchTargetSignature = ""
    private var idleDispatchCachedPartIDs: [UUID] = []
    private var idleDispatchCachedIncludesCard = true

    // Timer for mouseStillDown messages while mouse is held
    private var mouseStillDownTimer: Timer?
    private var mouseStillDownPartId: UUID?

    // Music-control drag playback state. Dragging across piano keys or step
    // sequencer cells should trigger each newly-entered target once.
    private var activeMusicControlDragPartId: UUID?
    private var lastMusicControlDragTriggerIdentifier: String?
    private var lastMusicControlDragPoint: CGPoint?
    private var activeKeyboardNotesByPartId: [UUID: String] = [:]
    private var activeKeyboardSustainedNotesByPartId: [UUID: MusicSustainedNoteSpec] = [:]

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

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityIdentifier() -> String {
        HypeAccessibilityID.canvas(cardId: currentCardId)
    }

    override func accessibilityLabel() -> String? {
        let cardName = document.cards.first(where: { $0.id == currentCardId })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cardName, !cardName.isEmpty {
            return "Hype card canvas: \(cardName)"
        }
        return "Hype card canvas"
    }

    override func accessibilityValue() -> Any? {
        "card=\(currentCardId.uuidString); tool=\(currentTool.rawValue); selected=\(selectedPartIds.count)"
    }

    override func accessibilityChildren() -> [Any]? {
        accessibilityRootChildren()
    }

    override func accessibilityVisibleChildren() -> [Any]? {
        accessibilityRootChildren()
    }

    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        accessibilityRootChildren().compactMap { $0 as? any NSAccessibilityElementProtocol }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        accessibilitySelectedPartChildren()
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        MainActor.assumeIsolated {
            guard let window else { return AccessibilityHitTestResult(self) }
            let windowPoint = window.convertPoint(fromScreen: point)
            let localPoint = convert(windowPoint, from: nil)
            guard bounds.contains(localPoint) else { return AccessibilityHitTestResult(nil) }

            let cardParts = document.partsForCard(currentCardId)
            let backgroundParts: [Part]
            if let card = document.cards.first(where: { $0.id == currentCardId }) {
                backgroundParts = document.partsForBackground(card.backgroundId)
            } else {
                backgroundParts = []
            }
            let hitParts = (backgroundParts + cardParts).filter {
                $0.visible && $0.enabled && $0.partType != .unknown && $0.width > 0 && $0.height > 0
            }
            for part in hitParts.reversed() {
                let rect = NSRect(x: part.left, y: part.top, width: part.width, height: part.height)
                if rect.contains(localPoint) {
                    return AccessibilityHitTestResult(CardCanvasPartAccessibilityElement(canvas: self, partId: part.id))
                }
            }
            return AccessibilityHitTestResult(self)
        }.value
    }

    override func keyDown(with event: NSEvent) {
        // While a field editor is active there's a small race
        // window: `startFieldEditing` schedules
        // `makeFirstResponder` via `DispatchQueue.main.async`, so
        // for one runloop tick after the click, `activeFieldEditor`
        // is set but the canvas is still firstResponder. If the
        // user types fast and presses Tab in that window, the Tab
        // event reaches THIS handler. Without intervention, the
        // old code path called `super.keyDown` which did nothing
        // and the event was lost — focus appeared to drop. Handle
        // Tab/Shift-Tab here by routing through the same
        // `moveFieldEditingFocus` that the in-field doCommandBy
        // path uses, then return so the keystroke isn't double-
        // dispatched.
        if activeFieldEditor != nil {
            if event.keyCode == 48 { // Tab
                moveFieldEditingFocus(reverse: event.modifierFlags.contains(.shift))
                return
            }
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

            return
        }

        // Delete or Backspace: delete all selected parts
        if event.keyCode == 51 || event.keyCode == 117 {
            if !selectedPartIds.isEmpty {
                coordinator?.deleteParts(ids: selectedPartIds)
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

        // Arrow keys: nudge selected parts on the 8-point authoring grid.
        // Holding Shift is the deliberate pixel-precision override.
        guard !selectedPartIds.isEmpty else {
            super.keyDown(with: event)
            return
        }
        let nudge: Double = event.modifierFlags.contains(.shift) ? LayoutGrid.fineNudge : LayoutGrid.standardNudge
        switch event.keyCode {
        case 123: // Left arrow
            coordinator?.moveParts(ids: selectedPartIds, dx: -nudge, dy: 0)
            needsDisplay = true; return
        case 124: // Right arrow
            coordinator?.moveParts(ids: selectedPartIds, dx: nudge, dy: 0)
            needsDisplay = true; return
        case 125: // Down arrow
            coordinator?.moveParts(ids: selectedPartIds, dx: 0, dy: nudge)
            needsDisplay = true; return
        case 126: // Up arrow
            coordinator?.moveParts(ids: selectedPartIds, dx: 0, dy: -nudge)
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
            return
        }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if isDragging || draggedPartId != nil || resizeHandle != .none || paletteDragTool != nil {
            needsDisplay = true
        }
        super.flagsChanged(with: event)
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
        let musicControlRenderOptions: MusicControlRenderOptions
        if isBrowseModeForRender {
            let renderCardParts = document.partsForCard(currentCardId)
            let renderBgParts: [Part]
            if let renderCard = document.cards.first(where: { $0.id == currentCardId }) {
                renderBgParts = document.partsForBackground(renderCard.backgroundId)
            } else {
                renderBgParts = []
            }
            // PartTypes whose live view is hosted by a real
            // NSView/SwiftUI subview (rather than drawn into the
            // CG context). The renderer skips these in the bitmap
            // pass so the host view's own draw doesn't double-draw.
            // `.toggle / .link / .menu / .searchField` were once
            // here but migrated to `.button` / `.field` styles in
            // `Part.init(from:)`; no live Part has those types
            // anymore, so they were dead in this set.
            let nativeKinds: Set<PartType> = [.spriteArea, .chart, .webpage, .video, .calendar, .pdf, .map, .colorWell, .stepper, .slider, .segmented, .audioRecorder, .scene3D, .progressView, .gauge]
            nativePartIds = Set(
                (renderCardParts + renderBgParts)
                    .filter { $0.visible && nativeKinds.contains($0.partType) }
                    .map(\.id)
            )
            let liveInstrumentPopupPartIds = Set(
                (renderCardParts + renderBgParts)
                    .filter {
                        $0.visible
                            && ($0.partType == .pianoKeyboard || $0.partType == .stepSequencer)
                            && $0.musicShowInstrument
                    }
                    .map(\.id)
            )
            musicControlRenderOptions = MusicControlRenderOptions(
                liveInstrumentPopupPartIds: liveInstrumentPopupPartIds,
                activeKeyboardNotesByPartId: activeKeyboardNotesByPartId
            )
        } else {
            nativePartIds = []
            musicControlRenderOptions = .default
        }
        renderer.render(
            ctx: ctx,
            document: document,
            cardId: currentCardId,
            size: bounds.size,
            skipPartId: activeFieldPartId,
            nativePartIds: nativePartIds,
            musicControlRenderOptions: musicControlRenderOptions
        )

        // Render the paint layer on top of card content
        let paintLayer = paintLayerForCurrentCard()
        if !paintLayer.isEmpty {
            paintLayer.render(into: ctx)
        }

        // Draw selection overlay for each selectable unit. Grouped
        // parts get one bounding box so they feel like one object.
        for unit in document.selectionUnits(for: selectedPartIds) {
            drawSelectionOverlay(ctx: ctx, bounds: unit.bounds)
        }

        // Draw alignment guides
        if !activeGuides.isEmpty {
            drawAlignmentGuides(ctx: ctx)
        }

        // Draw constraint rubber band during explicit Control+Option+drag.
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

        // Update calendar views for calendar parts
        updateCalendarViews()

        // Update PDF / map / color-well overlays for their parts.
        updatePDFViews()
        updateMapViews()
        updateColorWellViews()
        updateFormControlViews()
        updateAppleMusicBrowserViews()
        updateMusicInstrumentPopupViews()
        updateAudioRecorderViews()
        updateScene3DViews()
        // Phase 3 controls.
        updateProgressViewHosts()
        updateGaugeHosts()

        // Refresh per-part hover-help tooltips. Runs in both
        // edit and browse mode (the function itself short-circuits
        // out of edit mode), so changes to `Part.helpText` from
        // the inspector or HypeTalk show up on the next draw.
        updatePartToolTips()
        // Link / Menu / SearchField hosts removed in dedup —
        // those PartTypes are migrated to button (.link / .popup
        // style) and field (.search style) on decode.

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

        // Draw drag-to-place ghost for creation tools, otherwise keep the
        // existing rubber band for marquee selection.
        if let paletteDragTool, let paletteDragPoint {
            drawCreationGhost(tool: paletteDragTool, dragStart: nil, current: paletteDragPoint, fineControl: NSEvent.modifierFlags.contains(.shift))
        } else if isDragging, let start = dragStart, let current = dragCurrent,
                  let toolSpec = PartCreationDefaults.toolSpec(for: currentTool.rawValue) {
            drawCreationGhost(toolSpec: toolSpec, dragStart: start, current: current, fineControl: NSEvent.modifierFlags.contains(.shift))
        } else if isDragging, let start = dragStart, let current = dragCurrent {
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
        drawSelectionOverlay(
            ctx: ctx,
            bounds: PartBounds(left: part.left, top: part.top, width: part.width, height: part.height)
        )
    }

    private func drawSelectionOverlay(ctx: CGContext, bounds: PartBounds) {
        let theme = resolvedTheme
        let strokeNS = theme.selectionStroke.nsColor
        let rect = CGRect(x: bounds.left - 1, y: bounds.top - 1, width: bounds.width + 2, height: bounds.height + 2)
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

    private func drawCreationGhost(tool: ToolName, dragStart: CGPoint?, current: CGPoint, fineControl: Bool) {
        guard let toolSpec = PartCreationDefaults.toolSpec(for: tool.rawValue) else { return }
        drawCreationGhost(toolSpec: toolSpec, dragStart: dragStart, current: current, fineControl: fineControl)
    }

    private func drawCreationGhost(toolSpec: PartCreationToolSpec, dragStart: CGPoint?, current: CGPoint, fineControl: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var rect = PartCreationDefaults.creationRect(
            for: toolSpec.partType,
            dragStart: dragStart,
            currentPoint: current,
            fineControl: fineControl
        )
        rect = snappedCreationRect(rect, partType: toolSpec.partType, fineControl: fineControl, smartSpacing: NSEvent.modifierFlags.contains(.option))

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: 7, cornerHeight: 7, transform: nil)
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.addPath(path)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.restoreGState()
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

    @discardableResult
    private func performDefaultMusicControlAction(for part: Part, at point: CGPoint) -> MusicControlPlaybackRequest? {
        guard let request = MusicControlInteraction.playbackRequest(
            for: part,
            document: document,
            clickPoint: point
        ) else {
            return nil
        }

        startMusicControlRequest(request)
        applyActiveKeyboardNote(from: request)
        return request
    }

    private func startMusicControlRequest(_ request: MusicControlPlaybackRequest) {
        if let sustainedNote = request.sustainedNote {
            stopActiveKeyboardSustainedNote(forPartId: sustainedNote.partId)
        }
        playMusicControlRequest(request)
        if let sustainedNote = request.sustainedNote {
            activeKeyboardSustainedNotesByPartId[sustainedNote.partId] = sustainedNote
        }
    }

    private func playMusicControlRequest(_ request: MusicControlPlaybackRequest) {
        if let musicControlPlaybackHandler {
            musicControlPlaybackHandler(request, document)
            return
        }

        let provider = AppKitSystemProvider()
        let snapshot = document
        Task {
            if let appleMusicItem = request.appleMusicItem, snapshot.stack.appleMusicAllowed {
                try? await provider.playAppleMusic(appleMusicItem, engine: .application)
            } else if let sustainedNote = request.sustainedNote {
                await provider.playSustainedMusicNote(sustainedNote, document: snapshot)
            } else {
                await provider.playMusicPattern(request.pattern, loop: request.loop, document: snapshot)
            }
        }
    }

    private func beginMusicControlDragIfNeeded(part: Part, request: MusicControlPlaybackRequest?, at point: CGPoint) {
        guard part.partType == .pianoKeyboard || part.partType == .stepSequencer,
              let trigger = request?.triggerIdentifier,
              trigger.hasPrefix(dragTriggerPrefix(for: part)) else {
            activeMusicControlDragPartId = nil
            lastMusicControlDragTriggerIdentifier = nil
            lastMusicControlDragPoint = nil
            return
        }

        activeMusicControlDragPartId = part.id
        lastMusicControlDragTriggerIdentifier = trigger
        lastMusicControlDragPoint = point
    }

    private func performDraggedMusicControlAction(at point: CGPoint) -> Bool {
        guard let partId = activeMusicControlDragPartId else { return false }
        guard let part = document.parts.first(where: { $0.id == partId }),
              part.partType == .pianoKeyboard || part.partType == .stepSequencer else {
            activeMusicControlDragPartId = nil
            lastMusicControlDragTriggerIdentifier = nil
            lastMusicControlDragPoint = nil
            return true
        }

        let points = dragPlaybackSamplePoints(from: lastMusicControlDragPoint, to: point, part: part)
        lastMusicControlDragPoint = point
        for samplePoint in points {
            guard let request = MusicControlInteraction.playbackRequest(
                for: part,
                document: document,
                clickPoint: samplePoint
            ),
                  let trigger = request.triggerIdentifier,
                  trigger.hasPrefix(dragTriggerPrefix(for: part)) else {
                // Let re-entering the same key/cell after leaving it retrigger sound.
                if part.partType == .pianoKeyboard {
                    stopActiveKeyboardSustainedNote(forPartId: part.id)
                    clearActiveKeyboardNote(forPartId: part.id)
                }
                lastMusicControlDragTriggerIdentifier = nil
                continue
            }

            if trigger != lastMusicControlDragTriggerIdentifier {
                startMusicControlRequest(request)
                applyActiveKeyboardNote(from: request)
                lastMusicControlDragTriggerIdentifier = trigger
            }
        }
        return true
    }

    private func dragPlaybackSamplePoints(from previous: CGPoint?, to point: CGPoint, part: Part) -> [CGPoint] {
        guard let previous else { return [point] }

        let dx = point.x - previous.x
        let dy = point.y - previous.y
        let distance = sqrt(dx * dx + dy * dy)
        let spacing = dragPlaybackSamplingDistance(for: part)
        let steps = max(1, Int(ceil(distance / max(1, spacing))))
        return (1...steps).map { index in
            let t = CGFloat(index) / CGFloat(steps)
            return CGPoint(x: previous.x + dx * t, y: previous.y + dy * t)
        }
    }

    private func dragPlaybackSamplingDistance(for part: Part) -> CGFloat {
        switch part.partType {
        case .pianoKeyboard:
            let keyboard = MusicControlInteraction.keyboardRect(for: part)
            return max(1, keyboard.width / 28)
        case .stepSequencer:
            let grid = MusicControlInteraction.stepSequencerGridRect(for: part)
            let cellWidth = grid.width / CGFloat(MusicControlInteraction.stepSequencerColumnCount)
            let cellHeight = grid.height / CGFloat(MusicControlInteraction.stepSequencerRowCount)
            return max(1, min(cellWidth, cellHeight) / 2)
        default:
            return 4
        }
    }

    private func dragTriggerPrefix(for part: Part) -> String {
        switch part.partType {
        case .pianoKeyboard:
            return "keyboard:"
        case .stepSequencer:
            return "step:"
        default:
            return ""
        }
    }

    private func endMusicControlDrag() {
        stopActiveKeyboardSustainedNote(forPartId: activeMusicControlDragPartId)
        activeMusicControlDragPartId = nil
        lastMusicControlDragTriggerIdentifier = nil
        lastMusicControlDragPoint = nil
        if !activeKeyboardNotesByPartId.isEmpty {
            activeKeyboardNotesByPartId = [:]
            needsDisplay = true
        }
    }

    private func stopActiveKeyboardSustainedNote(forPartId partId: UUID?) {
        let notes: [MusicSustainedNoteSpec]
        if let partId {
            notes = activeKeyboardSustainedNotesByPartId[partId].map { [$0] } ?? []
            activeKeyboardSustainedNotesByPartId.removeValue(forKey: partId)
        } else {
            notes = Array(activeKeyboardSustainedNotesByPartId.values)
            activeKeyboardSustainedNotesByPartId.removeAll()
        }
        guard !notes.isEmpty else { return }

        if let musicControlSustainStopHandler {
            for note in notes {
                musicControlSustainStopHandler(note, document)
            }
            return
        }
        if musicControlPlaybackHandler != nil {
            return
        }

        let provider = AppKitSystemProvider()
        Task {
            for note in notes {
                await provider.stopSustainedMusicNote(id: note.id)
            }
        }
    }

    private func applyActiveKeyboardNote(from request: MusicControlPlaybackRequest) {
        guard let trigger = request.triggerIdentifier,
              let (partId, note) = keyboardTriggerParts(from: trigger) else {
            return
        }
        activeKeyboardNotesByPartId[partId] = note
        needsDisplay = true
    }

    private func clearActiveKeyboardNote(forPartId partId: UUID) {
        guard activeKeyboardNotesByPartId.removeValue(forKey: partId) != nil else { return }
        needsDisplay = true
    }

    private func keyboardTriggerParts(from trigger: String) -> (UUID, String)? {
        let prefix = "keyboard:"
        guard trigger.hasPrefix(prefix) else { return nil }
        let remainder = trigger.dropFirst(prefix.count)
        let pieces = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2, let partId = UUID(uuidString: String(pieces[0])) else { return nil }
        return (partId, String(pieces[1]))
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
        let fields = Self.editableFieldTabOrder(in: document, currentCardId: currentCardId)
        guard !fields.isEmpty else { return false }

        let nextPart: Part
        if let activeFieldPartId,
           let currentIndex = fields.firstIndex(where: { $0.id == activeFieldPartId }) {
            // Currently editing a known field — advance one step,
            // wrapping around at the ends.
            guard fields.count > 1 else { return true }
            let nextIndex = reverse
                ? (currentIndex - 1 + fields.count) % fields.count
                : (currentIndex + 1) % fields.count
            nextPart = fields[nextIndex]
        } else {
            // No active editor (or editing a part that's no longer
            // in the tab order — e.g. just deleted): fall back to
            // the first/last in the order.
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

        // Create the text field overlay at the full part rect. The
        // custom cell handles Hype's padding, search/scrolling
        // insets, and vertical centering through FieldTextLayout so
        // edit mode and static rendering stay visually aligned.
        let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
        let textField = NSTextField(frame: frame)

        // Swap in our custom cell BEFORE setting any cell-derived
        // properties (font, alignment, etc.) — those flow onto the
        // current cell, and replacing the cell after would lose them.
        let cell = HypeFieldEditorCell(textCell: "")
        cell.hypePadding = FieldTextLayout.padding(wideMargins: part.wideMargins)
        cell.leadingTextInset = FieldTextLayout.leadingInset(fieldStyle: part.fieldStyle)
        cell.rightScrollbarReserve = FieldTextLayout.trailingInset(fieldStyle: part.fieldStyle)
        // Keep AppKit out of single-line shortcut layout; Hype's
        // shared layout decides the vertical placement.
        cell.wraps = true
        cell.isScrollable = true
        cell.lineBreakMode = part.dontWrap ? .byClipping : .byWordWrapping
        cell.usesSingleLineMode = false
        textField.cell = cell

        let palette = FieldTextLayout.palette(for: part, theme: resolvedTheme)
        textField.stringValue = part.textContent
        textField.font = NSFont(name: part.textFont, size: CGFloat(part.textSize)) ?? NSFont.systemFont(ofSize: CGFloat(part.textSize))
        textField.textColor = palette.text
        textField.isBordered = false
        textField.drawsBackground = part.fieldStyle != .transparent
        textField.backgroundColor = palette.fill
        textField.focusRingType = .exterior
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self
        textField.alignment = part.textAlign == .center ? .center : part.textAlign == .right ? .right : .left
        textField.wantsLayer = true
        textField.layer?.borderColor = palette.stroke.cgColor
        textField.layer?.borderWidth = max(0, CGFloat(part.strokeWidth))
        textField.layer?.backgroundColor = (part.fieldStyle == .transparent ? NSColor.clear : palette.fill).cgColor
        textField.layer?.zPosition = 1000  // Ensure it's above all canvas drawing

        addSubview(textField, positioned: .above, relativeTo: nil)
        needsDisplay = true  // Redraw canvas to hide the underlying part

        activeFieldEditor = textField

        // Make the new field editor first responder synchronously
        // so the very next event (often Tab from a fast typist who
        // clicked-then-tabbed) lands on the textField's NSTextView,
        // not on the canvas. Previously this was wrapped in
        // `DispatchQueue.main.async` "to ensure the field is fully
        // in the view hierarchy"; in practice `addSubview(...)` has
        // already finished by this point and `makeFirstResponder`
        // succeeds synchronously. The async wrapper introduced a
        // one-runloop-tick race where Tab pressed in that window
        // fell through to the canvas's keyDown and vanished.
        // (The keyDown handler now also routes Tab through
        // `moveFieldEditingFocus` as a defense-in-depth fallback.)
        window?.makeFirstResponder(textField)
        if selectText {
            textField.selectText(nil)
        }
        activeFieldPartId = part.id
    }

    private func endFieldEditing() {
        if let editor = activeFieldEditor, let partId = activeFieldPartId {
            // Save the text back to the part
            let text = editor.stringValue
            coordinator?.updatePartText(id: partId, text: text)

            // Field-exit event semantics:
            //   closeField — text changed during this edit session.
            //     Fires FIRST so a `closeField` handler that mutates
            //     state runs before the more general `exitField`.
            //   exitField — fires on EVERY field exit, regardless of
            //     whether the text changed. The universal "blur"
            //     event (mirrors DOM `blur`, NSControl's
            //     `editingDidEnd`).
            //
            // Previously these two were XOR — `exitField` only
            // fired when the text was UNCHANGED, which meant a
            // handler like
            //     on exitField
            //       set the location of map "X" to the text of me
            //     end exitField
            // never ran when the user actually entered a new
            // address (text changed → only `closeField` fired).
            // The strict-XOR behavior matched HyperCard's docs but
            // not what authors actually expect when they write a
            // "fire when the user is done with this field" handler.
            if text != originalFieldText {
                coordinator?.dispatchMessage("closeField", to: partId)
            }
            coordinator?.dispatchMessage("exitField", to: partId)

            editor.removeFromSuperview()
        }
        activeFieldEditor = nil
        activeFieldPartId = nil
        originalFieldText = nil
    }

    // MARK: - Cursor

    func updateCursor() {
        guard mouseLocationInSelfIfCanvasOwnsCursor() != nil else {
            activeCursorDescriptor = nil
            return
        }
        applyCursor(cursorDescriptorForCurrentTool())
    }

    private func updateCursor(at point: CGPoint) {
        guard bounds.contains(point) else {
            activeCursorDescriptor = nil
            return
        }
        applyCursor(cursorDescriptorForCurrentTool())
    }

    private func cursorDescriptorForCurrentTool() -> CursorDescriptor {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        switch toolState.category {
        case .browse:
            return .pointingHand
        case .edit:
            if currentTool == .select {
                return .arrow
            } else {
                return .crosshair
            }
        case .paint:
            switch currentTool {
            case .eraser:
                return .eraser(radius: eraserRadius)
            case .spray:
                return .spray(radius: sprayRadius, colorToken: paintColorCursorToken)
            default:
                return .crosshair
            }
        }
    }

    private var paintColorCursorToken: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if let rgb = paintColor.usingColorSpace(.deviceRGB) {
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(format: "%.3f:%.3f:%.3f:%.3f", red, green, blue, alpha)
        }
        return paintColor.description
    }

    private func applyCursor(_ descriptor: CursorDescriptor) {
        guard activeCursorDescriptor != descriptor else { return }
        cursor(for: descriptor).set()
        activeCursorDescriptor = descriptor
    }

    private func cursor(for descriptor: CursorDescriptor) -> NSCursor {
        if let cached = cursorCache[descriptor] { return cached }

        let cursor: NSCursor
        switch descriptor {
        case .arrow:
            cursor = .arrow
        case .pointingHand:
            cursor = .pointingHand
        case .crosshair:
            cursor = .crosshair
        case .eraser(let radius):
            cursor = makeEraserCursor(radius: radius)
        case .spray(let radius, _):
            cursor = makeSprayCursor(radius: radius)
        }

        cursorCache[descriptor] = cursor
        return cursor
    }

    private func makeEraserCursor(radius: Int) -> NSCursor {
        let size = CGFloat(max(1, radius) * 2)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1)).stroke()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    private func makeSprayCursor(radius: Int) -> NSCursor {
        let size = CGFloat(max(1, radius) * 2)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        paintColor.withAlphaComponent(0.4).setStroke()
        let path = NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1))
        path.lineWidth = 1.5
        path.stroke()
        paintColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: size / 2 - 2, y: size / 2 - 2, width: 4, height: 4)).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    private func mouseLocationInSelfIfCanvasOwnsCursor() -> CGPoint? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point) else { return nil }

        // If a hosted AppKit/WebKit/SpriteKit subview is under the mouse,
        // let that native control own its cursor instead of forcing the
        // canvas cursor during unrelated SwiftUI updates.
        if let hitView = hitTest(point), hitView !== self {
            return nil
        }

        return point
    }

    // MARK: - Idle Timer

    /// True if the given script source declares `on <handlerName>`.
    ///
    /// Accepts `on <handlerName>` at the start of any line (ignoring leading
    /// whitespace). Stricter than `.contains("on idle")`, which would
    /// false-positive on comments like `-- on idle does X` and on
    /// handlers whose names happen to start with "idle" (e.g.
    /// `on idleState`), wastefully dispatching idle to parts that
    /// have no actual idle handler.
    fileprivate static func scriptHasHandler(_ script: String, named handlerName: String) -> Bool {
        let marker = "on \(handlerName.lowercased())"
        guard !script.isEmpty, !handlerName.isEmpty else { return false }
        for rawLine in script.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            if line.hasPrefix(marker) {
                // Next char after the handler name must be whitespace
                // or end-of-line, so "on idleState" doesn't count as
                // an `idle` handler.
                let remainder = line.dropFirst(marker.count)
                if remainder.isEmpty || remainder.first?.isWhitespace == true {
                    return true
                }
            }
        }
        return false
    }

    private static func scriptHasIdleHandler(_ script: String) -> Bool {
        scriptHasHandler(script, named: "idle")
    }

    private func idleDispatchTargetsForCurrentCard() -> (includeCardTarget: Bool, partIDs: [UUID]) {
        let cardParts = document.partsForCard(currentCardId)
        let card = document.cards.first(where: { $0.id == currentCardId })
        let bgParts = card.map { document.partsForBackground($0.backgroundId) } ?? []
        let background = card.flatMap { card in
            document.backgrounds.first(where: { $0.id == card.backgroundId })
        }
        let appHasIdle = coordinator?.appScriptHasHandler("idle") ?? false
        let signatureParts = [
            currentCardId.uuidString,
            card?.script ?? "",
            background?.script ?? "",
            document.stack.script,
            appHasIdle ? "app-idle" : "app-no-idle",
        ] + (cardParts + bgParts).map { "\($0.id.uuidString):\($0.script)" }
        let signature = signatureParts.joined(separator: "\u{1F}")
        if signature == idleDispatchTargetSignature {
            return (idleDispatchCachedIncludesCard, idleDispatchCachedPartIDs)
        }

        let includeCardTarget = CardCanvasNSView.scriptHasIdleHandler(card?.script ?? "")
            || CardCanvasNSView.scriptHasIdleHandler(background?.script ?? "")
            || CardCanvasNSView.scriptHasIdleHandler(document.stack.script)
            || appHasIdle
        let partIDs = (cardParts + bgParts)
            .filter { CardCanvasNSView.scriptHasIdleHandler($0.script) }
            .map(\.id)

        idleDispatchTargetSignature = signature
        idleDispatchCachedIncludesCard = includeCardTarget
        idleDispatchCachedPartIDs = partIDs
        return (includeCardTarget, partIDs)
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idleTimerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let toolState = ToolState(currentTool: self.currentTool.rawValue)
                guard toolState.category == .browse, self.activeFieldEditor == nil else { return }

                let targets = self.idleDispatchTargetsForCurrentCard()
                guard targets.includeCardTarget || !targets.partIDs.isEmpty else { return }
                self.coordinator?.dispatchIdleBurst(
                    cardTargetId: self.currentCardId,
                    includeCardTarget: targets.includeCardTarget,
                    partTargetIds: targets.partIDs
                )
            }
        }
        timer.tolerance = Self.idleTimerInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
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
    static let transitionPrimingDelay: TimeInterval = 0.05
    static let transitionCleanupPadding: TimeInterval = 0.10
    static let maximumTransitionDuration: TimeInterval = 10.0

    static func normalizedTransitionDuration(_ duration: TimeInterval?) -> TimeInterval {
        let requested = duration ?? defaultTransitionDuration
        guard requested.isFinite else { return defaultTransitionDuration }
        return min(max(requested, 0), maximumTransitionDuration)
    }

    static func navigationDelay(forTransitionDuration duration: TimeInterval) -> TimeInterval {
        transitionPrimingDelay + duration
    }

    static func cleanupDelay(forTransitionDuration duration: TimeInterval) -> TimeInterval {
        navigationDelay(forTransitionDuration: duration) + transitionCleanupPadding
    }

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
        // New control overlays added in 2026 — every native overlay
        // host needs to hide during a SpriteKit card transition,
        // otherwise it floats over the transition animation in its
        // old-card position. Recreated by updateNSView → draw().
        for (_, v) in calendarViews { v.isHidden = true }
        for (_, v) in pdfViews { v.isHidden = true }
        for (_, v) in mapViews { v.isHidden = true }
        for (_, v) in colorWellViews { v.isHidden = true }
        for (_, v) in stepperViews { v.isHidden = true }
        for (_, v) in sliderViews { v.isHidden = true }
        for (_, v) in segmentedViews { v.isHidden = true }
        for (_, v) in appleMusicBrowserViews { v.isHidden = true }
        for (_, v) in musicInstrumentPopupViews { v.isHidden = true }
        for (_, v) in audioRecorderViews { v.isHidden = true }
        for (_, v) in scene3DViews { v.isHidden = true }
        // Phase 3 control overlays.
        for (_, v) in progressViewHosts { v.isHidden = true }
        for (_, v) in gaugeHosts { v.isHidden = true }
    }

    /// Perform a card transition using SpriteKit.
    ///
    /// Captures the current card as a texture, presents it in an SKView,
    /// transitions to the new card's texture, then hides the SKView so
    /// normal CGContext rendering resumes.
    ///
    /// `duration` overrides the default transition length (1.0s) when the
    /// user writes `visual effect dissolve 2` in a script.
    @discardableResult
    func performCardTransition(to newCardId: UUID, effect: HypeCore.VisualEffect, duration: TimeInterval? = nil) -> Bool {
        guard effect != .none else {
            HypeLogger.shared.debug("Transition skipped: effect is .none", source: "Transition")
            return false
        }
        ensureCardSKView()
        guard let skView = cardSKView else {
            HypeLogger.shared.error("Transition failed: cardSKView is nil", source: "Transition")
            return false
        }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            HypeLogger.shared.error("Transition failed: bounds are zero", source: "Transition")
            return false
        }

        let dur = Self.normalizedTransitionDuration(duration)
        HypeLogger.shared.info("Starting \(effect) transition, duration=\(dur)s, size=\(Int(size.width))×\(Int(size.height))", source: "Transition")

        isTransitioning = true

        let usesInSceneFlip = effect == .flipHorizontal || effect == .flipVertical

        // Render the current card as a texture BEFORE hiding
        // embedded subviews — renderToImage only captures the
        // CGContext-drawn content (buttons, fields, shapes, text),
        // not the NSView overlays. The texture is a complete-enough
        // representation of the card for the transition.
        let currentNativePartIds = usesInSceneFlip ? [] : CardSKScene.nativeRenderablePartIds(document: document, cardId: currentCardId)
        let currentImage = renderer.renderToImage(document: document, cardId: currentCardId, size: size, nativePartIds: currentNativePartIds)
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

        // Pre-render the new card texture
        let newNativePartIds = usesInSceneFlip ? [] : CardSKScene.nativeRenderablePartIds(document: document, cardId: newCardId)
        let newImage = renderer.renderToImage(document: document, cardId: newCardId, size: size, nativePartIds: newNativePartIds)
        HypeLogger.shared.debug("New card rendered: \(Int(newImage.size.width))×\(Int(newImage.size.height))", source: "Transition")

        if usesInSceneFlip {
            performSafeFlipTransition(
                in: skView,
                currentImage: currentImage,
                newImage: newImage,
                cardSize: size,
                effect: effect,
                duration: dur
            )
            scheduleTransitionCleanup(duration: dur)
            return true
        }

        let currentScene = CardSKScene(cardSize: size)
        currentScene.updateCardTexture(currentImage)
        currentScene.updateNativeContent(document: document, cardId: currentCardId)
        skView.presentScene(currentScene)
        HypeLogger.shared.debug("Presented currentScene, skView.scene=\(skView.scene != nil)", source: "Transition")

        let newScene = CardSKScene(cardSize: size)
        newScene.updateCardTexture(newImage)
        newScene.updateNativeContent(document: document, cardId: newCardId)
        let transition = Self.skTransition(for: effect, duration: dur)

        // Delay the transition presentation so currentScene renders at least one frame
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionPrimingDelay) { [weak skView] in
            guard let skView = skView else {
                HypeLogger.shared.error("Transition delayed block: weak refs gone", source: "Transition")
                return
            }
            HypeLogger.shared.info("Presenting transition now: skView.hidden=\(skView.isHidden), scene=\(skView.scene != nil)", source: "Transition")
            skView.presentScene(newScene, transition: transition)
        }

        scheduleTransitionCleanup(duration: dur)
        return true
    }

    private func performSafeFlipTransition(
        in skView: SKView,
        currentImage: NSImage,
        newImage: NSImage,
        cardSize: CGSize,
        effect: HypeCore.VisualEffect,
        duration: TimeInterval
    ) {
        let scene = SKScene(size: cardSize)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .white

        let currentNode = SKSpriteNode(texture: SKTexture(image: currentImage), size: cardSize)
        currentNode.position = CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
        currentNode.zPosition = 1
        scene.addChild(currentNode)

        let newNode = SKSpriteNode(texture: SKTexture(image: newImage), size: cardSize)
        newNode.position = CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
        newNode.zPosition = 2
        newNode.isHidden = true
        scene.addChild(newNode)

        skView.presentScene(scene)
        HypeLogger.shared.debug("Presented safe flip scene, skView.scene=\(skView.scene != nil)", source: "Transition")

        let halfDuration = max(duration / 2, 0)
        let shrink: SKAction
        let grow: SKAction
        switch effect {
        case .flipVertical:
            shrink = .scaleY(to: 0.001, duration: halfDuration)
            grow = .scaleY(to: 1, duration: halfDuration)
            newNode.yScale = 0.001
        default:
            shrink = .scaleX(to: 0.001, duration: halfDuration)
            grow = .scaleX(to: 1, duration: halfDuration)
            newNode.xScale = 0.001
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionPrimingDelay) {
            currentNode.run(shrink) {
                currentNode.isHidden = true
                newNode.isHidden = false
                newNode.run(grow)
            }
        }
    }

    private func scheduleTransitionCleanup(duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cleanupDelay(forTransitionDuration: duration)) { [weak self] in
            HypeLogger.shared.info("Transition complete — hiding SKView, resuming draw()", source: "Transition")
            self?.isTransitioning = false
            self?.cardSKView?.isHidden = true
            self?.cardScene = nil
            self?.needsDisplay = true
        }
    }

    /// Convert a HyperCard-style VisualEffect into an SKTransition.
    static func skTransition(for effect: HypeCore.VisualEffect, duration: TimeInterval) -> SKTransition {
        switch effect {
        case .dissolve, .crossFade:
            return SKTransition.crossFade(withDuration: duration)
        case .fade:
            return SKTransition.fade(withDuration: duration)
        case .wipeLeft:
            return SKTransition.reveal(with: .left, duration: duration)
        case .wipeRight:
            return SKTransition.reveal(with: .right, duration: duration)
        case .wipeUp:
            return SKTransition.reveal(with: .up, duration: duration)
        case .wipeDown:
            return SKTransition.reveal(with: .down, duration: duration)
        case .irisOpen, .irisClose, .doorway:
            return SKTransition.doorway(withDuration: duration)
        case .scrollLeft, .pushLeft:
            return SKTransition.push(with: .left, duration: duration)
        case .scrollRight, .pushRight:
            return SKTransition.push(with: .right, duration: duration)
        case .scrollUp, .pushUp:
            return SKTransition.push(with: .up, duration: duration)
        case .scrollDown, .pushDown:
            return SKTransition.push(with: .down, duration: duration)
        case .moveInLeft:
            return SKTransition.moveIn(with: .left, duration: duration)
        case .moveInRight:
            return SKTransition.moveIn(with: .right, duration: duration)
        case .moveInUp:
            return SKTransition.moveIn(with: .up, duration: duration)
        case .moveInDown:
            return SKTransition.moveIn(with: .down, duration: duration)
        case .revealLeft:
            return SKTransition.reveal(with: .left, duration: duration)
        case .revealRight:
            return SKTransition.reveal(with: .right, duration: duration)
        case .revealUp:
            return SKTransition.reveal(with: .up, duration: duration)
        case .revealDown:
            return SKTransition.reveal(with: .down, duration: duration)
        case .flipHorizontal:
            return SKTransition.flipHorizontal(withDuration: duration)
        case .flipVertical:
            return SKTransition.flipVertical(withDuration: duration)
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
            if let mouseMovedTrackingArea {
                removeTrackingArea(mouseMovedTrackingArea)
                self.mouseMovedTrackingArea = nil
            }
            removeAllToolTips()
            toolTipTagToPartId.removeAll()
            registeredToolTipDescriptors.removeAll()
            activeCursorDescriptor = nil
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
        addCursorRect(bounds, cursor: cursor(for: cursorDescriptorForCurrentTool()))
    }

    // MARK: - Tracking areas for mouseMoved

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseMovedTrackingArea {
            removeTrackingArea(mouseMovedTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        mouseMovedTrackingArea = trackingArea
        startIdleTimer()
    }

    override func mouseEntered(with event: NSEvent) {
        activeCursorDescriptor = nil
        updateCursor(at: flippedPoint(for: event))
    }

    override func mouseExited(with event: NSEvent) {
        activeCursorDescriptor = nil
        if let oldId = hoveredPartId {
            hoveredPartId = nil
            coordinator?.dispatchMessage("mouseLeave", to: oldId)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = flippedPoint(for: event)
        updateCursor(at: point)
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

    // MARK: - Object Palette Dragging

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updatePaletteDrag(from: sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updatePaletteDrag(from: sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        paletteDragTool = nil
        paletteDragPoint = nil
        activeGuides = []
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.paletteTool(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let tool = Self.paletteTool(from: sender.draggingPasteboard) else {
            return false
        }
        let point = convert(sender.draggingLocation, from: nil)
        _ = commitCreationTool(
            tool,
            dragStart: nil,
            at: point,
            modifierFlags: NSEvent.modifierFlags,
            mode: .replaceSelectionAndSelectTool
        )
        paletteDragTool = nil
        paletteDragPoint = nil
        activeGuides = []
        needsDisplay = true
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        paletteDragTool = nil
        paletteDragPoint = nil
        activeGuides = []
        needsDisplay = true
    }

    private func updatePaletteDrag(from sender: NSDraggingInfo) -> Bool {
        guard let tool = Self.paletteTool(from: sender.draggingPasteboard),
              let toolSpec = PartCreationDefaults.toolSpec(for: tool.rawValue) else {
            return false
        }
        let point = convert(sender.draggingLocation, from: nil)
        let fineControl = NSEvent.modifierFlags.contains(.shift)
        let smartSpacing = NSEvent.modifierFlags.contains(.option)
        let rect = PartCreationDefaults.creationRect(
            for: toolSpec.partType,
            dragStart: nil,
            currentPoint: point,
            fineControl: fineControl
        )
        paletteDragTool = tool
        paletteDragPoint = point
        activeGuides = creationSnap(
            for: rect,
            partType: toolSpec.partType,
            fineControl: fineControl,
            smartSpacing: smartSpacing
        ).guides
        needsDisplay = true
        return true
    }

    static func paletteTool(from pasteboard: NSPasteboard) -> ToolName? {
        for type in objectToolPasteboardTypes {
            guard let payload = pasteboard.string(forType: type),
                  let tool = ObjectToolCatalog.toolName(fromDragPayload: payload) else {
                continue
            }
            return tool
        }
        return nil
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        endMusicControlDrag()

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
                persistPaintLayerForCurrentCard()
            case .spray:
                let pl = paintLayerForCurrentCard()
                pl.spray(cx: x, cy: y, radius: sprayRadius, density: max(10, sprayRadius * 2), color: paintColor)
                persistPaintLayerForCurrentCard()
            case .eraser:
                let pl = paintLayerForCurrentCard()
                pl.erase(cx: x, cy: y, radius: eraserRadius)
                persistPaintLayerForCurrentCard()
            case .bucket:
                let pl = paintLayerForCurrentCard()
                pl.floodFill(x: x, y: y, color: paintColor)
                persistPaintLayerForCurrentCard()
            default:
                break
            }

            dragStart = point
            isDragging = true
            needsDisplay = true
            return
        }

        let rawHitPart = renderer.partAtPoint(point, document: document, cardId: currentCardId)

        let toolCheck = ToolState(currentTool: currentTool.rawValue)

        // Filter hit parts only for edit-mode authoring. Browse mode must hit
        // the topmost visible card or background part so background controls
        // remain playable after switching to runtime mode.
        let hitPart: Part?
        if toolCheck.category == .browse {
            hitPart = rawHitPart
        } else if let part = rawHitPart {
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

        // Control+Option+click creates explicit layout constraints. Plain
        // Option is reserved for smart-spacing affinity during ordinary drags.
        if event.modifierFlags.contains(.option),
           event.modifierFlags.contains(.control),
           let part = hitPart {
            isConstraintDragging = true
            constraintSourcePartId = part.id
            constraintSourceEdge = nearestEdge(of: part, to: point)
            constraintDragEnd = point
            dragStart = point
            needsDisplay = true
            return
        }

        // Authoring-only Browse shortcuts are disabled when the stack is in
        // runtime mode. Runtime mode still uses the Browse tool for interaction,
        // but double-clicks and Cmd-clicks must stay available to the stack.
        let authoringBrowseMode = toolCheck.category == .browse && !document.stack.runtimeModeEnabled

        // Double-click on a part in authoring Browse mode → dispatch message and open properties
        // Cmd+click in authoring Browse mode: open script editor for the
        // topmost part under the cursor, regardless of editing
        // mode. Uses rawHitPart (not the editing-mode-filtered
        // hitPart) so background parts are reachable even when
        // not in background-edit mode. If no part is hit, opens
        // the card's script editor.
        if authoringBrowseMode && event.modifierFlags.contains(.command) {
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

        if event.clickCount == 2 && authoringBrowseMode, let part = hitPart {
            coordinator?.dispatchMessage("mouseDoubleClick", to: part.id)
            NotificationCenter.default.post(name: .editPartProperties, object: part.id)
            return
        }

        var toolState = ToolState(currentTool: currentTool.rawValue)
        toolState.selectedPartId = selectedPartIds.first

        // Handle select tool directly for cleaner click-vs-marquee logic
        if currentTool == .select {
            // Check resize handle first. A grouped selection counts
            // as one resizable unit even though selectedPartIds
            // contains every member.
            if let unit = singleResizableSelectionUnit() {
                let handle = hitTestResizeHandle(point)
                if handle != .none {
                    resizeHandle = handle
                    dragStart = point
                    draggedPartId = unit.ids.first
                    dragInitialBounds = unit.bounds
                    appliedDragTranslation = .zero
                    return
                }
            }

            if let part = hitPart {
                // Clicked ON a part — select it and prepare for drag.
                //
                // Modifier semantics:
                // - Shift+click: extend the selection (toggle on/off).
                //   This was the original modifier and stays for users
                //   trained on it.
                // - Cmd+click: same behavior. macOS users overwhelmingly
                //   reach for Cmd to toggle individual items in finder /
                //   table / canvas selection contexts; honoring it as a
                //   parallel modifier matches the platform convention.
                // - No modifier: replace the selection with this part,
                //   unless it's already part of the current selection
                //   (so dragging a member doesn't collapse a multi-select
                //   to one).
                let toggleSelection = event.modifierFlags.contains(.shift)
                    || event.modifierFlags.contains(.command)
                if toggleSelection {
                    if selectedPartIds.contains(part.id) {
                        coordinator?.removeFromSelection(part.id)
                        selectedPartIds.subtract(document.expandedGroupSelection([part.id]))
                    } else {
                        coordinator?.addToSelection(part.id)
                        selectedPartIds.formUnion(document.expandedGroupSelection([part.id]))
                    }
                } else if !selectedPartIds.contains(part.id) {
                    coordinator?.selectPart(part.id)
                    selectedPartIds = document.expandedGroupSelection([part.id])
                }
                resizeHandle = .none
                draggedPartId = part.id
                dragStart = point
                let prospectiveSelection = selectedPartIds.contains(part.id)
                    ? selectedPartIds
                    : document.expandedGroupSelection([part.id])
                dragInitialBounds = selectionBounds(for: prospectiveSelection)
                appliedDragTranslation = .zero
            } else {
                // Clicked on EMPTY space — start marquee selection
                coordinator?.selectPart(nil)
                selectedPartIds = []
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
            selectedPartIds = document.expandedGroupSelection([id])
            resizeHandle = .none
            draggedPartId = id
            dragStart = point
            dragInitialBounds = selectionBounds(for: [id])
            appliedDragTranslation = .zero
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
            if let part = document.parts.first(where: { $0.id == partId }) {
                let request = performDefaultMusicControlAction(for: part, at: point)
                beginMusicControlDragIfNeeded(part: part, request: request, at: point)
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
                Task { @MainActor in
                    guard let self = self, let pid = self.mouseStillDownPartId else { return }
                    self.coordinator?.dispatchMessage("mouseStillDown", to: pid)
                }
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
            default:
                break
            }

            needsDisplay = true
            return
        }

        if performDraggedMusicControlAction(at: point) {
            return
        }

        let fineControl = event.modifierFlags.contains(.shift)
        let smartSpacing = event.modifierFlags.contains(.option)

        if let partId = draggedPartId, let start = dragStart {
            let dx = Double(point.x - start.x)
            let dy = Double(point.y - start.y)
            let expandedSelection = document.expandedGroupSelection(selectedPartIds)
            if resizeHandle != .none, let unit = singleResizableSelectionUnit() {
                // Resize the selected unit. For groups, every member scales
                // proportionally inside the group bounds.
                coordinator?.beginCoalescedCanvasMutation(actionName: "Resize Objects")
                let originalBounds = dragInitialBounds ?? unit.bounds
                let currentBounds = unit.bounds
                var newBounds = resizedBounds(originalBounds, handle: resizeHandle, dx: dx, dy: dy)
                let otherParts = allOtherParts(excluding: unit.ids)
                let proposedPart = proxyPart(for: newBounds)
                let snap = alignmentEngine.computeResizeSnap(
                    resizingPart: proposedPart,
                    otherParts: otherParts,
                    canvasWidth: Double(bounds.width),
                    canvasHeight: Double(bounds.height),
                    fineControl: fineControl
                )
                newBounds = applyingResizeSnap(to: newBounds, handle: resizeHandle, dw: snap.dw, dh: snap.dh)
                activeGuides = snap.guides
                if let coordinator {
                    coordinator.performContinuousCanvasMutation {
                        coordinator.resizeParts(ids: unit.ids, from: currentBounds, to: newBounds)
                    }
                }
            } else if expandedSelection.contains(partId) {
                let units = currentSelectionUnits()
                let movingIds = units.count == 1 ? (units.first?.ids ?? expandedSelection) : expandedSelection
                let originalBounds = dragInitialBounds
                    ?? selectionBounds(for: movingIds)
                    ?? (units.first?.bounds)
                if let originalBounds {
                    coordinator?.beginCoalescedCanvasMutation(actionName: "Move Objects")
                    let otherParts = allOtherParts(excluding: movingIds)
                    var proposedPart = proxyPart(for: originalBounds)
                    proposedPart.left += dx
                    proposedPart.top += dy
                    let snap = alignmentEngine.computeMoveSnap(
                        movingPart: proposedPart,
                        otherParts: otherParts,
                        canvasWidth: Double(bounds.width),
                        canvasHeight: Double(bounds.height),
                        fineControl: fineControl,
                        smartSpacing: smartSpacing
                    )
                    let targetDx = dx + snap.dx
                    let targetDy = dy + snap.dy
                    let incrementalDx = targetDx - Double(appliedDragTranslation.width)
                    let incrementalDy = targetDy - Double(appliedDragTranslation.height)
                    activeGuides = snap.guides
                    if let coordinator, abs(incrementalDx) > 0.0001 || abs(incrementalDy) > 0.0001 {
                        coordinator.performContinuousCanvasMutation {
                            coordinator.moveParts(ids: movingIds, dx: incrementalDx, dy: incrementalDy)
                        }
                        appliedDragTranslation = CGSize(width: targetDx, height: targetDy)
                    }
                }
            } else {
                coordinator?.beginCoalescedCanvasMutation(actionName: "Move Object")
                if let coordinator {
                    coordinator.performContinuousCanvasMutation {
                        coordinator.movePart(id: partId, dx: dx, dy: dy)
                    }
                }
                activeGuides = []
            }
            needsDisplay = true
        } else if isDragging {
            dragCurrent = point
            if let toolSpec = PartCreationDefaults.toolSpec(for: currentTool.rawValue), let start = dragStart {
                let rect = PartCreationDefaults.creationRect(
                    for: toolSpec.partType,
                    dragStart: start,
                    currentPoint: point,
                    fineControl: fineControl
                )
                activeGuides = creationSnap(for: rect, partType: toolSpec.partType, fineControl: fineControl, smartSpacing: smartSpacing).guides
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Cancel mouseStillDown timer
        mouseStillDownTimer?.invalidate()
        mouseStillDownTimer = nil
        mouseStillDownPartId = nil
        endMusicControlDrag()

        let point = flippedPoint(for: event)

        // Handle constraint drag completion
        if isConstraintDragging {
            completeConstraintDrag(at: point)
            isConstraintDragging = false
            constraintSourcePartId = nil
            constraintSourceEdge = nil
            constraintDragEnd = nil
            dragStart = nil
            dragInitialBounds = nil
            appliedDragTranslation = .zero
            needsDisplay = true
            return
        }

        // Handle paint tool mouseUp. Object creation is owned by
        // canonical edit tools; paint tools mutate only the paint layer.
        if isDragging && ToolState(currentTool: currentTool.rawValue).category == .paint {
            switch currentTool {
            case .pencil:
                lastPencilPoint = nil
                persistPaintLayerForCurrentCard()

            case .spray, .eraser, .bucket:
                persistPaintLayerForCurrentCard()

            default:
                break
            }

            isDragging = false
            dragStart = nil
            dragCurrent = nil
            dragInitialBounds = nil
            appliedDragTranslation = .zero
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
            dragInitialBounds = nil
            appliedDragTranslation = .zero
            needsDisplay = true
            return
        }

        if draggedPartId != nil {
            coordinator?.endCoalescedCanvasMutation(
                actionName: resizeHandle == .none ? "Move Objects" : "Resize Objects"
            )
            draggedPartId = nil
            dragStart = nil
            dragInitialBounds = nil
            appliedDragTranslation = .zero
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
                // Auto-hilite for buttons: checkboxes and toggles
                // flip hilite on click. (`.switch` was removed — it
                // was a duplicate of `.toggle`; old docs migrate to
                // `.toggle` via `ButtonStyle.resolved(rawOrAlias:)`.)
                if part.partType == .button {
                    switch part.buttonStyle {
                    case .checkBox, .toggle:
                        coordinator?.togglePartHilite(id: part.id)
                    case .link:
                        // Link-style buttons open Part.url with a
                        // scheme allowlist (http / https / mailto).
                        // Same security guard the dedicated
                        // `LinkHostNSView` enforced before the
                        // dedup migration. The mouseUp script (if
                        // any) still dispatches afterwards.
                        let urlString = part.url
                        if !urlString.isEmpty,
                           let url = URL(string: urlString),
                           let scheme = url.scheme?.lowercased(),
                           ["http", "https", "mailto"].contains(scheme) {
                            NSWorkspace.shared.open(url)
                        }
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
        let result = mouseHandler.handleMouseUp(
            tool: toolState,
            hitPart: hitPart,
            dragStart: cgDragStart,
            point: point,
            fineControl: event.modifierFlags.contains(.shift)
        )

        switch result {
        case .createPart(_, _, _):
            let rapidPlacement = event.modifierFlags.contains(.shift)
                && !isExplicitCreationDrag(from: dragStart, to: point)
            _ = commitCreationTool(
                currentTool,
                dragStart: dragStart,
                at: point,
                modifierFlags: event.modifierFlags,
                mode: rapidPlacement ? .appendSelectionKeepPlacementTool : .replaceSelectionAndSelectTool
            )
        case .sendMessage(let partId, let message):
            coordinator?.dispatchMessage(message, to: partId)
        default:
            break
        }

        // Reset drag state
        isDragging = false
        dragStart = nil
        dragCurrent = nil
        dragInitialBounds = nil
        appliedDragTranslation = .zero
        activeGuides = []
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

    // MARK: - Calendar View Management

    /// Create, update, or remove NSDatePicker hosts for calendar
    /// parts on the current card. Mirrors the chart-view pattern:
    /// the live AppKit picker shows in browse mode, the CG
    /// `CalendarRenderer` placeholder shows in edit mode.
    private func updateCalendarViews() {
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
        let calendarParts = allParts.filter { $0.partType == .calendar && $0.visible }

        // In edit mode or no calendar parts, hide all live pickers.
        if !isBrowseMode || calendarParts.isEmpty {
            for (_, view) in calendarViews {
                view.removeFromSuperview()
            }
            calendarViews.removeAll()
            return
        }

        var activeIds = Set<UUID>()

        for part in calendarParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = calendarViews[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part)
                continue
            }

            // First-time create.
            let host = CalendarHostNSView(frame: frame)
            host.apply(part)
            // Wire date-change writeback into the live document so
            // HypeTalk reads of `the selectedDate of calendar "X"`
            // reflect the user's interactive choice.
            let partId = part.id
            host.onDateChange = { [weak self] iso in
                guard let self = self else { return }
                self.coordinator?.setPartCalendarDate(id: partId, isoDate: iso)
            }
            addSubview(host, positioned: .above, relativeTo: nil)
            calendarViews[part.id] = host
        }

        for id in calendarViews.keys where !activeIds.contains(id) {
            calendarViews[id]?.removeFromSuperview()
            calendarViews.removeValue(forKey: id)
        }
    }

    // MARK: - PDF View Management

    /// Create, update, or remove `PDFView` hosts for `pdf` parts.
    /// Same lifecycle as charts/calendars — live in browse mode,
    /// placeholder via `PDFRenderer` in edit mode.
    private func updatePDFViews() {
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
        let pdfParts = allParts.filter { $0.partType == .pdf && $0.visible }

        if !isBrowseMode || pdfParts.isEmpty {
            for (_, view) in pdfViews { view.removeFromSuperview() }
            pdfViews.removeAll()
            loadedPDFURLs.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in pdfParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = pdfViews[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part)
                continue
            }
            let host = PDFHostNSView(frame: frame)
            host.apply(part)
            addSubview(host, positioned: .above, relativeTo: nil)
            pdfViews[part.id] = host
        }
        for id in pdfViews.keys where !activeIds.contains(id) {
            pdfViews[id]?.removeFromSuperview()
            pdfViews.removeValue(forKey: id)
            loadedPDFURLs.removeValue(forKey: id)
        }
    }

    // MARK: - Per-part tooltip registration

    /// Re-register the system tooltip rects for every visible part
    /// with a non-empty `helpText`. Runs in browse mode only —
    /// edit-mode authors don't want hover bubbles competing with
    /// the click-to-select interaction. Called from `draw(_:)`
    /// after layout is settled.
    ///
    /// Tooltip registration is intentionally stable. Removing and
    /// re-adding the same tooltip rects on every draw resets AppKit's
    /// hover timers and makes bubbles feel intermittent during card
    /// navigation. We rebuild only when the set of tooltip-owning
    /// parts or their geometry changes.
    ///
    /// Z-order note: when two parts overlap, NSView resolves the
    /// hover to the most recently registered tooltip rect. We add
    /// background parts first, then card parts, each in document
    /// order, so the same topmost part wins as `CardRenderer`.
    private func updatePartToolTips() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let nextDescriptors = Self.toolTipDescriptors(
            in: document,
            currentCardId: currentCardId,
            isBrowseMode: toolState.category == .browse
        )

        guard nextDescriptors != registeredToolTipDescriptors else { return }

        removeAllToolTips()
        toolTipTagToPartId.removeAll()
        registeredToolTipDescriptors = nextDescriptors

        for descriptor in nextDescriptors {
            let tag = addToolTip(descriptor.rect, owner: self, userData: nil)
            toolTipTagToPartId[tag] = descriptor.partId
        }
    }

    static func toolTipDescriptors(
        in document: HypeDocument,
        currentCardId: UUID,
        isBrowseMode: Bool
    ) -> [ToolTipDescriptor] {
        guard isBrowseMode else { return [] }

        return tooltipRegistrationParts(in: document, currentCardId: currentCardId)
            .compactMap { part in
                guard part.visible,
                      !part.helpText.isEmpty,
                      part.width > 0,
                      part.height > 0
                else { return nil }

                return ToolTipDescriptor(
                    partId: part.id,
                    rect: NSRect(
                        x: part.left,
                        y: part.top,
                        width: part.width,
                        height: part.height
                    )
                )
            }
    }

    static func tooltipRegistrationParts(in document: HypeDocument, currentCardId: UUID) -> [Part] {
        let cardParts = document.partsForCard(currentCardId)
        guard let card = document.cards.first(where: { $0.id == currentCardId }) else {
            return cardParts
        }
        return document.partsForBackground(card.backgroundId) + cardParts
    }

    /// `NSToolTipOwner`-style callback. NSView calls this when the
    /// user has hovered long enough to show a tooltip; we look up
    /// the part via the tag we recorded in `updatePartToolTips`
    /// and return its current `helpText`. The fresh lookup means
    /// the displayed text is always whatever the part has stored
    /// RIGHT NOW, even if the author edited the field while the
    /// bubble was already on screen.
    @objc func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData: UnsafeMutableRawPointer?
    ) -> String {
        guard let partId = toolTipTagToPartId[tag],
              let part = document.parts.first(where: { $0.id == partId })
        else { return "" }
        return part.helpText
    }

    // MARK: - Map View Management

    /// Create, update, or remove `MKMapView` hosts for `map` parts.
    private func updateMapViews() {
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
        let mapParts = allParts.filter { $0.partType == .map && $0.visible }

        if !isBrowseMode || mapParts.isEmpty {
            for (_, view) in mapViews { view.removeFromSuperview() }
            mapViews.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in mapParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = mapViews[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part)
                continue
            }
            let host = MapHostNSView(frame: frame)
            host.apply(part)
            // Geocoding moved out of the host into
            // `MapLocationGeocoder` (driven by
            // `Coordinator.reconcileMapLocations` from updateNSView),
            // so the old `onLocationResolved` callback is gone — the
            // service writes resolved coords directly into the doc
            // and the host picks them up on its next apply().
            addSubview(host, positioned: .above, relativeTo: nil)
            mapViews[part.id] = host
        }
        for id in mapViews.keys where !activeIds.contains(id) {
            mapViews[id]?.removeFromSuperview()
            mapViews.removeValue(forKey: id)
        }
    }

    // MARK: - Color Well View Management

    /// Create, update, or remove `NSColorWell` hosts for
    /// `colorWell` parts. Color picks fire back through the
    /// coordinator so HypeTalk reads see the new value
    /// immediately and `colorChanged` messages dispatch on the
    /// part.
    private func updateColorWellViews() {
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
        let cwParts = allParts.filter { $0.partType == .colorWell && $0.visible }

        if !isBrowseMode || cwParts.isEmpty {
            for (_, view) in colorWellViews { view.removeFromSuperview() }
            colorWellViews.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in cwParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = colorWellViews[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part)
                continue
            }
            let host = ColorWellHostNSView(frame: frame)
            host.apply(part)
            let partId = part.id
            host.onColorChange = { [weak self] hex in
                guard let self = self else { return }
                self.coordinator?.setPartColorWellHex(id: partId, hex: hex)
            }
            addSubview(host, positioned: .above, relativeTo: nil)
            colorWellViews[part.id] = host
        }
        for id in colorWellViews.keys where !activeIds.contains(id) {
            colorWellViews[id]?.removeFromSuperview()
            colorWellViews.removeValue(forKey: id)
        }
    }

    // MARK: - Form Control View Management

    /// Create, update, or remove the four form-control hosts
    /// (stepper, slider, toggle, segmented) on the current card.
    /// Each routes user value-changes through the coordinator
    /// writeback so HypeTalk reads of `the value of slider "X"`
    /// reflect what's on screen, and the `valueChanged` /
    /// `selectionChanged` HypeTalk messages dispatch on the part.
    private func updateFormControlViews() {
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

        // Helper to clear-and-skip when the user is in edit mode.
        func clearAll() {
            for (_, v) in stepperViews { v.removeFromSuperview() }
            for (_, v) in sliderViews { v.removeFromSuperview() }
            for (_, v) in segmentedViews { v.removeFromSuperview() }
            stepperViews.removeAll()
            sliderViews.removeAll()
            segmentedViews.removeAll()
        }

        let formParts = allParts.filter {
            ($0.partType == .stepper || $0.partType == .slider || $0.partType == .segmented) && $0.visible
        }
        if !isBrowseMode || formParts.isEmpty {
            clearAll()
            return
        }

        var activeStepper = Set<UUID>()
        var activeSlider = Set<UUID>()
        var activeSegmented = Set<UUID>()

        for part in formParts {
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
            let partId = part.id

            switch part.partType {
            case .stepper:
                activeStepper.insert(partId)
                if let existing = stepperViews[partId] {
                    existing.isHidden = false
                    existing.frame = frame
                    existing.apply(part)
                } else {
                    let host = StepperHostNSView(frame: frame)
                    host.apply(part)
                    host.onValueChange = { [weak self] v in
                        self?.coordinator?.setPartControlValue(id: partId, value: v, message: "valueChanged")
                    }
                    addSubview(host, positioned: .above, relativeTo: nil)
                    stepperViews[partId] = host
                }
            case .slider:
                activeSlider.insert(partId)
                if let existing = sliderViews[partId] {
                    existing.isHidden = false
                    existing.frame = frame
                    existing.apply(part)
                } else {
                    let host = SliderHostNSView(frame: frame)
                    host.apply(part)
                    host.onValueChange = { [weak self] v in
                        self?.coordinator?.setPartControlValue(id: partId, value: v, message: "valueChanged")
                    }
                    addSubview(host, positioned: .above, relativeTo: nil)
                    sliderViews[partId] = host
                }
            case .segmented:
                activeSegmented.insert(partId)
                if let existing = segmentedViews[partId] {
                    existing.isHidden = false
                    existing.frame = frame
                    existing.apply(part)
                } else {
                    let host = SegmentedHostNSView(frame: frame)
                    host.apply(part)
                    host.onValueChange = { [weak self] idx in
                        self?.coordinator?.setPartControlValue(id: partId, value: Double(idx), message: "selectionChanged")
                    }
                    addSubview(host, positioned: .above, relativeTo: nil)
                    segmentedViews[partId] = host
                }
            default:
                break
            }
        }

        // Cleanup orphans.
        for id in stepperViews.keys where !activeStepper.contains(id) {
            stepperViews[id]?.removeFromSuperview()
            stepperViews.removeValue(forKey: id)
        }
        for id in sliderViews.keys where !activeSlider.contains(id) {
            sliderViews[id]?.removeFromSuperview()
            sliderViews.removeValue(forKey: id)
        }
        for id in segmentedViews.keys where !activeSegmented.contains(id) {
            segmentedViews[id]?.removeFromSuperview()
            segmentedViews.removeValue(forKey: id)
        }
    }

    // MARK: - Apple Music Browser Management

    /// Create, update, or remove live MusicKit Search hosts. The CG renderer
    /// still draws edit-mode placeholders; in browse mode this host supplies
    /// the actual search/select/play/seek UI and writes stable metadata back
    /// into the stack document.
    private func updateAppleMusicBrowserViews() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseMode = toolState.category == .browse

        let allParts = partsForCurrentCard()
        let browserParts = allParts.filter { $0.partType == .appleMusicBrowser && $0.visible }

        if !isBrowseMode || browserParts.isEmpty {
            for (_, view) in appleMusicBrowserViews { view.removeFromSuperview() }
            appleMusicBrowserViews.removeAll()
            return
        }

        let preferencesAllowAppleMusic = UserDefaults.standard.bool(forKey: AppleMusicConfiguration.enabledKey)
        var activeIds = Set<UUID>()
        for part in browserParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
            let partId = part.id
            let host: AppleMusicBrowserHostNSView
            if let existing = appleMusicBrowserViews[partId] {
                existing.isHidden = false
                existing.frame = frame
                host = existing
            } else {
                let created = AppleMusicBrowserHostNSView(frame: frame)
                created.onSearchConfigurationChange = { [weak self] term, scope, kind in
                    self?.coordinator?.setPartAppleMusicSearchConfiguration(
                        id: partId,
                        term: term,
                        scope: scope,
                        itemType: kind
                    )
                }
                created.onSelectionChange = { [weak self] item in
                    self?.coordinator?.setPartAppleMusicSelection(id: partId, item: item)
                }
                created.onPlaybackPositionChange = { [weak self] position in
                    self?.coordinator?.setPartAppleMusicPosition(id: partId, position: position)
                }
                created.onPlaybackEvent = { [weak self] message, params in
                    self?.coordinator?.dispatchAppleMusicBrowserEvent(id: partId, message: message, params: params)
                }
                addSubview(created, positioned: .above, relativeTo: nil)
                appleMusicBrowserViews[partId] = created
                host = created
            }
            host.apply(
                part: part,
                stackAllowsAppleMusic: document.stack.appleMusicAllowed,
                preferencesAllowAppleMusic: preferencesAllowAppleMusic
            )
        }

        for id in appleMusicBrowserViews.keys where !activeIds.contains(id) {
            appleMusicBrowserViews[id]?.removeFromSuperview()
            appleMusicBrowserViews.removeValue(forKey: id)
        }
    }

    // MARK: - Music Instrument Popup Management

    /// Creates live instrument popups only when piano-keyboard or step-sequencer
    /// parts opt into showing them. The playable surfaces remain
    /// CGContext-rendered and route note playback through the existing
    /// browse-mode music-control path.
    private func updateMusicInstrumentPopupViews() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseMode = toolState.category == .browse

        let allParts = partsForCurrentCard()
        let popupParts = allParts.filter {
            ($0.partType == .pianoKeyboard || $0.partType == .stepSequencer) && $0.visible && $0.musicShowInstrument
        }

        if !isBrowseMode || popupParts.isEmpty {
            for (_, view) in musicInstrumentPopupViews { view.removeFromSuperview() }
            musicInstrumentPopupViews.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in popupParts {
            activeIds.insert(part.id)
            let frame = MusicControlInteraction.musicInstrumentPopupRect(for: part)
            guard !frame.isEmpty else { continue }
            let partId = part.id
            let host: MusicInstrumentPopupHostNSView
            if let existing = musicInstrumentPopupViews[partId] {
                existing.isHidden = false
                existing.frame = frame
                host = existing
            } else {
                let created = MusicInstrumentPopupHostNSView(frame: frame)
                created.onInstrumentChange = { [weak self] instrument in
                    self?.coordinator?.setPartMusicInstrumentName(id: partId, instrument: instrument)
                }
                addSubview(created, positioned: .above, relativeTo: nil)
                musicInstrumentPopupViews[partId] = created
                host = created
            }
            host.apply(part: part)
        }

        for id in musicInstrumentPopupViews.keys where !activeIds.contains(id) {
            musicInstrumentPopupViews[id]?.removeFromSuperview()
            musicInstrumentPopupViews.removeValue(forKey: id)
        }
    }

    // MARK: - Audio Recorder View Management

    /// Create, update, or remove `AudioRecorderHostNSView`s for
    /// `audioRecorder` parts. The host owns the AVAudioRecorder
    /// engine; setting the part's `audioRecording` flag to true
    /// flips the host into recording mode.
    private func updateAudioRecorderViews() {
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
        let recorderParts = allParts.filter { $0.partType == .audioRecorder && $0.visible }

        if !isBrowseMode || recorderParts.isEmpty {
            for (_, view) in audioRecorderViews {
                view.stop()
                view.removeFromSuperview()
            }
            audioRecorderViews.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in recorderParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = audioRecorderViews[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part)
                continue
            }
            let host = AudioRecorderHostNSView(frame: frame)
            host.apply(part)
            let partId = part.id
            host.onStateChange = { [weak self] recording, playing, duration, outputPath, embeddedData in
                self?.coordinator?.setPartAudioRecorderState(
                    id: partId,
                    recording: recording,
                    playing: playing,
                    duration: duration,
                    outputPath: outputPath,
                    embeddedData: embeddedData
                )
            }
            addSubview(host, positioned: .above, relativeTo: nil)
            audioRecorderViews[part.id] = host
        }
        for id in audioRecorderViews.keys where !activeIds.contains(id) {
            audioRecorderViews[id]?.stop()
            audioRecorderViews[id]?.removeFromSuperview()
            audioRecorderViews.removeValue(forKey: id)
        }
    }

    // MARK: - Scene3D View Management

    /// Create, update, or remove `SCNView` hosts for `scene3D` parts.
    private func updateScene3DViews() {
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
        let parts3D = allParts.filter { $0.partType == .scene3D && $0.visible }

        if !isBrowseMode || parts3D.isEmpty {
            for (_, view) in scene3DViews { view.removeFromSuperview() }
            scene3DViews.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in parts3D {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)

            if let existing = scene3DViews[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part, repository: document.spriteRepository)
                continue
            }
            let host = Scene3DHostNSView(frame: frame)
            let partId = part.id
            host.onLoadFailed = { [weak self] reason in
                self?.coordinator?.dispatchScene3DLoadFailed(id: partId, reason: reason)
            }
            host.apply(part, repository: document.spriteRepository)
            addSubview(host, positioned: .above, relativeTo: nil)
            scene3DViews[part.id] = host
        }
        for id in scene3DViews.keys where !activeIds.contains(id) {
            scene3DViews[id]?.removeFromSuperview()
            scene3DViews.removeValue(forKey: id)
        }
    }

    // MARK: - Phase 3 Control View Management

    /// Create, update, or remove `ProgressViewHostNSView`s for `progressView` parts.
    private func updateProgressViewHosts() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseMode = toolState.category == .browse

        let allParts = partsForCurrentCard()
        let typeParts = allParts.filter { $0.partType == .progressView && $0.visible }

        if !isBrowseMode || typeParts.isEmpty {
            for (_, v) in progressViewHosts { v.removeFromSuperview() }
            progressViewHosts.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in typeParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
            if let existing = progressViewHosts[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part)
                continue
            }
            let host = ProgressViewHostNSView(frame: frame)
            host.apply(part)
            let partId = part.id
            host.onProgressFinished = { [weak self] in
                self?.coordinator?.setPartProgressFinished(id: partId)
            }
            addSubview(host, positioned: .above, relativeTo: nil)
            progressViewHosts[part.id] = host
        }
        for id in progressViewHosts.keys where !activeIds.contains(id) {
            progressViewHosts[id]?.removeFromSuperview()
            progressViewHosts.removeValue(forKey: id)
        }
    }

    /// Create, update, or remove `GaugeHostNSView`s for `gauge` parts.
    private func updateGaugeHosts() {
        let toolState = ToolState(currentTool: currentTool.rawValue)
        let isBrowseMode = toolState.category == .browse

        let allParts = partsForCurrentCard()
        let typeParts = allParts.filter { $0.partType == .gauge && $0.visible }

        if !isBrowseMode || typeParts.isEmpty {
            for (_, v) in gaugeHosts { v.removeFromSuperview() }
            gaugeHosts.removeAll()
            return
        }

        var activeIds = Set<UUID>()
        for part in typeParts {
            activeIds.insert(part.id)
            let frame = CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
            if let existing = gaugeHosts[part.id] {
                existing.isHidden = false
                existing.frame = frame
                existing.apply(part)
                continue
            }
            let host = GaugeHostNSView(frame: frame)
            host.apply(part)
            let partId = part.id
            host.onValueChange = { [weak self] v in
                self?.coordinator?.setPartGaugeValue(id: partId, value: v)
            }
            addSubview(host, positioned: .above, relativeTo: nil)
            gaugeHosts[part.id] = host
        }
        for id in gaugeHosts.keys where !activeIds.contains(id) {
            gaugeHosts[id]?.removeFromSuperview()
            gaugeHosts.removeValue(forKey: id)
        }
    }

    // updateLinkHosts / updateMenuHosts / updateSearchFieldHosts removed
    // in dedup. The new home for these controls:
    //   - link → button with ButtonStyle.link (URL open + scheme allowlist
    //     handled in the canvas's mouseUp dispatch)
    //   - menu → button with ButtonStyle.popup (popupItems)
    //   - searchField → field with FieldStyle.search (existing field
    //     overlay handles the input)
    // Old documents migrate at decode time so this code is unreachable.

    /// Helper: all parts visible on the current card + its background.
    private func partsForCurrentCard() -> [Part] {
        let cardParts = document.partsForCard(currentCardId)
        let bgParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            bgParts = document.partsForBackground(card.backgroundId)
        } else {
            bgParts = []
        }
        return cardParts + bgParts
    }

    // MARK: - Sprite View Management

    func releasePartRuntimeResources(partId: UUID) {
        GIFAnimator.shared.remove(partId: partId)

        if let skView = spriteViews[partId] {
            skView.presentScene(nil)
            skView.removeFromSuperview()
        }
        spriteViews.removeValue(forKey: partId)
        spriteScenes.removeValue(forKey: partId)
        spriteBridges.removeValue(forKey: partId)
        loadedSceneSpecs.removeValue(forKey: partId)
        lastSceneMousePosition.removeValue(forKey: partId)
        loadedActiveSceneIDs.removeValue(forKey: partId)
        dispatchedLifecycleSceneIDs.removeValue(forKey: partId)
        pendingSceneLoads = pendingSceneLoads.filter { $0.partId != partId }
        frameUpdateDispatchInFlight.remove(partId)
        frameUpdateDispatchPayloads.removeValue(forKey: partId)
        frameUpdateDispatchSignatures.removeValue(forKey: partId)
        blockedSpriteDispatchSignatures.removeValue(forKey: partId)
    }

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
            dispatchedLifecycleSceneIDs.removeAll()
            pendingSceneLoads.removeAll()
            lastSceneMousePosition.removeAll()
            frameUpdateDispatchInFlight.removeAll()
            frameUpdateDispatchPayloads.removeAll()
            frameUpdateDispatchSignatures.removeAll()
            blockedSpriteDispatchSignatures.removeAll()
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
                refreshFrameUpdateDispatchPayloadIfNeeded(for: part)

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
                        let previousSpec = previousActiveSceneSpec(for: part)
                        let needsRebuild = bridge.applyLiveUpdates(
                            spec: spec,
                            previousSpec: previousSpec,
                            to: scene,
                            repository: document.spriteRepository
                        )
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
                            if let currentSceneId {
                                refreshFrameUpdateDispatchPayload(for: part, sceneId: currentSceneId, scene: spec)
                            }
                        }
                        loadedSceneSpecs[part.id] = part.sceneSpec
                        if let previousSceneId,
                           let currentSceneId,
                           previousSceneId != currentSceneId {
                            scheduleSpriteLifecycleMessagesIfNeeded(partId: part.id, sceneId: currentSceneId)
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
        for id in Array(spriteViews.keys) where !activeIds.contains(id) {
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
            releasePartRuntimeResources(partId: id)
        }
    }

    private func previousActiveSceneSpec(for part: Part) -> SceneSpec? {
        guard let previousJSON = loadedSceneSpecs[part.id] else { return nil }
        let fallbackSize = SizeSpec(width: part.width, height: part.height)
        return SpriteAreaSpec.fromStoredJSON(previousJSON, fallbackSize: fallbackSize)?.activeScene
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
            frameUpdateDispatchPayloads.removeValue(forKey: part.id)
            frameUpdateDispatchSignatures.removeValue(forKey: part.id)
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
        refreshFrameUpdateDispatchPayload(for: part, sceneId: sceneEntry.id, scene: spec)

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

        scheduleSpriteLifecycleMessagesIfNeeded(partId: part.id, sceneId: sceneEntry.id)
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

        return makeSpriteDispatchContext(partId: part.id, sceneId: resolvedSceneId, scene: scene, nodeId: nodeId)
    }

    private func makeSpriteDispatchContext(
        partId: UUID,
        sceneId: UUID,
        scene: SceneSpec,
        nodeId: UUID? = nil
    ) -> (targetId: UUID, context: ScriptDispatchContext) {
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

        hierarchyPrefix.append(sceneId)
        objectScripts[sceneId] = scene.script
        objectDescriptions[sceneId] = "scene \"\(scene.name)\""
        hierarchyPrefix.append(partId)

        let targetId = hierarchyPrefix.first ?? sceneId
        let context = ScriptDispatchContext(
            hierarchyPrefix: hierarchyPrefix,
            objectScripts: objectScripts,
            objectDescriptions: objectDescriptions
        )
        return (targetId, context)
    }

    private func refreshFrameUpdateDispatchPayload(for part: Part, sceneId: UUID, scene: SceneSpec) {
        let payload = makeSpriteDispatchContext(partId: part.id, sceneId: sceneId, scene: scene)
        let signature = frameUpdateDispatchSignature(for: part)
        frameUpdateDispatchPayloads[part.id] = (
            targetId: payload.targetId,
            context: payload.context,
            hasHandler: spriteHierarchyHasHandler(named: "frameUpdate", partId: part.id, scriptContext: payload.context)
        )
        frameUpdateDispatchSignatures[part.id] = signature
        if blockedSpriteDispatchSignatures[part.id] != signature {
            blockedSpriteDispatchSignatures.removeValue(forKey: part.id)
        }
    }

    private func refreshFrameUpdateDispatchPayloadIfNeeded(for part: Part) {
        let signature = frameUpdateDispatchSignature(for: part)
        guard frameUpdateDispatchPayloads[part.id] == nil || frameUpdateDispatchSignatures[part.id] != signature else {
            return
        }
        guard let areaSpec = part.spriteAreaSpecModel,
              let sceneEntry = areaSpec.activeSceneEntry,
              let scene = areaSpec.activeScene else {
            frameUpdateDispatchPayloads.removeValue(forKey: part.id)
            frameUpdateDispatchSignatures.removeValue(forKey: part.id)
            blockedSpriteDispatchSignatures.removeValue(forKey: part.id)
            return
        }
        refreshFrameUpdateDispatchPayload(for: part, sceneId: sceneEntry.id, scene: scene)
    }

    private func frameUpdateDispatchSignature(for part: Part) -> String {
        var pieces = [part.sceneSpec, part.script]
        if let cardId = part.cardId,
           let card = document.cards.first(where: { $0.id == cardId }) {
            pieces.append(card.script)
            if let background = document.backgrounds.first(where: { $0.id == card.backgroundId }) {
                pieces.append(background.script)
            }
        } else if let backgroundId = part.backgroundId,
                  let background = document.backgrounds.first(where: { $0.id == backgroundId }) {
            pieces.append(background.script)
        }
        pieces.append(document.stack.script)
        return pieces.joined(separator: "\u{1F}")
    }

    func blockSpriteDispatch(after error: ScriptError) {
        guard let partId = spriteAreaPartId(forScriptObject: error.objectId),
              let part = document.parts.first(where: { $0.id == partId }) else {
            return
        }
        let signature = frameUpdateDispatchSignature(for: part)
        blockedSpriteDispatchSignatures[partId] = signature
        frameUpdateDispatchInFlight.remove(partId)
        HypeLogger.shared.warn(
            "Disabled SpriteKit event dispatch for sprite area '\(part.name)' after script error in \(error.handler). Edit or rebuild the scene script to resume gameplay dispatch.",
            source: "SpriteKit"
        )
    }

    private func spriteDispatchIsBlocked(for partId: UUID) -> Bool {
        guard let blockedSignature = blockedSpriteDispatchSignatures[partId] else {
            return false
        }
        guard let part = document.parts.first(where: { $0.id == partId }) else {
            blockedSpriteDispatchSignatures.removeValue(forKey: partId)
            return false
        }
        if frameUpdateDispatchSignature(for: part) == blockedSignature {
            return true
        }
        blockedSpriteDispatchSignatures.removeValue(forKey: partId)
        return false
    }

    private func spriteAreaPartId(forScriptObject objectId: UUID?) -> UUID? {
        guard let objectId else { return nil }
        for part in document.parts where part.partType == .spriteArea {
            if part.id == objectId {
                return part.id
            }
            guard let areaSpec = part.spriteAreaSpecModel else { continue }
            if areaSpec.scenes.contains(where: { $0.id == objectId }) {
                return part.id
            }
            if areaSpec.scenes.contains(where: { $0.scene.node(id: objectId) != nil }) {
                return part.id
            }
        }
        return nil
    }

    private func spriteHierarchyHasHandler(
        named handlerName: String,
        partId: UUID,
        scriptContext: ScriptDispatchContext
    ) -> Bool {
        if scriptContext.objectScripts.values.contains(where: { Self.scriptHasHandler($0, named: handlerName) }) {
            return true
        }
        guard let part = document.parts.first(where: { $0.id == partId }) else { return false }
        if Self.scriptHasHandler(part.script, named: handlerName) {
            return true
        }
        if let cardId = part.cardId,
           let card = document.cards.first(where: { $0.id == cardId }) {
            if Self.scriptHasHandler(card.script, named: handlerName) {
                return true
            }
            if let background = document.backgrounds.first(where: { $0.id == card.backgroundId }),
               Self.scriptHasHandler(background.script, named: handlerName) {
                return true
            }
        } else if let backgroundId = part.backgroundId,
                  let background = document.backgrounds.first(where: { $0.id == backgroundId }),
                  Self.scriptHasHandler(background.script, named: handlerName) {
            return true
        }
        return Self.scriptHasHandler(document.stack.script, named: handlerName)
    }

    private func scheduleSpriteLifecycleMessagesIfNeeded(partId: UUID, sceneId: UUID) {
        guard dispatchedLifecycleSceneIDs[partId] != sceneId else { return }
        let key = SpriteLifecycleDispatchKey(partId: partId, sceneId: sceneId)
        guard !pendingSceneLoads.contains(key) else { return }

        dispatchedLifecycleSceneIDs[partId] = sceneId
        pendingSceneLoads.insert(key)

        // Lifecycle handlers can mutate the scene. Defer them until after
        // SpriteKit presentation and gate by scene id so a same-scene rebuild
        // caused by `openScene` does not recursively dispatch `openScene` again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            defer { self.pendingSceneLoads.remove(key) }
            guard self.spriteScenes[partId] != nil,
                  self.loadedActiveSceneIDs[partId] == sceneId else {
                return
            }
            self.dispatchSpriteLifecycleMessages(partId: partId, sceneId: sceneId)
        }
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
        guard let unit = singleResizableSelectionUnit() else {
            return .none
        }

        let handleSize: CGFloat = 10 // slightly larger hit area than visual
        let rect = CGRect(x: unit.bounds.left, y: unit.bounds.top, width: unit.bounds.width, height: unit.bounds.height)

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

    @discardableResult
    func commitCreationTool(
        _ tool: ToolName,
        dragStart: CGPoint? = nil,
        at point: CGPoint,
        modifierFlags: NSEvent.ModifierFlags = [],
        mode: CreationCommitMode = .replaceSelectionAndSelectTool
    ) -> UUID? {
        guard let toolSpec = PartCreationDefaults.toolSpec(for: tool.rawValue) else {
            return nil
        }

        let fineControl = modifierFlags.contains(.shift)
        let smartSpacing = modifierFlags.contains(.option)
        let baseRect = PartCreationDefaults.creationRect(
            for: toolSpec.partType,
            dragStart: dragStart,
            currentPoint: point,
            fineControl: fineControl
        )
        let rect = creationSnap(
            for: baseRect,
            partType: toolSpec.partType,
            fineControl: fineControl,
            smartSpacing: smartSpacing
        ).rect

        var newPart = Part(
            partType: toolSpec.partType,
            cardId: editingBackground ? nil : currentCardId,
            backgroundId: editingBackground ? currentBackgroundId : nil,
            left: rect.origin.x,
            top: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
        newPart.name = "\(toolSpec.partType.rawValue.capitalized) \(allVisibleParts().count + 1)"
        if let shapeTypeStr = toolSpec.extras["shapeType"], let shapeType = ShapeType(rawValue: shapeTypeStr) {
            newPart.shapeType = shapeType
        }
        if toolSpec.partType == .spriteArea {
            let defaultAreaSpec = SpriteAreaSpec(
                defaultSceneNamed: "main",
                fallbackSize: SizeSpec(width: Double(newPart.width), height: Double(newPart.height))
            )
            newPart.setSpriteAreaSpec(defaultAreaSpec)
        }

        coordinator?.addPart(newPart)
        switch mode {
        case .replaceSelectionAndSelectTool:
            coordinator?.selectPart(newPart.id)
        case .appendSelectionKeepPlacementTool:
            coordinator?.addToSelection(newPart.id)
        }
        if let updatedDocument = coordinator?.parent.document.document {
            document = updatedDocument
        }
        switch mode {
        case .replaceSelectionAndSelectTool:
            selectedPartIds = document.expandedGroupSelection([newPart.id])
            currentTool = .select
        case .appendSelectionKeepPlacementTool:
            selectedPartIds.formUnion(document.expandedGroupSelection([newPart.id]))
            currentTool = tool
        }
        activeGuides = []
        if mode == .replaceSelectionAndSelectTool {
            NotificationCenter.default.post(
                name: .selectTool,
                object: ToolName.select,
                userInfo: [ToolSelectionNotification.preserveSelectionUserInfoKey: true]
            )
        }
        return newPart.id
    }

    private func isExplicitCreationDrag(from start: CGPoint?, to point: CGPoint) -> Bool {
        guard let start else { return false }
        let dx = Double(abs(point.x - start.x))
        let dy = Double(abs(point.y - start.y))
        return dx >= LayoutGrid.explicitCreationDragThreshold
            || dy >= LayoutGrid.explicitCreationDragThreshold
    }

    private func creationSnap(
        for rect: CGRect,
        partType: PartType,
        fineControl: Bool,
        smartSpacing: Bool
    ) -> (rect: CGRect, guides: [SnapGuide]) {
        var proposedPart = Part(
            partType: partType,
            cardId: editingBackground ? nil : currentCardId,
            backgroundId: editingBackground ? currentBackgroundId : nil,
            left: rect.origin.x,
            top: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
        proposedPart.textSize = 14
        let snap = alignmentEngine.computeMoveSnap(
            movingPart: proposedPart,
            otherParts: allVisibleParts(),
            canvasWidth: Double(bounds.width),
            canvasHeight: Double(bounds.height),
            fineControl: fineControl,
            smartSpacing: smartSpacing
        )
        var snapped = rect
        snapped.origin.x += snap.dx
        snapped.origin.y += snap.dy
        return (snapped, snap.guides)
    }

    private func snappedCreationRect(
        _ rect: CGRect,
        partType: PartType,
        fineControl: Bool,
        smartSpacing: Bool
    ) -> CGRect {
        creationSnap(
            for: rect,
            partType: partType,
            fineControl: fineControl,
            smartSpacing: smartSpacing
        ).rect
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
            return cardParts.filter { $0.visible }
        }
    }

    /// Get all parts on the current card/background except the one being manipulated.
    private func allOtherParts(excluding partId: UUID) -> [Part] {
        allOtherParts(excluding: [partId])
    }

    /// Get all parts on the current card/background except the parts being manipulated.
    private func allOtherParts(excluding excludedIds: Set<UUID>) -> [Part] {
        let cardParts = document.partsForCard(currentCardId)
        let bgParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            bgParts = document.partsForBackground(card.backgroundId)
        } else {
            bgParts = []
        }
        return (cardParts + bgParts).filter { !excludedIds.contains($0.id) }
    }

    private func selectionBounds(for ids: Set<UUID>) -> PartBounds? {
        PartBounds.union(document.parts.filter { ids.contains($0.id) })
    }

    private func currentSelectionUnits() -> [PartSelectionUnit] {
        document.selectionUnits(for: selectedPartIds)
    }

    private func singleResizableSelectionUnit() -> PartSelectionUnit? {
        let units = currentSelectionUnits()
        return units.count == 1 ? units[0] : nil
    }

    private func resizedBounds(_ bounds: PartBounds, handle: ResizeHandle, dx: Double, dy: Double) -> PartBounds {
        let minSize: Double = 10
        var left = bounds.left
        var top = bounds.top
        var width = bounds.width
        var height = bounds.height

        switch handle {
        case .topLeft:
            let newW = max(minSize, width - dx)
            let newH = max(minSize, height - dy)
            left += width - newW
            top += height - newH
            width = newW
            height = newH
        case .topCenter:
            let newH = max(minSize, height - dy)
            top += height - newH
            height = newH
        case .topRight:
            width = max(minSize, width + dx)
            let newH = max(minSize, height - dy)
            top += height - newH
            height = newH
        case .rightCenter:
            width = max(minSize, width + dx)
        case .bottomRight:
            width = max(minSize, width + dx)
            height = max(minSize, height + dy)
        case .bottomCenter:
            height = max(minSize, height + dy)
        case .bottomLeft:
            let newW = max(minSize, width - dx)
            left += width - newW
            width = newW
            height = max(minSize, height + dy)
        case .leftCenter:
            let newW = max(minSize, width - dx)
            left += width - newW
            width = newW
        case .none:
            break
        }

        return PartBounds(left: left, top: top, width: width, height: height)
    }

    private func applyingResizeSnap(to bounds: PartBounds, handle: ResizeHandle, dw: Double, dh: Double) -> PartBounds {
        var result = bounds

        if handle.affectsWidth, abs(dw) > 0.0001 {
            let right = result.right
            result.width = max(10, result.width + dw)
            if handle.anchorsRightEdge {
                result.left = right - result.width
            }
        }

        if handle.affectsHeight, abs(dh) > 0.0001 {
            let bottom = result.bottom
            result.height = max(10, result.height + dh)
            if handle.anchorsBottomEdge {
                result.top = bottom - result.height
            }
        }

        return result
    }

    private func proxyPart(for bounds: PartBounds) -> Part {
        Part(partType: .shape, cardId: currentCardId, left: bounds.left, top: bounds.top, width: bounds.width, height: bounds.height)
    }

    /// Get or create the paint layer for the current card.
    func paintLayerForCurrentCard() -> PaintLayer {
        if let existing = paintLayers[currentCardId] {
            return existing
        }
        let layer: PaintLayer
        if let persisted = document.paintLayer(forCardId: currentCardId) {
            layer = PaintLayer(snapshot: persisted)
        } else {
            layer = PaintLayer(width: max(1, Int(bounds.width)), height: max(1, Int(bounds.height)))
        }
        paintLayers[currentCardId] = layer
        return layer
    }

    @MainActor
    func persistPaintLayerForCurrentCard() {
        guard let layer = paintLayers[currentCardId] else { return }
        let snapshot = layer.snapshot(cardId: currentCardId)
        if snapshot.isEmpty {
            document.removePaintLayer(forCardId: currentCardId)
            coordinator?.removePaintLayer(cardId: currentCardId)
        } else {
            document.setPaintLayer(snapshot)
            coordinator?.setPaintLayer(snapshot)
        }
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
            case .margin:  color = NSColor.systemOrange.withAlphaComponent(0.5)
            case .baseline: color = NSColor.systemTeal.withAlphaComponent(0.55)
            case .grid:    color = NSColor.systemGray.withAlphaComponent(0.35)
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

private extension CardCanvasNSView.ResizeHandle {
    var affectsWidth: Bool {
        switch self {
        case .topLeft, .topRight, .rightCenter, .bottomRight, .bottomLeft, .leftCenter:
            return true
        case .topCenter, .bottomCenter, .none:
            return false
        }
    }

    var affectsHeight: Bool {
        switch self {
        case .topLeft, .topCenter, .topRight, .bottomRight, .bottomCenter, .bottomLeft:
            return true
        case .rightCenter, .leftCenter, .none:
            return false
        }
    }

    var anchorsRightEdge: Bool {
        switch self {
        case .topLeft, .bottomLeft, .leftCenter:
            return true
        default:
            return false
        }
    }

    var anchorsBottomEdge: Bool {
        switch self {
        case .topLeft, .topCenter, .topRight:
            return true
        default:
            return false
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
        guard !spriteDispatchIsBlocked(for: partId) else { return }

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
                coordinator?.dispatchMessageToCard("keyDown", params: [characters])
            }
        case .keyUp(let characters, _):
            if let payload = spriteDispatchContext(for: partId) {
                coordinator?.dispatchMessage("keyUp", to: payload.targetId, params: [characters], scriptContext: payload.context)
            } else {
                coordinator?.dispatchMessage("keyUp", to: partId, params: [characters])
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
            let toolState = ToolState(currentTool: currentTool.rawValue)
            guard toolState.category == .browse, activeFieldEditor == nil else {
                frameUpdateDispatchInFlight.remove(partId)
                return
            }
            guard !frameUpdateDispatchInFlight.contains(partId) else {
                return
            }
            if frameUpdateDispatchPayloads[partId] == nil,
               let part = document.parts.first(where: { $0.id == partId }) {
                refreshFrameUpdateDispatchPayloadIfNeeded(for: part)
            }
            guard let payload = frameUpdateDispatchPayloads[partId],
                  payload.hasHandler,
                  let coordinator else {
                return
            }

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
            frameUpdateDispatchInFlight.insert(partId)
            coordinator.dispatchMessage(
                "frameUpdate",
                to: payload.targetId,
                params: [String(deltaTime)],
                mouseX: mouseX,
                mouseY: mouseY,
                scriptContext: payload.context,
                completion: { [weak self] in
                    self?.frameUpdateDispatchInFlight.remove(partId)
                }
            )
        case .sceneDidLoad:
            // Lifecycle events are now dispatched directly from rebuildSpriteScene()
            // This case is kept for completeness but should not fire in normal flow
            if let sceneId = loadedActiveSceneIDs[partId] {
                scheduleSpriteLifecycleMessagesIfNeeded(partId: partId, sceneId: sceneId)
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
