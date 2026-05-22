import SwiftUI
import HypeCore

struct SpriteSceneGuideContext: Identifiable {
    let partId: UUID
    let sceneId: UUID?

    var id: String {
        "\(partId.uuidString):\(sceneId?.uuidString ?? "active")"
    }
}

private enum SpriteSceneTemplate: String, CaseIterable, Identifiable {
    case blank
    case platformer
    case topDown
    case puzzle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Blank"
        case .platformer: return "Platformer"
        case .topDown: return "Top Down"
        case .puzzle: return "Puzzle"
        }
    }

    var description: String {
        switch self {
        case .blank: return "Start with a clean scene and only the essentials."
        case .platformer: return "Gravity, a player actor, floor bounds, camera, and HUD."
        case .topDown: return "Top-down actor, camera, HUD, and optional tile map."
        case .puzzle: return "Static board-like scene with labels, camera, and logic hooks."
        }
    }
}

private struct SpriteSceneSetupDraft {
    var sceneName: String
    var width: Double
    var height: Double
    var scaleMode: SceneScaleMode
    var backgroundColor: String
    var gravityX: Double
    var gravityY: Double
    var template: SpriteSceneTemplate
    var wantsPlayerNode: Bool
    var wantsCamera: Bool
    var wantsHUD: Bool
    var wantsWorldBounds: Bool
    var wantsTileMap: Bool
    var playerAssetId: UUID?
    var tilesetAssetId: UUID?
    var showPhysicsDebug: Bool
    var showFPSDebug: Bool
    var showNodeCountDebug: Bool
    var addSceneDidLoadScript: Bool
    var addOpenSceneScript: Bool
    var addFrameUpdateScript: Bool
    var addContactScripts: Bool
    var addKeyboardScript: Bool
}

struct SpriteSceneSetupGuide: View {
    @Binding var document: HypeDocumentWrapper
    let partId: UUID
    let sceneId: UUID?
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var stepIndex: Int = 0
    @State private var draft: SpriteSceneSetupDraft
    @State private var selectedGameTemplateID: String = ""
    @State private var templateError: String?

