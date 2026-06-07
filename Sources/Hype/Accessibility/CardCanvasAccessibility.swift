import AppKit
import HypeCore

private enum CardCanvasAccessibilityActionName {
    static let openScript = "Open Script"
    static let revealInInspector = "Reveal in Inspector"
    static let delete = "Delete"
    static let moveLeft = "Move Left"
    static let moveRight = "Move Right"
    static let moveUp = "Move Up"
    static let moveDown = "Move Down"
    static let resizeLarger = "Resize Larger"
    static let resizeSmaller = "Resize Smaller"
}

private final class AccessibilityChildrenResult: @unchecked Sendable {
    let value: [Any]?

    init(_ value: [Any]?) {
        self.value = value
    }
}

@preconcurrency
@inline(__always)
private func withCanvas<T: Sendable>(
    _ canvas: CardCanvasNSView?,
    fallback: @autoclosure () -> T,
    _ action: @MainActor (CardCanvasNSView) -> T
) -> T {
    guard let canvas else { return fallback() }
    return MainActor.assumeIsolated { action(canvas) }
}

final class CardCanvasPartAccessibilityElement: NSAccessibilityElement, @unchecked Sendable {
    weak var canvas: CardCanvasNSView?
    let partId: UUID

    init(canvas: CardCanvasNSView, partId: UUID) {
        self.canvas = canvas
        self.partId = partId
        super.init()
    }

    override func accessibilityParent() -> Any? {
        canvas
    }

    override func accessibilityIdentifier() -> String {
        HypeAccessibilityID.part(partId)
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        let partId = partId
        return withCanvas(canvas, fallback: .group) { $0.accessibilityRole(forPart: partId) }
    }

    override func accessibilityLabel() -> String? {
        let partId = partId
        return withCanvas(canvas, fallback: nil) { $0.accessibilityLabel(forPart: partId) }
    }

    override func accessibilityHelp() -> String? {
        let partId = partId
        return withCanvas(canvas, fallback: nil) { $0.accessibilityHelp(forPart: partId) }
    }

    override func accessibilityValue() -> Any? {
        let partId = partId
        return withCanvas(canvas, fallback: nil) { $0.accessibilityValue(forPart: partId) }
    }

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        guard let value = accessibilityValue as? String else { return }
        let partId = partId
        let textValue = value
        withCanvas(canvas, fallback: ()) { $0.setAccessibilityValue(textValue, forPart: partId) }
    }

    override func accessibilityFrame() -> NSRect {
        let partId = partId
        return withCanvas(canvas, fallback: .zero) { $0.accessibilityFrame(forPart: partId) }
    }

    override func accessibilityChildren() -> [Any]? {
        guard let canvas else { return nil }
        let partId = partId
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                guard let part = canvas.document.parts.first(where: { $0.id == partId }),
                      part.partType == .spriteArea,
                      let spec = part.spriteAreaSpecModel else { return AccessibilityChildrenResult(nil) }
                return AccessibilityChildrenResult([CardCanvasSpriteSceneAccessibilityElement(canvas: canvas, partId: part.id, sceneId: spec.activeSceneID)])
            }.value
        }
        return DispatchQueue.main.sync {
            guard let part = canvas.document.parts.first(where: { $0.id == partId }),
                  part.partType == .spriteArea,
                  let spec = part.spriteAreaSpecModel else { return nil }
            return [CardCanvasSpriteSceneAccessibilityElement(canvas: canvas, partId: part.id, sceneId: spec.activeSceneID)]
        }
    }

    override func accessibilityActionNames() -> [NSAccessibility.Action] {
        [.press, .pick]
    }

    override func accessibilityActionDescription(_ action: NSAccessibility.Action) -> String? {
        switch action {
        case .press:
            return "Activate \(accessibilityLabel() ?? "part")"
        case .pick:
            return "Select \(accessibilityLabel() ?? "part")"
        default:
            return nil
        }
    }

    override func accessibilityPerformPress() -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.performAccessibilityPress(onPart: partId) }
    }

    override func accessibilityPerformPick() -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.performAccessibilityPick(onPart: partId) }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.openScript, target: self, selector: #selector(openScript(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.revealInInspector, target: self, selector: #selector(revealInInspector(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.delete, target: self, selector: #selector(deletePart(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.moveLeft, target: self, selector: #selector(moveLeft(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.moveRight, target: self, selector: #selector(moveRight(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.moveUp, target: self, selector: #selector(moveUp(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.moveDown, target: self, selector: #selector(moveDown(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.resizeLarger, target: self, selector: #selector(resizeLarger(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.resizeSmaller, target: self, selector: #selector(resizeSmaller(_:))),
        ]
    }

    @objc private func openScript(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.openAccessibilityScriptEditor(forPart: partId) }
    }

    @objc private func revealInInspector(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.revealAccessibilityPartInInspector(partId) }
    }

    @objc private func deletePart(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.deleteAccessibilityPart(partId) }
    }

    @objc private func moveLeft(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.moveAccessibilityPart(partId, dx: -1, dy: 0) }
    }

    @objc private func moveRight(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.moveAccessibilityPart(partId, dx: 1, dy: 0) }
    }

    @objc private func moveUp(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.moveAccessibilityPart(partId, dx: 0, dy: -1) }
    }

    @objc private func moveDown(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.moveAccessibilityPart(partId, dx: 0, dy: 1) }
    }

    @objc private func resizeLarger(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.resizeAccessibilityPart(partId, dw: 10, dh: 10) }
    }

    @objc private func resizeSmaller(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        return withCanvas(canvas, fallback: false) { $0.resizeAccessibilityPart(partId, dw: -10, dh: -10) }
    }
}

