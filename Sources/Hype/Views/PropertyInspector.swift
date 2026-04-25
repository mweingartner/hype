import SwiftUI
import HypeCore
import UniformTypeIdentifiers

/// System font families, loaded once for the font picker.
private let systemFontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

struct PropertyInspector: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var selectedPartIds: Set<UUID>
    var currentTool: ToolName = .browse
    var currentCardId: UUID? = nil
    @Binding var paintColor: Color
    @Binding var pencilRadius: Double
    @State private var showingScript = false
    @State private var showingCardScript = false
    @State private var showingBgScript = false
    @State private var showingStackScript = false
    @State private var showingHypeScript = false
    @State private var selectedNodeId: UUID?
    @State private var draggedNodeId: UUID?
    @State private var sceneGuideContext: SpriteSceneGuideContext?

    var body: some View {
        Group {
            if selectedPartIds.count > 1 {
                multiSelectionView
            } else if let partId = selectedPartIds.first,
               let part = document.document.parts.first(where: { $0.id == partId }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Properties")
                            .font(.headline)
                            .padding(.bottom, 4)

                        commonSection(part: part)

                        Divider()

                        switch part.partType {
                        case .button: buttonSection(part: part)
                        case .field: fieldSection(part: part)
                        case .shape: shapeSection(part: part)
                        case .webpage: webpageSection(part: part)
                        case .image: imageSection(part: part)
                        case .video: videoSection(part: part)
                        case .chart: chartSection(part: part)
                        case .spriteArea: spriteAreaSection(part: part)
                        }

                        // Font controls for buttons and fields
                        if part.partType == .button || part.partType == .field {
                            Divider()
                            textFormattingSection(part: part)
                        }

                        Divider()

                        // Script section
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SCRIPT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            Button(action: {
                                openScriptEditorWindow(document: $document, partId: partId, target: .part(partId))
                            }) {
                                HStack {
                                    Image(systemName: "applescript")
                                    Text(part.script.isEmpty ? "Add Script..." : "Edit Script...")
                                }
                            }

                            if !part.script.isEmpty {
                                Text(String(part.script.prefix(100)) + (part.script.count > 100 ? "..." : ""))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }

                        Divider()

                        // Constraints section
                        constraintsSection(partId: part.id)

                        Divider()

                        // Delete part
                        Button(role: .destructive, action: {
                            let idToDelete = part.id
                            selectedPartIds = []
                            document.document.removeConstraintsForPart(idToDelete)
                            document.document.removePart(id: idToDelete)
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Part")
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            } else if currentTool == .pencil || currentTool == .spray || currentTool == .eraser {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Paint Tools")
                            .font(.headline)
                            .padding(.bottom, 4)

                        paintToolSection
                    }
                    .padding()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scripts")
                            .font(.headline)
                            .padding(.bottom, 4)
                        scriptsSection
                    }
                    .padding()
                }
            }
        }
        .frame(width: 260)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(item: $sceneGuideContext) { context in
            SpriteSceneSetupGuide(
                document: $document,
                partId: context.partId,
                sceneId: context.sceneId
            ) {
                sceneGuideContext = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSpriteNodeInInspector)) { notification in
            let info = notification.userInfo ?? [:]
            guard let partId = info["partId"] as? UUID,
                  let nodeId = info["nodeId"] as? UUID else { return }
            guard selectedPartIds.contains(partId) else { return }
            if let sceneId = info["sceneId"] as? UUID {
                document.document.updatePart(id: partId) { part in
                    part.updateSpriteAreaSpec { areaSpec in
                        _ = areaSpec.activateScene(id: sceneId)
                    }
                }
            }
            selectedNodeId = nodeId
        }
        .onChange(of: selectedPartIds) { _, _ in
            selectedNodeId = nil
        }
    }

    // MARK: - Multi-selection view

    private var multiSelectionView: some View {
        let selectedParts = document.document.parts.filter { selectedPartIds.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(selectedParts.count) Parts Selected")
                    .font(.headline)
                    .padding(.bottom, 4)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("ALIGNMENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        alignButton("Align Left", icon: "align.horizontal.left", notificationName: .alignLeft)
                        alignButton("Align Center", icon: "align.horizontal.center", notificationName: .alignHCenter)
                        alignButton("Align Right", icon: "align.horizontal.right", notificationName: .alignRight)
                    }
                    HStack(spacing: 4) {
                        alignButton("Align Top", icon: "align.vertical.top", notificationName: .alignTop)
                        alignButton("Align Middle", icon: "align.vertical.center", notificationName: .alignVCenter)
                        alignButton("Align Bottom", icon: "align.vertical.bottom", notificationName: .alignBottom)
                    }
                    HStack(spacing: 4) {
                        alignButton("Distribute H", icon: "distribute.horizontal.center", notificationName: .distributeH)
                        alignButton("Distribute V", icon: "distribute.vertical.center", notificationName: .distributeV)
                    }
                }

                Divider()

                // Common properties that can be bulk-edited
                VStack(alignment: .leading, spacing: 6) {
                    Text("COMMON PROPERTIES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Toggle("Visible", isOn: Binding(
                        get: { selectedParts.allSatisfy(\.visible) },
                        set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.visible = newVal } } }
                    ))
                    Toggle("Enabled", isOn: Binding(
                        get: { selectedParts.allSatisfy(\.enabled) },
                        set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.enabled = newVal } } }
                    ))
                }

                // Font properties if all selected parts are buttons or fields
                let hasText = selectedParts.allSatisfy { $0.partType == .button || $0.partType == .field }
                if hasText {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TEXT FORMATTING")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Font").font(.system(size: 11))
                            TextField("", text: Binding(
                                get: { selectedParts.first?.textFont ?? "" },
                                set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.textFont = newVal } } }
                            )).textFieldStyle(.roundedBorder).font(.system(size: 11))
                        }
                        HStack {
                            Text("Size").font(.system(size: 11))
                            TextField("", value: Binding(
                                get: { selectedParts.first?.textSize ?? 14 },
                                set: { newVal in for id in selectedPartIds { document.document.updatePart(id: id) { $0.textSize = newVal } } }
                            ), format: .number).textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 60)
                        }
                    }
                }

                Divider()

                // Delete all selected
                Button(role: .destructive, action: {
                    let ids = selectedPartIds
                    selectedPartIds = []
                    for id in ids {
                        document.document.removePart(id: id)
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete \(selectedParts.count) Parts")
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    private func alignButton(_ tooltip: String, icon: String, notificationName: Notification.Name) -> some View {
        Button(action: {
            NotificationCenter.default.post(name: notificationName, object: nil)
        }) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
        }
        .help(tooltip)
    }

    // MARK: - Paint Tool Section

    @ViewBuilder
    private var paintToolSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let toolLabel = currentTool == .pencil ? "Pencil" : currentTool == .spray ? "Spray" : "Eraser"
            Text(toolLabel).font(.subheadline).bold()

            if currentTool == .pencil || currentTool == .spray {
                HStack {
                    Text("Aperture")
                        .font(.system(size: 11))
                    Slider(value: $pencilRadius, in: 1...50, step: 1)
                    Text("\(Int(pencilRadius))")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 24, alignment: .trailing)
                }
            }

            if currentTool == .eraser {
                HStack {
                    Text("Radius")
                        .font(.system(size: 11))
                    Slider(value: $pencilRadius, in: 1...50, step: 1)
                    Text("\(Int(pencilRadius))")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 24, alignment: .trailing)
                }
            }

            if currentTool != .eraser {
                ColorPicker("Color", selection: $paintColor, supportsOpacity: false)
            }
        }
    }

    // MARK: - Scripts Section (no part selected)

    @ViewBuilder
    private var scriptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cardId = currentCardId {
                let card = document.document.cards.first(where: { $0.id == cardId })
                let cardName = card?.name.isEmpty == false ? card!.name : "Card"

                Button(action: {
                    openScriptEditorWindow(document: $document, target: .card(cardId))
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait")
                        Text("Edit \(cardName) Script...")
                    }
                }

                if let bgId = card?.backgroundId {
                    let bg = document.document.backgrounds.first(where: { $0.id == bgId })
                    let bgName = bg?.name.isEmpty == false ? bg!.name : "Background"
                    Button(action: {
                        openScriptEditorWindow(document: $document, target: .background(bgId))
                    }) {
                        HStack {
                            Image(systemName: "rectangle.on.rectangle")
                            Text("Edit \(bgName) Script...")
                        }
                    }
                }
            }

            Button(action: {
                openScriptEditorWindow(document: $document, target: .stack)
            }) {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text("Edit Stack Script...")
                }
            }

            Divider()

            // BACKGROUNDS browser
            //
            // Lists every background in the stack and lets the user
            // re-bind the current card to a different one. Without
            // this UI the only way to "use" a background was via
            // HypeTalk or a manual edit of the saved file — which
            // is what made `New Background...` look like a no-op
            // (the background existed but no surface in the app
            // showed it). The picker also includes a count so the
            // user gets immediate confirmation that creating a new
            // background actually worked.
            backgroundsPicker

            Divider()

            Button(action: {
                openScriptEditorWindow(document: $document, target: .hype)
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Edit Hype Script...")
                }
            }

            Text("Messages pass: part → card → background → stack → Hype")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    /// Listing of every background in the stack with a picker
    /// that re-assigns the current card to a different one,
    /// default-star controls, and delete buttons.
    @ViewBuilder
    private var backgroundsPicker: some View {
        let backgrounds = document.document.backgrounds
        let defaultId = document.document.resolvedDefaultBackgroundId
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("BACKGROUNDS").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                Text("(\(backgrounds.count))").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: .addNewBackground, object: nil)
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("New Background...")
            }

            // Picker for the current card's background.
            if let cardId = currentCardId,
               let cardIdx = document.document.cards.firstIndex(where: { $0.id == cardId }) {
                Picker("Card uses", selection: bindCardBackground(cardIndex: cardIdx)) {
                    ForEach(backgrounds, id: \.id) { bg in
                        Text(bg.name.isEmpty ? "Background \(bg.id.uuidString.prefix(4))" : bg.name)
                            .tag(bg.id)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 11))
            }

            // Background list with default star, card count, and delete.
            ForEach(backgrounds, id: \.id) { bg in
                let isDefault = bg.id == defaultId
                let cardCount = document.document.cardsForBackground(bg.id).count
                HStack(spacing: 4) {
                    Button(action: {
                        document.document.defaultBackgroundId = bg.id
                    }) {
                        Image(systemName: isDefault ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundColor(isDefault ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isDefault ? "Default background" : "Set as default background")

                    Text(bg.name.isEmpty ? "Background \(bg.id.uuidString.prefix(4))" : bg.name)
                        .font(.system(size: 10))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(cardCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .help("\(cardCount) card\(cardCount == 1 ? "" : "s") on this background")

                    Button(action: {
                        deleteBackground(id: bg.id, name: bg.name)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(backgrounds.count > 1 ? .secondary : .secondary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(backgrounds.count <= 1)
                    .help(backgrounds.count > 1 ? "Delete background" : "Cannot delete the last background")
                }
            }
        }
    }

    /// Show a confirmation alert and remove the background if confirmed.
    private func deleteBackground(id: UUID, name: String) {
        let alert = NSAlert()
        alert.messageText = "Delete Background"
        alert.informativeText = "Delete \"\(name)\"? Cards using it will be reassigned to the default background."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        document.document.removeBackground(id: id)
    }

    /// Binding for the current card's `backgroundId`, with the
    /// write side updating the card model directly. Lets the
    /// SwiftUI Picker drive the actual document state.
    private func bindCardBackground(cardIndex: Int) -> Binding<UUID> {
        Binding(
            get: { document.document.cards[cardIndex].backgroundId },
            set: { newId in
                document.document.cards[cardIndex].backgroundId = newId
            }
        )
    }

    // MARK: - Sections

    @ViewBuilder
    private func commonSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Identity").font(.subheadline).foregroundColor(.secondary)
            propertyRow("Name", binding: bindPartString(part.id, \.name))
            propertyRow("Type", value: part.partType.rawValue.capitalized)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Position").font(.subheadline).foregroundColor(.secondary)
            HStack {
                numberField("X", binding: bindPartDouble(part.id, \.left))
                numberField("Y", binding: bindPartDouble(part.id, \.top))
            }
            HStack {
                numberField("W", binding: bindPartDouble(part.id, \.width))
                numberField("H", binding: bindPartDouble(part.id, \.height))
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("State").font(.subheadline).foregroundColor(.secondary)
            Toggle("Visible", isOn: bindPartBool(part.id, \.visible))
            Toggle("Enabled", isOn: bindPartBool(part.id, \.enabled))
        }
    }

    @ViewBuilder
    private func buttonSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Button").font(.subheadline).foregroundColor(.secondary)
            Picker("Style", selection: bindPartButtonStyle(part.id)) {
                ForEach(HypeCore.ButtonStyle.pickerCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            propertyRow("Label", binding: bindPartString(part.id, \.textContent))
            Toggle("Show Name", isOn: bindPartBool(part.id, \.showName))
            Toggle("Auto Hilite", isOn: bindPartBool(part.id, \.autoHilite))

            // Popup items editor (only shown for popup style)
            if part.buttonStyle == .popup {
                Divider()
                Text("POPUP ITEMS").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                Text("One item per line. First item is the default selection.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                TextEditor(text: bindPartString(part.id, \.popupItems))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.gray.opacity(0.5))
            }

        }
    }

    @ViewBuilder
    private func fieldSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Field").font(.subheadline).foregroundColor(.secondary)
            Picker("Style", selection: bindPartFieldStyle(part.id)) {
                ForEach(HypeCore.FieldStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            Toggle("Lock Text", isOn: bindPartBool(part.id, \.lockText))
            Toggle("Don't Wrap", isOn: bindPartBool(part.id, \.dontWrap))
            Toggle("Rich Text", isOn: bindPartBool(part.id, \.richText))
            Toggle("Wide Margins", isOn: bindPartBool(part.id, \.wideMargins))

            Divider()
            Text("Events").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
            Toggle("Enter Key Event", isOn: Binding(
                get: { document.document.parts.first(where: { $0.id == part.id })?.enterKeyEnabled ?? false },
                set: { newValue in
                    document.document.updatePart(id: part.id) { p in
                        p.enterKeyEnabled = newValue
                        // Auto-add template script if enabling and no enterKey handler exists
                        if newValue && !p.script.lowercased().contains("on enterkey") {
                            let template = "on enterKey\n  -- Runs when Enter is pressed in this field\n  \nend enterKey"
                            if p.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                p.script = template
                            } else {
                                p.script += "\n\n" + template
                            }
                        }
                    }
                }
            ))
            if part.enterKeyEnabled {
                Text("Press Enter in browse mode to trigger the enterKey handler")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Text("Content").font(.system(size: 11)).foregroundColor(.secondary)
                TextEditor(text: bindPartString(part.id, \.textContent))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.gray.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func shapeSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape").font(.subheadline).foregroundColor(.secondary)
            Picker("Shape", selection: bindPartShapeType(part.id)) {
                ForEach(HypeCore.ShapeType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            ColorPicker("Fill", selection: bindPartColor(part.id, \.fillColor))
            ColorPicker("Stroke", selection: bindPartColor(part.id, \.strokeColor))
            numberField("Stroke Width", binding: bindPartDouble(part.id, \.strokeWidth))
            numberField("Corner Radius", binding: bindPartDouble(part.id, \.cornerRadius))
        }
    }

    @ViewBuilder
    private func webpageSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Web Page").font(.subheadline).foregroundColor(.secondary)
            propertyRow("URL", binding: bindPartString(part.id, \.url))
        }
    }

    @ViewBuilder
    private func imageSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Image").font(.subheadline).foregroundColor(.secondary)

            Button("Choose Image...") {
                chooseImageForPart(partId: part.id)
            }

            Toggle("Invert on Click", isOn: bindPartBool(part.id, \.invertOnClick))
            // Custom binding: flipping the `animated` flag must also tell
            // the animator to start or stop. A plain `bindPartBool` would
            // mutate the Part model without touching the animator's
            // internal `isRunning` state, leaving a GIF playing forever
            // even after the user toggled it off (reported regression:
            // "It also would not stop animating when I toggled the
            // animated property").
            Toggle("Animated", isOn: bindAnimatedToggle(part.id))

            if let data = part.imageData {
                Text("Image loaded (\(data.count / 1024) KB)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func videoSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Video").font(.subheadline).foregroundColor(.secondary)
            propertyRow("URL/Path", binding: bindPartString(part.id, \.videoURL))
            Button("Choose Video...") {
                chooseVideoForPart(partId: part.id)
            }
            if !part.videoURL.isEmpty {
                Text(part.videoURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func chooseVideoForPart(partId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .movie, .quickTimeMovie]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            document.document.updatePart(id: partId) { $0.videoURL = url.absoluteString }
        }
    }

    private func chooseImageForPart(partId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                document.document.updatePart(id: partId) { $0.imageData = data }
            }
        }
    }

    @ViewBuilder
    private func spriteAreaSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sprite Area").font(.subheadline).bold()

            if let areaSpec = part.spriteAreaSpecModel,
               let spec = areaSpec.activeScene {
                HStack {
                    Text("Active Scene").font(.system(size: 11))
                    Spacer()
                    Picker("Active Scene", selection: bindActiveSceneId(part.id)) {
                        ForEach(areaSpec.scenes) { entry in
                            Text(entry.scene.name).tag(entry.id)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 11))
                    Button(action: { addScene(partId: part.id) }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Add Scene")
                }

                HStack(spacing: 8) {
                    Button("Guide Setup") {
                        sceneGuideContext = SpriteSceneGuideContext(partId: part.id, sceneId: areaSpec.activeSceneEntry?.id)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)

                    Button("Scene Script") {
                        if let sceneId = areaSpec.activeSceneEntry?.id {
                            openScriptEditorWindow(document: $document, target: .scene(partId: part.id, sceneId: sceneId))
                        }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)

                    Button("Repository") {
                        openSpriteRepositoryWindow(document: $document)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }

                propertyRow("Scene Name", binding: bindSceneSpecString(part.id, \.name))
                propertyRow("Nodes", value: "\(spec.nodes.count)")
                propertyRow("Size", value: "\(Int(spec.size.width)) \u{00d7} \(Int(spec.size.height))")

                let checklist = spec.authoringChecklist(using: document.document.spriteRepository)
                Divider()
                Text("Setup Checklist").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                ForEach(checklist) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: checklistIcon(for: item.status))
                            .font(.system(size: 9))
                            .foregroundColor(checklistColor(for: item.status))
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 10, weight: .medium))
                            Text(item.detail).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                }

                Picker("Scale", selection: bindSceneScaleMode(part.id)) {
                    ForEach(SceneScaleMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .font(.system(size: 11))

                Divider()
                Text("Physics").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                HStack {
                    Text("Gravity").font(.system(size: 11))
                    Spacer()
                    numberField("dx", binding: bindSceneSpecDouble(part.id, \.gravity.dx))
                    numberField("dy", binding: bindSceneSpecDouble(part.id, \.gravity.dy))
                }

                Divider()
                Text("Controls").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Button(action: { toggleScenePause(partId: part.id) }) {
                        Image(systemName: spec.isPaused ? "play.fill" : "pause.fill")
                    }
                    .help(spec.isPaused ? "Play" : "Pause")

                    Button(action: { stepScene(partId: part.id) }) {
                        Image(systemName: "forward.frame.fill")
                    }
                    .help("Step One Frame")

                    Button(action: { reloadScene(partId: part.id) }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload Scene")
                }
                .buttonStyle(.borderless)

                Divider()
                Text("Debug").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                Toggle("Show FPS", isOn: bindSceneSpecBool(part.id, \.showsFPS))
                Toggle("Show Physics", isOn: bindSceneSpecBool(part.id, \.showsPhysics))
                Toggle("Show Node Count", isOn: bindSceneSpecBool(part.id, \.showsNodeCount))
                Toggle("Paused", isOn: bindSceneSpecBool(part.id, \.isPaused))

                Divider()
                Text("Nodes").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)

                if !spec.nodes.isEmpty {
                    nodeTreeView(partId: part.id, nodes: spec.nodes, depth: 0)

                    // Drop zone for reparenting to top level
                    HStack {
                        Image(systemName: "arrow.turn.up.left")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Drop here for top level")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(4)
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        guard let sourceId = draggedNodeId else { return false }
                        modifySceneSpec(partId: part.id) { spec in
                            guard let sourceNode = Self.removeNodeFromTree(nodeId: sourceId, from: &spec.nodes) else { return }
                            spec.nodes.append(sourceNode)
                        }
                        draggedNodeId = nil
                        return true
                    }
                }

                Menu {
                    Button("Sprite")  { addSpriteNode(partId: part.id) }
                    Button("Shape")   { addShapeNode(partId: part.id) }
                    Button("Label")   { addLabelNode(partId: part.id) }
                    Divider()
                    Button("Emitter") { addEmitterNode(partId: part.id) }
                    Button("Audio")   { addAudioNode(partId: part.id) }
                    Button("Video")   { addVideoNode(partId: part.id) }
                    Divider()
                    Button("Camera")  { addCameraNode(partId: part.id) }
                    Divider()
                    Button("Group")   { addGroupNode(partId: part.id) }
                } label: {
                    Label("Add Node", systemImage: "plus.circle")
                        .font(.system(size: 11))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No scene configured")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Button("Open Guided Setup") {
                        sceneGuideContext = SpriteSceneGuideContext(partId: part.id, sceneId: nil)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func checklistIcon(for status: SceneChecklistStatus) -> String {
        switch status {
        case .complete: return "checkmark.circle.fill"
        case .recommended: return "exclamationmark.circle"
        case .missing: return "xmark.circle"
        }
    }

    private func checklistColor(for status: SceneChecklistStatus) -> Color {
        switch status {
        case .complete: return .green
        case .recommended: return .orange
        case .missing: return .red
        }
    }

    private func nodeIcon(_ type: NodeType) -> String {
        switch type {
        case .sprite: return "photo"
        case .label: return "textformat"
        case .shape: return "square"
        case .group: return "folder"
        case .emitter: return "sparkles"
        case .audio: return "waveform"
        case .tileMap: return "square.grid.3x3"
        case .camera: return "camera"
        case .video: return "play.rectangle"
        case .crop: return "crop"
        case .effect: return "wand.and.stars"
        case .light: return "lightbulb"
        }
    }

    // MARK: - Node Tree View

    private func nodeTreeView(partId: UUID, nodes: [HypeNodeSpec], depth: Int) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                VStack(alignment: .leading, spacing: 0) {
                    // Node header row — indented by depth
                    HStack(spacing: 4) {
                        Spacer().frame(width: CGFloat(depth) * 16)

                        // Disclosure triangle for nodes with children
                        if !node.children.isEmpty {
                            Image(systemName: selectedNodeId == node.id ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        } else {
                            Spacer().frame(width: 10)
                        }

                        Image(systemName: nodeIcon(node.nodeType))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("name", text: bindNodeName(partId: partId, nodeId: node.id))
                            .font(.system(size: 11))
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity)
                        if !node.children.isEmpty {
                            Text("(\(node.children.count))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        Text(node.nodeType.rawValue)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Button(action: {
                            openScriptEditorWindow(document: $document, target: .node(partId: partId, nodeId: node.id))
                        }) {
                            Image(systemName: "applescript")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        Button(action: { removeSceneNode(partId: partId, nodeId: node.id) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedNodeId = selectedNodeId == node.id ? nil : node.id }
                    .padding(.vertical, 2)
                    .background(selectedNodeId == node.id ? Color.accentColor.opacity(0.08) : Color.clear)
                    .cornerRadius(4)
                    // Drag source
                    .onDrag {
                        draggedNodeId = node.id
                        return NSItemProvider(object: node.id.uuidString as NSString)
                    }
                    // Drop target — reparent dragged node to this node
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        guard let sourceId = draggedNodeId, sourceId != node.id else { return false }
                        modifySceneSpec(partId: partId) { spec in
                            guard let sourceNode = Self.removeNodeFromTree(nodeId: sourceId, from: &spec.nodes) else { return }
                            Self.addNodeToParentInTree(node: sourceNode, parentId: node.id, nodes: &spec.nodes)
                        }
                        draggedNodeId = nil
                        return true
                    }

                    // Expanded detail panel
                    if selectedNodeId == node.id {
                        nodeDetailPanel(partId: partId, node: node)
                            .padding(.leading, CGFloat(depth) * 16 + 16)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(4)
                    }

                    // Recursively show children
                    if !node.children.isEmpty {
                        nodeTreeView(partId: partId, nodes: node.children, depth: depth + 1)
                    }
                }
            }
        )
    }

    // MARK: - Node Hierarchy Helpers

    /// Recursively remove a node by ID from a node tree. Returns the removed node.
    @discardableResult
    private static func removeNodeFromTree(nodeId: UUID, from nodes: inout [HypeNodeSpec]) -> HypeNodeSpec? {
        if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
            return nodes.remove(at: idx)
        }
        for i in 0..<nodes.count {
            if let removed = removeNodeFromTree(nodeId: nodeId, from: &nodes[i].children) {
                return removed
            }
        }
        return nil
    }

    /// Recursively add a node as a child of a target parent node by ID.
    private static func addNodeToParentInTree(node: HypeNodeSpec, parentId: UUID, nodes: inout [HypeNodeSpec]) {
        for i in 0..<nodes.count {
            if nodes[i].id == parentId {
                nodes[i].children.append(node)
                return
            }
            addNodeToParentInTree(node: node, parentId: parentId, nodes: &nodes[i].children)
        }
    }

    /// Recursively add a node as a child of a target parent node by name.
    private static func addNodeToParentByName(node: HypeNodeSpec, parentName: String, nodes: inout [HypeNodeSpec]) -> Bool {
        for i in 0..<nodes.count {
            if nodes[i].name.lowercased() == parentName.lowercased() {
                nodes[i].children.append(node)
                return true
            }
            if addNodeToParentByName(node: node, parentName: parentName, nodes: &nodes[i].children) {
                return true
            }
        }
        return false
    }

    /// Recursively update a node by ID in a node tree.
    @discardableResult
    private static func updateNodeInTree(nodeId: UUID, in nodes: inout [HypeNodeSpec], transform: (inout HypeNodeSpec) -> Void) -> Bool {
        for i in 0..<nodes.count {
            if nodes[i].id == nodeId {
                transform(&nodes[i])
                return true
            }
            if updateNodeInTree(nodeId: nodeId, in: &nodes[i].children, transform: transform) {
                return true
            }
        }
        return false
    }

    /// Recursively find a node by ID in a node tree.
    private static func findNodeById(_ nodeId: UUID, in nodes: [HypeNodeSpec]) -> HypeNodeSpec? {
        for node in nodes {
            if node.id == nodeId { return node }
            if let found = findNodeById(nodeId, in: node.children) { return found }
        }
        return nil
    }

    /// Find the parent name of a node by ID. Returns empty string if top-level.
    private static func findParentName(of nodeId: UUID, in nodes: [HypeNodeSpec], parentName: String) -> String? {
        for node in nodes {
            if node.id == nodeId { return parentName }
            if let result = findParentName(of: nodeId, in: node.children, parentName: node.name) {
                return result
            }
        }
        return nil
    }

    /// Collect all group names in the node tree, excluding a specific node ID.
    private func getAllGroupNames(partId: UUID, excludeNodeId: UUID) -> [String] {
        let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
        guard let spec = SceneSpec.fromJSON(json) else { return [] }
        var names: [String] = []
        Self.collectGroupNames(from: spec.nodes, excluding: excludeNodeId, into: &names)
        return names
    }

    private static func collectGroupNames(from nodes: [HypeNodeSpec], excluding: UUID, into names: inout [String]) {
        for node in nodes {
            if node.nodeType == .group && node.id != excluding && !node.name.isEmpty {
                names.append(node.name)
            }
            collectGroupNames(from: node.children, excluding: excluding, into: &names)
        }
    }

    /// Binding for the parent of a node — used in the Parent picker.
    private func bindNodeParent(partId: UUID, nodeId: UUID) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                guard let spec = SceneSpec.fromJSON(json) else { return "" }
                return Self.findParentName(of: nodeId, in: spec.nodes, parentName: "") ?? ""
            },
            set: { newParent in
                modifySceneSpec(partId: partId) { spec in
                    guard let node = Self.removeNodeFromTree(nodeId: nodeId, from: &spec.nodes) else { return }
                    if newParent.isEmpty {
                        spec.nodes.append(node)
                    } else {
                        if !Self.addNodeToParentByName(node: node, parentName: newParent, nodes: &spec.nodes) {
                            // If parent not found, add to top level as fallback
                            spec.nodes.append(node)
                        }
                    }
                }
            }
        )
    }

    /// Helper binding for SceneSpec boolean properties.
    private func bindSceneSpecBool(_ partId: UUID, _ keyPath: WritableKeyPath<SceneSpec, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return spec[keyPath: keyPath]
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { $0[keyPath: keyPath] = newVal }
            }
        )
    }

    /// Reads the SceneSpec JSON from a part, applies a mutation, and writes it back.
    private func modifySceneSpec(partId: UUID, transform: (inout SceneSpec) -> Void) {
        document.document.updatePart(id: partId) { part in
            part.updateActiveSceneSpec(transform)
        }
    }

    private func bindActiveSceneId(_ partId: UUID) -> Binding<UUID> {
        Binding(
            get: {
                document.document.parts.first(where: { $0.id == partId })?.activeSceneID ?? UUID()
            },
            set: { newSceneId in
                document.document.updatePart(id: partId) { part in
                    part.updateSpriteAreaSpec { areaSpec in
                        _ = areaSpec.activateScene(id: newSceneId)
                    }
                }
            }
        )
    }

    private func addScene(partId: UUID) {
        document.document.updatePart(id: partId) { part in
            part.updateSpriteAreaSpec { areaSpec in
                _ = areaSpec.addScene(named: "Scene", basedOn: areaSpec.activeScene)
            }
        }
    }

    /// Binding helper for SceneSpec string properties.
    private func bindSceneSpecString(_ partId: UUID, _ keyPath: WritableKeyPath<SceneSpec, String>) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return spec[keyPath: keyPath]
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { $0[keyPath: keyPath] = newVal }
            }
        )
    }

    /// Binding helper for SceneSpec double properties.
    private func bindSceneSpecDouble(_ partId: UUID, _ keyPath: WritableKeyPath<SceneSpec, Double>) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return spec[keyPath: keyPath]
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { $0[keyPath: keyPath] = newVal }
            }
        )
    }

    private func addSpriteNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            let node = HypeNodeSpec(
                name: "sprite \(count)",
                nodeType: .sprite,
                position: PointSpec(x: 100, y: 100),
                size: SizeSpec(width: 48, height: 48)
            )
            spec.nodes.append(node)
        }
    }

    private func addShapeNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            let node = HypeNodeSpec(
                name: "shape \(count)",
                nodeType: .shape,
                position: PointSpec(x: 100, y: 100),
                shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#FFFFFF", strokeColor: "#000000", lineWidth: 1)
            )
            spec.nodes.append(node)
        }
    }

    private func addLabelNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            let node = HypeNodeSpec(
                name: "label \(count)",
                nodeType: .label,
                position: PointSpec(x: 100, y: 100),
                text: "Label",
                fontName: "Helvetica",
                fontSize: 24,
                fontColor: "#000000"
            )
            spec.nodes.append(node)
        }
    }

    private func addEmitterNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            var node = HypeNodeSpec(
                name: "emitter \(count)",
                nodeType: .emitter,
                position: PointSpec(x: 100, y: 100)
            )
            node.emitterSpec = EmitterSpec()
            spec.nodes.append(node)
        }
    }

    private func addVideoNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            let node = HypeNodeSpec(
                name: "video \(count)",
                nodeType: .video,
                position: PointSpec(x: 100, y: 100),
                size: SizeSpec(width: 320, height: 240),
                videoAutoplay: true
            )
            spec.nodes.append(node)
        }
    }

    private func addAudioNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            var node = HypeNodeSpec(
                name: "audio \(count)",
                nodeType: .audio,
                position: PointSpec(x: 100, y: 100)
            )
            node.audioAutoplay = true
            node.audioLoop = false
            spec.nodes.append(node)
        }
    }

    private func addCameraNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            let node = HypeNodeSpec(
                name: "camera \(count)",
                nodeType: .camera,
                position: PointSpec(x: spec.size.width / 2, y: spec.size.height / 2)
            )
            spec.nodes.append(node)
        }
    }

    private func addGroupNode(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            let count = spec.nodes.count + 1
            let node = HypeNodeSpec(
                name: "group \(count)",
                nodeType: .group,
                position: PointSpec(x: 0, y: 0)
            )
            spec.nodes.append(node)
        }
    }

    private func bindSceneScaleMode(_ partId: UUID) -> Binding<SceneScaleMode> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                return SceneSpec.fromJSON(json)?.scaleMode ?? .aspectFit
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { $0.scaleMode = newVal }
            }
        )
    }

    private func removeSceneNode(partId: UUID, nodeId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            Self.removeNodeFromTree(nodeId: nodeId, from: &spec.nodes)
        }
    }

    // MARK: - Scene Controls

    private func toggleScenePause(partId: UUID) {
        modifySceneSpec(partId: partId) { spec in
            spec.isPaused.toggle()
        }
    }

    private func stepScene(partId: UUID) {
        // Step = unpause for one frame, then re-pause
        modifySceneSpec(partId: partId) { spec in
            spec.isPaused = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            modifySceneSpec(partId: partId) { spec in
                spec.isPaused = true
            }
        }
    }

    private func reloadScene(partId: UUID) {
        // Force a scene rebuild by clearing and restoring the sceneSpec
        guard let idx = document.document.parts.firstIndex(where: { $0.id == partId }) else { return }
        let spec = document.document.parts[idx].sceneSpec
        document.document.parts[idx].sceneSpec = ""
        DispatchQueue.main.async {
            document.document.parts[idx].sceneSpec = spec
        }
    }

    private func bindNodeName(partId: UUID, nodeId: UUID) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.name ?? ""
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0.name = newVal }
                }
            }
        )
    }

    // MARK: - Node Detail Panel

    @ViewBuilder
    private func nodeDetailPanel(partId: UUID, node: HypeNodeSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Node Script") {
                    openScriptEditorWindow(document: $document, target: .node(partId: partId, nodeId: node.id))
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)

                if let assetId = node.assetRef?.id {
                    Button("Reveal Asset") {
                        openSpriteRepositoryWindow(document: $document, initialAssetId: assetId)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }
            }

            // -- Common properties (all node types) --
            Text("POSITION").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
            HStack {
                numberField("X", binding: bindNodePositionX(partId: partId, nodeId: node.id))
                numberField("Y", binding: bindNodePositionY(partId: partId, nodeId: node.id))
            }
            HStack {
                numberField("W", binding: bindNodeWidth(partId: partId, nodeId: node.id))
                numberField("H", binding: bindNodeHeight(partId: partId, nodeId: node.id))
            }
            HStack {
                numberField("Rotation", binding: bindNodeDouble(partId: partId, nodeId: node.id, \.rotation))
                numberField("Z", binding: bindNodeDouble(partId: partId, nodeId: node.id, \.zPosition))
            }
            HStack {
                Text("Alpha").font(.system(size: 10)).foregroundColor(.secondary)
                Slider(value: bindNodeDouble(partId: partId, nodeId: node.id, \.alpha), in: 0...1)
                Text(String(format: "%.1f", node.alpha)).font(.system(size: 10, design: .monospaced)).frame(width: 28)
            }
            Toggle("Hidden", isOn: bindNodeBool(partId: partId, nodeId: node.id, \.isHidden))
                .font(.system(size: 11))

            // Parent assignment
            let allGroupNames = getAllGroupNames(partId: partId, excludeNodeId: node.id)
            if !allGroupNames.isEmpty {
                Picker("Parent", selection: bindNodeParent(partId: partId, nodeId: node.id)) {
                    Text("(top level)").tag("" as String)
                    ForEach(allGroupNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .font(.system(size: 11))
            }

            Divider()

            // -- Type-specific properties --
            switch node.nodeType {
            case .sprite:
                spriteNodeProperties(partId: partId, node: node)
            case .label:
                labelNodeProperties(partId: partId, node: node)
            case .shape:
                shapeNodeProperties(partId: partId, node: node)
            case .audio:
                audioNodeProperties(partId: partId, node: node)
            case .emitter:
                emitterNodeProperties(partId: partId, node: node)
            case .video:
                videoNodeProperties(partId: partId, node: node)
            case .crop:
                Text("CROP").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Text("Uses asset as mask texture").font(.system(size: 10)).foregroundColor(.secondary)
                spriteNodeProperties(partId: partId, node: node)
            case .effect:
                Text("EFFECT").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Text("Applies Core Image filter").font(.system(size: 10)).foregroundColor(.secondary)
            case .light:
                Text("LIGHT").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Text("Illuminates sprites with lighting").font(.system(size: 10)).foregroundColor(.secondary)
            case .group, .tileMap, .camera:
                EmptyView()
            }

            // -- Physics properties (all node types except group) --
            if node.nodeType != .group {
                Divider()
                physicsNodeProperties(partId: partId, node: node)
            }
        }
    }

    // MARK: - Type-Specific Node Properties

    @ViewBuilder
    private func spriteNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        Text("SPRITE").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)

        let imageAssets = document.document.spriteRepository.assets.filter {
            $0.kind == .imageTexture || $0.kind == .spriteSheet
        }

        if imageAssets.isEmpty {
            Text("No assets -- open Sprite Repository to import")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        } else {
            Picker("Asset", selection: bindNodeAsset(partId: partId, nodeId: node.id)) {
                Text("None").tag(nil as UUID?)
                ForEach(imageAssets) { asset in
                    Text(asset.name).tag(asset.id as UUID?)
                }
            }
            .font(.system(size: 11))

            // Show thumbnail preview of selected asset
            if let ref = node.assetRef, let asset = document.document.spriteRepository.asset(byId: ref.id) {
                if let img = NSImage(data: asset.data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 48)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }

    @ViewBuilder
    private func labelNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        Text("LABEL").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
        propertyRow("Text", binding: bindNodeOptionalString(partId: partId, nodeId: node.id, \.text))

        Picker("Font", selection: bindNodeOptionalString(partId: partId, nodeId: node.id, \.fontName)) {
            ForEach(systemFontFamilies, id: \.self) { fontName in
                Text(fontName).font(.system(size: 11)).tag(fontName as String?)
            }
        }
        .font(.system(size: 11))

        numberField("Size", binding: bindNodeOptionalDouble(partId: partId, nodeId: node.id, \.fontSize))

        ColorPicker("Color", selection: bindNodeColor(partId: partId, nodeId: node.id, getter: { $0.fontColor }, setter: { $0.fontColor = $1 }))
    }

    @ViewBuilder
    private func shapeNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        Text("SHAPE").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)

        Picker("Type", selection: bindShapeType(partId: partId, nodeId: node.id)) {
            ForEach(SpriteShapeType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .font(.system(size: 11))

        ColorPicker("Fill", selection: bindShapeFillColor(partId: partId, nodeId: node.id))
        ColorPicker("Stroke", selection: bindShapeStrokeColor(partId: partId, nodeId: node.id))
        numberField("Line Width", binding: bindShapeLineWidth(partId: partId, nodeId: node.id))
        numberField("Corner Radius", binding: bindShapeCornerRadius(partId: partId, nodeId: node.id))
    }

    @ViewBuilder
    private func audioNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        Text("AUDIO").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)

        let audioAssets = document.document.spriteRepository.assets.filter { $0.kind == .audioClip }

        if audioAssets.isEmpty {
            Text("No audio assets -- open Sprite Repository to import")
                .font(.system(size: 10)).foregroundColor(.secondary)
        } else {
            Picker("Asset", selection: bindNodeAsset(partId: partId, nodeId: node.id)) {
                Text("None").tag(nil as UUID?)
                ForEach(audioAssets) { asset in
                    Text(asset.name).tag(asset.id as UUID?)
                }
            }
            .font(.system(size: 11))
        }

        Toggle("Loop", isOn: bindNodeOptionalBool(partId: partId, nodeId: node.id, \.audioLoop))
            .font(.system(size: 11))
        Toggle("Autoplay", isOn: bindNodeOptionalBool(partId: partId, nodeId: node.id, \.audioAutoplay))
            .font(.system(size: 11))
        HStack {
            Text("Volume").font(.system(size: 10)).foregroundColor(.secondary)
            Slider(value: bindNodeOptionalDouble(partId: partId, nodeId: node.id, \.audioVolume), in: 0...1)
        }
    }

    @ViewBuilder
    private func videoNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        Text("VIDEO").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)

        let videoAssets = document.document.spriteRepository.assets.filter { $0.kind == .videoClip }

        if videoAssets.isEmpty {
            Text("No video assets -- open Sprite Repository to import")
                .font(.system(size: 10)).foregroundColor(.secondary)
        } else {
            Picker("Asset", selection: bindNodeAsset(partId: partId, nodeId: node.id)) {
                Text("None").tag(nil as UUID?)
                ForEach(videoAssets) { asset in
                    Text(asset.name).tag(asset.id as UUID?)
                }
            }
            .font(.system(size: 11))
        }

        Toggle("Loop", isOn: bindNodeOptionalBool(partId: partId, nodeId: node.id, \.videoLoop))
            .font(.system(size: 11))
        Toggle("Autoplay", isOn: bindNodeOptionalBool(partId: partId, nodeId: node.id, \.videoAutoplay))
            .font(.system(size: 11))

        HStack {
            numberField("W", binding: bindNodeWidth(partId: partId, nodeId: node.id))
            numberField("H", binding: bindNodeHeight(partId: partId, nodeId: node.id))
        }
    }

    @ViewBuilder
    private func emitterNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        Text("EMITTER").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)

        HStack {
            numberField("Birth Rate", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleBirthRate))
            numberField("Lifetime", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleLifetime))
        }
        HStack {
            numberField("Speed", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleSpeed))
            numberField("Speed Range", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleSpeedRange))
        }
        HStack {
            numberField("Angle", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.emissionAngle))
            numberField("Angle Range", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.emissionAngleRange))
        }
        HStack {
            Text("Alpha").font(.system(size: 10)).foregroundColor(.secondary)
            Slider(value: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleAlpha), in: 0...1)
            Text(String(format: "%.1f", node.emitterSpec?.particleAlpha ?? 1))
                .font(.system(size: 10, design: .monospaced)).frame(width: 28)
        }
        numberField("Alpha Speed", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleAlphaSpeed))
        HStack {
            Text("Scale").font(.system(size: 10)).foregroundColor(.secondary)
            Slider(value: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleScale), in: 0...2)
            Text(String(format: "%.2f", node.emitterSpec?.particleScale ?? 0.3))
                .font(.system(size: 10, design: .monospaced)).frame(width: 36)
        }
        numberField("Scale Speed", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particleScaleSpeed))
        ColorPicker("Particle Color", selection: bindEmitterColor(partId: partId, nodeId: node.id))
        HStack {
            numberField("Pos Range X", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particlePositionRangeX))
            numberField("Pos Range Y", binding: bindEmitterDouble(partId: partId, nodeId: node.id, \.particlePositionRangeY))
        }
    }

    // MARK: - Emitter Binding Helpers

    /// Generic Double binding for EmitterSpec fields.
    private func bindEmitterDouble(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<EmitterSpec, Double>) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                guard let node = Self.findNodeById(nodeId, in: spec.nodes),
                      let emitter = node.emitterSpec else { return 0 }
                return emitter[keyPath: keyPath]
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.emitterSpec == nil { $0.emitterSpec = EmitterSpec() }
                        $0.emitterSpec?[keyPath: keyPath] = newVal
                    }
                }
            }
        )
    }

    /// Color binding for EmitterSpec particle color.
    private func bindEmitterColor(partId: UUID, nodeId: UUID) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                let hex = Self.findNodeById(nodeId, in: spec.nodes)?.emitterSpec?.particleColor ?? "#FFFFFF"
                return Color(hex: hex)
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.emitterSpec == nil { $0.emitterSpec = EmitterSpec() }
                        $0.emitterSpec?.particleColor = newVal.toHex()
                    }
                }
            }
        )
    }

    // MARK: - Physics Node Properties

    @ViewBuilder
    private func physicsNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        Text("PHYSICS").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)

        // Enable physics toggle
        Toggle("Enable Physics", isOn: bindNodeHasPhysics(partId: partId, nodeId: node.id))
            .font(.system(size: 11))

        if node.physicsBody != nil {
            // Body type picker
            Picker("Body", selection: bindPhysicsBodyType(partId: partId, nodeId: node.id)) {
                Text("Circle").tag(PhysicsBodyType.circle)
                Text("Rectangle").tag(PhysicsBodyType.rect)
            }
            .font(.system(size: 11))

            Toggle("Dynamic", isOn: bindPhysicsBool(partId: partId, nodeId: node.id, \.isDynamic))
                .font(.system(size: 11))
            Toggle("Gravity", isOn: bindPhysicsBool(partId: partId, nodeId: node.id, \.affectedByGravity))
                .font(.system(size: 11))
            Toggle("Rotation", isOn: bindPhysicsBool(partId: partId, nodeId: node.id, \.allowsRotation))
                .font(.system(size: 11))

            HStack {
                Text("Bounce").font(.system(size: 10)).foregroundColor(.secondary)
                Slider(value: bindPhysicsDouble(partId: partId, nodeId: node.id, \.restitution), in: 0...1)
                Text(String(format: "%.1f", node.physicsBody?.restitution ?? 0.2))
                    .font(.system(size: 10, design: .monospaced)).frame(width: 28)
            }
            HStack {
                Text("Friction").font(.system(size: 10)).foregroundColor(.secondary)
                Slider(value: bindPhysicsDouble(partId: partId, nodeId: node.id, \.friction), in: 0...1)
                Text(String(format: "%.1f", node.physicsBody?.friction ?? 0.2))
                    .font(.system(size: 10, design: .monospaced)).frame(width: 28)
            }
        }
    }

    // MARK: - Physics Binding Helpers

    private func bindNodeHasPhysics(partId: UUID, nodeId: UUID) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.physicsBody != nil
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if newVal {
                            $0.physicsBody = PhysicsBodySpec()
                        } else {
                            $0.physicsBody = nil
                        }
                    }
                }
            }
        )
    }

    private func bindPhysicsBodyType(partId: UUID, nodeId: UUID) -> Binding<PhysicsBodyType> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.physicsBody?.bodyType ?? .rect
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.physicsBody == nil { $0.physicsBody = PhysicsBodySpec() }
                        $0.physicsBody?.bodyType = newVal
                    }
                }
            }
        )
    }

    private func bindPhysicsBool(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<PhysicsBodySpec, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.physicsBody?[keyPath: keyPath] ?? true
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.physicsBody == nil { $0.physicsBody = PhysicsBodySpec() }
                        $0.physicsBody?[keyPath: keyPath] = newVal
                    }
                }
            }
        )
    }

    private func bindPhysicsDouble(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<PhysicsBodySpec, Double>) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.physicsBody?[keyPath: keyPath] ?? 0
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.physicsBody == nil { $0.physicsBody = PhysicsBodySpec() }
                        $0.physicsBody?[keyPath: keyPath] = newVal
                    }
                }
            }
        )
    }

    // MARK: - Node Binding Helpers

    /// Generic Double binding for HypeNodeSpec fields.
    private func bindNodeDouble(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<HypeNodeSpec, Double>) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?[keyPath: keyPath] ?? 0
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0[keyPath: keyPath] = newVal }
                }
            }
        )
    }

    /// Generic Bool binding for HypeNodeSpec fields.
    private func bindNodeBool(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<HypeNodeSpec, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?[keyPath: keyPath] ?? false
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0[keyPath: keyPath] = newVal }
                }
            }
        )
    }

    /// Binding for optional Double fields on HypeNodeSpec.
    private func bindNodeOptionalDouble(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<HypeNodeSpec, Double?>) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?[keyPath: keyPath] ?? 0
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0[keyPath: keyPath] = newVal }
                }
            }
        )
    }

    /// Binding for optional String fields on HypeNodeSpec.
    private func bindNodeOptionalString(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<HypeNodeSpec, String?>) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?[keyPath: keyPath] ?? ""
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0[keyPath: keyPath] = newVal }
                }
            }
        )
    }

    /// Binding for optional Bool fields on HypeNodeSpec.
    private func bindNodeOptionalBool(partId: UUID, nodeId: UUID, _ keyPath: WritableKeyPath<HypeNodeSpec, Bool?>) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?[keyPath: keyPath] ?? false
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0[keyPath: keyPath] = newVal }
                }
            }
        )
    }

    /// Binding for node position X coordinate.
    private func bindNodePositionX(partId: UUID, nodeId: UUID) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.position.x ?? 0
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0.position.x = newVal }
                }
            }
        )
    }

    /// Binding for node position Y coordinate.
    private func bindNodePositionY(partId: UUID, nodeId: UUID) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.position.y ?? 0
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0.position.y = newVal }
                }
            }
        )
    }

    /// Binding for node width, creating SizeSpec if nil.
    private func bindNodeWidth(partId: UUID, nodeId: UUID) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.size?.width ?? 50
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.size == nil {
                            $0.size = SizeSpec(width: newVal, height: 50)
                        } else {
                            $0.size?.width = newVal
                        }
                    }
                }
            }
        )
    }

    /// Binding for node height, creating SizeSpec if nil.
    private func bindNodeHeight(partId: UUID, nodeId: UUID) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.size?.height ?? 50
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.size == nil {
                            $0.size = SizeSpec(width: 50, height: newVal)
                        } else {
                            $0.size?.height = newVal
                        }
                    }
                }
            }
        )
    }

    /// Binding for node asset reference (optional UUID).
    private func bindNodeAsset(partId: UUID, nodeId: UUID) -> Binding<UUID?> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.assetRef?.id
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if let assetId = newVal,
                           let asset = document.document.spriteRepository.asset(byId: assetId) {
                            $0.assetRef = AssetRef(id: asset.id, name: asset.name, mimeType: asset.mimeType)
                        } else {
                            $0.assetRef = nil
                        }
                    }
                }
            }
        )
    }

    /// Generic color binding for HypeNodeSpec using getter/setter closures on hex strings.
    private func bindNodeColor(partId: UUID, nodeId: UUID, getter: @escaping (HypeNodeSpec) -> String?, setter: @escaping (inout HypeNodeSpec, String?) -> Void) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                guard let node = Self.findNodeById(nodeId, in: spec.nodes),
                      let hex = getter(node) else { return .black }
                return Color(hex: hex)
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { setter(&$0, newVal.toHex()) }
                }
            }
        )
    }

    /// Binding for shape type, creating default ShapeNodeSpec if nil.
    private func bindShapeType(partId: UUID, nodeId: UUID) -> Binding<SpriteShapeType> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.shapeSpec?.shapeType ?? .rect
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.shapeSpec == nil { $0.shapeSpec = ShapeNodeSpec() }
                        $0.shapeSpec?.shapeType = newVal
                    }
                }
            }
        )
    }

    /// Binding for shape fill color.
    private func bindShapeFillColor(partId: UUID, nodeId: UUID) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                let hex = Self.findNodeById(nodeId, in: spec.nodes)?.shapeSpec?.fillColor ?? "#FFFFFF"
                return Color(hex: hex)
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.shapeSpec == nil { $0.shapeSpec = ShapeNodeSpec() }
                        $0.shapeSpec?.fillColor = newVal.toHex()
                    }
                }
            }
        )
    }

    /// Binding for shape stroke color.
    private func bindShapeStrokeColor(partId: UUID, nodeId: UUID) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                let hex = Self.findNodeById(nodeId, in: spec.nodes)?.shapeSpec?.strokeColor ?? "#000000"
                return Color(hex: hex)
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.shapeSpec == nil { $0.shapeSpec = ShapeNodeSpec() }
                        $0.shapeSpec?.strokeColor = newVal.toHex()
                    }
                }
            }
        )
    }

    /// Binding for shape line width.
    private func bindShapeLineWidth(partId: UUID, nodeId: UUID) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.shapeSpec?.lineWidth ?? 1
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.shapeSpec == nil { $0.shapeSpec = ShapeNodeSpec() }
                        $0.shapeSpec?.lineWidth = newVal
                    }
                }
            }
        )
    }

    /// Binding for shape corner radius.
    private func bindShapeCornerRadius(partId: UUID, nodeId: UUID) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == partId })?.sceneSpec ?? ""
                let spec = SceneSpec.fromJSON(json) ?? SceneSpec()
                return Self.findNodeById(nodeId, in: spec.nodes)?.shapeSpec?.cornerRadius ?? 0
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) {
                        if $0.shapeSpec == nil { $0.shapeSpec = ShapeNodeSpec() }
                        $0.shapeSpec?.cornerRadius = newVal
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func textFormattingSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text Formatting").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Text("Font").frame(width: 40, alignment: .trailing).font(.system(size: 11))
                Picker("", selection: bindPartString(part.id, \.textFont)) {
                    ForEach(systemFontFamilies, id: \.self) { fontName in
                        Text(fontName).font(.system(size: 11)).tag(fontName)
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
            }
            numberField("Size", binding: bindPartDouble(part.id, \.textSize))
            Picker("Align", selection: bindPartTextAlign(part.id)) {
                Image(systemName: "text.alignleft").tag(HypeCore.TextAlignment.left)
                Image(systemName: "text.aligncenter").tag(HypeCore.TextAlignment.center)
                Image(systemName: "text.alignright").tag(HypeCore.TextAlignment.right)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func chartSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chart").font(.subheadline).foregroundColor(.secondary)

            let config = ChartConfig.fromJSON(part.chartData) ?? ChartConfig()

            Picker("Type", selection: bindChartType(part.id)) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            propertyRow("Title", binding: bindChartField(part.id, \.title))
            Toggle("Show Legend", isOn: bindChartBool(part.id, \.showLegend))
            Toggle("Show Grid", isOn: bindChartBool(part.id, \.showGrid))

            propertyRow("X Label", binding: bindChartField(part.id, \.xAxisLabel))
            propertyRow("Y Label", binding: bindChartField(part.id, \.yAxisLabel))

            Divider()

            // Series management
            ForEach(Array(config.series.enumerated()), id: \.element.id) { index, series in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Series \(index + 1)").font(.system(size: 10, weight: .bold))
                        Spacer()
                        ColorPicker("", selection: bindSeriesColor(part.id, seriesIndex: index))
                            .labelsHidden().frame(width: 20)
                        Button(action: { removeSeries(partId: part.id, index: index) }) {
                            Image(systemName: "minus.circle").foregroundColor(.red)
                        }.buttonStyle(.borderless)
                    }
                    TextField("Name", text: bindSeriesName(part.id, seriesIndex: index))
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))

                    // Data points with per-point color
                    ForEach(Array(series.data.enumerated()), id: \.element.id) { di, _ in
                        HStack(spacing: 3) {
                            ColorPicker("", selection: bindDataPointColor(part.id, seriesIndex: index, dataIndex: di, seriesColor: series.color))
                                .labelsHidden().frame(width: 18, height: 18)
                            TextField("Label", text: bindDataLabel(part.id, seriesIndex: index, dataIndex: di))
                                .textFieldStyle(.roundedBorder).font(.system(size: 10))
                            TextField("Value", value: bindDataValue(part.id, seriesIndex: index, dataIndex: di), format: .number)
                                .textFieldStyle(.roundedBorder).font(.system(size: 10)).frame(width: 55)
                            Button(action: { removeDataPoint(partId: part.id, seriesIndex: index, dataIndex: di) }) {
                                Image(systemName: "xmark").font(.system(size: 8))
                            }.buttonStyle(.borderless)
                        }
                    }
                    Button("+ Add Data Point") { addDataPoint(partId: part.id, seriesIndex: index) }
                        .font(.system(size: 10))
                }
                .padding(4)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(4)
            }

            Button("+ Add Series") { addSeries(partId: part.id) }
                .font(.system(size: 10))
        }
    }

    // MARK: - Chart Binding Helpers

    private func modifyChartConfig(partId: UUID, transform: (inout ChartConfig) -> Void) {
        let existing = document.document.parts.first(where: { $0.id == partId })?.chartData ?? ""
        var config = ChartConfig.fromJSON(existing) ?? ChartConfig()
        transform(&config)
        document.document.updatePart(id: partId) { $0.chartData = config.toJSON() }
    }

    private func bindChartType(_ id: UUID) -> Binding<ChartType> {
        Binding(
            get: { ChartConfig.fromJSON(document.document.parts.first(where: { $0.id == id })?.chartData ?? "")?.chartType ?? .bar },
            set: { newVal in modifyChartConfig(partId: id) { $0.chartType = newVal } }
        )
    }

    private func bindChartField(_ id: UUID, _ keyPath: WritableKeyPath<ChartConfig, String>) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? ""
            },
            set: { newVal in modifyChartConfig(partId: id) { $0[keyPath: keyPath] = newVal } }
        )
    }

    private func bindChartBool(_ id: UUID, _ keyPath: WritableKeyPath<ChartConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? true
            },
            set: { newVal in modifyChartConfig(partId: id) { $0[keyPath: keyPath] = newVal } }
        )
    }

    private func bindSeriesName(_ id: UUID, seriesIndex: Int) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count else { return "" }
                return config.series[seriesIndex].name
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count else { return }
                    config.series[seriesIndex].name = newVal
                }
            }
        )
    }

    private func bindSeriesColor(_ id: UUID, seriesIndex: Int) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count else { return .blue }
                return Color(hex: config.series[seriesIndex].color)
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count else { return }
                    config.series[seriesIndex].color = newVal.toHex()
                }
            }
        )
    }

    private func bindDataLabel(_ id: UUID, seriesIndex: Int, dataIndex: Int) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return "" }
                return config.series[seriesIndex].data[dataIndex].name
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
                    config.series[seriesIndex].data[dataIndex].name = newVal
                }
            }
        )
    }

    private func bindDataValue(_ id: UUID, seriesIndex: Int, dataIndex: Int) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return 0 }
                return config.series[seriesIndex].data[dataIndex].value
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
                    config.series[seriesIndex].data[dataIndex].value = newVal
                }
            }
        )
    }

    private func addSeries(partId: UUID) {
        modifyChartConfig(partId: partId) { config in
            let colors = ["#4A90D9", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C"]
            let colorIndex = config.series.count % colors.count
            config.series.append(ChartSeries(name: "Series \(config.series.count + 1)", color: colors[colorIndex]))
        }
    }

    private func removeSeries(partId: UUID, index: Int) {
        modifyChartConfig(partId: partId) { config in
            guard index < config.series.count else { return }
            config.series.remove(at: index)
        }
    }

    private func addDataPoint(partId: UUID, seriesIndex: Int) {
        modifyChartConfig(partId: partId) { config in
            guard seriesIndex < config.series.count else { return }
            let count = config.series[seriesIndex].data.count
            config.series[seriesIndex].data.append(ChartDataPoint(name: "Item \(count + 1)", value: 0))
        }
    }

    private func bindDataPointColor(_ id: UUID, seriesIndex: Int, dataIndex: Int, seriesColor: String) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return Color(hex: seriesColor) }
                let pointColor = config.series[seriesIndex].data[dataIndex].color
                if !pointColor.isEmpty {
                    return Color(hex: pointColor)
                }
                return Color(hex: seriesColor)
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
                    config.series[seriesIndex].data[dataIndex].color = newVal.toHex()
                }
            }
        )
    }

    private func removeDataPoint(partId: UUID, seriesIndex: Int, dataIndex: Int) {
        modifyChartConfig(partId: partId) { config in
            guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
            config.series[seriesIndex].data.remove(at: dataIndex)
        }
    }

    // MARK: - Constraints section

    @ViewBuilder
    private func constraintsSection(partId: UUID) -> some View {
        let partConstraints = document.document.constraintsForPart(partId)
        VStack(alignment: .leading, spacing: 4) {
            Text("CONSTRAINTS").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
            if partConstraints.isEmpty {
                Text("Option+drag from this part to another part or canvas edge to create a constraint")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            ForEach(partConstraints) { constraint in
                HStack {
                    Text("\(constraint.sourceEdge.rawValue) -> \(constraint.targetType == .canvas ? "canvas " : "")\(constraint.targetEdge.rawValue)")
                        .font(.system(size: 10))
                    Spacer()
                    TextField("", value: Binding(
                        get: { abs(constraint.distance) },
                        set: { newVal in
                            if let idx = document.document.constraints.firstIndex(where: { $0.id == constraint.id }) {
                                // Preserve the sign (direction), update magnitude
                                let sign: Double = document.document.constraints[idx].distance >= 0 ? 1 : -1
                                document.document.constraints[idx].distance = sign * abs(newVal)
                            }
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .font(.system(size: 10))
                    Text("px").font(.system(size: 10)).foregroundColor(.secondary)
                    Button(action: { document.document.removeConstraint(id: constraint.id) }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Binding helpers

    private func bindPartString(_ id: UUID, _ keyPath: WritableKeyPath<Part, String>) -> Binding<String> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { newValue in document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func bindPartDouble(_ id: UUID, _ keyPath: WritableKeyPath<Part, Double>) -> Binding<Double> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { newValue in document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func bindPartBool(_ id: UUID, _ keyPath: WritableKeyPath<Part, Bool>) -> Binding<Bool> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? false },
            set: { newValue in document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// Binding for the image "Animated" toggle that flips `Part.animated`
    /// AND drives the GIFAnimator. A naive `bindPartBool(... \.animated)`
    /// would only mutate the Part model — the animator's timer keeps
    /// ticking and the GIF keeps playing until some other path (a
    /// redraw path guarded on `part.animated`) notices. Wrapping the
    /// setter here so the UI toggle mirrors the HypeTalk
    /// `set the animated of X to false` path, which already invokes
    /// `GIFAnimator.shared.stop(partId:)`.
    private func bindAnimatedToggle(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.animated ?? false },
            set: { newValue in
                document.document.updatePart(id: id) { $0.animated = newValue }
                #if canImport(AppKit)
                // Look up fresh after the mutation — we need the part's
                // current imageData for the start path.
                guard let part = document.document.parts.first(where: { $0.id == id }) else { return }
                if newValue {
                    if let data = part.imageData {
                        GIFAnimator.shared.start(partId: id, imageData: data)
                    }
                } else {
                    GIFAnimator.shared.stop(partId: id)
                }
                #endif
            }
        )
    }

    private func bindPartButtonStyle(_ id: UUID) -> Binding<HypeCore.ButtonStyle> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.buttonStyle ?? .roundRect },
            set: { newValue in document.document.updatePart(id: id) { $0.buttonStyle = newValue } }
        )
    }

    private func bindPartFieldStyle(_ id: UUID) -> Binding<HypeCore.FieldStyle> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.fieldStyle ?? .rectangle },
            set: { newValue in document.document.updatePart(id: id) { $0.fieldStyle = newValue } }
        )
    }

    private func bindPartShapeType(_ id: UUID) -> Binding<HypeCore.ShapeType> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.shapeType ?? .rectangle },
            set: { newValue in document.document.updatePart(id: id) { $0.shapeType = newValue } }
        )
    }

    private func bindPartTextAlign(_ id: UUID) -> Binding<HypeCore.TextAlignment> {
        Binding(
            get: { document.document.parts.first(where: { $0.id == id })?.textAlign ?? .center },
            set: { newValue in document.document.updatePart(id: id) { $0.textAlign = newValue } }
        )
    }

    private func bindPartColor(_ id: UUID, _ keyPath: WritableKeyPath<Part, String>) -> Binding<Color> {
        Binding(
            get: {
                let hex = document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? "#FFFFFF"
                return Color(hex: hex)
            },
            set: { newValue in
                document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue.toHex() }
            }
        )
    }

    // MARK: - Helper views

    private func propertyRow(_ label: String, binding: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .trailing).font(.system(size: 11))
            TextField("", text: binding).textFieldStyle(.roundedBorder).font(.system(size: 11))
        }
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .trailing).font(.system(size: 11)).foregroundColor(.secondary)
            Text(value).font(.system(size: 11))
        }
    }

    private func numberField(_ label: String, binding: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("", value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 60)
        }
    }
}

