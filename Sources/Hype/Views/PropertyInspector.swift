import SwiftUI
import HypeCore
import UniformTypeIdentifiers

/// System font families, loaded once for the font picker.
private let systemFontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

struct PropertyInspector: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var selectedPartIds: Set<UUID>
    @Environment(\.hypeTheme) private var hypeTheme
    var currentTool: ToolName = .browse
    var currentCardId: UUID? = nil
    @Binding var paintColor: Color
    @Binding var pencilRadius: Double
    var userLevel: HypeUserLevel = .scripting
    @State private var showingScript = false
    @State private var showingCardScript = false
    @State private var showingBgScript = false
    @State private var showingStackScript = false
    @State private var showingHypeScript = false
    /// Sprite-scene node selection. A `Set<UUID>` so multiple nodes
    /// can be selected at once. Cmd / Shift + click on a row in the
    /// node tree toggles the row's id in this set; a plain click
    /// replaces the set with that single id (or clears if it was
    /// already the only one selected). Mirrors the part-selection
    /// model on the canvas.
    ///
    /// Convenience accessor `selectedNodeId` returns the single
    /// element when the set has cardinality 1, otherwise nil. The
    /// per-node detail panel reads this so it expands ONLY when the
    /// selection isn't ambiguous; the multi-node panel above the
    /// tree handles selections of size 2+.
    @State private var selectedNodeIds: Set<UUID> = []
    private var selectedNodeId: UUID? {
        selectedNodeIds.count == 1 ? selectedNodeIds.first : nil
    }
    @State private var draggedNodeId: UUID?
    @State private var sceneGuideContext: SpriteSceneGuideContext?
    /// Tracks whether the "Game Recipe" DisclosureGroup is expanded in the inspector.
    @State private var recipeGroupExpanded: Bool = false
    /// The preset ID selected in the "Start Game Recipe" preset picker before committing.
    @State private var recipePresetPickerID: String = ""
    /// Pending new-entity name typed into the Add Entity row.
    @State private var newEntityName: String = ""
    /// Pending new-entity role for the Add Entity row.
    @State private var newEntityRole: EntityRole = .decoration
    /// Diagnostics surfaced from the last Build Game compilation.
    @State private var recipeBuildDiagnostics: [String] = []
    /// When true the diagnostics caption is shown below the Build button.
    @State private var recipeBuildDiagnosticsExpanded: Bool = false
    /// Pre-fetched from Keychain on `.onAppear`. Used by the
    /// scene3D inspector's "Generate from prompt…" button to
    /// avoid a synchronous Keychain probe on the main thread (M4).
    @State private var meshyKeyIsSet: Bool = false
    /// When set, `Generate3DSheet` is presented targeting this part.
    @State private var generate3DSheetTargetPartId: UUID? = nil
    @State private var appleMusicInspectorResults: [AppleMusicItemRef] = []
    @State private var appleMusicInspectorSelectedSource = ""
    @State private var appleMusicInspectorStatus = "Apple Music is idle."

    var body: some View {
        Group {
            if selectedPartIds.count > 1 {
                multiSelectionView
            } else if let partId = selectedPartIds.first,
               let part = document.document.parts.first(where: { $0.id == partId }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Single-select headline echoes the multi-select
                        // pattern ("N Parts Selected"): tell the user
                        // which part they're inspecting, not just
                        // "Properties" (the whole pane is properties).
                        Text("\(part.name.isEmpty ? "Untitled" : part.name) — \(part.partType.displayName)")
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
                        case .calendar: calendarSection(part: part)
                        case .pdf: pdfSection(part: part)
                        case .map: mapSection(part: part)
                        case .colorWell: colorWellSection(part: part)
                        case .stepper, .slider: numericControlSection(part: part)
                        case .segmented: segmentedSection(part: part)
                        case .audioRecorder: audioRecorderSection(part: part)
                        case .musicPlayer, .pianoKeyboard, .stepSequencer, .musicMixer: audioKitMusicControlSection(part: part)
                        case .appleMusicBrowser: musicKitSearchSection(part: part)
                        case .musicQueue: legacyMusicQueueSection(part: part)
                        case .scene3D: scene3DSection(part: part)
                        case .progressView: progressViewSection(part: part)
                        case .gauge: gaugeSection(part: part)
                        case .divider: dividerSection(part: part)
                        // .toggle / .link / .menu / .searchField handled
                        // by the migration in Part.init(from:) — old
                        // documents arrive here as button / field with
                        // the appropriate style, so the section
                        // dispatches above already cover them.
                        case .toggle, .link, .menu, .searchField, .unknown: EmptyView()
                        }

                        // Font controls for buttons and fields
                        if part.partType == .button || part.partType == .field {
                            Divider()
                            textFormattingSection(part: part)
                        }

                        Divider()

                        if userLevel.canEditScripts {
                            // Script section
                            VStack(alignment: .leading, spacing: 6) {
                                sectionHeading("SCRIPT")

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
                        }

                        // Constraints section
                        constraintsSection(partId: part.id)

                        Divider()

                        // Single-part theme info: read-only — the
                        // controls live in the no-part-selected
                        // inspector and the Theme Designer window.
                        // Showing the resolved theme here just
                        // answers the question "what theme is this
                        // part rendering under?" without scattering
                        // editing controls across every part type.
                        themeInfoSection

                        Divider()

                        // Delete part
                        Button(role: .destructive, action: {
                            let idToDelete = part.id
                            selectedPartIds = []
                            document.document.deletePart(id: idToDelete)
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
                        Text(userLevel.canEditScripts ? "Scripts" : "Stack")
                            .font(.headline)
                            .padding(.bottom, 4)
                        if userLevel.canEditScripts {
                            scriptsSection

                            Divider()
                        }

                        if userLevel.canAuthorObjects {
                            // Theme picker rows for the current card,
                            // its background, and the stack default.
                            // This is the primary editing surface for
                            // theme assignment — the Theme Designer
                            // window only authors theme values; this
                            // section is what wires those values to
                            // surfaces. See `themePickerSection`.
                            themePickerSection
                        } else {
                            Text(userLevel.helpText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 260)
        // Inspector panel chrome — uses the theme's panel surface
        // treatment. Liquid Glass picks up `.regularMaterial`; flat
        // themes apply `inspectorBackground` directly.
        .hypeSurface(.panel, theme: hypeTheme)
        // Force the colorScheme to match the panel background's
        // luminance so SwiftUI's labels (Color.primary / Text /
        // Picker / TextField) pick a contrasting color. Without
        // this, a light-bg theme like Sunset shows white labels
        // when macOS is in dark mode (and vice versa).
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
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
            selectedNodeIds = [nodeId]
        }
        .onChange(of: selectedPartIds) { _, _ in
            selectedNodeIds = []
        }
        .onAppear {
            meshyKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        }
        .sheet(item: Binding(
            get: { generate3DSheetTargetPartId.map { Generate3DSheetPartTarget(partId: $0) } },
            set: { generate3DSheetTargetPartId = $0?.partId }
        )) { target in
            Generate3DSheet(
                document: $document,
                targetPartId: target.partId,
                onAssetImported: { ref in
                    document.document.updatePart(id: target.partId) { $0.scene3DAssetRef = ref }
                },
                onDismiss: { generate3DSheetTargetPartId = nil }
            )
        }
    }

    // MARK: - Multi-selection view

    private var multiSelectionView: some View {
        let selectedParts = document.document.parts.filter { selectedPartIds.contains($0.id) }
        // Whether the current selection is HOMOGENEOUS in part type —
        // gates type-specific sections (text formatting, fill / stroke).
        let allButtonOrField = !selectedParts.isEmpty && selectedParts.allSatisfy { $0.partType == .button || $0.partType == .field }
        // Parts that respect part.fillColor / part.strokeColor when
        // the renderer paints them (verified against ButtonRenderer,
        // FieldRenderer, ShapeRenderer, DividerRenderer). Hiding the
        // color row for parts that ignore those fields avoids the
        // "I edited the color but nothing changed" footgun.
        let allHonorFillStroke = !selectedParts.isEmpty && selectedParts.allSatisfy {
            $0.partType == .shape || $0.partType == .button || $0.partType == .field || $0.partType == .divider
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(selectedParts.count) Parts Selected")
                    .font(.headline)
                    .padding(.bottom, 4)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    sectionHeading("ALIGNMENT")

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

                // Position & Size — always shown. Differing values across
                // the selection appear as empty fields with the "Multiple"
                // placeholder; typing a value applies it uniformly to
                // every selected part. This is the load-bearing case the
                // user asked for: "edit the height of a selected group of
                // controls" — type once, all match.
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeading("POSITION & SIZE")

                    HStack(spacing: 8) {
                        multiNumberField("X", keyPath: \.left)
                        multiNumberField("Y", keyPath: \.top)
                    }
                    HStack(spacing: 8) {
                        multiNumberField("Width", keyPath: \.width)
                        multiNumberField("Height", keyPath: \.height)
                    }
                }

                Divider()

                // Behavior flags — always shown. `commonValue` returns
                // false when the selected parts disagree, so the
                // toggle reads as "off" until you flip it (which
                // applies "on" to all). That's intentional: it lets
                // a user with mixed visibility flip the whole group
                // visible in one click.
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeading("State")

                    Toggle("Visible", isOn: bindMultiBool(\.visible))
                    Toggle("Enabled", isOn: bindMultiBool(\.enabled))
                    Toggle("Show Name", isOn: bindMultiBool(\.showName))
                }

                // Appearance: fill / stroke / corner radius. Only shown
                // when every selected part actually honors these fields
                // in its renderer (shape / button / field / divider).
                // Hiding the section for parts that ignore the fields
                // (image, video, chart, sprite area, …) prevents the
                // "I edited it but nothing happened" surprise.
                if allHonorFillStroke {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeading("APPEARANCE")

                        // ColorPicker swatch + hex text — two ways to
                        // pick the same color. Differing values: swatch
                        // is transparent; hex field shows "Multiple".
                        multiColorRow(label: "Fill", keyPath: \.fillColor)
                        multiColorRow(label: "Stroke", keyPath: \.strokeColor)
                        // Stacked, not abbreviated — "Stroke Width" /
                        // "Corner Radius" side by side genuinely don't
                        // fit this panel's width at the full words, so
                        // each gets its own row instead of shortening
                        // the label (design-mock §2.4).
                        multiNumberField("Stroke Width", keyPath: \.strokeWidth)
                        multiNumberField("Corner Radius", keyPath: \.cornerRadius)
                    }
                }

                // Text formatting only when every selected part is a
                // button or field — the only part types whose
                // renderers consult textFont / textSize / etc.
                if allButtonOrField {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeading("TEXT FORMATTING")

                        multiStringField("Font", keyPath: \.textFont)
                        multiNumberField("Size", keyPath: \.textSize)

                        // Alignment as a 3-way segmented Picker.
                        // Differing values fall back to .center; the
                        // user re-selects to override across all
                        // selected parts in one click.
                        HStack {
                            Text("Align").font(.system(size: 11)).frame(width: 80, alignment: .trailing)
                                .foregroundColor(.secondary)
                            Picker("", selection: bindMultiTextAlign()) {
                                Image(systemName: "text.alignleft").tag(HypeCore.TextAlignment.left)
                                Image(systemName: "text.aligncenter").tag(HypeCore.TextAlignment.center)
                                Image(systemName: "text.alignright").tag(HypeCore.TextAlignment.right)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityLabel("Align")
                        }

                        // Font color across the selection. Empty hex
                        // means "auto / contrast-aware against fill" —
                        // the renderer's fallback path.
                        multiColorRow(label: "Text Color", keyPath: \.fontColor)

                        // textStyle toggles (Bold / Italic / Underline /
                        // Strikethrough) across the selection. A toggle
                        // appears active when EVERY selected part has
                        // the flag set. Tapping it flips the flag on
                        // every selected part — so a mixed-state group
                        // turns uniformly ON in one click, and a
                        // uniformly-ON group turns OFF.
                        HStack(spacing: 4) {
                            Text("Style").font(.system(size: 11)).frame(width: 80, alignment: .trailing)
                                .foregroundColor(.secondary)
                            multiStyleToggle(flag: .bold,          systemImage: "bold")
                            multiStyleToggle(flag: .italic,        systemImage: "italic")
                            multiStyleToggle(flag: .underline,     systemImage: "underline")
                            multiStyleToggle(flag: .strikethrough, systemImage: "strikethrough")
                            Spacer()
                        }
                    }
                }

                Divider()

                // Delete all selected. Multi-delete is destructive
                // and previously fired without any confirmation; a
                // mis-click could vaporize a dozen parts. Match the
                // `addNewBackgroundFlow` pattern used elsewhere — an
                // NSAlert confirm. Single-part delete (count == 1)
                // skips the alert: it's reversible via undo and the
                // user clearly aimed at the one selected part.
                Button(role: .destructive, action: {
                    let ids = Array(selectedPartIds)
                    let count = ids.count
                    let proceed: () -> Void = {
                        selectedPartIds = []
                        for id in ids {
                            document.document.deletePart(id: id)
                        }
                    }
                    if count >= 2 {
                        let alert = NSAlert()
                        alert.messageText = "Delete \(count) parts?"
                        alert.informativeText = "This action can be undone with ⌘Z."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Delete")
                        alert.addButton(withTitle: "Cancel")
                        if alert.runModal() == .alertFirstButtonReturn {
                            proceed()
                        }
                    } else {
                        proceed()
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
                    Text("Edit Global Hype Script...")
                }
            }
            .help("Global Hype script is stored in this Mac's app preferences. Use the stack script for portable stack behavior.")

            Text("Messages pass: part → card → background → stack → Hype")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Theme Picker (no part selected)

    /// Three Picker rows — Card / Background / Stack — letting the
    /// user assign or inherit a theme at any level of the cascade.
    /// Card and Background both have an "Inherit" entry that nils
    /// out the local `themeName`, so the cascade falls through to
    /// the next level. Stack has no Inherit entry because
    /// `Stack.themeName` is non-optional (the cascade has to
    /// terminate somewhere — see `BuiltInThemes.fallbackName`).
    ///
    /// Each row's trailing label shows the live cascade-resolution
    /// state (e.g. "(inheriting from background)") so the user can
    /// see why a card looks the way it does without opening the
    /// designer.
    ///
    /// The "Edit Themes..." button posts `.openThemeDesigner`, which
    /// `MainContentView` observes to open or focus the detached
    /// designer window. Reusing the notification keeps this button
    /// and the Edit menu item in lockstep — there's only one path
    /// to opening the designer.
    @ViewBuilder
    private var themePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeading("THEME")
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: .openThemeDesigner, object: nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                        Text("Edit Themes...")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Open the Theme Designer window")
            }

            // Card row
            if let cardId = currentCardId,
               let cardIdx = document.document.cards.firstIndex(where: { $0.id == cardId }) {
                themePickerRow(
                    label: "Card",
                    selection: cardThemeBinding(cardIndex: cardIdx),
                    showInherit: true,
                    cascadeNote: cascadeNote(for: .card(cardId))
                )

                // Background row — Card.backgroundId is non-optional
                // but the background it points at may have been
                // deleted, so we still need a `firstIndex` guard.
                let bgId = document.document.cards[cardIdx].backgroundId
                if let bgIdx = document.document.backgrounds.firstIndex(where: { $0.id == bgId }) {
                    let bg = document.document.backgrounds[bgIdx]
                    let bgLabel = "Background: \(bg.name.isEmpty ? "Untitled" : bg.name)"
                    themePickerRow(
                        label: bgLabel,
                        selection: backgroundThemeBinding(backgroundIndex: bgIdx),
                        showInherit: true,
                        cascadeNote: cascadeNote(for: .background(bgId))
                    )
                }
            }

            // Stack row — no inherit entry; cascade terminates here.
            themePickerRow(
                label: "Stack",
                selection: stackThemeBindingNonOptional(),
                showInherit: false,
                cascadeNote: nil
            )
        }
    }

    /// Render a single theme picker row. The `selection` is an
    /// optional binding so we can use `nil` to mean "inherit from
    /// the next cascade level" for card/background pickers; the
    /// stack picker wraps its non-optional `String` in a Binding
    /// here for a uniform API.
    @ViewBuilder
    private func themePickerRow(
        label: String,
        selection: Binding<String?>,
        showInherit: Bool,
        cascadeNote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(label, selection: selection) {
                if showInherit {
                    Text("Inherit").tag(String?.none)
                    Divider()
                }
                ForEach(document.document.allAvailableThemes) { theme in
                    Text(theme.name).tag(String?.some(theme.name))
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))

            if let note = cascadeNote {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    /// Build a human-readable description of where the cascade
    /// resolves for the given scope, used as the dimmed trailing
    /// label under each picker. Returns nil when the scope's local
    /// theme is set (no inheritance happening to call out).
    private func cascadeNote(for scope: ThemePickerScope) -> String? {
        guard let cardId = currentCardId else { return nil }
        let (theme, origin) = document.document.effectiveThemeOrigin(forCard: cardId)
        switch scope {
        case .card(let id):
            // Only show a note when the card has no local theme,
            // i.e. the cascade is doing work for this scope.
            guard let card = document.document.cards.first(where: { $0.id == id }),
                  card.themeName == nil
            else { return nil }
            switch origin {
            case .card:        return "(using \(theme.name))"
            case .background:  return "(inheriting from background → \(theme.name))"
            case .stack:       return "(inheriting from stack → \(theme.name))"
            case .fallback:    return "(falling back to \(theme.name))"
            }
        case .background(let id):
            guard let bg = document.document.backgrounds.first(where: { $0.id == id }),
                  bg.themeName == nil
            else { return nil }
            switch origin {
            case .background:  return "(using \(theme.name))"
            case .stack:       return "(inheriting from stack → \(theme.name))"
            case .fallback:    return "(falling back to \(theme.name))"
            case .card:        return nil  // shouldn't happen at bg scope
            }
        }
    }

    /// Read-only theme info row shown at the bottom of the
    /// per-part inspector. Mirrors the cascade resolution so the
    /// user can answer "what theme is this part rendering under?"
    /// without leaving the inspector.
    @ViewBuilder
    private var themeInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("THEME")
            let (theme, origin) = document.document.effectiveThemeOrigin(forCard: currentCardId)
            HStack {
                Text("\(theme.name)")
                    .font(.system(size: 11))
                Spacer()
                Text("(from \(originLabel(origin)))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .italic()
            }
            Button(action: {
                NotificationCenter.default.post(name: .openThemeDesigner, object: nil)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette")
                    Text("Edit Themes...")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Open the Theme Designer window")
        }
    }

    private func originLabel(_ origin: ThemeOrigin) -> String {
        switch origin {
        case .card:        return "card"
        case .background:  return "background"
        case .stack:       return "stack"
        case .fallback:    return "system fallback"
        }
    }

    /// Optional-string binding for `Card.themeName`. Selecting the
    /// "Inherit" entry sets the underlying value to nil.
    private func cardThemeBinding(cardIndex: Int) -> Binding<String?> {
        Binding(
            get: { document.document.cards[cardIndex].themeName },
            set: { newValue in
                document.document.cards[cardIndex].themeName = newValue
            }
        )
    }

    /// Optional-string binding for `Background.themeName`.
    private func backgroundThemeBinding(backgroundIndex: Int) -> Binding<String?> {
        Binding(
            get: { document.document.backgrounds[backgroundIndex].themeName },
            set: { newValue in
                document.document.backgrounds[backgroundIndex].themeName = newValue
            }
        )
    }

    /// Wrap the non-optional `Stack.themeName` in an optional-string
    /// binding so it can share the same picker row signature as the
    /// card/background pickers. The setter coerces nil to the
    /// fallback name to satisfy the non-optional invariant.
    private func stackThemeBindingNonOptional() -> Binding<String?> {
        Binding(
            get: { document.document.stack.themeName },
            set: { newValue in
                document.document.stack.themeName = newValue ?? BuiltInThemes.fallbackName
            }
        )
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
                sectionHeading("BACKGROUNDS")
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

    /// Single source of truth for inspector section headings.
    /// Single-select used to use `.subheadline` mixed-case
    /// ("Position", "State") while multi-select used 10pt uppercase
    /// bold ("POSITION & SIZE") — two visual languages inside the
    /// same inspector. Routing every section title through this
    /// helper unifies on the 10pt uppercase pattern used by Xcode's
    /// inspector and keeps the styling in one place if it ever
    /// changes again.
    @ViewBuilder
    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func commonSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Identity")
            propertyRow("Name", binding: bindPartString(part.id, \.name))
            propertyRow("Type", value: part.partType.displayName)
        }
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Position & Size")
            HStack {
                numberField("X", binding: bindPartDouble(part.id, \.left))
                numberField("Y", binding: bindPartDouble(part.id, \.top))
            }
            HStack {
                numberField("Width", binding: bindPartDouble(part.id, \.width))
                numberField("Height", binding: bindPartDouble(part.id, \.height))
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("State")
            Toggle("Visible", isOn: bindPartBool(part.id, \.visible))
            Toggle("Enabled", isOn: bindPartBool(part.id, \.enabled))
        }
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Help")
            // Multi-line help text shown as a native `NSToolTip`
            // when the user hovers this part in browse mode.
            // Empty disables the bubble entirely. Fixed-height
            // editor so authors can write a sentence or two
            // without the inspector layout jumping; the system
            // tooltip wraps long lines automatically.
            TextEditor(text: bindPartString(part.id, \.helpText))
                .font(.system(size: 11))
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            Text("Shown on hover in browse mode. Leave empty for no bubble.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func buttonSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Button")
            Picker("Style", selection: bindPartButtonStyle(part.id)) {
                ForEach(HypeCore.ButtonStyle.pickerCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            propertyRow("Label", binding: bindPartString(part.id, \.textContent))
            Text("Shown on the button when Show Name is off.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Toggle("Show Name", isOn: bindPartBool(part.id, \.showName))
            Toggle("Auto Hilite", isOn: bindPartBool(part.id, \.autoHilite))

            // Hilite is the checked / on state for the three
            // styles that actually render one (classic HyperCard:
            // checkbox / radio / toggle switch). Hidden for every
            // other style so authors don't see a row with no
            // visible effect.
            if [HypeCore.ButtonStyle.toggle, .checkBox, .radio].contains(part.buttonStyle) {
                Toggle("Hilite", isOn: bindPartBool(part.id, \.hilite))
                Text("The checked / on state.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            // Popup items editor (only shown for popup style)
            if part.buttonStyle == .popup {
                Divider()
                sectionHeading("POPUP ITEMS")
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
            sectionHeading("Field")
            Picker("Style", selection: bindPartFieldStyle(part.id)) {
                ForEach(HypeCore.FieldStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            Toggle("Lock Text", isOn: bindPartBool(part.id, \.lockText))
            Toggle("Don't Wrap", isOn: bindPartBool(part.id, \.dontWrap))
            Toggle("Rich Text", isOn: bindPartBool(part.id, \.richText))
            Toggle("Wide Margins", isOn: bindPartBool(part.id, \.wideMargins))

            Divider()
            sectionHeading("Events")
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
                Text("Contents").font(.system(size: 11)).foregroundColor(.secondary)
                TextEditor(text: bindPartString(part.id, \.textContent))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.gray.opacity(0.5))
            }

            // Search-style-only properties. Hidden for every other
            // field style since neither has an effect there — the
            // gap the design mock closes (search style was
            // selectable but its properties were unreachable).
            if part.fieldStyle == .search {
                Divider()
                propertyRow("Prompt", binding: bindPartString(part.id, \.searchPrompt))
                Toggle("Search While Typing", isOn: bindPartBool(part.id, \.searchSendsImmediately))
                Text("When off, searching happens when Return is pressed.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func shapeSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Shape")
            Picker("Style", selection: bindPartShapeType(part.id)) {
                ForEach(HypeCore.ShapeType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            colorPropertyRow(label: "Fill", partId: part.id, keyPath: \.fillColor,
                             supportsOpacity: true)
            colorPropertyRow(label: "Stroke", partId: part.id, keyPath: \.strokeColor,
                             supportsOpacity: true)
            numberField("Stroke Width", binding: bindPartDouble(part.id, \.strokeWidth))
            numberField("Corner Radius", binding: bindPartDouble(part.id, \.cornerRadius))
            numberField("Rotation", binding: bindPartDouble(part.id, \.rotation), unit: "°")
        }
    }

    @ViewBuilder
    private func webpageSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Web Page")
            propertyRow("URL", binding: bindPartString(part.id, \.url))
        }
    }

    @ViewBuilder
    private func imageSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Image")

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
            // Chroma-key the image's dominant corner-pixel color so
            // the card shows through. Useful for JPGs / indexed GIFs
            // whose "background" is a solid color rather than real
            // alpha. Backed by ImageChromaKey (see ImageRenderer).
            Toggle("Transparent Background", isOn: bindPartBool(part.id, \.transparentBackground))
                .help("Treat the image's dominant corner color as transparent so whatever's behind shows through. Already-transparent PNGs are unaffected.")
            numberField("Rotation", binding: bindPartDouble(part.id, \.rotation), unit: "°")

            // CoreImage filter — applied at render time. None means
            // pass-through. Some filters (sepia / blur / vignette /
            // posterize) honor the intensity slider; others ignore it.
            HStack {
                Text("Filter").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.imageFilter)) {
                    Text("None").tag("")
                    Text("Sepia").tag("sepia")
                    Text("Black & White").tag("blackwhite")
                    Text("Mono").tag("mono")
                    Text("Noir").tag("noir")
                    Text("Blur").tag("blur")
                    Text("Vignette").tag("vignette")
                    Text("Invert").tag("invert")
                    Text("Posterize").tag("posterize")
                    Text("Comic").tag("comic")
                    Text("Process").tag("process")
                    Text("Transfer").tag("transfer")
                    Text("Instant").tag("instant")
                    Text("Fade").tag("fade")
                    Text("Tonal").tag("tonal")
                    Text("Chrome").tag("chrome")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Filter")
            }
            if !part.imageFilter.isEmpty && ["sepia", "blur", "vignette", "posterize"].contains(part.imageFilter) {
                HStack {
                    Text("Intensity").font(.system(size: 10))
                    Slider(value: bindPartIntensityValue(part.id), in: 0...1)
                    Text(String(format: "%.2f", part.imageFilterIntensity))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }
            }

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
            sectionHeading("Video")
            propertyRow("Source", binding: bindPartString(part.id, \.videoURL), placeholder: "File path or URL")
            Button("Choose Video...") {
                chooseVideoForPart(partId: part.id)
            }
            if !part.videoURL.isEmpty {
                Text(part.videoURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Toggle("Autoplay", isOn: bindPartBool(part.id, \.videoAutoplay))
            Toggle("Loop", isOn: bindPartBool(part.id, \.videoLoop))
            HStack {
                Text("Volume").font(.system(size: 10)).foregroundColor(.secondary)
                Slider(value: bindPartDouble(part.id, \.videoVolume), in: 0...1)
            }
            numberField("Play Rate", binding: bindPartDouble(part.id, \.videoPlayRate), unit: "×")
        }
    }

    private func calendarSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Calendar")
            propertyRow("Date", binding: bindPartString(part.id, \.selectedDate), placeholder: "yyyy-MM-dd")
            if TargetRuntimeCalendarStyle(rawOrAlias: part.calendarStyle).persistsTime {
                propertyRow("Time", binding: bindPartString(part.id, \.selectedTime), placeholder: "HH:mm:ss")
            }
            propertyRow("Display Month", binding: bindPartString(part.id, \.displayMonth), placeholder: "yyyy-MM")
            propertyRow("Min Date", binding: bindPartString(part.id, \.minDate))
            propertyRow("Max Date", binding: bindPartString(part.id, \.maxDate))
            HStack {
                Text("Style").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.calendarStyle)) {
                    Text("Graphical").tag("graphical")
                    Text("Textual").tag("textual")
                    Text("Clock + Calendar").tag("clockAndCalendar")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Style")
            }
        }
    }

    private func pdfSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("PDF")
            propertyRow("Source", binding: bindPartString(part.id, \.pdfURL))
            Button("Choose PDF...") { choosePDFForPart(partId: part.id) }
            HStack {
                Text("Page").font(.system(size: 10))
                Stepper(value: bindPartInt(part.id, \.pdfCurrentPage), in: 1...10000) {
                    Text("\(part.pdfCurrentPage)")
                }
            }
            HStack {
                Text("Display Mode").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.pdfDisplayMode)) {
                    Text("Single").tag("single")
                    Text("Continuous").tag("continuous")
                    Text("Two Up").tag("twoUp")
                    Text("Two Up Continuous").tag("twoUpContinuous")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Display Mode")
            }
            Toggle("Auto-Scale to Fit", isOn: bindPartBool(part.id, \.pdfAutoScales))
        }
    }

    private func choosePDFForPart(partId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let asset = try StackAssetEmbedder.importLocalFile(
                    at: url,
                    as: .document,
                    preferredName: url.lastPathComponent,
                    into: &document.document.assetRepository
                )
                let ref = document.document.assetRepository.assetRef(for: asset)
                document.document.updatePart(id: partId) {
                    $0.pdfAssetRef = ref
                    $0.pdfURL = StackAssetEmbedder.assetURLString(for: asset)
                }
            } catch {
                showAssetImportError(error)
            }
        }
    }

    private func mapSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Map")
            propertyRow("Center Lat", binding: bindPartDoubleString(part.id, \.mapCenterLat))
            propertyRow("Center Lon", binding: bindPartDoubleString(part.id, \.mapCenterLon))
            propertyRow("Span", binding: bindPartDoubleString(part.id, \.mapSpan), unit: "°")
            propertyRow("Location", binding: Binding<String>(
                get: { document.document.parts.first(where: { $0.id == part.id })?.mapLocation ?? "" },
                // Clamp to 256 chars to match the AI tool + HypeTalk
                // setter contract — keeps document size predictable
                // and avoids transmitting bloated strings to CLGeocoder.
                set: { newValue in
                    document.document.updatePart(id: part.id) {
                        $0.mapLocation = String(newValue.prefix(256))
                    }
                }
            ))
            Text("Place name, address, or US ZIP. Sent to Apple for geocoding. Leave blank to use lat/lon directly.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            HStack {
                Text("Type").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.mapType)) {
                    Text("Standard").tag("standard")
                    Text("Satellite").tag("satellite")
                    Text("Hybrid").tag("hybrid")
                    Text("Muted Standard").tag("mutedStandard")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Type")
            }
            propertyRow("Annotations", binding: bindPartString(part.id, \.mapAnnotationsJSON))
            Text("Format: [{\"lat\":37.77,\"lon\":-122.42,\"title\":\"HQ\"}]")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Toggle("Show User Location", isOn: bindPartBool(part.id, \.mapShowsUserLocation))
            Text("Shows the system location dot in Browse mode. macOS asks for location permission the first time.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func colorWellSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Color Well")
            colorPropertyRow(label: "Color", partId: part.id, keyPath: \.colorWellHex,
                             supportsOpacity: true)
            Toggle("Interactive", isOn: bindPartBool(part.id, \.colorWellInteractive))
        }
    }

    private func numericControlSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading(part.partType == .stepper ? "Stepper" : "Slider")
            propertyRow("Value", binding: bindPartDoubleString(part.id, \.controlValue))
            propertyRow("Min", binding: bindPartDoubleString(part.id, \.controlMin))
            propertyRow("Max", binding: bindPartDoubleString(part.id, \.controlMax))
            if part.partType == .stepper {
                propertyRow("Step", binding: bindPartDoubleString(part.id, \.controlStep))
            }
        }
    }

    // toggleSection removed — toggle parts now migrate to button +
    // ButtonStyle.toggle on decode (see Part.init(from:)) and use
    // the existing button section.

    private func segmentedSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Segmented")
            propertyRow("Segments", binding: bindPartString(part.id, \.segmentItems))
            Text("Separate segments with | — e.g. Day|Week|Month.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            propertyRow("Selected Segment", binding: bindPartDoubleString(part.id, \.controlValue))
            Text("0 = first segment.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func scene3DSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("3D Scene")

            // From Repository — preferred path. Picks a model3D asset
            // embedded in the Asset Repository. When set, this takes
            // priority over the Object Path URL below.
            HStack {
                Text("From Repository").font(.system(size: 10))
                Picker("", selection: bindScene3DAssetRef(part.id)) {
                    Text("\u{2014} None \u{2014}").tag(Optional<UUID>.none)
                    ForEach(model3DAssets) { asset in
                        Text(asset.name).tag(Optional(asset.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(model3DAssets.isEmpty)
                .accessibilityLabel("From Repository")
            }

            // Generate-from-prompt button — opens Generate3DSheet
            // bound to this part so the imported asset is auto-assigned.
            Button("Generate from prompt\u{2026}") { openGenerate3DSheetForPart(partId: part.id) }
                .controlSize(.small)

            Text("Pick a 3D model from the Asset Repository, or generate one from a prompt. GLB assets render through their USDZ companion, so keep USDZ enabled for Meshy-generated models.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Object Path is the author-visible source path (fallback).
            // Accepts .usdz / .usd / .scn / .dae / .obj / .stl. STL is
            // auto-converted to a cached .obj on import.
            HStack {
                propertyRow("Object Path", binding: bindPartObjectPath(part.id))
                Button("Choose 3D Model...") { chooseModelForPart(partId: part.id) }
                    .controlSize(.small)
            }
            Text("Accepts .usdz, .usd, .scn, .dae, .obj, .stl, .ply, .abc, .fbx. STL is converted to a cached .obj automatically. GLB files require a USDZ companion in the Asset Repository.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            // Resolved path is read-only — it shows what SceneKit
            // actually loads (a cached .obj for STL inputs, the
            // source path for everything else). Letting the user
            // edit it directly would bypass STLConverter's size cap
            // and NaN sanitization, so we render it as a label.
            propertyRow("Resolved Path", value: part.scene3DURL.isEmpty ? "(none)" : part.scene3DURL)
            Toggle("Allow Camera Control", isOn: bindPartBool(part.id, \.scene3DAllowsCameraControl))
            Toggle("Auto Lighting", isOn: bindPartBool(part.id, \.scene3DAutoLighting))
            colorPropertyRow(label: "Background", partId: part.id, keyPath: \.scene3DBackground,
                             hint: "Empty hex = transparent (let the card show through)")
            HStack {
                Text("Anti-Aliasing").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.scene3DAntialiasing)) {
                    Text("None").tag("none")
                    Text("2× MSAA").tag("multisampling2X")
                    Text("4× MSAA").tag("multisampling4X")
                    Text("8× MSAA").tag("multisampling8X")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Anti-Aliasing")
            }
        }
    }

    // MARK: - Scene3D Meshy helpers

    /// All `.model3D` assets in the Asset Repository, sorted by name.
    private var model3DAssets: [Asset] {
        document.document.assetRepository.assets
            .filter { $0.kind == .model3D }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Binding that reads/writes `Part.scene3DAssetRef` as an optional `UUID`
    /// for use in a `Picker`. The Picker tags are `Optional<UUID>` so the "None"
    /// entry maps cleanly to `nil`.
    private func bindScene3DAssetRef(_ partId: UUID) -> Binding<UUID?> {
        Binding(
            get: {
                self.document.document.parts.first(where: { $0.id == partId })?.scene3DAssetRef?.id
            },
            set: { newId in
                self.document.document.updatePart(id: partId) { part in
                    if let id = newId,
                       let asset = self.document.document.assetRepository.asset(byId: id) {
                        part.scene3DAssetRef = self.document.document.assetRepository.assetRef(for: asset)
                        part.scene3DSourceURL = ""
                        part.scene3DURL = ""
                    } else {
                        part.scene3DAssetRef = nil
                    }
                }
            }
        )
    }

    /// Check the Meshy gate and either open the Generate3D sheet for this
    /// part or surface an alert directing the user to enable the feature.
    private func openGenerate3DSheetForPart(partId: UUID) {
        switch Meshy3DGate.status(for: document.document, keyIsSet: meshyKeyIsSet) {
        case .ready:
            generate3DSheetTargetPartId = partId
        case .stackDisabled:
            let alert = NSAlert()
            alert.messageText = "Enable 3D generation for this stack?"
            alert.informativeText = "Generated 3D models will be downloaded from api.meshy.ai and embedded in this stack. You can disable this in Preferences \u{2192} Meshy.ai."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                document.document.stack.meshyEnabled = true
                generate3DSheetTargetPartId = partId
            }
        case .apiKeyMissing:
            let alert = NSAlert()
            alert.messageText = "Meshy API key required"
            alert.informativeText = "Add your Meshy.ai API key in Preferences \u{2192} Meshy.ai before generating 3D models."
            alert.addButton(withTitle: "Open Preferences\u{2026}")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    /// Binding for the author-visible `scene3DSourceURL` field that also
    /// routes through the STL converter when the extension is `.stl`.
    /// Reading returns `scene3DSourceURL` (or falls back to `scene3DURL`
    /// for older documents). Writing stores the source path AND resolves
    /// the SceneKit-loadable URL.
    private func bindPartObjectPath(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let part = self.document.document.parts.first(where: { $0.id == id }) else { return "" }
                return part.scene3DSourceURL.isEmpty ? part.scene3DURL : part.scene3DSourceURL
            },
            set: { newValue in
                self.document.document.updatePart(id: id) {
                    $0.scene3DAssetRef = nil
                    $0.scene3DSourceURL = newValue
                    if STLConverter.isSTL(path: newValue) {
                        $0.scene3DURL = (try? STLConverter.convert(stlPath: newValue)) ?? ""
                    } else {
                        $0.scene3DURL = newValue
                    }
                }
            }
        )
    }

    private func chooseModelForPart(partId: UUID) {
        let panel = NSOpenPanel()
        // SceneKit-loadable formats plus .stl (auto-converted on import).
        // Include `.usd` (plain ASCII USD) alongside `.usdz`. macOS has
        // built-in UTType registrations for all of these — STL maps to
        // `public.standard-tesselated-geometry-format`.
        let exts = ["usdz", "usd", "scn", "dae", "obj", "stl", "glb", "gltf", "fbx"]
        panel.allowedContentTypes = exts.compactMap { UTType(filenameExtension: $0) }
        // Belt-and-suspenders: if a user has a model in a non-standard
        // format we still accept it — the Scene3D loader will reject
        // unsupported types at load time with a `modelLoadFailed` event,
        // which is more user-friendly than the picker greying it out.
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Pick a 3D model — .usdz / .usd / .scn / .dae / .obj / .stl"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let renderURL: URL
                if STLConverter.isSTL(path: url.path),
                   let convertedPath = try? STLConverter.convert(stlPath: url.path) {
                    renderURL = URL(fileURLWithPath: convertedPath)
                } else {
                    renderURL = url
                }
                let asset = try StackAssetEmbedder.importLocalFile(
                    at: renderURL,
                    as: .model3D,
                    preferredName: renderURL.lastPathComponent,
                    into: &document.document.assetRepository
                )
                let ref = document.document.assetRepository.assetRef(for: asset)
                document.document.updatePart(id: partId) {
                    $0.scene3DAssetRef = ref
                    $0.scene3DSourceURL = ""
                    $0.scene3DURL = ""
                }
            } catch {
                showAssetImportError(error)
            }
        }
    }

    private func audioRecorderSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Audio Recorder")
            Toggle("Recording", isOn: bindPartBool(part.id, \.audioRecording))
            Toggle("Playing", isOn: bindPartBool(part.id, \.audioPlaying))
                .disabled(part.audioOutputPath.isEmpty && part.audioData == nil)
            Toggle("Save Recordings in Stack", isOn: bindPartBool(part.id, \.audioEmbedInStack))
            Text("Toggle Recording / Playing here, or use the buttons on the part. HypeTalk: `set the recording of recorder \"X\" to true`, `set the playing of recorder \"X\" to true`.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(part.audioEmbedInStack
                 ? "New recordings are stored inside this stack so the stack stays portable."
                 : "New recordings use the external output path below. Turn on Save Recordings in Stack for portable stacks.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            HStack {
                Text("Format").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.audioFormat)) {
                    Text("AAC (.m4a)").tag("m4a")
                    Text("Linear PCM (.caf)").tag("caf")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Format")
            }
            if !part.audioEmbedInStack {
                propertyRow("Output Path", binding: bindPartString(part.id, \.audioOutputPath))
                Text("Empty path = Hype chooses a temporary file. Set a path only when you intentionally want a separate audio file.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            if let audioData = part.audioData {
                propertyRow("Stored Audio", value: ByteCountFormatter.string(fromByteCount: Int64(audioData.count), countStyle: .file))
            }
            propertyRow("Duration", value: String(format: "%.1f s", part.audioDuration))
        }
    }

    private func audioKitMusicControlSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Synth Music")
            propertyRow("Pattern", binding: bindPartString(part.id, \.musicPatternName))
            Picker("Instrument", selection: bindMusicInstrumentName(part.id)) {
                ForEach(MusicInstrumentCatalog.instruments, id: \.name) { instrument in
                    Text(instrument.isPercussion ? "\(instrument.name) (Drums)" : instrument.name)
                        .tag(instrument.name)
                }
            }
            .pickerStyle(.menu)
            if part.partType == .pianoKeyboard {
                Picker("Keys", selection: bindMusicKeyCount(part.id)) {
                    ForEach(MusicKeyboardKeyCount.supportedValues, id: \.self) { keyCount in
                        Text("\(keyCount) keys").tag(keyCount)
                    }
                }
                .pickerStyle(.menu)
            }
            tempoEditor(part: part)
            if part.partType == .pianoKeyboard || part.partType == .stepSequencer {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show Control Type", isOn: bindPartBool(part.id, \.musicShowControlType))
                    Toggle("Show Pattern Name", isOn: bindPartBool(part.id, \.musicShowPattern))
                    Toggle("Show Instrument Popup", isOn: bindPartBool(part.id, \.musicShowInstrument))
                    Toggle("Show Tempo", isOn: bindPartBool(part.id, \.musicShowTempo))
                    Text("When Instrument Popup is shown, Browse mode lets the user choose from Hype's available instruments.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            Toggle("Loop", isOn: bindPartBool(part.id, \.musicLoop))
            propertyRow("Volume", binding: bindPartDoubleString(part.id, \.musicVolume))
            if part.partType == .stepSequencer || part.partType == .musicMixer {
                propertyRow("Tracks", value: musicTrackCountDescription(part.musicTrackData))
                Text("Edit tracks on the control in Browse mode. Scripts: the trackData of this part.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Text("Synth controls play stack-contained Hype music patterns. Use Apple Music search for Apple Music catalog or library lookup.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    /// Read-only "Tracks" row value for the sequencer/mixer synth
    /// controls — a real track editor is a documented deferral
    /// (design-mock §7); this row just answers "how many tracks are
    /// stored" so the inspector isn't silent about `musicTrackData`.
    /// Parses as a bag of JSON objects the same tolerant way the
    /// runtime's `MusicModel.tracks(fromStoredTrackData:)` does
    /// (arbitrary keys, no required `id`/`pan`/etc.) rather than
    /// through `MusicTrackSpec`'s strict Codable synthesis, which
    /// would reject track JSON written by the AI tool surface.
    private func musicTrackCountDescription(_ trackDataJSON: String) -> String {
        guard let data = trackDataJSON.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !array.isEmpty else {
            return "(none)"
        }
        return "\(array.count)"
    }

    private func tempoEditor(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tempo")
                    .font(.system(size: 10))
                Spacer()
                TextField("BPM", value: bindMusicTempoInt(part.id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .font(.system(size: 11, design: .monospaced))
                Text("BPM")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: bindMusicTempoDouble(part.id),
                in: Double(MusicTempo.minimum)...Double(MusicTempo.maximum),
                step: 1
            )
        }
    }

    private func musicKitSearchSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Apple Music")
            propertyRow("Search", binding: bindPartString(part.id, \.musicSearchTerm))
            Picker("Search Scope", selection: bindPartString(part.id, \.musicSearchScope)) {
                Text("Catalog").tag(AppleMusicSearchScope.catalog.rawValue)
                Text("Library").tag(AppleMusicSearchScope.library.rawValue)
            }
            .pickerStyle(.menu)
            Picker("Type", selection: bindPartString(part.id, \.musicSourceType)) {
                ForEach([AppleMusicItemKind.song, .album, .artist, .playlist], id: \.rawValue) { kind in
                    Text(appleMusicDisplayName(for: kind)).tag(kind.rawValue)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Button("Authorize") { authorizeAppleMusicFromInspector() }
                Button("Search") { searchAppleMusicFromInspector(part: part) }
            }
            if !appleMusicInspectorResults.isEmpty {
                Picker("Result", selection: $appleMusicInspectorSelectedSource) {
                    ForEach(appleMusicInspectorResults, id: \.encodedSource) { item in
                        Text(appleMusicInspectorTitle(for: item)).tag(item.encodedSource)
                    }
                }
                .pickerStyle(.menu)
                Button("Use Selected Item") {
                    selectAppleMusicInspectorResult(partId: part.id)
                }
            }
            propertyRow("Selected ID", binding: bindPartString(part.id, \.musicSourceID))
            propertyRow("Title", binding: bindPartString(part.id, \.musicSourceTitle))
            propertyRow("Artist", binding: bindPartString(part.id, \.musicSourceArtist))
            propertyRow("Album", binding: bindPartString(part.id, \.musicSourceAlbum))
            propertyRow("Artwork URL", binding: bindPartString(part.id, \.musicArtworkURL))
            propertyRow("Position", binding: bindPartDoubleString(part.id, \.musicPosition), unit: "s")
            propertyRow("Duration", binding: bindPartDoubleString(part.id, \.musicDuration), unit: "s")
            HStack {
                Button("Play") { playAppleMusicFromInspector(part: part) }
                    .disabled(part.musicSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Seek") { seekAppleMusicFromInspector(part: part) }
                    .disabled(part.musicSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Stop") { stopAppleMusicFromInspector() }
            }
            Text(appleMusicInspectorStatus)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text("MusicKit stores Apple Music IDs and metadata snapshots only. It does not embed protected Apple Music audio in the stack.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func authorizeAppleMusicFromInspector() {
        guard UserDefaults.standard.bool(forKey: AppleMusicConfiguration.enabledKey) else {
            appleMusicInspectorStatus = "Enable Apple Music in Preferences first."
            return
        }
        appleMusicInspectorStatus = "Checking Apple Music authorization..."
        Task { @MainActor in
            let status = await AppleMusicProviderFactory.makeDefault().requestAuthorization()
            appleMusicInspectorStatus = "Apple Music authorization: \(status.rawValue)"
        }
    }

    private func searchAppleMusicFromInspector(part: Part) {
        guard UserDefaults.standard.bool(forKey: AppleMusicConfiguration.enabledKey),
              document.document.stack.appleMusicAllowed else {
            appleMusicInspectorStatus = "Enable Apple Music in Preferences and for this stack."
            return
        }
        let term = part.musicSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            appleMusicInspectorStatus = "Enter search text first."
            return
        }
        let scope = AppleMusicSearchScope(rawValue: part.musicSearchScope) ?? .catalog
        let kind = AppleMusicItemKind.parse(part.musicSourceType) ?? .song
        appleMusicInspectorStatus = "Searching Apple Music..."
        Task { @MainActor in
            do {
                let results = try await AppleMusicProviderFactory.makeDefault().search(
                    AppleMusicSearchRequest(term: term, scope: scope, itemKinds: [kind], limit: 12)
                )
                appleMusicInspectorResults = results
                appleMusicInspectorSelectedSource = results.first?.encodedSource ?? ""
                appleMusicInspectorStatus = results.isEmpty ? "No Apple Music results." : "Found \(results.count) result(s)."
                for item in results {
                    document.document.musicLibrary.upsertAppleMusicItem(item)
                }
            } catch {
                appleMusicInspectorResults = []
                appleMusicInspectorSelectedSource = ""
                appleMusicInspectorStatus = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    private func selectAppleMusicInspectorResult(partId: UUID) {
        guard let item = appleMusicInspectorResults.first(where: { $0.encodedSource == appleMusicInspectorSelectedSource }) else {
            appleMusicInspectorStatus = "Choose a search result first."
            return
        }
        document.document.musicLibrary.upsertAppleMusicItem(item)
        document.document.updatePart(id: partId) { part in
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
        appleMusicInspectorStatus = "Selected \(appleMusicDisplayName(for: item.kind).lowercased()) '\(item.titleSnapshot)'."
    }

    private func playAppleMusicFromInspector(part: Part) {
        guard UserDefaults.standard.bool(forKey: AppleMusicConfiguration.enabledKey),
              document.document.stack.appleMusicAllowed else {
            appleMusicInspectorStatus = "Enable Apple Music in Preferences and for this stack."
            return
        }
        guard let item = appleMusicRef(from: part) else {
            appleMusicInspectorStatus = "Select an Apple Music item first."
            return
        }
        Task { @MainActor in
            do {
                try await AppleMusicProviderFactory.makeDefault().play(item, engine: appleMusicPlaybackEngine())
                appleMusicInspectorStatus = "Playing '\(item.titleSnapshot)'."
            } catch {
                appleMusicInspectorStatus = "Playback failed: \(error.localizedDescription)"
            }
        }
    }

    private func seekAppleMusicFromInspector(part: Part) {
        Task { @MainActor in
            do {
                try await AppleMusicProviderFactory.makeDefault().seek(to: max(0, part.musicPosition), engine: appleMusicPlaybackEngine())
                appleMusicInspectorStatus = "Position set to \(part.musicPosition) seconds."
            } catch {
                appleMusicInspectorStatus = "Seek failed: \(error.localizedDescription)"
            }
        }
    }

    private func stopAppleMusicFromInspector() {
        Task { @MainActor in
            await AppleMusicProviderFactory.makeDefault().stop(engine: appleMusicPlaybackEngine())
            appleMusicInspectorStatus = "Stopped Apple Music."
        }
    }

    private func appleMusicRef(from part: Part) -> AppleMusicItemRef? {
        guard !part.musicSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let kind = AppleMusicItemKind.parse(part.musicSourceType) else {
            return nil
        }
        return AppleMusicItemRef(
            id: part.musicSourceID,
            kind: kind,
            source: MusicSourceKind.parse(part.musicSourceKind),
            titleSnapshot: part.musicSourceTitle.isEmpty ? part.musicSourceID : part.musicSourceTitle,
            artistSnapshot: part.musicSourceArtist,
            albumSnapshot: part.musicSourceAlbum,
            artworkURLSnapshot: part.musicArtworkURL,
            durationSnapshot: part.musicDuration > 0 ? part.musicDuration : nil
        )
    }

    private func appleMusicPlaybackEngine() -> AppleMusicPlaybackEngine {
        let raw = UserDefaults.standard.string(forKey: AppleMusicConfiguration.playbackEngineKey)
        return raw.flatMap(AppleMusicPlaybackEngine.init(rawValue:)) ?? AppleMusicConfiguration.defaultPlaybackEngine
    }

    private func appleMusicDisplayName(for kind: AppleMusicItemKind) -> String {
        switch kind {
        case .song: return "Song"
        case .album: return "Album"
        case .artist: return "Artist"
        case .playlist: return "Playlist"
        case .station: return "Station"
        case .musicVideo: return "Music Video"
        }
    }

    private func appleMusicInspectorTitle(for item: AppleMusicItemRef) -> String {
        let detail = [item.artistSnapshot, item.albumSnapshot]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " - ")
        return detail.isEmpty ? item.titleSnapshot : "\(item.titleSnapshot) - \(detail)"
    }

    private func legacyMusicQueueSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Legacy Music Queue")
            propertyRow("Queue Data", binding: bindPartString(part.id, \.musicQueueData))
            Text("This legacy queue remains readable for older stacks. New stacks should use synth controls for stack music and MusicKit Search for Apple Music lookup.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Phase 3 control sections

    private func progressViewSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Progress View")
            propertyRow("Label", binding: bindPartString(part.id, \.progressLabel))
            Toggle("Circular Spinner", isOn: bindPartBool(part.id, \.progressIsCircular))
            Toggle("Indeterminate", isOn: bindPartBool(part.id, \.progressIsIndeterminate))
            if !part.progressIsIndeterminate {
                propertyRow("Value", binding: bindPartDoubleString(part.id, \.progressValue))
                propertyRow("Max", binding: bindPartDoubleString(part.id, \.progressTotal))
                Text("Progress runs from 0 to Max.")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
            colorPropertyRow(label: "Tint", partId: part.id, keyPath: \.progressTint,
                             hint: "Empty = system accent color")
            HStack {
                Stepper(
                    "Decimals: \(part.progressDecimals)",
                    value: Binding<Int>(
                        get: { (self.document.document.parts.first { $0.id == part.id }?.progressDecimals) ?? 0 },
                        set: { newValue in
                            self.document.document.updatePart(id: part.id) {
                                $0.progressDecimals = max(0, min(10, newValue))
                            }
                        }
                    ),
                    in: 0...10
                )
                .font(.system(size: 11))
            }
            Text("0 = integer-only steps when the value is set. Same contract as the gauge control.")
                .font(.system(size: 9)).foregroundColor(.secondary)
            Text("HypeTalk: `set the value of progressView \"X\" to 0.5`. Fires `progressFinished` when value reaches max.")
                .font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    private func gaugeSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Gauge")
            propertyRow("Label", binding: bindPartString(part.id, \.gaugeLabel))
            propertyRow("Value", binding: bindPartDoubleString(part.id, \.gaugeValue))
            propertyRow("Min", binding: bindPartDoubleString(part.id, \.gaugeMin))
            propertyRow("Max", binding: bindPartDoubleString(part.id, \.gaugeMax))
            HStack {
                Text("Style").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.gaugeStyle)) {
                    Text("Linear Capacity").tag("linearCapacity")
                    Text("Accessory Circular").tag("accessoryCircular")
                    Text("Acc. Circular Cap.").tag("accessoryCircularCapacity")
                    Text("Accessory Linear").tag("accessoryLinear")
                    Text("Acc. Linear Cap.").tag("accessoryLinearCapacity")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Style")
            }
            colorPropertyRow(label: "Tint", partId: part.id, keyPath: \.gaugeTint,
                             hint: "Empty = system accent color")
            propertyRow("Min Label", binding: bindPartString(part.id, \.gaugeMinLabel))
            propertyRow("Max Label", binding: bindPartString(part.id, \.gaugeMaxLabel))
            HStack {
                Stepper(
                    "Decimals: \(part.gaugeDecimals)",
                    value: Binding<Int>(
                        get: { (self.document.document.parts.first { $0.id == part.id }?.gaugeDecimals) ?? 0 },
                        set: { newValue in
                            self.document.document.updatePart(id: part.id) {
                                $0.gaugeDecimals = max(0, min(10, newValue))
                            }
                        }
                    ),
                    in: 0...10
                )
                .font(.system(size: 11))
            }
            Text("0 = integer-only steps when scrubbing the gauge. Raise for finer precision (max 10).")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // linkSection / menuSection / searchFieldSection removed in dedup —
    // these standalone PartTypes were collapsed into ButtonStyle.link /
    // .popup and FieldStyle.search. The inspector dispatch routes the
    // migrated parts through the existing button / field sections.

    private func dividerSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Divider")
            HStack {
                Text("Orientation").font(.system(size: 10))
                Picker("", selection: bindPartString(part.id, \.dividerOrientation)) {
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Orientation")
            }
            propertyRow("Thickness", binding: bindPartDoubleString(part.id, \.dividerThickness), unit: "pt")
            colorPropertyRow(label: "Color", partId: part.id, keyPath: \.dividerColor,
                             hint: "Empty hex = system separator color")
        }
    }

    /// String<->Double round-trip binding for property-row text
    /// fields that need a numeric backing value. Empty / unparsable
    /// input is treated as zero so the field stays editable.
    private func bindPartDoubleString(_ id: UUID, _ keyPath: WritableKeyPath<Part, Double>) -> Binding<String> {
        Binding<String>(
            get: {
                guard let part = self.document.document.parts.first(where: { $0.id == id }) else { return "" }
                return String(part[keyPath: keyPath])
            },
            set: { newValue in
                let parsed = Double(newValue) ?? 0
                self.document.document.updatePart(id: id) { $0[keyPath: keyPath] = parsed }
            }
        )
    }

    /// Slider binding for `imageFilterIntensity` clamped to 0...1.
    private func bindPartIntensityValue(_ id: UUID) -> Binding<Double> {
        Binding<Double>(
            get: {
                self.document.document.parts.first(where: { $0.id == id })?.imageFilterIntensity ?? 0
            },
            set: { newValue in
                self.document.document.updatePart(id: id) {
                    $0.imageFilterIntensity = max(0, min(1, newValue))
                }
            }
        )
    }

    /// Int-backed property-row helper. Mirrors `bindPartDoubleString`.
    private func bindPartInt(_ id: UUID, _ keyPath: WritableKeyPath<Part, Int>) -> Binding<Int> {
        Binding<Int>(
            get: {
                self.document.document.parts.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0
            },
            set: { newValue in
                self.document.document.updatePart(id: id) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func chooseVideoForPart(partId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .movie, .quickTimeMovie]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let asset = try StackAssetEmbedder.importLocalFile(
                    at: url,
                    as: .videoClip,
                    preferredName: url.lastPathComponent,
                    into: &document.document.assetRepository
                )
                let ref = document.document.assetRepository.assetRef(for: asset)
                document.document.updatePart(id: partId) {
                    $0.videoAssetRef = ref
                    $0.videoURL = StackAssetEmbedder.assetURLString(for: asset)
                }
            } catch {
                showAssetImportError(error)
            }
        }
    }

    private func showAssetImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not import asset into stack"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
            sectionHeading("Sprite Area")

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

                    Button(action: { removeActiveScene(partId: part.id) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .disabled(areaSpec.scenes.count <= 1)
                    .help(areaSpec.scenes.count <= 1 ? "A Sprite Area must keep at least one scene" : "Delete Active Scene")
                }

                HStack(spacing: 8) {
                    Button("Guide Setup") {
                        sceneGuideContext = SpriteSceneGuideContext(partId: part.id, sceneId: areaSpec.activeSceneEntry?.id)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)

                    if userLevel.canEditScripts {
                        Button("Scene Script") {
                            if let sceneId = areaSpec.activeSceneEntry?.id {
                                openScriptEditorWindow(document: $document, target: .scene(partId: part.id, sceneId: sceneId))
                            }
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                    }

                    Button("Repository") {
                        openAssetRepositoryWindow(document: $document)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }

                propertyRow("Scene Name", binding: bindSceneSpecString(part.id, \.name))
                propertyRow("Nodes", value: "\(spec.nodes.count)")
                propertyRow("Size", value: "\(Int(spec.size.width)) \u{00d7} \(Int(spec.size.height))")

                let checklist = spec.authoringChecklist(using: document.document.assetRepository)
                Divider()
                sectionHeading("Setup Checklist")
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

                // MARK: Game Recipe
                if userLevel.canAuthorObjects {
                    gameRecipeSection(partId: part.id)
                }

                Picker("Scale", selection: bindSceneScaleMode(part.id)) {
                    ForEach(SceneScaleMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .font(.system(size: 11))

                // Same Part.transparentBackground flag image parts
                // use. When on, the SKView composites against the
                // card surface (and any image part beneath shows
                // through). The scene's stored backgroundColor is
                // ignored at runtime — restored if the user turns
                // the flag back off.
                Toggle("Transparent Background",
                       isOn: bindPartBool(part.id, \.transparentBackground))
                    .help("Let whatever's behind this sprite area (e.g. a card image) show through. The scene's nodes still render normally on top.")

                Divider()
                sectionHeading("Physics")
                HStack {
                    Text("Gravity").font(.system(size: 11))
                    Spacer()
                    numberField("dx", binding: bindSceneSpecDouble(part.id, \.gravity.dx))
                    numberField("dy", binding: bindSceneSpecDouble(part.id, \.gravity.dy))
                }

                Divider()
                sectionHeading("Controls")
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
                sectionHeading("Debug")
                Toggle("Show FPS", isOn: bindSceneSpecBool(part.id, \.showsFPS))
                Toggle("Show Physics", isOn: bindSceneSpecBool(part.id, \.showsPhysics))
                Toggle("Show Node Count", isOn: bindSceneSpecBool(part.id, \.showsNodeCount))
                Toggle("Paused", isOn: bindSceneSpecBool(part.id, \.isPaused))

                Divider()
                sectionHeading("Nodes")

                if !spec.nodes.isEmpty {
                    // Multi-node panel — appears above the tree when
                    // 2+ nodes are selected. Uniform-edit experience
                    // mirrors the part-level multi-selection panel:
                    // type a value once, every selected node adopts
                    // it; differing values surface as the "Multiple"
                    // placeholder.
                    if selectedNodeIds.count > 1 {
                        multiNodeSelectionPanel(partId: part.id, sceneSpec: spec)
                            .padding(.bottom, 6)
                    }
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

    // MARK: - Game Recipe Inspector

    /// Collapsible "Game Recipe" group shown below the setup checklist in the
    /// Sprite Area inspector. Provides manual authoring parity with the AI
    /// recipe tools: start a recipe, add/remove entities, attach/detach
    /// behaviors, and compile via the same `RecipeCompiler.compile+merge` core
    /// used by the AI `build_game` tool.
    ///
    /// All mutations go through `document.document.updatePart(id:)` so they
    /// are undoable and trigger autosave.
    @ViewBuilder
    private func gameRecipeSection(partId: UUID) -> some View {
        Divider()
        gameRecipeDisclosureGroup(partId: partId)
    }

    private func gameRecipeDisclosureGroup(partId: UUID) -> some View {
        let recipe = document.document.parts.first(where: { $0.id == partId })?.spriteAreaSpecModel?.recipe
        let entityCount = recipe?.entities.count ?? 0
        let hasRecipe = recipe != nil

        return DisclosureGroup(
            isExpanded: $recipeGroupExpanded,
            content: {
                if let recipe {
                    recipeExistingContent(partId: partId, recipe: recipe)
                } else {
                    recipeStartContent(partId: partId)
                }
            },
            label: {
                HStack(spacing: 4) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Game Recipe")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    if hasRecipe {
                        Text("(\(entityCount) entities)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        )
        .font(.system(size: 11))
    }

    /// Content shown when no recipe exists yet: a "Start Game Recipe" button
    /// with an optional genre preset picker.
    @ViewBuilder
    private func recipeStartContent(partId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Declarative recipe lets you describe game entities and behaviors. The Build Game button compiles them into nodes and HypeTalk scripts.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let presetIDs = GenrePresetLibrary.presetIDs
            if !presetIDs.isEmpty {
                Picker("Preset", selection: $recipePresetPickerID) {
                    Text("Blank").tag("")
                    ForEach(presetIDs, id: \.self) { pid in
                        Text(pid).tag(pid)
                    }
                }
                .font(.system(size: 11))
            }

            Button("Start Game Recipe") {
                startRecipe(partId: partId)
            }
            .font(.system(size: 10))
            .buttonStyle(.borderless)
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
    }

    /// Content shown when a recipe exists: entity list, add-entity row,
    /// and the Build Game button.
    @ViewBuilder
    private func recipeExistingContent(partId: UUID, recipe: GameRecipe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Entity list
            if !recipe.entities.isEmpty {
                Text("Entities").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                ForEach(recipe.entities) { entity in
                    recipeEntityRow(partId: partId, entity: entity)
                }
            }

            // Add Entity row
            Divider()
            Text("Add Entity").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
            HStack(spacing: 4) {
                TextField("name", text: $newEntityName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)

                Picker("", selection: $newEntityRole) {
                    ForEach(EntityRole.allCases, id: \.self) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .labelsHidden()
                .font(.system(size: 10))
                .frame(width: 90)
                .accessibilityLabel("Role")

                Button("Add") {
                    addRecipeEntity(partId: partId)
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
                .disabled(newEntityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Build Game button
            Divider()
            Button(action: { buildGame(partId: partId) }) {
                HStack(spacing: 4) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 11))
                    Text("Build Game")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .help("Compile the recipe into scene nodes and HypeTalk scripts (same compiler the AI uses).")

            // Diagnostics from the last build
            if !recipeBuildDiagnostics.isEmpty {
                DisclosureGroup(
                    isExpanded: $recipeBuildDiagnosticsExpanded,
                    content: {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(recipeBuildDiagnostics, id: \.self) { msg in
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange)
                                    Text(msg)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    },
                    label: {
                        Text("Build diagnostics (\(recipeBuildDiagnostics.count))")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                )
            }

            // Remove recipe button
            Divider()
            Button("Remove Recipe") {
                removeRecipe(partId: partId)
            }
            .font(.system(size: 9))
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
    }

    /// A single entity row: editable name, role picker, behavior chips,
    /// and a delete button.
    @ViewBuilder
    private func recipeEntityRow(partId: UUID, entity: GameEntity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField("name", text: bindEntityName(partId: partId, entityId: entity.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)

                Picker("", selection: bindEntityRole(partId: partId, entityId: entity.id)) {
                    ForEach(EntityRole.allCases, id: \.self) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .labelsHidden()
                .font(.system(size: 9))
                .frame(width: 80)
                .accessibilityLabel("Role")

                Button(action: { removeRecipeEntity(partId: partId, entityId: entity.id) }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }

            // Behavior chips: scrolling HStack of toggle buttons for every BehaviorKind.
            // Splitting into two rows keeps the inspector from overflowing.
            let attached = Set(entity.behaviors.map(\.kind))
            behaviorChipsView(
                partId: partId,
                entityId: entity.id,
                attachedKinds: attached
            )
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(4)
    }

    /// Behavior chips laid out as a wrapped flow using two rows of distinct
    /// behavior kind groups to keep column width manageable.
    @ViewBuilder
    private func behaviorChipsView(
        partId: UUID,
        entityId: UUID,
        attachedKinds: Set<BehaviorKind>
    ) -> some View {
        // Split into movement/physics vs. game-logic chips for two compact rows.
        let movementKinds: [BehaviorKind] = [
            .platformerMovement, .topDownMovement, .eightDirection,
            .followPointer, .chaseTarget, .patrol,
            .physicsBody, .bounce, .wrapAround,
            .constrainToBounds, .destroyOutsideBounds, .draggable,
            .rotator, .oscillate, .spawner
        ]
        let logicKinds: [BehaviorKind] = [
            .collectible, .damageOnContact, .health, .scoreOnCollect,
            .winOnReach, .winOnScore, .loseOnContact, .loseOnZeroHealth
        ]

        VStack(alignment: .leading, spacing: 2) {
            behaviorChipRow(
                partId: partId,
                entityId: entityId,
                kinds: movementKinds,
                attachedKinds: attachedKinds
            )
            behaviorChipRow(
                partId: partId,
                entityId: entityId,
                kinds: logicKinds,
                attachedKinds: attachedKinds
            )
        }
    }

    @ViewBuilder
    private func behaviorChipRow(
        partId: UUID,
        entityId: UUID,
        kinds: [BehaviorKind],
        attachedKinds: Set<BehaviorKind>
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(kinds, id: \.self) { kind in
                    let isOn = attachedKinds.contains(kind)
                    Button(action: {
                        toggleBehavior(partId: partId, entityId: entityId, kind: kind, isOn: isOn)
                    }) {
                        Text(Self.behaviorShortLabel(kind))
                            .font(.system(size: 8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(isOn ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.15))
                            .foregroundColor(isOn ? .white : .primary)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.borderless)
                    .help(kind.rawValue)
                }
            }
        }
    }

    // MARK: - Game Recipe: Pure Helpers

    /// Short display label for a behavior kind chip. Pure — safe to unit-test.
    static func behaviorShortLabel(_ kind: BehaviorKind) -> String {
        switch kind {
        case .platformerMovement: return "platMove"
        case .topDownMovement:    return "tdMove"
        case .eightDirection:     return "8dir"
        case .followPointer:      return "followPtr"
        case .chaseTarget:        return "chase"
        case .patrol:             return "patrol"
        case .physicsBody:        return "physics"
        case .bounce:             return "bounce"
        case .wrapAround:         return "wrap"
        case .constrainToBounds:  return "constrain"
        case .destroyOutsideBounds: return "destroyOOB"
        case .spawner:            return "spawner"
        case .collectible:        return "collect"
        case .damageOnContact:    return "damage"
        case .health:             return "health"
        case .scoreOnCollect:     return "score+"
        case .winOnReach:         return "winReach"
        case .winOnScore:         return "winScore"
        case .loseOnContact:      return "loseCtct"
        case .loseOnZeroHealth:   return "loseHP"
        case .draggable:          return "drag"
        case .rotator:            return "rotate"
        case .oscillate:          return "osc"
        }
    }

    /// Default `params` for a newly-attached behavior. Mirrors the
    /// documented defaults from `Behavior.swift`. Pure — safe to unit-test.
    static func defaultParamsForBehavior(_ kind: BehaviorKind) -> [String: String] {
        switch kind {
        case .platformerMovement:   return ["speed": "200", "jumpForce": "620"]
        case .topDownMovement:      return ["speed": "200"]
        case .eightDirection:       return ["speed": "200"]
        case .followPointer:        return ["speed": "220", "axis": "both"]
        case .chaseTarget:          return ["targetRole": "player", "speed": "120"]
        case .patrol:               return ["axis": "x", "speed": "120", "range": "120"]
        case .physicsBody:          return ["dynamic": "true", "restitution": "0.2", "friction": "0.2", "bodyShape": "rect"]
        case .spawner:              return ["spawnRole": "enemy", "interval": "1.5", "fromEdge": "top", "velocity": "0,-160", "max": "8"]
        case .damageOnContact:      return ["amount": "1", "targetRole": "player"]
        case .health:               return ["max": "3"]
        case .scoreOnCollect:       return ["points": "10"]
        case .winOnScore:           return ["threshold": "100"]
        case .loseOnContact:        return ["withRole": "hazard"]
        case .destroyOutsideBounds: return ["margin": "80"]
        case .rotator:              return ["degreesPerSecond": "90"]
        case .oscillate:            return ["axis": "y", "amplitude": "40", "period": "2"]
        default:                    return [:]
        }
    }

    /// Build a default `GameEntity` for a given name and role. Pure — safe to unit-test.
    static func defaultEntity(name: String, role: EntityRole) -> GameEntity {
        let defaultSize = defaultEntitySize(for: role)
        return GameEntity(
            name: name,
            role: role,
            position: PointSpec(x: 100, y: 100),
            size: defaultSize,
            count: 1
        )
    }

    /// Default size heuristic per role. Pure — safe to unit-test.
    static func defaultEntitySize(for role: EntityRole) -> SizeSpec {
        switch role {
        case .background: return SizeSpec(width: 800, height: 600)
        case .wall:       return SizeSpec(width: 200, height: 32)
        case .hud:        return SizeSpec(width: 160, height: 32)
        case .player:     return SizeSpec(width: 56, height: 56)
        default:          return SizeSpec(width: 48, height: 48)
        }
    }

    // MARK: - Game Recipe: Bindings

    private func bindEntityName(partId: UUID, entityId: UUID) -> Binding<String> {
        Binding(
            get: {
                document.document.parts.first(where: { $0.id == partId })?
                    .spriteAreaSpecModel?.recipe?
                    .entities.first(where: { $0.id == entityId })?.name ?? ""
            },
            set: { newVal in
                modifyRecipe(partId: partId) { recipe in
                    guard let idx = recipe.entities.firstIndex(where: { $0.id == entityId }) else { return }
                    recipe.entities[idx].name = newVal
                }
            }
        )
    }

    private func bindEntityRole(partId: UUID, entityId: UUID) -> Binding<EntityRole> {
        Binding(
            get: {
                document.document.parts.first(where: { $0.id == partId })?
                    .spriteAreaSpecModel?.recipe?
                    .entities.first(where: { $0.id == entityId })?.role ?? .decoration
            },
            set: { newVal in
                modifyRecipe(partId: partId) { recipe in
                    guard let idx = recipe.entities.firstIndex(where: { $0.id == entityId }) else { return }
                    recipe.entities[idx].role = newVal
                }
            }
        )
    }

    // MARK: - Game Recipe: Mutation Helpers

    /// Apply `transform` to the recipe inside this part, committing through
    /// `document.document.updatePart` so mutations are undoable and autosaved.
    private func modifyRecipe(partId: UUID, transform: (inout GameRecipe) -> Void) {
        document.document.updatePart(id: partId) { part in
            part.updateRecipe { optRecipe in
                guard var recipe = optRecipe else { return }
                transform(&recipe)
                optRecipe = recipe
            }
        }
    }

    private func startRecipe(partId: UUID) {
        guard let part = document.document.parts.first(where: { $0.id == partId }) else { return }
        let sceneName = part.spriteAreaSpecModel?.activeScene?.name ?? (part.name.isEmpty ? "Game" : part.name)
        let sceneSize = part.spriteAreaSpecModel?.activeScene?.size
            ?? SizeSpec(width: max(100, part.width), height: max(100, part.height))

        let preset: GameRecipe?
        if recipePresetPickerID.isEmpty {
            preset = nil
        } else {
            preset = GenrePresetLibrary.preset(for: recipePresetPickerID, sceneName: sceneName, sceneSize: sceneSize)
        }

        let newRecipe = preset ?? GameRecipe(sceneName: sceneName, sceneSize: sceneSize)
        document.document.updatePart(id: partId) { part in
            part.updateRecipe { $0 = newRecipe }
        }
        recipeGroupExpanded = true
    }

    private func removeRecipe(partId: UUID) {
        document.document.updatePart(id: partId) { part in
            part.updateRecipe { $0 = nil }
        }
        recipeBuildDiagnostics = []
    }

    private func addRecipeEntity(partId: UUID) {
        let trimmed = newEntityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entity = Self.defaultEntity(name: trimmed, role: newEntityRole)
        modifyRecipe(partId: partId) { recipe in
            recipe.entities.append(entity)
        }
        newEntityName = ""
        newEntityRole = .decoration
    }

    private func removeRecipeEntity(partId: UUID, entityId: UUID) {
        modifyRecipe(partId: partId) { recipe in
            recipe.entities.removeAll { $0.id == entityId }
        }
    }

    private func toggleBehavior(partId: UUID, entityId: UUID, kind: BehaviorKind, isOn: Bool) {
        modifyRecipe(partId: partId) { recipe in
            guard let entityIdx = recipe.entities.firstIndex(where: { $0.id == entityId }) else { return }
            if isOn {
                recipe.entities[entityIdx].behaviors.removeAll { $0.kind == kind }
            } else {
                let behavior = Behavior(
                    kind: kind,
                    params: Self.defaultParamsForBehavior(kind)
                )
                recipe.entities[entityIdx].behaviors.append(behavior)
            }
        }
    }

    /// Compile the recipe and merge the result into the active scene, using
    /// the identical `RecipeCompiler.compile+merge` path the AI `build_game`
    /// tool uses. Mutations are committed through `updatePart` (undoable).
    private func buildGame(partId: UUID) {
        guard let part = document.document.parts.first(where: { $0.id == partId }),
              let recipe = part.spriteAreaSpecModel?.recipe else {
            recipeBuildDiagnostics = ["No recipe found. Start a recipe first."]
            recipeBuildDiagnosticsExpanded = true
            return
        }

        let compilationResult = RecipeCompiler.compile(recipe, repository: document.document.assetRepository)

        document.document.updatePart(id: partId) { p in
            p.updateActiveSceneSpec { scene in
                // Mirror the AI executor's build_game: apply recipe geometry,
                // then merge nodes and script.
                scene.size = recipe.sceneSize
                scene.backgroundColor = recipe.backgroundColor
                scene.gravity = recipe.gravity
                RecipeCompiler.merge(compilationResult, into: &scene)
            }
        }

        recipeBuildDiagnostics = compilationResult.diagnostics
        recipeBuildDiagnosticsExpanded = !compilationResult.diagnostics.isEmpty
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
                            Image(systemName: selectedNodeIds.contains(node.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        } else {
                            Spacer().frame(width: 10)
                        }

                        Image(systemName: nodeIcon(node.nodeType))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("name", text: bindNodeName(partId: partId, node: node))
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
                        if userLevel.canEditScripts {
                            Button(action: {
                                openScriptEditorWindow(document: $document, target: .node(partId: partId, nodeId: node.id))
                            }) {
                                Image(systemName: "applescript")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                        }
                        Button(action: { removeSceneNode(partId: partId, nodeId: node.id) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    // Tap handler with modifier-aware semantics:
                    // - Plain click: replace selection (or toggle off
                    //   if this was already the only selected node)
                    // - Cmd or Shift + click: toggle this node in /
                    //   out of the multi-selection
                    // SwiftUI's `onTapGesture` doesn't expose the
                    // event's modifier flags directly, but `NSEvent`
                    // exposes the global modifier state at any
                    // moment; reading it inside the closure is
                    // accurate and avoids needing layered
                    // `.gesture(TapGesture().modifiers(...))`
                    // declarations.
                    .onTapGesture {
                        let flags = NSEvent.modifierFlags
                        let toggle = flags.contains(.command) || flags.contains(.shift)
                        if toggle {
                            if selectedNodeIds.contains(node.id) {
                                selectedNodeIds.remove(node.id)
                            } else {
                                selectedNodeIds.insert(node.id)
                            }
                        } else if selectedNodeIds == [node.id] {
                            selectedNodeIds = []
                        } else {
                            selectedNodeIds = [node.id]
                        }
                    }
                    .padding(.vertical, 2)
                    .background(selectedNodeIds.contains(node.id) ? Color.accentColor.opacity(0.08) : Color.clear)
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
                    // Per-node detail expands only when exactly ONE
                    // node is selected — when multiple are picked
                    // the multi-node panel rendered above the tree
                    // takes over (showing common properties across
                    // the selection); per-node detail would be
                    // ambiguous in that state.
                    if selectedNodeIds.count == 1 && selectedNodeIds.contains(node.id) {
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

    private func removeActiveScene(partId: UUID) {
        document.document.updatePart(id: partId) { part in
            part.updateSpriteAreaSpec { areaSpec in
                _ = areaSpec.removeScene(id: areaSpec.activeSceneID)
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

    private func bindNodeName(partId: UUID, node: HypeNodeSpec) -> Binding<String> {
        Binding(
            get: {
                node.name
            },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: node.id, in: &spec.nodes) { $0.name = newVal }
                }
            }
        )
    }

    // MARK: - Multi-Node Selection Panel
    //
    // Renders above the sprite-scene tree when 2+ nodes are
    // selected. Mirrors the part-level multi-selection panel:
    // common-value detection across the selection, "Multiple"
    // placeholder for divergent properties, single-edit applies
    // to every selected node. The set of editable properties is
    // chosen to be common across all `HypeNodeSpec` types
    // (sprite, label, shape, group, camera, emitter, audio,
    // video, tilemap) — geometry, transform, alpha, visibility.
    // Type-specific text fields (text, fontName, fontSize,
    // fontColor) only show when every selected node is a label.

    @ViewBuilder
    private func multiNodeSelectionPanel(partId: UUID, sceneSpec: SceneSpec) -> some View {
        // Walk the scene tree once and collect every selected node
        // by id. The tree may be deeply nested (groups inside
        // groups), so a flat list of candidates is awkward — but
        // findNodeById already handles the recursive descent.
        let selected = selectedNodeIds.compactMap { id in
            Self.findNodeById(id, in: sceneSpec.nodes)
        }
        // Type-homogeneity gates the optional sections. Empty list
        // suppresses the whole panel — defensive in case the
        // selection state references nodes that have been removed.
        let allLabels = !selected.isEmpty && selected.allSatisfy { $0.nodeType == .label }
        let allHaveSize = !selected.isEmpty && selected.allSatisfy { $0.size != nil }

        VStack(alignment: .leading, spacing: 6) {
            Text("\(selected.count) Nodes Selected")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.accentColor)

            // Position + Size — the load-bearing case. Scene nodes
            // store position as a nested PointSpec; KeyPaths to
            // nested struct fields work because position is `var`.
            HStack(spacing: 8) {
                multiNodeNumberField("X", partId: partId, nodes: selected, keyPath: \.position.x)
                multiNodeNumberField("Y", partId: partId, nodes: selected, keyPath: \.position.y)
            }
            if allHaveSize {
                HStack(spacing: 8) {
                    multiNodeOptionalSizeField("Width", partId: partId, nodes: selected, axis: .width)
                    multiNodeOptionalSizeField("Height", partId: partId, nodes: selected, axis: .height)
                }
            }

            // Transform: rotation, scale, alpha, zPosition.
            HStack(spacing: 8) {
                multiNodeNumberField("Rotation", partId: partId, nodes: selected, keyPath: \.rotation)
                multiNodeNumberField("Alpha", partId: partId, nodes: selected, keyPath: \.alpha)
            }
            HStack(spacing: 8) {
                multiNodeNumberField("Scale X", partId: partId, nodes: selected, keyPath: \.xScale)
                multiNodeNumberField("Scale Y", partId: partId, nodes: selected, keyPath: \.yScale)
            }
            HStack(spacing: 8) {
                multiNodeNumberField("Z", partId: partId, nodes: selected, keyPath: \.zPosition)
            }

            // Visibility — the only non-numeric property uniformly
            // available across every node type. "Visible" (inverted
            // binding over the stored `isHidden`) matches the single
            // node panel and the part-level polarity — one concept,
            // one polarity, everywhere (design-mock §1.5.4).
            Toggle("Visible", isOn: Binding(
                get: { !(MultiSelectionEditing.commonValue(in: selected, for: \.isHidden) ?? false) },
                set: { newVal in applyToSelectedNodes(partId: partId, ids: selectedNodeIds) { $0.isHidden = !newVal } }
            ))

            // Label-only text formatting. The Optional<String> /
            // Optional<Double> in HypeNodeSpec means we have to
            // bridge through dedicated bindings rather than the
            // generic numeric / string helpers.
            if allLabels {
                Divider()
                HStack {
                    Text("Text").font(.system(size: 11)).foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
                    TextField("Multiple", text: Binding(
                        get: { MultiSelectionEditing.commonValue(in: selected, for: \.text)?.flatMap { $0 } ?? "" },
                        set: { newVal in applyToSelectedNodes(partId: partId, ids: selectedNodeIds) { $0.text = newVal.isEmpty ? nil : newVal } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                }
                HStack(spacing: 8) {
                    multiNodeOptionalNumberField("Size", partId: partId, nodes: selected, keyPath: \.fontSize)
                }
                // Font color (label nodes only).
                HStack {
                    ColorPicker("", selection: Binding<Color>(
                        get: {
                            // Optional<String> nested — flatten to a hex
                            // for the color helper.
                            let common = MultiSelectionEditing.commonValue(in: selected, for: \.fontColor)
                            if let hex = common?.flatMap({ $0 }), !hex.isEmpty {
                                return Color(hex: hex)
                            }
                            return Color.clear
                        },
                        set: { newVal in
                            let hex = newVal.toHex()
                            applyToSelectedNodes(partId: partId, ids: selectedNodeIds) { $0.fontColor = hex }
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Text Color")
                    Text("Text Color").font(.system(size: 11))
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(6)
    }

    /// Multi-node numeric edit row for a non-optional Double KeyPath
    /// (position.x/y, rotation, alpha, xScale, yScale, zPosition).
    /// Mirrors `multiNumberField` for parts.
    private func multiNodeNumberField(
        _ label: String,
        partId: UUID,
        nodes: [HypeNodeSpec],
        keyPath: WritableKeyPath<HypeNodeSpec, Double>
    ) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("Multiple", text: Binding(
                get: {
                    guard let v = MultiSelectionEditing.commonValue(in: nodes, for: keyPath) else { return "" }
                    return v == v.rounded() ? String(Int(v)) : String(v)
                },
                set: { newVal in
                    let trimmed = newVal.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, let parsed = Double(trimmed) else { return }
                    applyToSelectedNodes(partId: partId, ids: selectedNodeIds) { $0[keyPath: keyPath] = parsed }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(width: 60)
        }
    }

    /// Multi-node numeric edit row for an OPTIONAL Double KeyPath
    /// (fontSize on label nodes). Empty input clears the value to
    /// nil; a parsable number sets it.
    private func multiNodeOptionalNumberField(
        _ label: String,
        partId: UUID,
        nodes: [HypeNodeSpec],
        keyPath: WritableKeyPath<HypeNodeSpec, Double?>
    ) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("Multiple", text: Binding(
                get: {
                    let common = MultiSelectionEditing.commonValue(in: nodes, for: keyPath)
                    guard let v = common?.flatMap({ $0 }) else { return "" }
                    return v == v.rounded() ? String(Int(v)) : String(v)
                },
                set: { newVal in
                    let trimmed = newVal.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        applyToSelectedNodes(partId: partId, ids: selectedNodeIds) { $0[keyPath: keyPath] = nil }
                    } else if let parsed = Double(trimmed) {
                        applyToSelectedNodes(partId: partId, ids: selectedNodeIds) { $0[keyPath: keyPath] = parsed }
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(width: 60)
        }
    }

    /// Multi-node numeric edit for `size.width` / `size.height`.
    /// `size` itself is `SizeSpec?`, so the binding has to handle
    /// the Optional<SizeSpec> case explicitly — we can't write to
    /// `size.width` if `size == nil`. Setter assigns a fresh
    /// SizeSpec when missing.
    private enum SizeAxis { case width, height }
    private func multiNodeOptionalSizeField(
        _ label: String,
        partId: UUID,
        nodes: [HypeNodeSpec],
        axis: SizeAxis
    ) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("Multiple", text: Binding(
                get: {
                    // Read all current values for the chosen axis.
                    let values: [Double?] = nodes.map { node in
                        switch axis {
                        case .width:  return node.size?.width
                        case .height: return node.size?.height
                        }
                    }
                    guard let first = values.first, let f = first else { return "" }
                    return values.dropFirst().allSatisfy { $0 == f }
                        ? (f == f.rounded() ? String(Int(f)) : String(f))
                        : ""
                },
                set: { newVal in
                    let trimmed = newVal.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, let parsed = Double(trimmed) else { return }
                    applyToSelectedNodes(partId: partId, ids: selectedNodeIds) { node in
                        switch axis {
                        case .width:
                            if var size = node.size { size.width = parsed; node.size = size }
                            else { node.size = SizeSpec(width: parsed, height: 0) }
                        case .height:
                            if var size = node.size { size.height = parsed; node.size = size }
                            else { node.size = SizeSpec(width: 0, height: parsed) }
                        }
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(width: 60)
        }
    }

    /// Apply a transform to every node in `ids` inside `partId`'s
    /// scene spec. Single canonical entry point so the multi-node
    /// editing path looks like a sibling of `applyToSelected`
    /// (which targets canvas parts).
    private func applyToSelectedNodes(
        partId: UUID,
        ids: Set<UUID>,
        transform: @escaping (inout HypeNodeSpec) -> Void
    ) {
        modifySceneSpec(partId: partId) { spec in
            for id in ids {
                _ = Self.updateNodeInTree(nodeId: id, in: &spec.nodes, transform: transform)
            }
        }
    }

    // MARK: - Node Detail Panel

    @ViewBuilder
    private func nodeDetailPanel(partId: UUID, node: HypeNodeSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if userLevel.canEditScripts {
                    Button("Node Script") {
                        openScriptEditorWindow(document: $document, target: .node(partId: partId, nodeId: node.id))
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }

                if let assetId = node.assetRef?.id {
                    Button("Reveal Asset") {
                        openAssetRepositoryWindow(document: $document, initialAssetId: assetId)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }
            }

            // -- Common properties (all node types) --
            sectionHeading("Position")
            HStack {
                numberField("X", binding: bindNodePositionX(partId: partId, nodeId: node.id))
                numberField("Y", binding: bindNodePositionY(partId: partId, nodeId: node.id))
            }
            HStack {
                numberField("Width", binding: bindNodeWidth(partId: partId, nodeId: node.id))
                numberField("Height", binding: bindNodeHeight(partId: partId, nodeId: node.id))
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
            Toggle("Visible", isOn: bindNodeVisible(partId: partId, nodeId: node.id))
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
                sectionHeading("Crop")
                Text("Uses asset as mask texture").font(.system(size: 10)).foregroundColor(.secondary)
                spriteNodeProperties(partId: partId, node: node)
            case .effect:
                sectionHeading("Effect")
                Text("Applies Core Image filter").font(.system(size: 10)).foregroundColor(.secondary)
            case .light:
                sectionHeading("Light")
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
        sectionHeading("Sprite")

        let imageAssets = document.document.assetRepository.assets.filter {
            $0.kind == .imageTexture || $0.kind == .spriteSheet
        }

        if imageAssets.isEmpty {
            Text("No assets -- open Asset Repository to import")
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
            if let ref = node.assetRef, let asset = document.document.assetRepository.asset(byId: ref.id) {
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
        sectionHeading("Label")
        propertyRow("Text", binding: bindNodeOptionalString(partId: partId, nodeId: node.id, \.text))

        Picker("Font", selection: bindNodeOptionalString(partId: partId, nodeId: node.id, \.fontName)) {
            ForEach(systemFontFamilies, id: \.self) { fontName in
                Text(fontName).font(.system(size: 11)).tag(fontName as String?)
            }
        }
        .font(.system(size: 11))

        numberField("Size", binding: bindNodeOptionalDouble(partId: partId, nodeId: node.id, \.fontSize))

        ColorPicker("Text Color", selection: bindNodeColor(partId: partId, nodeId: node.id, getter: { $0.fontColor }, setter: { $0.fontColor = $1 }))
    }

    @ViewBuilder
    private func shapeNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        sectionHeading("Shape")

        Picker("Style", selection: bindShapeType(partId: partId, nodeId: node.id)) {
            ForEach(SpriteShapeType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
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
        sectionHeading("Audio")

        let audioAssets = document.document.assetRepository.assets.filter { $0.kind == .audioClip }

        if audioAssets.isEmpty {
            Text("No audio assets -- open Asset Repository to import")
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
        sectionHeading("Video")

        let videoAssets = document.document.assetRepository.assets.filter { $0.kind == .videoClip }

        if videoAssets.isEmpty {
            Text("No video assets -- open Asset Repository to import")
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
            numberField("Width", binding: bindNodeWidth(partId: partId, nodeId: node.id))
            numberField("Height", binding: bindNodeHeight(partId: partId, nodeId: node.id))
        }
    }

    @ViewBuilder
    private func emitterNodeProperties(partId: UUID, node: HypeNodeSpec) -> some View {
        sectionHeading("Emitter")

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
        sectionHeading("Physics")

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
            Toggle("Affected by Gravity", isOn: bindPhysicsBool(partId: partId, nodeId: node.id, \.affectedByGravity))
                .font(.system(size: 11))
            Toggle("Allow Rotation", isOn: bindPhysicsBool(partId: partId, nodeId: node.id, \.allowsRotation))
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

    /// "Visible" toggle for a single node — the inverse of the
    /// stored `isHidden` flag. One polarity for one concept across
    /// the node single panel, the node multi panel, and the part
    /// panel, all of which say "Visible" (design-mock §1.5.4).
    private func bindNodeVisible(partId: UUID, nodeId: UUID) -> Binding<Bool> {
        Binding(
            get: { !bindNodeBool(partId: partId, nodeId: nodeId, \.isHidden).wrappedValue },
            set: { newVal in
                modifySceneSpec(partId: partId) { spec in
                    Self.updateNodeInTree(nodeId: nodeId, in: &spec.nodes) { $0.isHidden = !newVal }
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
                           let asset = document.document.assetRepository.asset(byId: assetId) {
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
            sectionHeading("Text Formatting")
            HStack {
                Text("Font").frame(width: 40, alignment: .trailing).font(.system(size: 11))
                Picker("", selection: bindPartString(part.id, \.textFont)) {
                    ForEach(systemFontFamilies, id: \.self) { fontName in
                        Text(fontName).font(.system(size: 11)).tag(fontName)
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .accessibilityLabel("Font")
            }
            numberField("Size", binding: bindPartDouble(part.id, \.textSize))
            Picker("Align", selection: bindPartTextAlign(part.id)) {
                Image(systemName: "text.alignleft").tag(HypeCore.TextAlignment.left)
                Image(systemName: "text.aligncenter").tag(HypeCore.TextAlignment.center)
                Image(systemName: "text.alignright").tag(HypeCore.TextAlignment.right)
            }
            .pickerStyle(.segmented)

            // Font color — empty hex means "auto / contrast-aware".
            // ColorPicker writes any hex; the existing
            // colorPropertyRow already pairs swatch + hex text.
            colorPropertyRow(label: "Text Color", partId: part.id, keyPath: \.fontColor,
                             hint: "Empty = auto (contrasts with the part fill).")

            // textStyle toggles. Each toggle reads / writes one flag
            // of `TextStyleFlags`; the underlying `part.textStyle`
            // stays the canonical comma-joined string ("plain" /
            // "bold, italic" / "bold, underline, strikethrough").
            HStack(spacing: 4) {
                Text("Style").frame(width: 40, alignment: .trailing).font(.system(size: 11))
                styleToggle(part: part, flag: .bold,          systemImage: "bold")
                styleToggle(part: part, flag: .italic,        systemImage: "italic")
                styleToggle(part: part, flag: .underline,     systemImage: "underline")
                styleToggle(part: part, flag: .strikethrough, systemImage: "strikethrough")
                Spacer()
            }
        }
    }

    // MARK: - textStyle toggle helpers

    /// Discriminator for the four supported text-style flags. Used
    /// by both the single-part `styleToggle` and the multi-selection
    /// `multiStyleToggle` so both surfaces share the same enum +
    /// reads / writes through the same canonical
    /// `TextStyleFlags.rawString`.
    fileprivate enum TextStyleFlag {
        case bold, italic, underline, strikethrough
    }

    /// Single-part toggle for one text-style flag. Reads
    /// `part.textStyle`, parses through `TextStyleFlags`, mutates the
    /// requested flag, writes the canonical rawString back. The
    /// resulting button shows as "selected" (bold-tinted) when the
    /// flag is currently set so the user can see the active style at
    /// a glance.
    @ViewBuilder
    fileprivate func styleToggle(part: Part, flag: TextStyleFlag, systemImage: String) -> some View {
        let active = isStyleFlagSet(part: part, flag: flag)
        Button(action: { toggleStyleFlag(partId: part.id, flag: flag) }) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: active ? .bold : .regular))
                .frame(width: 26, height: 22)
                .background(active ? Color.accentColor.opacity(0.25) : Color.clear)
                .foregroundColor(active ? .accentColor : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    fileprivate func isStyleFlagSet(part: Part, flag: TextStyleFlag) -> Bool {
        let flags = TextStyleFlags(string: part.textStyle)
        switch flag {
        case .bold:          return flags.bold
        case .italic:        return flags.italic
        case .underline:     return flags.underline
        case .strikethrough: return flags.strikethrough
        }
    }

    fileprivate func toggleStyleFlag(partId: UUID, flag: TextStyleFlag) {
        document.document.updatePart(id: partId) { part in
            var flags = TextStyleFlags(string: part.textStyle)
            switch flag {
            case .bold:          flags.bold.toggle()
            case .italic:        flags.italic.toggle()
            case .underline:     flags.underline.toggle()
            case .strikethrough: flags.strikethrough.toggle()
            }
            part.textStyle = flags.rawString
        }
    }

    @ViewBuilder
    private func chartSection(part: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Chart")

            let config = ChartConfig.fromJSON(part.chartData) ?? ChartConfig()

            Picker("Type", selection: bindChartType(part.id)) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            propertyRow("Title", binding: bindChartField(part.id, \.title))
            Toggle("Show Legend", isOn: bindChartBool(part.id, \.showLegend))
            Toggle("Show Grid", isOn: bindChartBool(part.id, \.showGrid))

            if config.chartType == .spider {
                Toggle("Interactive", isOn: bindChartBool(part.id, \.interactable, defaultValue: false))
            } else {
                propertyRow("X Label", binding: bindChartField(part.id, \.xAxisLabel))
                propertyRow("Y Label", binding: bindChartField(part.id, \.yAxisLabel))
            }

            if config.chartType == .spider {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spider Chart")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Each data point has its own min, current, and max value. Series color controls the layered polygon.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Toggle("Show Value Labels", isOn: bindChartBool(part.id, \.spiderShowValueLabels))
                    Toggle("Split Area", isOn: bindChartBool(part.id, \.spiderShowSplitArea))
                    Toggle("Circular Grid", isOn: bindChartBool(part.id, \.spiderCircularGrid))
                    HStack(spacing: 6) {
                        Text("Rings").font(.system(size: 10)).frame(width: 48, alignment: .leading)
                        Stepper(
                            value: bindChartInt(
                                part.id,
                                \.spiderRingCount,
                                min: ChartConfig.spiderMinimumRingCount,
                                max: ChartConfig.spiderMaximumRingCount
                            ),
                            in: ChartConfig.spiderMinimumRingCount...ChartConfig.spiderMaximumRingCount
                        ) {
                            Text("\(config.spiderRingCount)")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Decimals").font(.system(size: 10)).frame(width: 48, alignment: .leading)
                        Stepper(
                            value: bindChartInt(
                                part.id,
                                \.spiderDecimalPlaces,
                                min: ChartConfig.spiderMinimumDecimalPlaces,
                                max: ChartConfig.spiderMaximumDecimalPlaces
                            ),
                            in: ChartConfig.spiderMinimumDecimalPlaces...ChartConfig.spiderMaximumDecimalPlaces
                        ) {
                            Text("\(config.spiderDecimalPlaces)")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 24, alignment: .trailing)
                        }
                        Text("0 = integers")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("Opacity").font(.system(size: 10)).frame(width: 48, alignment: .leading)
                        TextField("0.24", value: bindChartDouble(part.id, \.spiderFillOpacity, min: 0, max: 1), format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 6) {
                        Text("Point").font(.system(size: 10)).frame(width: 48, alignment: .leading)
                        TextField("2", value: bindChartDouble(part.id, \.spiderPointRadius, min: 1, max: 12), format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    chartColorRow("Grid Color", partId: part.id, keyPath: \.spiderGridColor, fallback: "#C9CDD3")
                    chartColorRow("Axis Color", partId: part.id, keyPath: \.spiderAxisColor, fallback: "#AEB4BE")
                    chartColorRow("Label Color", partId: part.id, keyPath: \.spiderLabelColor, fallback: "#111827")
                }
                .padding(6)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(4)
            }

            Divider()

            // Series management
            ForEach(Array(config.series.enumerated()), id: \.element.id) { index, series in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Series \(index + 1)").font(.system(size: 10, weight: .bold))
                        Spacer()
                        ColorPicker("", selection: bindSeriesColor(part.id, seriesIndex: index))
                            .labelsHidden().frame(width: 20)
                            .accessibilityLabel("Series \(index + 1) color")
                        TextField("Hex", text: bindSeriesColorHex(part.id, seriesIndex: index))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10))
                            .frame(width: 78)
                            .accessibilityLabel("Series \(index + 1) hex value")
                        Button(action: { removeSeries(partId: part.id, index: index) }) {
                            Image(systemName: "minus.circle").foregroundColor(.red)
                        }.buttonStyle(.borderless)
                    }
                    TextField("Name", text: bindSeriesName(part.id, seriesIndex: index))
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))

                    // Data points. Spider charts use per-point min/value/max and series color only.
                    ForEach(Array(series.data.enumerated()), id: \.element.id) { di, _ in
                        if config.chartType == .spider {
                            spiderDataPointEditor(partId: part.id, seriesIndex: index, dataIndex: di)
                        } else {
                            HStack(spacing: 3) {
                                ColorPicker("", selection: bindDataPointColor(part.id, seriesIndex: index, dataIndex: di, seriesColor: series.color))
                                    .labelsHidden().frame(width: 18, height: 18)
                                    .accessibilityLabel("Data point color")
                                TextField("Hex", text: bindDataPointColorHex(part.id, seriesIndex: index, dataIndex: di, seriesColor: series.color))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10))
                                    .frame(width: 72)
                                    .accessibilityLabel("Data point hex value")
                                TextField("Label", text: bindDataLabel(part.id, seriesIndex: index, dataIndex: di))
                                    .textFieldStyle(.roundedBorder).font(.system(size: 10))
                                TextField("Value", value: bindDataValue(part.id, seriesIndex: index, dataIndex: di), format: .number)
                                    .textFieldStyle(.roundedBorder).font(.system(size: 10)).frame(width: 55)
                                Button(action: { removeDataPoint(partId: part.id, seriesIndex: index, dataIndex: di) }) {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }.buttonStyle(.borderless)
                            }
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

    private func spiderDataPointEditor(partId: UUID, seriesIndex: Int, dataIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Data Point \(dataIndex + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { removeDataPoint(partId: partId, seriesIndex: seriesIndex, dataIndex: dataIndex) }) {
                    Label("Remove Data Point", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove this data point")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Name")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("Name", text: bindDataLabel(partId, seriesIndex: seriesIndex, dataIndex: dataIndex))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .accessibilityLabel("Data point name")
            }

            HStack(alignment: .top, spacing: 6) {
                spiderNumberField(
                    "Value",
                    value: bindDataValue(partId, seriesIndex: seriesIndex, dataIndex: dataIndex),
                    help: "Current value. Interactive dragging moves this value between the minimum and maximum."
                )
                spiderNumberField(
                    "Min",
                    value: bindDataMinimumValue(partId, seriesIndex: seriesIndex, dataIndex: dataIndex),
                    help: "Lowest selectable value for this point."
                )
                spiderNumberField(
                    "Max",
                    value: bindDataMaximumValue(partId, seriesIndex: seriesIndex, dataIndex: dataIndex),
                    help: "Highest selectable value for this point."
                )
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.16), lineWidth: 1)
        )
        .help("Spider points store name, value, minimum, and maximum. Runtime dragging maps the point along its vector from minimum to maximum.")
    }

    private func spiderNumberField(_ title: String, value: Binding<Double>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .accessibilityLabel("Data point \(title.lowercased())")
                .help(help)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private func bindChartBool(
        _ id: UUID,
        _ keyPath: WritableKeyPath<ChartConfig, Bool>,
        defaultValue: Bool = true
    ) -> Binding<Bool> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? defaultValue
            },
            set: { newVal in modifyChartConfig(partId: id) { $0[keyPath: keyPath] = newVal } }
        )
    }

    private func bindChartDouble(
        _ id: UUID,
        _ keyPath: WritableKeyPath<ChartConfig, Double>,
        min: Double? = nil,
        max: Double? = nil
    ) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? 0
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    var value = newVal
                    if let min { value = Swift.max(value, min) }
                    if let max { value = Swift.min(value, max) }
                    config[keyPath: keyPath] = value
                }
            }
        )
    }

    private func bindChartInt(
        _ id: UUID,
        _ keyPath: WritableKeyPath<ChartConfig, Int>,
        min: Int,
        max: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? min
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    config[keyPath: keyPath] = Swift.min(Swift.max(newVal, min), max)
                }
            }
        )
    }

    private func bindChartColor(
        _ id: UUID,
        _ keyPath: WritableKeyPath<ChartConfig, String>,
        fallback: String
    ) -> Binding<Color> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let hex = ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? fallback
                return Color(hex: hex)
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    config[keyPath: keyPath] = ChartConfig.normalizedHex(newVal.toHex(), fallback: fallback)
                }
            }
        )
    }

    private func bindChartColorHex(
        _ id: UUID,
        _ keyPath: WritableKeyPath<ChartConfig, String>,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                return ChartConfig.fromJSON(json)?[keyPath: keyPath] ?? fallback
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    let current = config[keyPath: keyPath]
                    config[keyPath: keyPath] = ChartConfig.normalizedHex(newVal, fallback: current.isEmpty ? fallback : current)
                }
            }
        )
    }

    private func chartColorRow(
        _ title: String,
        partId: UUID,
        keyPath: WritableKeyPath<ChartConfig, String>,
        fallback: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10)).frame(width: 64, alignment: .leading)
            ColorPicker("", selection: bindChartColor(partId, keyPath, fallback: fallback))
                .labelsHidden()
                .frame(width: 22)
                .accessibilityLabel(title)
            TextField("Hex", text: bindChartColorHex(partId, keyPath, fallback: fallback))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
                .accessibilityLabel("\(title) hex value")
        }
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

    private func bindSeriesColorHex(_ id: UUID, seriesIndex: Int) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count else { return "#4A90D9" }
                return config.series[seriesIndex].color
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count else { return }
                    config.series[seriesIndex].color = ChartConfig.normalizedHex(
                        newVal,
                        fallback: config.series[seriesIndex].color.isEmpty ? "#4A90D9" : config.series[seriesIndex].color
                    )
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
                    if config.chartType == .spider {
                        let point = config.series[seriesIndex].data[dataIndex]
                        config.series[seriesIndex].data[dataIndex].value = config.clampedSpiderValue(newVal, for: point)
                    } else {
                        config.series[seriesIndex].data[dataIndex].value = newVal
                    }
                }
            }
        )
    }

    private func bindDataMinimumValue(_ id: UUID, seriesIndex: Int, dataIndex: Int) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return 0 }
                return config.series[seriesIndex].data[dataIndex].minimumValue
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
                    config.series[seriesIndex].data[dataIndex].minimumValue = newVal
                    config.series[seriesIndex].data[dataIndex].normalizeRangeAndValue(includeCurrentValue: false)
                }
            }
        )
    }

    private func bindDataMaximumValue(_ id: UUID, seriesIndex: Int, dataIndex: Int) -> Binding<Double> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return 100 }
                return config.series[seriesIndex].data[dataIndex].maximumValue
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count, dataIndex < config.series[seriesIndex].data.count else { return }
                    config.series[seriesIndex].data[dataIndex].maximumValue = newVal
                    config.series[seriesIndex].data[dataIndex].normalizeRangeAndValue(includeCurrentValue: false)
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
            let point = config.chartType == .spider
                ? ChartDataPoint(name: "Item \(count + 1)", value: 50, minimumValue: 0, maximumValue: 100)
                : ChartDataPoint(name: "Item \(count + 1)", value: 0)
            config.series[seriesIndex].data.append(point)
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

    private func bindDataPointColorHex(
        _ id: UUID,
        seriesIndex: Int,
        dataIndex: Int,
        seriesColor: String
    ) -> Binding<String> {
        Binding(
            get: {
                let json = document.document.parts.first(where: { $0.id == id })?.chartData ?? ""
                let config = ChartConfig.fromJSON(json) ?? ChartConfig()
                guard seriesIndex < config.series.count,
                      dataIndex < config.series[seriesIndex].data.count else {
                    return seriesColor
                }
                let pointColor = config.series[seriesIndex].data[dataIndex].color
                return pointColor.isEmpty ? seriesColor : pointColor
            },
            set: { newVal in
                modifyChartConfig(partId: id) { config in
                    guard seriesIndex < config.series.count,
                          dataIndex < config.series[seriesIndex].data.count else { return }
                    let fallback = config.series[seriesIndex].data[dataIndex].color.isEmpty
                        ? seriesColor
                        : config.series[seriesIndex].data[dataIndex].color
                    config.series[seriesIndex].data[dataIndex].color = ChartConfig.normalizedHex(newVal, fallback: fallback)
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
            sectionHeading("CONSTRAINTS")
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

    private func bindMusicInstrumentName(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                let rawValue = document.document.parts.first(where: { $0.id == id })?.musicInstrumentName ?? ""
                return MusicInstrumentCatalog.resolve(rawValue).name
            },
            set: { newValue in
                document.document.updatePart(id: id) {
                    $0.musicInstrumentName = MusicInstrumentCatalog.resolve(newValue).name
                }
            }
        )
    }

    private func bindMusicTempoInt(_ id: UUID) -> Binding<Int> {
        Binding(
            get: {
                let value = document.document.parts.first(where: { $0.id == id })?.musicTempo ?? Double(MusicTempo.defaultBPM)
                return MusicTempo.clamp(value)
            },
            set: { newValue in
                document.document.updatePart(id: id) {
                    $0.musicTempo = Double(MusicTempo.clamp(newValue))
                }
            }
        )
    }

    private func bindMusicTempoDouble(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                let value = document.document.parts.first(where: { $0.id == id })?.musicTempo ?? Double(MusicTempo.defaultBPM)
                return Double(MusicTempo.clamp(value))
            },
            set: { newValue in
                document.document.updatePart(id: id) {
                    $0.musicTempo = Double(MusicTempo.clamp(newValue))
                }
            }
        )
    }

    private func bindMusicKeyCount(_ id: UUID) -> Binding<Int> {
        Binding(
            get: {
                let value = document.document.parts.first(where: { $0.id == id })?.musicKeyCount ?? MusicKeyboardKeyCount.defaultValue
                return MusicKeyboardKeyCount.normalize(value)
            },
            set: { newValue in
                document.document.updatePart(id: id) {
                    $0.musicKeyCount = MusicKeyboardKeyCount.normalize(newValue)
                }
            }
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

    // MARK: - Multi-selection helpers
    //
    // Provide get/set across the whole selection so the multi-selection
    // panel can edit a property uniformly. When the selected parts have
    // different values for a property, the binding's `get` returns a
    // sentinel ("" or `false`) so the UI can render an empty field
    // (interpreted as "Multiple"); typing into the field applies the
    // new value to EVERY selected part.

    /// The value shared by every selected part for `keyPath`, or
    /// `nil` if the values differ. Empty selection yields `nil`.
    /// Delegates to `MultiSelectionEditing.commonValue` so the
    /// canonical implementation lives in one testable place.
    private func commonValue<T: Equatable>(_ keyPath: KeyPath<Part, T>) -> T? {
        let parts = document.document.parts.filter { selectedPartIds.contains($0.id) }
        return MultiSelectionEditing.commonValue(in: parts, for: keyPath)
    }

    /// Apply the same value to every part in the current selection.
    /// Delegates to `MultiSelectionEditing.applyValue`.
    private func applyToSelected<T>(_ keyPath: WritableKeyPath<Part, T>, _ value: T) {
        MultiSelectionEditing.applyValue(value, to: keyPath, in: &document.document, for: selectedPartIds)
    }

    /// String binding across the selection. Differing values surface
    /// as an empty string so the placeholder ("Multiple") shows;
    /// typing replaces every part's value.
    private func bindMultiString(_ keyPath: WritableKeyPath<Part, String>) -> Binding<String> {
        Binding(
            get: { commonValue(keyPath) ?? "" },
            set: { applyToSelected(keyPath, $0) }
        )
    }

    /// Double binding that ROUND-TRIPS through String so SwiftUI's
    /// `TextField` can show an empty placeholder when values differ
    /// across the selection. `TextField(value:format:)` with a
    /// non-optional `Binding<Double>` would force "0" as the empty
    /// case — visually indistinguishable from a real zero. The
    /// String form lets us keep the field actually empty in the
    /// "differing" case so the placeholder reads as intended.
    private func bindMultiDoubleString(_ keyPath: WritableKeyPath<Part, Double>) -> Binding<String> {
        Binding(
            get: {
                guard let v = commonValue(keyPath) else { return "" }
                return v == v.rounded() ? String(Int(v)) : String(v)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let parsed = Double(trimmed) else { return }
                applyToSelected(keyPath, parsed)
            }
        )
    }

    /// Bool binding across the selection. Differing values surface
    /// as `false` (the toggle's "off" state); flipping the toggle
    /// applies the new value to every selected part.
    private func bindMultiBool(_ keyPath: WritableKeyPath<Part, Bool>) -> Binding<Bool> {
        Binding(
            get: { commonValue(keyPath) ?? false },
            set: { applyToSelected(keyPath, $0) }
        )
    }

    /// A 60pt-wide TextField for a numeric property across the
    /// selection. The binding's get returns "" when values differ
    /// so the placeholder reads "Multiple"; typing applies the
    /// parsed value to every selected part. Invalid input is
    /// silently rejected (the field reverts on focus loss).
    private func multiNumberField(_ label: String, keyPath: WritableKeyPath<Part, Double>) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("Multiple", text: bindMultiDoubleString(keyPath))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 60)
        }
    }

    /// A wider TextField for non-numeric properties (font name,
    /// hex color string). Same placeholder semantics as
    /// `multiNumberField` — empty value means values differ across
    /// the selection.
    private func multiStringField(_ label: String, keyPath: WritableKeyPath<Part, String>) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).frame(width: 80, alignment: .trailing)
                .foregroundColor(.secondary)
            TextField("Multiple", text: bindMultiString(keyPath))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }

    // MARK: - Multi-selection color

    /// Color binding across the selection. Reading returns the shared
    /// color (parsed from the common hex) or `Color.clear` when the
    /// selected parts have different colors — the swatch will appear
    /// dim/transparent so the user can tell the field is in the
    /// "Multiple" state. Picking a color encodes it as `#RRGGBB`
    /// (or `#RRGGBBAA` when supportsOpacity is on) and applies that
    /// hex to every selected part.
    private func bindMultiColor(_ keyPath: WritableKeyPath<Part, String>) -> Binding<Color> {
        Binding(
            get: {
                if let hex = commonValue(keyPath) {
                    return Color(hex: hex)
                }
                return Color.clear   // visual cue: differing values → transparent swatch
            },
            set: { newValue in
                applyToSelected(keyPath, newValue.toHex())
            }
        )
    }

    /// Multi-select equivalent of `colorPropertyRow`. Renders a
    /// ColorPicker swatch + a hex text field side by side. When the
    /// selection has differing values the swatch is transparent (a
    /// macOS visual cue for "no value") and the hex field shows the
    /// "Multiple" placeholder. Picking a color in the swatch
    /// IMMEDIATELY synchronizes every selected part to that color
    /// (resolves the divergence). Typing in the hex field has the
    /// same effect.
    @ViewBuilder
    private func multiColorRow(
        label: String,
        keyPath: WritableKeyPath<Part, String>,
        supportsOpacity: Bool = false
    ) -> some View {
        HStack {
            ColorPicker("", selection: bindMultiColor(keyPath), supportsOpacity: supportsOpacity)
                .labelsHidden()
                .accessibilityLabel(label)
            Text(label).font(.system(size: 11))
            Spacer()
            TextField("Multiple", text: bindMultiString(keyPath))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 90)
                .accessibilityLabel(label)
        }
    }

    // MARK: - Multi-selection text style toggles

    /// One-flag toggle button (Bold / Italic / Underline /
    /// Strikethrough) across the multi-selection. Visual states:
    ///   • All selected parts have the flag set → "active" (accent
    ///     background, bold weight).
    ///   • Mixed or none → "inactive" (plain weight, no background).
    /// Tap behavior:
    ///   • From "active": flip OFF for every selected part.
    ///   • From "inactive" (or mixed): flip ON for every selected
    ///     part.
    /// This matches the macOS convention used by
    /// `Toolbar > Format > Bold/Italic` in TextEdit and Pages: a
    /// mixed-state button resolves to ON in one click rather than
    /// cycling through three states.
    @ViewBuilder
    fileprivate func multiStyleToggle(flag: TextStyleFlag, systemImage: String) -> some View {
        let parts = document.document.parts.filter { selectedPartIds.contains($0.id) }
        let allActive = !parts.isEmpty && parts.allSatisfy { isStyleFlagSet(part: $0, flag: flag) }
        Button(action: {
            let turnOn = !allActive
            for p in parts {
                document.document.updatePart(id: p.id) { part in
                    var flags = TextStyleFlags(string: part.textStyle)
                    switch flag {
                    case .bold:          flags.bold = turnOn
                    case .italic:        flags.italic = turnOn
                    case .underline:     flags.underline = turnOn
                    case .strikethrough: flags.strikethrough = turnOn
                    }
                    part.textStyle = flags.rawString
                }
            }
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: allActive ? .bold : .regular))
                .frame(width: 26, height: 22)
                .background(allActive ? Color.accentColor.opacity(0.25) : Color.clear)
                .foregroundColor(allActive ? .accentColor : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Multi-selection text alignment

    /// `Binding<TextAlignment>` across the selection. When the parts
    /// disagree, returns `.center` (the visual default) so the
    /// segmented Picker reads as "centered" — the user re-selects
    /// the alignment they actually want and every part adopts it.
    /// SwiftUI's `Picker` doesn't have a clean "Multiple" placeholder
    /// state for an enum value, so the convention here is to fall
    /// back to a sensible default and rely on the user understanding
    /// "every selected part now matches what I just picked."
    private func bindMultiTextAlign() -> Binding<HypeCore.TextAlignment> {
        Binding(
            get: { commonValue(\.textAlign) ?? .center },
            set: { applyToSelected(\.textAlign, $0) }
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

    /// Shared color-property row. Renders an interactive ColorPicker
    /// + an editable hex text field side by side, both bound to the
    /// same `Part` keypath. Picking a color writes the hex value
    /// back; typing a hex value updates the picker's swatch on the
    /// next render. The optional `hint` line below renders in the
    /// secondary text style.
    ///
    /// Use this anywhere a part has a stored hex color so authors
    /// can choose either a visual swatch (most common) or a precise
    /// hex value (scriptable / shareable). One pattern, all parts.
    @ViewBuilder
    private func colorPropertyRow(
        label: String,
        partId: UUID,
        keyPath: WritableKeyPath<Part, String>,
        hint: String? = nil,
        supportsOpacity: Bool = false
    ) -> some View {
        HStack {
            ColorPicker("", selection: bindPartColor(partId, keyPath), supportsOpacity: supportsOpacity)
                .labelsHidden()
                .accessibilityLabel(label)
            Text(label).font(.system(size: 11))
            Spacer()
            TextField("hex", text: bindPartString(partId, keyPath))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 90)
                .accessibilityLabel(label)
        }
        if let hint = hint {
            Text(hint).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    // MARK: - Helper views

    /// Trailing-label text row for a `String` property. `placeholder`
    /// carries input-format hints ("yyyy-MM-dd") that used to live in
    /// the row label itself (design-mock §1.6 — hints move to the
    /// field, never the label). `unit` renders a secondary trailing
    /// `Text` after the field — the canonical way units are shown
    /// (the Tempo/BPM idiom, §1.6), never a label parenthetical.
    /// `accessibilityLabel` is wired to the row's canonical `label`
    /// so a `TextField` with a detached `Text` sibling still reads
    /// correctly to VoiceOver (§6).
    private func propertyRow(
        _ label: String,
        binding: Binding<String>,
        placeholder: String = "",
        unit: String? = nil
    ) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .trailing).font(.system(size: 11))
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .accessibilityLabel(label)
            if let unit {
                Text(unit).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .trailing).font(.system(size: 11)).foregroundColor(.secondary)
            Text(value).font(.system(size: 11))
        }
    }

    /// Compact numeric row. `unit` renders a secondary trailing
    /// `Text` after the field — the Tempo/BPM idiom (design-mock
    /// §1.6) — so a rotation/degrees or play-rate row never has to
    /// stuff the unit into the label itself.
    private func numberField(_ label: String, binding: Binding<Double>, unit: String? = nil) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("", value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 60)
                .accessibilityLabel(label)
            if let unit {
                Text(unit).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }
}

/// Identifiable wrapper around a `UUID` used by `PropertyInspector` to
/// present `Generate3DSheet` via `.sheet(item:)`. Carrying the part ID in an
/// `Identifiable` struct lets SwiftUI derive the presentation trigger from
/// optionality (`nil` = no sheet, non-nil = present for that part).
private struct Generate3DSheetPartTarget: Identifiable {
    let partId: UUID
    var id: UUID { partId }
}

/// Local scope tag used by `themePickerSection` and `cascadeNote` to
/// pick which level of the cascade the trailing label should describe.
/// Stack-scope is omitted because it never inherits — its picker has
/// no Inherit entry and shows no cascade note.
private enum ThemePickerScope {
    case card(UUID)
    case background(UUID)
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

/// Resolve the script editor target without changing script ownership.
/// Sprite areas have two valid script slots: the container part script
/// and the active scene script. Runtime errors that originate in the
/// container must open the container script; explicit scene edit buttons
/// pass `.scene(...)` when the scene script is intended.
@MainActor
private func effectiveScriptTarget(
    in document: HypeDocument,
    target: ScriptTarget?,
    partId: UUID?
) -> ScriptTarget? {
    scriptEditorResolvedTarget(in: document, target: target, partId: partId)
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
                let typeName = part.partType.displayName
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
        let typeName = part.partType.displayName
        let name = part.name.isEmpty ? "Untitled" : part.name
        windowTitle = "\(name) (\(typeName)) — Script Editor"
    } else {
        windowTitle = "Script Editor"
    }
    window.title = windowTitle
    window.minSize = NSSize(width: 450, height: 350)
    window.isReleasedWhenClosed = false
    // Previously: `window.appearance = NSAppearance(named: .aqua)`
    // — a legacy force-light from when the script editor was a
    // monochrome view. Now that themes drive the background, that
    // override actively fights system Dark Mode users. Letting the
    // appearance inherit from the system + theme cascade is the
    // right behavior on macOS 11+.

    // Build the editor view; theme + system appearance now cascade naturally.
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
    // Previously forced .light at three levels (environment +
    // colorScheme + preferredColorScheme) plus an aqua appearance
    // on the hosting view. The Script Editor's internal chrome
    // (toolbar, command palette) already adapts to the active
    // theme via `hypeTheme.toolbarColorScheme` /
    // `hypeTheme.chromeColorScheme` (ScriptEditor.swift:346, 423,
    // 435), so the global force-light here was both redundant and
    // user-hostile to Dark Mode users.

    let hostingView = NSHostingView(rootView: editorView)
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

// MARK: - Resizable Asset Repository Window

/// Keeps a strong reference to open asset repository windows. As
/// with `activeScriptWindows` above, the window is detached from
/// SwiftUI's view graph so it needs its own retain cycle manager
/// or macOS will deallocate it the moment the opener's stack frame
/// returns.
@MainActor
private var activeAssetRepositoryWindows: [NSWindow] = []

/// Opens the asset repository browser in a movable, resizable NSWindow
/// with light appearance. Replaces the previous `.sheet`-based
/// presentation, which used a fixed 600×400 frame and couldn't be
/// resized — users asked to see more thumbnails at once and to
/// keep the browser open while working on a card. A detached
/// window supports both.
///
/// The window remembers its size across sessions via UserDefaults
/// under the `assetRepositoryWidth` / `assetRepositoryHeight`
/// keys, mirroring how `openScriptEditorWindow` persists its own
/// frame.
@MainActor
func openAssetRepositoryWindow(
    document: Binding<HypeDocumentWrapper>,
    initialAssetId: UUID? = nil
) {
    // Reuse an existing window instead of stacking duplicates if
    // the user clicks the toolbar button twice. The browser is
    // effectively a singleton from the user's perspective.
    if let existing = activeAssetRepositoryWindows.first {
        existing.makeKeyAndOrderFront(nil)
        if let initialAssetId {
            NotificationCenter.default.post(
                name: .selectAssetRepositoryAsset,
                object: nil,
                userInfo: ["assetId": initialAssetId]
            )
        }
        return
    }

    let savedWidth = UserDefaults.standard.double(forKey: "assetRepositoryWidth")
    let savedHeight = UserDefaults.standard.double(forKey: "assetRepositoryHeight")
    let width = savedWidth > 0 ? savedWidth : 780
    let height = savedHeight > 0 ? savedHeight : 520

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Asset Repository"
    window.minSize = NSSize(width: 560, height: 360)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)

    let closeAction: () -> Void = { [weak window] in window?.close() }
    let browserView = AssetRepositoryView(document: document, onDone: closeAction)
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
                name: .selectAssetRepositoryAsset,
                object: nil,
                userInfo: ["assetId": initialAssetId]
            )
        }
    }

    activeAssetRepositoryWindows.append(window)

    NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
            UserDefaults.standard.set(window.frame.width, forKey: "assetRepositoryWidth")
            UserDefaults.standard.set(window.frame.height, forKey: "assetRepositoryHeight")
        }
    }
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak window] _ in
        MainActor.assumeIsolated {
            if let w = window { activeAssetRepositoryWindows.removeAll { $0 === w } }
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