final class CardCanvasSpriteSceneAccessibilityElement: NSAccessibilityElement, @unchecked Sendable {
    weak var canvas: CardCanvasNSView?
    let partId: UUID
    let sceneId: UUID

    init(canvas: CardCanvasNSView, partId: UUID, sceneId: UUID) {
        self.canvas = canvas
        self.partId = partId
        self.sceneId = sceneId
        super.init()
    }

    override func accessibilityParent() -> Any? {
        guard let canvas else { return nil }
        return CardCanvasPartAccessibilityElement(canvas: canvas, partId: partId)
    }

    override func accessibilityIdentifier() -> String {
        HypeAccessibilityID.spriteScene(partId: partId, sceneId: sceneId)
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityLabel() -> String? {
        let partId = partId
        let sceneId = sceneId
        return withCanvas(canvas, fallback: nil) { $0.accessibilityLabel(forScene: sceneId, inPart: partId) }
    }

    override func accessibilityValue() -> Any? {
        let partId = partId
        let sceneId = sceneId
        return withCanvas(canvas, fallback: nil) { $0.accessibilityValue(forScene: sceneId, inPart: partId) }
    }

    override func accessibilityFrame() -> NSRect {
        let partId = partId
        return withCanvas(canvas, fallback: .zero) { $0.accessibilityFrame(forPart: partId) }
    }

    override func accessibilityChildren() -> [Any]? {
        guard let canvas else { return nil }
        let partId = partId
        let sceneId = sceneId
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                guard let part = canvas.document.parts.first(where: { $0.id == partId }),
                      let scene = part.spriteAreaSpecModel?.scene(id: sceneId) else { return AccessibilityChildrenResult(nil) }
                return AccessibilityChildrenResult(scene.allNodes
                    .filter { !$0.isHidden }
                    .map { CardCanvasSpriteNodeAccessibilityElement(canvas: canvas, partId: partId, sceneId: sceneId, nodeId: $0.id) })
            }.value
        }
        return DispatchQueue.main.sync {
            guard let part = canvas.document.parts.first(where: { $0.id == partId }),
                  let scene = part.spriteAreaSpecModel?.scene(id: sceneId) else { return nil }
            return scene.allNodes
                .filter { !$0.isHidden }
                .map { CardCanvasSpriteNodeAccessibilityElement(canvas: canvas, partId: partId, sceneId: sceneId, nodeId: $0.id) }
        }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.openScript, target: self, selector: #selector(openScript(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.revealInInspector, target: self, selector: #selector(revealInInspector(_:))),
        ]
    }

    @objc private func openScript(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        let sceneId = sceneId
        return withCanvas(canvas, fallback: false) { $0.openAccessibilityScriptEditor(forScene: sceneId, inPart: partId) }
    }

    @objc private func revealInInspector(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        let sceneId = sceneId
        return withCanvas(canvas, fallback: false) { $0.revealAccessibilitySceneInInspector(sceneId: sceneId, partId: partId) }
    }
}