// MARK: - Script Editor Sheet (used as fallback for .sheet() presentation)

struct ScriptEditorSheet: View {
    @Binding var document: HypeDocumentWrapper
    var partId: UUID? = nil
    var target: ScriptTarget? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScriptEditor(document: $document, partId: partId, target: target, onDone: { dismiss() })
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding(8)
        }
        .frame(minWidth: 500, idealWidth: 650, maxWidth: .infinity,
               minHeight: 400, idealHeight: 500, maxHeight: .infinity)
    }
}

// MARK: - Resizable Script Editor Window

/// Keeps a strong reference to open script editor windows, keyed by
/// `ScriptTarget.identityKey`. The dictionary is the deduplication
/// substrate behind `openScriptEditorWindow`: a second invocation
/// for the same target finds the existing window and refreshes it
/// in place rather than opening a duplicate.
///
/// Why: a runtime error inside an `on idle` handler used to spawn
/// a new script editor window every 500 ms (the idle timer
/// interval) until the user managed to quit the app. The dedup
/// map combined with the auto-switch-to-edit-mode in
/// `MainContentView`'s `.showScriptError` observer means the
/// script editor opens once, the idle timer stops on the same
/// turn, and the user is left looking at exactly one error
/// surface they can fix.
///
/// Windows that don't have an identifiable target (the legacy
/// "open from a property inspector button" path) are stored under
/// a generated UUID key so they still get cleaned up on close but
/// don't collide with target-keyed windows.
@MainActor
private var activeScriptWindows: [String: NSWindow] = [:]