    init(
        document: Binding<HypeDocumentWrapper>,
        partId: UUID,
        sceneId: UUID?,
        onDone: @escaping () -> Void
    ) {
        self._document = document
        self.partId = partId
        self.sceneId = sceneId
        self.onDone = onDone

        let initialDraft: SpriteSceneSetupDraft
        if let part = document.wrappedValue.document.parts.first(where: { $0.id == partId }),
           let areaSpec = part.spriteAreaSpecModel {
            let entry = areaSpec.scenes.first(where: { $0.id == sceneId }) ?? areaSpec.activeSceneEntry
            let scene = entry?.scene ?? SceneSpec(size: areaSpec.designSize, scaleMode: areaSpec.scaleMode)
            let nodes = scene.allNodes
            let firstSpriteAsset = nodes.first(where: { $0.nodeType == .sprite })?.assetRef?.id
            let firstTileSetAsset = nodes.first(where: { $0.nodeType == .tileMap })?.tileMapSpec?.tileSetAssetRef?.id
            let hasHUD = nodes.contains { $0.nodeType == .label }
            let hasPlayer = nodes.contains { ["player", "hero", "avatar"].contains($0.name.lowercased()) }
            let hasCamera = nodes.contains { $0.nodeType == .camera }
            let hasTileMap = nodes.contains { $0.nodeType == .tileMap }
            let hasBounds = nodes.contains {
                ["floor", "leftWall", "rightWall", "ceiling", "bounds"].contains($0.name.lowercased())
            }
            let template: SpriteSceneTemplate = scene.gravity.dy < -1 ? .platformer : (hasTileMap ? .topDown : .blank)
            initialDraft = SpriteSceneSetupDraft(
                sceneName: scene.name.isEmpty ? "main" : scene.name,
                width: scene.size.width > 0 ? scene.size.width : max(400, part.width),
                height: scene.size.height > 0 ? scene.size.height : max(300, part.height),
                scaleMode: scene.scaleMode,
                backgroundColor: scene.backgroundColor,
                gravityX: scene.gravity.dx,
                gravityY: scene.gravity.dy,
                template: template,
                wantsPlayerNode: hasPlayer || template != .blank,
                wantsCamera: hasCamera || template != .blank,
                wantsHUD: hasHUD || template != .blank,
                wantsWorldBounds: hasBounds || template == .platformer,
                wantsTileMap: hasTileMap,
                playerAssetId: firstSpriteAsset,
                tilesetAssetId: firstTileSetAsset,
                showPhysicsDebug: scene.showsPhysics,
                showFPSDebug: scene.showsFPS,
                showNodeCountDebug: scene.showsNodeCount,
                addSceneDidLoadScript: scene.script.localizedCaseInsensitiveContains("on sceneDidLoad"),
                addOpenSceneScript: scene.script.localizedCaseInsensitiveContains("on openScene"),
                addFrameUpdateScript: scene.script.localizedCaseInsensitiveContains("on frameUpdate"),
                addContactScripts: scene.script.localizedCaseInsensitiveContains("on beginContact"),
                addKeyboardScript: scene.script.localizedCaseInsensitiveContains("on keyDown")
            )
        } else {
            initialDraft = SpriteSceneSetupDraft(
                sceneName: "main",
                width: 800,
                height: 600,
                scaleMode: .aspectFit,
                backgroundColor: "#FFFFFF",
                gravityX: 0,
                gravityY: -9.8,
                template: .blank,
                wantsPlayerNode: true,
                wantsCamera: true,
                wantsHUD: true,
                wantsWorldBounds: false,
                wantsTileMap: false,
                playerAssetId: nil,
                tilesetAssetId: nil,
                showPhysicsDebug: false,
                showFPSDebug: false,
                showNodeCountDebug: false,
                addSceneDidLoadScript: true,
                addOpenSceneScript: true,
                addFrameUpdateScript: false,
                addContactScripts: false,
                addKeyboardScript: false
            )
        }
        _draft = State(initialValue: initialDraft)
    }

    private let stepTitles = ["Basics", "World", "Logic"]

    private var imageAssets: [SpriteAsset] {
        document.document.spriteRepository.assets.filter {
            $0.kind == .imageTexture || $0.kind == .spriteSheet
        }
    }

    private var tileSetAssets: [SpriteAsset] {
        document.document.spriteRepository.assets.filter { $0.kind == .tileSet }
    }

    private var completionItems: [SceneChecklistItem] {
        [
            SceneChecklistItem(
                key: "basics",
                title: "Scene Basics",
                status: draft.sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.width <= 0 || draft.height <= 0 ? .missing : .complete,
                detail: "Name, size, and scale mode are set."
            ),
            SceneChecklistItem(
                key: "content",
                title: "World Content",
                status: (draft.wantsPlayerNode || draft.wantsTileMap || draft.wantsHUD || draft.wantsWorldBounds) ? .complete : .recommended,
                detail: "Choose the starter content to create."
            ),
            SceneChecklistItem(
                key: "assets",
                title: "Assets",
                status: assetChecklistStatus,
                detail: assetChecklistDetail
            ),
            SceneChecklistItem(
                key: "scripts",
                title: "Starter Scripts",
                status: (draft.addSceneDidLoadScript || draft.addOpenSceneScript || draft.addFrameUpdateScript || draft.addContactScripts || draft.addKeyboardScript) ? .complete : .recommended,
                detail: "Seed lifecycle and input handlers so the scene is ready to wire up."
            )
        ]
    }

    private var assetChecklistStatus: SceneChecklistStatus {
        if draft.wantsTileMap && draft.tilesetAssetId == nil {
            return .missing
        }
        if draft.wantsPlayerNode && draft.playerAssetId == nil {
            return .recommended
        }
        return .complete
    }