final class CardCanvasSpriteNodeAccessibilityElement: NSAccessibilityElement, @unchecked Sendable {
    weak var canvas: CardCanvasNSView?
    let partId: UUID
    let sceneId: UUID
    let nodeId: UUID

    init(canvas: CardCanvasNSView, partId: UUID, sceneId: UUID, nodeId: UUID) {
        self.canvas = canvas
        self.partId = partId
        self.sceneId = sceneId
        self.nodeId = nodeId
        super.init()
    }

    override func accessibilityParent() -> Any? {
        guard let canvas else { return nil }
        return CardCanvasSpriteSceneAccessibilityElement(canvas: canvas, partId: partId, sceneId: sceneId)
    }

    override func accessibilityIdentifier() -> String {
        HypeAccessibilityID.spriteNode(partId: partId, sceneId: sceneId, nodeId: nodeId)
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        let partId = partId
        let sceneId = sceneId
        let nodeId = nodeId
        return withCanvas(canvas, fallback: .group) { $0.accessibilityRole(forNode: nodeId, sceneId: sceneId, partId: partId) }
    }

    override func accessibilityLabel() -> String? {
        let partId = partId
        let sceneId = sceneId
        let nodeId = nodeId
        return withCanvas(canvas, fallback: nil) { $0.accessibilityLabel(forNode: nodeId, sceneId: sceneId, partId: partId) }
    }

    override func accessibilityValue() -> Any? {
        let partId = partId
        let sceneId = sceneId
        let nodeId = nodeId
        return withCanvas(canvas, fallback: nil) { $0.accessibilityValue(forNode: nodeId, sceneId: sceneId, partId: partId) }
    }

    override func accessibilityFrame() -> NSRect {
        let partId = partId
        let sceneId = sceneId
        let nodeId = nodeId
        return withCanvas(canvas, fallback: .zero) { $0.accessibilityFrame(forNode: nodeId, sceneId: sceneId, partId: partId) }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.openScript, target: self, selector: #selector(openScript(_:))),
            NSAccessibilityCustomAction(name: CardCanvasAccessibilityActionName.revealInInspector, target: self, selector: #selector(revealInInspector(_:))),
        ]
    }

    @objc private func openScript(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        let sceneId = sceneId
        let nodeId = nodeId
        return withCanvas(canvas, fallback: false) { $0.openAccessibilityScriptEditor(forNode: nodeId, sceneId: sceneId, partId: partId) }
    }

    @objc private func revealInInspector(_ action: NSAccessibilityCustomAction) -> Bool {
        let partId = partId
        let sceneId = sceneId
        let nodeId = nodeId
        return withCanvas(canvas, fallback: false) { $0.revealAccessibilityNodeInInspector(nodeId: nodeId, sceneId: sceneId, partId: partId) }
    }
}