/// Generate a unique key for a target, falling back to a fresh
/// UUID for opens that have no resolvable target. Used by
/// `openScriptEditorWindow` to find or create the window slot.
@MainActor
private func scriptWindowKey(for target: ScriptTarget?, partId: UUID?) -> String {
    if let target = target { return target.identityKey }
    if let partId = partId { return "part:\(partId.uuidString)" }
    return "unkeyed:\(UUID().uuidString)"
}

/// Sprite areas execute user-authored scripts on their active
/// `SceneSpec`, not on the legacy part-level script slot. Redirect
/// generic "open this part's script" requests to the active scene so
/// Cmd-click, runtime errors, and older callers show the same script
/// that SpriteKit actually runs.
@MainActor
private func effectiveScriptTarget(
    in document: HypeDocument,
    target: ScriptTarget?,
    partId: UUID?
) -> ScriptTarget? {
    let initialTarget = target ?? partId.map { ScriptTarget.part($0) }
    guard case .part(let id) = initialTarget,
          let part = document.parts.first(where: { $0.id == id }),
          part.partType == .spriteArea,
          let sceneId = part.spriteAreaSpecModel?.activeSceneEntry?.id else {
        return initialTarget
    }
    return .scene(partId: id, sceneId: sceneId)
}

/// Opens the ScriptEditor in a movable, resizable NSWindow with light appearance.
///
/// `initialErrorLine` and `initialErrorMessage` let the caller surface
/// a runtime error on editor open — the offending line is highlighted
/// in red and the message banner at the bottom shows the description.
/// Both are optional; passing `nil` (the default) opens the editor
/// clean as it did before.
///
/// **Idempotent.** If a script editor window for the same target is
/// already open, this function brings it forward and posts a
/// `.refreshScriptError` notification with the new highlight line
/// and banner instead of opening a duplicate window. This prevents
/// the runaway-windows scenario where a buggy `on idle` handler
/// spawned a new editor every 500 ms.
@MainActor
func openScriptEditorWindow(
    document: Binding<HypeDocumentWrapper>,
    partId: UUID? = nil,
    target: ScriptTarget? = nil,
    initialErrorLine: Int? = nil,
    initialErrorMessage: String? = nil
) {
    let doc = document.wrappedValue.document
    let resolvedTarget = effectiveScriptTarget(in: doc, target: target, partId: partId)
    let key = scriptWindowKey(for: resolvedTarget, partId: nil)

    // If a window for this target is already open, reuse it.
    // Bring it forward, refresh the error highlight, and return
    // without creating a second window.
    if let existing = activeScriptWindows[key] {
        existing.makeKeyAndOrderFront(nil)
        // Push the new error context into the live ScriptEditor
        // for that window. The editor's notification observer
        // checks the identityKey so a script editor for another
        // target ignores this broadcast.
        var refreshInfo: [AnyHashable: Any] = ["identityKey": key]
        if let line = initialErrorLine { refreshInfo["line"] = line }
        if let message = initialErrorMessage { refreshInfo["message"] = message }
        NotificationCenter.default.post(
            name: .refreshScriptError,
            object: nil,
            userInfo: refreshInfo
        )
        return
    }

    let savedWidth = UserDefaults.standard.double(forKey: "scriptEditorWidth")
    let savedHeight = UserDefaults.standard.double(forKey: "scriptEditorHeight")
    let width = savedWidth > 0 ? savedWidth : 650
    let height = savedHeight > 0 ? savedHeight : 500

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    // Build a descriptive window title from the target
    let windowTitle: String
    if let t = resolvedTarget {
        switch t {
        case .part(let id):
            if let part = doc.parts.first(where: { $0.id == id }) {
                let typeName = part.partType.rawValue.capitalized
                let name = part.name.isEmpty ? "Untitled" : part.name
                windowTitle = "\(name) (\(typeName)) — Script Editor"
            } else {
                windowTitle = "Part — Script Editor"
            }
        case .card(let id):
            let card = doc.cards.first(where: { $0.id == id })
            let name = card?.name.isEmpty == false ? card!.name : "Card"
            windowTitle = "\(name) — Script Editor"
        case .background(let id):
            let bg = doc.backgrounds.first(where: { $0.id == id })
            let name = bg?.name.isEmpty == false ? bg!.name : "Background"
            windowTitle = "\(name) — Script Editor"
        case .scene(let partId, let sceneId):
            let part = doc.parts.first(where: { $0.id == partId })
            let areaSpec = part?.spriteAreaSpecModel
            let scene = areaSpec?.scenes.first(where: { $0.id == sceneId })?.scene
            let areaName = part?.name.isEmpty == false ? part!.name : "Sprite Area"
            let sceneName = scene?.name.isEmpty == false ? scene!.name : "Scene"
            windowTitle = "\(areaName) / \(sceneName) — Script Editor"
        case .node(let partId, let nodeId):
            let part = doc.parts.first(where: { $0.id == partId })
            let areaSpec = part?.spriteAreaSpecModel
            let node = areaSpec?.scenes.lazy.compactMap { $0.scene.node(id: nodeId) }.first
            let areaName = part?.name.isEmpty == false ? part!.name : "Sprite Area"
            let nodeName = node?.name.isEmpty == false ? node!.name : "Node"
            let nodeType = node?.nodeType.rawValue.capitalized ?? "Node"
            windowTitle = "\(areaName) / \(nodeName) (\(nodeType)) — Script Editor"
        case .stack:
            windowTitle = "\(doc.stack.name) (Stack) — Script Editor"
        case .hype:
            windowTitle = "Hype App — Script Editor"
        }
    } else if let pid = partId, let part = doc.parts.first(where: { $0.id == pid }) {
        let typeName = part.partType.rawValue.capitalized
        let name = part.name.isEmpty ? "Untitled" : part.name
        windowTitle = "\(name) (\(typeName)) — Script Editor"
    } else {
        windowTitle = "Script Editor"
    }
    window.title = windowTitle
    window.minSize = NSSize(width: 450, height: 350)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)

    // Build the editor view with light color scheme forced at every level
    let closeAction: () -> Void = { [weak window] in window?.close() }
    let editorView = VStack(spacing: 0) {
        ScriptEditor(
            document: document,
            partId: partId,
            target: resolvedTarget,
            initialErrorLine: initialErrorLine,
            initialErrorMessage: initialErrorMessage,
            identityKey: key,
            onDone: closeAction
        )
        HStack {
            Spacer()
            Button("Done") { closeAction() }
                .keyboardShortcut(.return)
        }
        .padding(8)
    }
    .environment(\.colorScheme, .light)
    .colorScheme(.light)
    .preferredColorScheme(.light)

    let hostingView = NSHostingView(rootView: editorView)
    hostingView.appearance = NSAppearance(named: .aqua)
    window.contentView = hostingView
    window.center()
    window.makeKeyAndOrderFront(nil)

    activeScriptWindows[key] = window

    NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
            UserDefaults.standard.set(window.frame.width, forKey: "scriptEditorWidth")
            UserDefaults.standard.set(window.frame.height, forKey: "scriptEditorHeight")
        }
    }
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
            // Remove from the dedup map by key so a future
            // openScriptEditorWindow call for this target opens a
            // fresh window rather than poking at a deallocated one.
            // Discard the returned NSWindow? explicitly so the
            // closure's inferred return type stays Void.
            _ = activeScriptWindows.removeValue(forKey: key)
        }
    }
}