    private var assetChecklistDetail: String {
        if draft.wantsTileMap && draft.tilesetAssetId == nil {
            return "Pick a classified tileset or import one into the repository."
        }
        if draft.wantsPlayerNode && draft.playerAssetId == nil {
            return "A player texture is optional; the guide will fall back to a shape node."
        }
        return "Required starter assets are available."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SpriteKit Scene Setup")
                        .font(.headline)
                    Text("Walk through the core scene decisions so size, camera, world content, assets, and starter scripts are all accounted for.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(Array(stepTitles.enumerated()), id: \.offset) { offset, title in
                            Label(title, systemImage: offset <= stepIndex ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11, weight: offset == stepIndex ? .bold : .regular))
                                .foregroundColor(offset <= stepIndex ? .accentColor : .secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding()

            Divider()

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if stepIndex == 0 {
                            basicsStep
                        } else if stepIndex == 1 {
                            worldStep
                        } else {
                            logicStep
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 430, idealWidth: 520)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Checklist")
                        .font(.system(size: 12, weight: .bold))
                    ForEach(completionItems) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: icon(for: item.status))
                                .foregroundColor(color(for: item.status))
                                .font(.system(size: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 11, weight: .medium))
                                Text(item.detail).font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Button("Open Repository") {
                        openSpriteRepositoryWindow(document: $document)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
                .padding()
                .frame(minWidth: 220, idealWidth: 240)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                    onDone()
                }
                Spacer()
                if stepIndex > 0 {
                    Button("Back") {
                        stepIndex -= 1
                    }
                }
                if stepIndex < stepTitles.count - 1 {
                    Button("Next") {
                        stepIndex += 1
                    }
                    .disabled(!canContinue)
                } else {
                    Button("Apply Setup") {
                        if applyDraft() {
                            dismiss()
                            onDone()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply)
                }
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 520)
        // Sheet surface — themed so the wizard chrome (header,
        // checklist, step navigation footer) follows the active
        // stack theme.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so labels in the form steps and
        // checklist remain readable on the themed bg.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
    }

    private var canContinue: Bool {
        switch stepIndex {
        case 0:
            return canApplyBasics
        default:
            return true
        }
    }

    private var canApply: Bool {
        canApplyBasics && !(draft.wantsTileMap && draft.tilesetAssetId == nil)
    }

    private var canApplyBasics: Bool {
        !draft.sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.width > 0 &&
        draft.height > 0
    }

    @ViewBuilder
    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Define the scene container").font(.subheadline).bold()
            Text("Set the design size and scale behavior first. This drives how SpriteKit content fits inside the Sprite Area.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            TextField("Scene name", text: $draft.sceneName)
                .textFieldStyle(.roundedBorder)

            HStack {
                labeledNumberField("Width", value: $draft.width)
                labeledNumberField("Height", value: $draft.height)
            }

            Picker("Scale mode", selection: $draft.scaleMode) {
                ForEach(SceneScaleMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            // Background color — ColorPicker swatch + hex text in
            // sync. Mirrors `PropertyInspector.colorPropertyRow` so
            // every color-picking surface in the app has the same
            // shape: pick visually OR type a precise hex; the two
            // fields stay in lockstep through the shared binding.
            HStack {
                ColorPicker("", selection: Binding<Color>(
                    get: { Color(hex: draft.backgroundColor) },
                    set: { newVal in draft.backgroundColor = newVal.toHex() }
                ), supportsOpacity: false)
                .labelsHidden()
                Text("Background").font(.system(size: 11))
                Spacer()
                TextField("hex", text: $draft.backgroundColor)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 90)
            }

            HStack {
                labeledNumberField("Gravity X", value: $draft.gravityX)
                labeledNumberField("Gravity Y", value: $draft.gravityY)
            }
        }
    }