extension CardCanvasNSView {
    func refreshAccessibilityTreeIfNeeded() {
        let signature = accessibilityTreeSignature()
        guard signature != accessibilitySignature else { return }
        accessibilitySignature = signature
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func accessibilityRootChildren() -> [CardCanvasPartAccessibilityElement] {
        accessibilityVisibleParts().map { accessibilityElement(forPart: $0.id) }
    }

    func accessibilitySelectedPartChildren() -> [CardCanvasPartAccessibilityElement] {
        accessibilityVisibleParts()
            .filter { selectedPartIds.contains($0.id) }
            .map { accessibilityElement(forPart: $0.id) }
    }

    func accessibilityElement(forPart partId: UUID) -> CardCanvasPartAccessibilityElement {
        CardCanvasPartAccessibilityElement(canvas: self, partId: partId)
    }

    func accessibilityElement(forScene sceneId: UUID, inPart partId: UUID) -> CardCanvasSpriteSceneAccessibilityElement {
        CardCanvasSpriteSceneAccessibilityElement(canvas: self, partId: partId, sceneId: sceneId)
    }

    func accessibilityElement(forNode nodeId: UUID, sceneId: UUID, partId: UUID) -> CardCanvasSpriteNodeAccessibilityElement {
        CardCanvasSpriteNodeAccessibilityElement(canvas: self, partId: partId, sceneId: sceneId, nodeId: nodeId)
    }

    func accessibilityElement(atScreenPoint point: NSPoint) -> Any? {
        guard let window else { return self }
        let windowPoint = window.convertPoint(fromScreen: point)
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else { return nil }

        for part in accessibilityVisibleParts().reversed() {
            if NSRect(x: part.left, y: part.top, width: part.width, height: part.height).contains(localPoint) {
                return accessibilityElement(forPart: part.id)
            }
        }
        return self
    }

    func accessibilityRole(forPart partId: UUID) -> NSAccessibility.Role {
        guard let part = document.parts.first(where: { $0.id == partId }) else { return .group }
        switch part.partType {
        case .button, .stepper, .musicPlayer, .toggle, .link, .menu:
            return .button
        case .field, .searchField:
            return .textField
        case .image:
            return .image
        case .slider:
            return .slider
        case .divider:
            return .splitter
        default:
            return .group
        }
    }

    func accessibilityLabel(forPart partId: UUID) -> String {
        guard let part = document.parts.first(where: { $0.id == partId }) else { return "Missing part" }
        let name = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return "\(part.partType.rawValue) \(name)"
        }
        return "\(part.partType.rawValue) \(part.id.uuidString)"
    }

    func accessibilityHelp(forPart partId: UUID) -> String? {
        guard let part = document.parts.first(where: { $0.id == partId }) else { return nil }
        let help = part.helpText.trimmingCharacters(in: .whitespacesAndNewlines)
        return help.isEmpty ? nil : help
    }