// MARK: - Resizable Sprite Repository Window

/// Keeps a strong reference to open sprite repository windows. As
/// with `activeScriptWindows` above, the window is detached from
/// SwiftUI's view graph so it needs its own retain cycle manager
/// or macOS will deallocate it the moment the opener's stack frame
/// returns.
@MainActor
private var activeSpriteRepositoryWindows: [NSWindow] = []

/// Opens the SpriteRepositoryView in a movable, resizable NSWindow
/// with light appearance. Replaces the previous `.sheet`-based
/// presentation, which used a fixed 600×400 frame and couldn't be
/// resized — users asked to see more thumbnails at once and to
/// keep the browser open while working on a card. A detached
/// window supports both.
///
/// The window remembers its size across sessions via UserDefaults
/// under the `spriteRepositoryWidth` / `spriteRepositoryHeight`
/// keys, mirroring how `openScriptEditorWindow` persists its own
/// frame.
@MainActor
func openSpriteRepositoryWindow(
    document: Binding<HypeDocumentWrapper>,
    initialAssetId: UUID? = nil
) {
    // Reuse an existing window instead of stacking duplicates if
    // the user clicks the toolbar button twice. The browser is
    // effectively a singleton from the user's perspective.
    if let existing = activeSpriteRepositoryWindows.first {
        existing.makeKeyAndOrderFront(nil)
        if let initialAssetId {
            NotificationCenter.default.post(
                name: .selectSpriteRepositoryAsset,
                object: nil,
                userInfo: ["assetId": initialAssetId]
            )
        }
        return
    }

    let savedWidth = UserDefaults.standard.double(forKey: "spriteRepositoryWidth")
    let savedHeight = UserDefaults.standard.double(forKey: "spriteRepositoryHeight")
    let width = savedWidth > 0 ? savedWidth : 780
    let height = savedHeight > 0 ? savedHeight : 520

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Sprite Repository"
    window.minSize = NSSize(width: 560, height: 360)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)

    let closeAction: () -> Void = { [weak window] in window?.close() }
    let browserView = SpriteRepositoryView(document: document, onDone: closeAction)
        .environment(\.colorScheme, .light)
        .colorScheme(.light)
        .preferredColorScheme(.light)

    let hostingView = NSHostingView(rootView: browserView)
    hostingView.appearance = NSAppearance(named: .aqua)
    window.contentView = hostingView
    window.center()
    window.makeKeyAndOrderFront(nil)

    if let initialAssetId {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .selectSpriteRepositoryAsset,
                object: nil,
                userInfo: ["assetId": initialAssetId]
            )
        }
    }

    activeSpriteRepositoryWindows.append(window)

    NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
            UserDefaults.standard.set(window.frame.width, forKey: "spriteRepositoryWidth")
            UserDefaults.standard.set(window.frame.height, forKey: "spriteRepositoryHeight")
        }
    }
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak window] _ in
        MainActor.assumeIsolated {
            if let w = window { activeSpriteRepositoryWindows.removeAll { $0 === w } }
        }
    }
}

// MARK: - Color hex conversion

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else {
            self = .white; return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#FFFFFF"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