    @ViewBuilder
    private var worldStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("2. Choose world content").font(.subheadline).bold()
            Text("Pick a starter template, then turn on the pieces you want Hype to create for you.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Picker("Template", selection: $draft.template) {
                ForEach(SpriteSceneTemplate.allCases) { template in
                    Text(template.title).tag(template)
                }
            }
            .onChange(of: draft.template) { _, newValue in
                applyTemplateDefaults(newValue)
            }

            Text(draft.template.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Divider()

            Picker("Complete game template", selection: $selectedGameTemplateID) {
                Text("Starter scene only").tag("")
                ForEach(SpriteGameTemplateBuilder.templateCatalog) { template in
                    Text(template.displayName).tag(template.id)
                }
            }

            if let selectedGameTemplate {
                Text(selectedGameTemplate.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Controls: \(selectedGameTemplate.supportedControls.joined(separator: ", "))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Applying this replaces the active scene with a deterministic, self-contained playable scaffold.")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }

            if let templateError {
                Text(templateError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Divider()

            Toggle("Starter player node", isOn: $draft.wantsPlayerNode)
            Toggle("Camera node", isOn: $draft.wantsCamera)
            Toggle("HUD label", isOn: $draft.wantsHUD)
            Toggle("World bounds", isOn: $draft.wantsWorldBounds)
            Toggle("Tile map", isOn: $draft.wantsTileMap)

            if draft.wantsPlayerNode {
                Picker("Player asset", selection: $draft.playerAssetId) {
                    Text("Use a shape fallback").tag(nil as UUID?)
                    ForEach(imageAssets) { asset in
                        Text(asset.name).tag(asset.id as UUID?)
                    }
                }
            }

            if draft.wantsTileMap {
                if tileSetAssets.isEmpty {
                    Text("No classified tilesets yet. Open the repository and classify a tileset first.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                } else {
                    Picker("Tileset", selection: $draft.tilesetAssetId) {
                        Text("Choose a tileset").tag(nil as UUID?)
                        ForEach(tileSetAssets) { asset in
                            Text(asset.name).tag(asset.id as UUID?)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var logicStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("3. Seed scripts and debug views").font(.subheadline).bold()
            Text("Seed the handlers you expect to use so the scene is ready to script instead of starting from a blank file.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Toggle("Show physics overlay", isOn: $draft.showPhysicsDebug)
            Toggle("Show FPS", isOn: $draft.showFPSDebug)
            Toggle("Show node count", isOn: $draft.showNodeCountDebug)

            Divider()

            Toggle("Add sceneDidLoad handler", isOn: $draft.addSceneDidLoadScript)
            Toggle("Add openScene handler", isOn: $draft.addOpenSceneScript)
            Toggle("Add frameUpdate handler", isOn: $draft.addFrameUpdateScript)
            Toggle("Add beginContact / endContact handlers", isOn: $draft.addContactScripts)
            Toggle("Add keyDown / keyUp handlers", isOn: $draft.addKeyboardScript)

            Text("The guide only appends missing starter handlers. Existing scene and node scripts are preserved.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func labeledNumberField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func icon(for status: SceneChecklistStatus) -> String {
        switch status {
        case .complete: return "checkmark.circle.fill"
        case .recommended: return "exclamationmark.circle"
        case .missing: return "xmark.circle"
        }
    }

    private func color(for status: SceneChecklistStatus) -> Color {
        switch status {
        case .complete: return .green
        case .recommended: return .orange
        case .missing: return .red
        }
    }

    private var selectedGameTemplate: GameTemplateDescriptor? {
        guard !selectedGameTemplateID.isEmpty else { return nil }
        return SpriteGameTemplateCatalog.descriptor(for: selectedGameTemplateID)
    }

    private func applyTemplateDefaults(_ template: SpriteSceneTemplate) {
        switch template {
        case .blank:
            draft.gravityX = 0
            draft.gravityY = 0
            draft.wantsPlayerNode = false
            draft.wantsCamera = false
            draft.wantsHUD = false
            draft.wantsWorldBounds = false
            draft.wantsTileMap = false
        case .platformer:
            draft.gravityX = 0
            draft.gravityY = -9.8
            draft.wantsPlayerNode = true
            draft.wantsCamera = true
            draft.wantsHUD = true
            draft.wantsWorldBounds = true
        case .topDown:
            draft.gravityX = 0
            draft.gravityY = 0
            draft.wantsPlayerNode = true
            draft.wantsCamera = true
            draft.wantsHUD = true
            draft.wantsWorldBounds = true
            draft.wantsTileMap = true
        case .puzzle:
            draft.gravityX = 0
            draft.gravityY = 0
            draft.wantsPlayerNode = false
            draft.wantsCamera = true
            draft.wantsHUD = true
            draft.wantsWorldBounds = false
        }
    }

    private func applyDraft() -> Bool {
        templateError = nil
        if let selectedGameTemplate {
            guard let partIndex = document.document.parts.firstIndex(where: { $0.id == partId }) else {
                templateError = "Sprite Area not found."
                return false
            }
            do {
                _ = try SpriteGameTemplateBuilder.applyTemplate(
                    to: &document.document,
                    partIndex: partIndex,
                    spriteAreaName: document.document.parts[partIndex].name,
                    gameType: selectedGameTemplate.id
                )
                return true
            } catch {
                templateError = error.localizedDescription
                return false
            }
        }

        document.document.updatePart(id: partId) { part in
            part.updateSpriteAreaSpec { areaSpec in
                areaSpec.designSize = SizeSpec(width: draft.width, height: draft.height)
                areaSpec.scaleMode = draft.scaleMode
                areaSpec.showsPhysics = draft.showPhysicsDebug
                areaSpec.showsFPS = draft.showFPSDebug
                areaSpec.showsNodeCount = draft.showNodeCountDebug

                let targetSceneId: UUID
                if let sceneId,
                   areaSpec.scenes.contains(where: { $0.id == sceneId }) {
                    targetSceneId = sceneId
                    _ = areaSpec.activateScene(id: sceneId)
                } else if let existing = areaSpec.scenes.first(where: { $0.scene.name.lowercased() == draft.sceneName.lowercased() }) {
                    targetSceneId = existing.id
                    _ = areaSpec.activateScene(id: existing.id)
                } else {
                    targetSceneId = areaSpec.addScene(named: draft.sceneName, basedOn: areaSpec.activeScene).id
                }

                guard let index = areaSpec.scenes.firstIndex(where: { $0.id == targetSceneId }) else { return }
                var scene = areaSpec.scenes[index].scene
                scene.name = draft.sceneName
                scene.size = SizeSpec(width: draft.width, height: draft.height)
                scene.scaleMode = draft.scaleMode
                scene.backgroundColor = draft.backgroundColor
                scene.gravity = VectorSpec(dx: draft.gravityX, dy: draft.gravityY)
                scene.showsPhysics = draft.showPhysicsDebug
                scene.showsFPS = draft.showFPSDebug
                scene.showsNodeCount = draft.showNodeCountDebug

                seedStarterContent(into: &scene)
                scene.script = seededSceneScript(existing: scene.script)

                areaSpec.scenes[index].scene = scene
                areaSpec.activeSceneID = targetSceneId
            }
        }
        return true
    }

    private func seedStarterContent(into scene: inout SceneSpec) {
        let playerName = "player"

        if draft.wantsPlayerNode {
            let playerPosition = playerPosition(for: scene)
            let existingPlayerId = scene.node(named: playerName)?.id
            if let existingPlayerId {
                scene.updateNode(id: existingPlayerId) { node in
                    node.position = playerPosition
                    node.script = mergeStarterNodeScript(existing: node.script)
                    if let assetId = draft.playerAssetId,
                       let asset = document.document.spriteRepository.asset(byId: assetId) {
                        node.assetRef = document.document.spriteRepository.assetRef(for: asset)
                        if node.size == nil {
                            node.size = SizeSpec(width: 64, height: 64)
                        }
                    } else if node.nodeType == .sprite {
                        node.size = node.size ?? SizeSpec(width: 56, height: 56)
                    }
                    if draft.template == .platformer || draft.template == .topDown {
                        node.physicsBody = node.physicsBody ?? PhysicsBodySpec(
                            bodyType: .rect,
                            isDynamic: true,
                            restitution: 0.1,
                            friction: 0.4,
                            affectedByGravity: draft.template == .platformer,
                            allowsRotation: false
                        )
                    }
                }
            } else {
                scene.nodes.append(makePlayerNode(position: playerPosition))
            }
        }

        if draft.wantsCamera && scene.node(named: "camera") == nil {
            scene.nodes.append(HypeNodeSpec(
                name: "camera",
                nodeType: .camera,
                position: PointSpec(x: scene.size.width / 2, y: scene.size.height / 2),
                cameraTarget: draft.wantsPlayerNode ? playerName : nil
            ))
        }

        if draft.wantsHUD && scene.node(named: "scoreLabel") == nil {
            scene.nodes.append(HypeNodeSpec(
                name: "scoreLabel",
                nodeType: .label,
                position: PointSpec(x: 96, y: 32),
                text: "Score: 0",
                fontName: "Helvetica-Bold",
                fontSize: 22,
                fontColor: "#111111"
            ))
        }

        if draft.wantsWorldBounds {
            seedBounds(into: &scene)
        }

        if draft.wantsTileMap,
           let tilesetId = draft.tilesetAssetId,
           let tileset = document.document.spriteRepository.asset(byId: tilesetId),
           scene.node(named: "worldTiles") == nil {
            var tileMap = HypeNodeSpec(
                name: "worldTiles",
                nodeType: .tileMap,
                position: PointSpec(x: scene.size.width / 2, y: scene.size.height / 2)
            )
            tileMap.tileMapSpec = TileMapSpec(
                columns: max(8, Int(scene.size.width / Double(max(tileset.tileWidth, 32)))),
                rows: max(6, Int(scene.size.height / Double(max(tileset.tileHeight, 32)))),
                tileWidth: Double(max(tileset.tileWidth, 32)),
                tileHeight: Double(max(tileset.tileHeight, 32)),
                tileSetAssetRef: document.document.spriteRepository.assetRef(for: tileset),
                tileSetColumns: max(tileset.tileColumns, 1),
                tileData: []
            )
            scene.nodes.append(tileMap)
        }
    }

    private func playerPosition(for scene: SceneSpec) -> PointSpec {
        switch draft.template {
        case .platformer:
            return PointSpec(x: scene.size.width * 0.25, y: scene.size.height * 0.72)
        case .topDown, .puzzle, .blank:
            return PointSpec(x: scene.size.width / 2, y: scene.size.height / 2)
        }
    }

    private func makePlayerNode(position: PointSpec) -> HypeNodeSpec {
        if let assetId = draft.playerAssetId,
           let asset = document.document.spriteRepository.asset(byId: assetId) {
            var node = HypeNodeSpec(
                name: "player",
                nodeType: .sprite,
                position: position,
                size: SizeSpec(width: 64, height: 64),
                script: mergeStarterNodeScript(existing: "")
            )
            node.assetRef = document.document.spriteRepository.assetRef(for: asset)
            if draft.template == .platformer || draft.template == .topDown {
                node.physicsBody = PhysicsBodySpec(
                    bodyType: .rect,
                    isDynamic: true,
                    restitution: 0.1,
                    friction: 0.4,
                    affectedByGravity: draft.template == .platformer,
                    allowsRotation: false
                )
            }
            return node
        }

        var fallback = HypeNodeSpec(
            name: "player",
            nodeType: .shape,
            position: position,
            size: SizeSpec(width: 56, height: 56),
            shapeSpec: ShapeNodeSpec(
                shapeType: .circle,
                fillColor: "#5DADE2",
                strokeColor: "#1F3A5F",
                lineWidth: 2
            ),
            script: mergeStarterNodeScript(existing: "")
        )
        if draft.template == .platformer || draft.template == .topDown {
            fallback.physicsBody = PhysicsBodySpec(
                bodyType: .circle,
                isDynamic: true,
                restitution: 0.1,
                friction: 0.4,
                affectedByGravity: draft.template == .platformer,
                allowsRotation: false
            )
        }
        return fallback
    }

    private func seedBounds(into scene: inout SceneSpec) {
        if scene.node(named: "floor") == nil {
            var floor = HypeNodeSpec(
                name: "floor",
                nodeType: .shape,
                position: PointSpec(x: scene.size.width / 2, y: scene.size.height - 28),
                size: SizeSpec(width: scene.size.width, height: 32),
                shapeSpec: ShapeNodeSpec(
                    shapeType: .rect,
                    fillColor: "#A67C52",
                    strokeColor: "#6E4B2A",
                    lineWidth: 1
                )
            )
            floor.physicsBody = PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: false,
                restitution: 0,
                friction: 0.8,
                affectedByGravity: false,
                allowsRotation: false
            )
            scene.nodes.append(floor)
        }

        if draft.template != .platformer {
            if scene.node(named: "leftWall") == nil {
                var leftWall = HypeNodeSpec(
                    name: "leftWall",
                    nodeType: .shape,
                    position: PointSpec(x: 8, y: scene.size.height / 2),
                    size: SizeSpec(width: 16, height: scene.size.height),
                    shapeSpec: ShapeNodeSpec(fillColor: "#D8D8D8", strokeColor: "#888888", lineWidth: 1)
                )
                leftWall.physicsBody = PhysicsBodySpec(isDynamic: false, affectedByGravity: false, allowsRotation: false)
                scene.nodes.append(leftWall)
            }
            if scene.node(named: "rightWall") == nil {
                var rightWall = HypeNodeSpec(
                    name: "rightWall",
                    nodeType: .shape,
                    position: PointSpec(x: scene.size.width - 8, y: scene.size.height / 2),
                    size: SizeSpec(width: 16, height: scene.size.height),
                    shapeSpec: ShapeNodeSpec(fillColor: "#D8D8D8", strokeColor: "#888888", lineWidth: 1)
                )
                rightWall.physicsBody = PhysicsBodySpec(isDynamic: false, affectedByGravity: false, allowsRotation: false)
                scene.nodes.append(rightWall)
            }
        }
    }

    private func seededSceneScript(existing: String) -> String {
        var script = existing
        if draft.addSceneDidLoadScript {
            script = ensureHandler("sceneDidLoad", in: script, body: [
                "  -- Prepare scene state here"
            ])
        }
        if draft.addOpenSceneScript {
            script = ensureHandler("openScene", in: script, body: [
                "  -- Start gameplay here"
            ])
        }
        if draft.addFrameUpdateScript {
            script = ensureHandler("frameUpdate", in: script, body: [
                "  -- Advanced: avoid heavy work in frameUpdate"
            ])
        }
        if draft.addContactScripts {
            script = ensureHandler("beginContact", in: script, body: [
                "  -- Respond to collisions here"
            ])
            script = ensureHandler("endContact", in: script, body: [
                "  -- Cleanup collision state here"
            ])
        }
        if draft.addKeyboardScript {
            script = ensureHandler("keyDown", in: script, body: [
                "  -- Route keyboard input here"
            ])
            script = ensureHandler("keyUp", in: script, body: [
                "  -- Handle key release here"
            ])
        }
        return script.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergeStarterNodeScript(existing: String) -> String {
        ensureHandler("mouseDown", in: existing, body: [
            "  pass mouseDown"
        ])
    }

    private func ensureHandler(_ handler: String, in script: String, body: [String]) -> String {
        if script.localizedCaseInsensitiveContains("on \(handler)") {
            return script
        }
        let block = (["on \(handler)"] + body + ["end \(handler)"]).joined(separator: "\n")
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return block
        }
        return trimmed + "\n\n" + block
    }
}