    func accessibilityValue(forPart partId: UUID) -> String {
        guard let part = document.parts.first(where: { $0.id == partId }) else { return "" }
        var components: [String] = [
            "type=\(part.partType.rawValue)",
            "id=\(part.id.uuidString)",
            "scope=\(part.backgroundId == nil ? "card" : "background")",
            "left=\(rounded(part.left))",
            "top=\(rounded(part.top))",
            "width=\(rounded(part.width))",
            "height=\(rounded(part.height))",
            "visible=\(part.visible)",
            "enabled=\(part.enabled)",
        ]
        if selectedPartIds.contains(part.id) {
            components.append("selected=true")
        }
        if part.partType == .field || part.partType == .button {
            let text = part.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                components.append("text=\(text)")
            }
        }
        if part.partType == .spriteArea, let spec = part.spriteAreaSpecModel {
            components.append("sceneCount=\(spec.scenes.count)")
            components.append("activeScene=\(spec.activeSceneID.uuidString)")
            components.append("nodeCount=\(spec.activeScene?.allNodes.count ?? 0)")
        }
        if [.musicPlayer, .pianoKeyboard, .stepSequencer, .musicMixer].contains(part.partType) {
            components.append("musicPattern=\(part.musicPatternName)")
            components.append("musicInstrument=\(part.musicInstrumentName)")
            components.append("musicTempo=\(MusicTempo.clamp(part.musicTempo))")
            components.append("musicLoop=\(part.musicLoop)")
        } else if part.partType == .appleMusicBrowser {
            components.append("musicKitSearch=\(part.musicSearchTerm)")
            components.append("musicKitScope=\(part.musicSearchScope)")
            components.append("musicKitType=\(part.musicSourceType)")
            if !part.musicSourceID.isEmpty {
                components.append("musicKitSelection=\(part.musicSourceKind):\(part.musicSourceType):\(part.musicSourceID)")
            }
        } else if part.partType == .musicQueue {
            components.append("musicQueueData=\(part.musicQueueData)")
        }
        return components.joined(separator: "; ")
    }

    func setAccessibilityValue(_ value: String, forPart partId: UUID) {
        guard let part = document.parts.first(where: { $0.id == partId }) else { return }
        switch part.partType {
        case .field, .searchField:
            coordinator?.updatePartText(id: partId, text: value)
        case .button:
            coordinator?.setPartText(id: partId, text: value)
        default:
            coordinator?.setPartName(id: partId, name: value)
        }
        needsDisplay = true
        refreshAccessibilityTreeIfNeeded()
    }

    func accessibilityFrame(forPart partId: UUID) -> NSRect {
        guard let part = document.parts.first(where: { $0.id == partId }) else { return .zero }
        return screenRect(forLocalRect: NSRect(x: part.left, y: part.top, width: part.width, height: part.height))
    }

    func accessibilityChildren(forPart partId: UUID) -> [CardCanvasSpriteSceneAccessibilityElement]? {
        guard let part = document.parts.first(where: { $0.id == partId }),
              part.partType == .spriteArea,
              let spec = part.spriteAreaSpecModel else { return nil }
        return [accessibilityElement(forScene: spec.activeSceneID, inPart: part.id)]
    }

    func accessibilityLabel(forScene sceneId: UUID, inPart partId: UUID) -> String {
        guard let scene = spriteScene(sceneId, partId: partId) else { return "Sprite scene" }
        let name = scene.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Sprite scene \(sceneId.uuidString)" : "Sprite scene \(name)"
    }

    func accessibilityValue(forScene sceneId: UUID, inPart partId: UUID) -> String {
        guard let scene = spriteScene(sceneId, partId: partId) else { return "" }
        return [
            "id=\(sceneId.uuidString)",
            "size=\(rounded(scene.size.width))x\(rounded(scene.size.height))",
            "nodes=\(scene.allNodes.count)",
            "paused=\(scene.isPaused)",
        ].joined(separator: "; ")
    }

    func accessibilityChildren(forScene sceneId: UUID, inPart partId: UUID) -> [CardCanvasSpriteNodeAccessibilityElement]? {
        guard let scene = spriteScene(sceneId, partId: partId) else { return nil }
        return scene.allNodes
            .filter { !$0.isHidden }
            .map { accessibilityElement(forNode: $0.id, sceneId: sceneId, partId: partId) }
    }

    func accessibilityRole(forNode nodeId: UUID, sceneId: UUID, partId: UUID) -> NSAccessibility.Role {
        guard let node = spriteNode(nodeId, sceneId: sceneId, partId: partId) else { return .group }
        switch node.nodeType {
        case .label:
            return .staticText
        case .sprite, .shape, .tileMap, .emitter, .effect:
            return .image
        default:
            return .group
        }
    }

    func accessibilityLabel(forNode nodeId: UUID, sceneId: UUID, partId: UUID) -> String {
        guard let node = spriteNode(nodeId, sceneId: sceneId, partId: partId) else { return "Sprite node" }
        let name = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "\(node.nodeType.rawValue) node \(node.id.uuidString)" : "\(node.nodeType.rawValue) \(name)"
    }

    func accessibilityValue(forNode nodeId: UUID, sceneId: UUID, partId: UUID) -> String {
        guard let node = spriteNode(nodeId, sceneId: sceneId, partId: partId) else { return "" }
        var components: [String] = [
            "id=\(node.id.uuidString)",
            "type=\(node.nodeType.rawValue)",
            "x=\(rounded(node.position.x))",
            "y=\(rounded(node.position.y))",
            "hidden=\(node.isHidden)",
        ]
        if let size = node.size {
            components.append("width=\(rounded(size.width))")
            components.append("height=\(rounded(size.height))")
        }
        if let text = node.text, !text.isEmpty {
            components.append("text=\(text)")
        }
        return components.joined(separator: "; ")
    }

    func accessibilityFrame(forNode nodeId: UUID, sceneId: UUID, partId: UUID) -> NSRect {
        guard let part = document.parts.first(where: { $0.id == partId }),
              let scene = spriteScene(sceneId, partId: partId),
              let node = scene.node(id: nodeId) else {
            return accessibilityFrame(forPart: partId)
        }
        let nodeSize = node.size ?? SizeSpec(width: 24, height: 24)
        let sx = scene.size.width > 0 ? part.width / scene.size.width : 1
        let sy = scene.size.height > 0 ? part.height / scene.size.height : 1
        let width = max(8, nodeSize.width * sx * abs(node.xScale))
        let height = max(8, nodeSize.height * sy * abs(node.yScale))
        let local = NSRect(
            x: part.left + node.position.x * sx - width / 2,
            y: part.top + node.position.y * sy - height / 2,
            width: width,
            height: height
        )
        return screenRect(forLocalRect: local)
    }

    func performAccessibilityPick(onPart partId: UUID) -> Bool {
        guard document.stack.userLevel.hypeUserLevel.canAuthorObjects,
              document.parts.contains(where: { $0.id == partId }) else { return false }
        coordinator?.selectPart(partId)
        selectedPartIds = document.expandedGroupSelection([partId])
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        return true
    }

    func performAccessibilityPress(onPart partId: UUID) -> Bool {
        guard let part = document.parts.first(where: { $0.id == partId }) else { return false }
        let effectiveTool = CardCanvasNSView.effectiveMouseTool(
            currentTool: currentTool,
            runtimeModeEnabled: document.stack.runtimeModeEnabled,
            userLevel: document.stack.userLevel.hypeUserLevel
        )
        if ToolState(currentTool: effectiveTool.rawValue).category == .browse {
            if document.stack.userLevel.hypeUserLevel.canEditTextFields,
               part.partType == .field && !part.lockText {
                setAccessibilityValue(part.textContent, forPart: partId)
            }
            coordinator?.dispatchMessage("mouseUp", to: partId)
            return true
        }
        return performAccessibilityPick(onPart: partId)
    }

    func openAccessibilityScriptEditor(forPart partId: UUID) -> Bool {
        guard document.stack.userLevel.hypeUserLevel.canEditScripts,
              document.parts.contains(where: { $0.id == partId }) else { return false }
        NotificationCenter.default.post(
            name: .openPartScriptEditor,
            object: nil,
            userInfo: ["partId": partId, "target": ScriptTarget.part(partId)]
        )
        return true
    }

    func openAccessibilityScriptEditor(forScene sceneId: UUID, inPart partId: UUID) -> Bool {
        guard document.stack.userLevel.hypeUserLevel.canEditScripts,
              spriteScene(sceneId, partId: partId) != nil else { return false }
        NotificationCenter.default.post(
            name: .openPartScriptEditor,
            object: nil,
            userInfo: ["partId": partId, "target": ScriptTarget.scene(partId: partId, sceneId: sceneId)]
        )
        return true
    }

    func openAccessibilityScriptEditor(forNode nodeId: UUID, sceneId: UUID, partId: UUID) -> Bool {
        guard document.stack.userLevel.hypeUserLevel.canEditScripts,
              spriteNode(nodeId, sceneId: sceneId, partId: partId) != nil else { return false }
        NotificationCenter.default.post(
            name: .openPartScriptEditor,
            object: nil,
            userInfo: ["partId": partId, "target": ScriptTarget.node(partId: partId, nodeId: nodeId)]
        )
        return true
    }

    func revealAccessibilityPartInInspector(_ partId: UUID) -> Bool {
        guard document.stack.userLevel.hypeUserLevel.canAuthorObjects,
              document.parts.contains(where: { $0.id == partId }) else { return false }
        NotificationCenter.default.post(name: .editPartProperties, object: partId)
        return performAccessibilityPick(onPart: partId)
    }

    func revealAccessibilitySceneInInspector(sceneId: UUID, partId: UUID) -> Bool {
        guard document.stack.userLevel.hypeUserLevel.canAuthorObjects,
              spriteScene(sceneId, partId: partId) != nil else { return false }
        NotificationCenter.default.post(
            name: .revealSpriteNode,
            object: nil,
            userInfo: ["partId": partId, "sceneId": sceneId]
        )
        return true
    }

    func revealAccessibilityNodeInInspector(nodeId: UUID, sceneId: UUID, partId: UUID) -> Bool {
        guard document.stack.userLevel.hypeUserLevel.canAuthorObjects,
              spriteNode(nodeId, sceneId: sceneId, partId: partId) != nil else { return false }
        NotificationCenter.default.post(
            name: .revealSpriteNode,
            object: nil,
            userInfo: ["partId": partId, "sceneId": sceneId, "nodeId": nodeId]
        )
        return true
    }

    func deleteAccessibilityPart(_ partId: UUID) -> Bool {
        guard document.parts.contains(where: { $0.id == partId }) else { return false }
        coordinator?.deletePart(id: partId)
        refreshAccessibilityTreeIfNeeded()
        return true
    }

    func moveAccessibilityPart(_ partId: UUID, dx: Double, dy: Double) -> Bool {
        guard document.parts.contains(where: { $0.id == partId }) else { return false }
        coordinator?.movePart(id: partId, dx: dx, dy: dy)
        needsDisplay = true
        refreshAccessibilityTreeIfNeeded()
        return true
    }

    func resizeAccessibilityPart(_ partId: UUID, dw: Double, dh: Double) -> Bool {
        guard document.parts.contains(where: { $0.id == partId }) else { return false }
        coordinator?.resizeAccessibilityPart(id: partId, dw: dw, dh: dh)
        needsDisplay = true
        refreshAccessibilityTreeIfNeeded()
        return true
    }

    private func accessibilityVisibleParts() -> [Part] {
        let cardParts = document.partsForCard(currentCardId)
        let backgroundParts: [Part]
        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            backgroundParts = document.partsForBackground(card.backgroundId)
        } else {
            backgroundParts = []
        }
        return (backgroundParts + cardParts).filter { part in
            part.visible && part.enabled && part.partType != .unknown && part.width > 0 && part.height > 0
        }
    }

    private func spriteScene(_ sceneId: UUID, partId: UUID) -> SceneSpec? {
        guard let part = document.parts.first(where: { $0.id == partId }),
              let spec = part.spriteAreaSpecModel else { return nil }
        return spec.scene(id: sceneId)
    }

    private func spriteNode(_ nodeId: UUID, sceneId: UUID, partId: UUID) -> HypeNodeSpec? {
        spriteScene(sceneId, partId: partId)?.node(id: nodeId)
    }

    private func screenRect(forLocalRect localRect: NSRect) -> NSRect {
        guard let window else { return localRect }
        let windowRect = convert(localRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    private func accessibilityTreeSignature() -> String {
        let partSignatures = accessibilityVisibleParts().map { part in
            [
                part.id.uuidString,
                part.partType.rawValue,
                part.name,
                rounded(part.left),
                rounded(part.top),
                rounded(part.width),
                rounded(part.height),
                String(part.visible),
                String(selectedPartIds.contains(part.id)),
                part.sceneSpec.count.description,
            ].joined(separator: "|")
        }
        return ([currentCardId.uuidString, currentTool.rawValue, editingBackground.description] + partSignatures)
            .joined(separator: "\n")
    }

    private func rounded(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
