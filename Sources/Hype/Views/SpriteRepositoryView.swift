import SwiftUI
import HypeCore
import UniformTypeIdentifiers

/// A SwiftUI view for browsing, importing, and managing sprite assets in the repository.
///
/// Presentation is handled by the caller. The legacy pattern
/// (`.sheet(isPresented:) { SpriteRepositoryView(document:) }`)
/// stays supported — dismiss is inferred from the environment when
/// `onDone` is nil. When the view is hosted in a standalone NSWindow
/// via `openSpriteRepositoryWindow`, the caller passes an `onDone`
/// closure that closes the window instead, since `@Environment(\.dismiss)`
/// doesn't reach NSHostingView contexts.
struct SpriteRepositoryView: View {
    @Binding var document: HypeDocumentWrapper
    /// Optional close callback. When non-nil, the Done button calls
    /// this instead of the SwiftUI `dismiss` environment action. Used
    /// by `openSpriteRepositoryWindow` to close the detached window.
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAssetIds: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var editingNameId: UUID? = nil
    @State private var editingName: String = ""
    /// Local copy of the selected asset's name for the TextField.
    /// Synced from the document when selection changes, written
    /// back on commit (Return key or focus loss). Using a @State
    /// string instead of a live Binding prevents the "name reverts"
    /// bug where each keystroke mutated the document, triggered a
    /// view rebuild, and the TextField was reconstructed with a
    /// stale value before the mutation propagated.
    @State private var assetNameDraft: String = ""
    @State private var sliceCols: Int = 4
    @State private var sliceRows: Int = 1
    @State private var clipFps: Double = 12

    // MARK: - Tileset classification state
    // Local state for the classify panel. Seeded from the selected
    // asset when focus changes, so the user can tweak values before
    // committing them with the "Classify as tileset" button.
    @State private var tilesetW: Int = 32
    @State private var tilesetH: Int = 32
    @State private var tilesetCols: Int = 0
    @State private var tilesetRows: Int = 0
    @State private var tilesetEditingAssetId: UUID? = nil

    private var filteredAssets: [SpriteAsset] {
        if searchText.isEmpty { return document.document.spriteRepository.assets }
        return document.document.spriteRepository.assets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Dispatch the close action: prefer the explicit `onDone`
    /// callback (set by `openSpriteRepositoryWindow`) and fall back
    /// to SwiftUI's environment dismiss for legacy sheet-based
    /// presentations.
    private func dismissAction() {
        if let onDone = onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    var body: some View {
        HSplitView {
            // Left: asset grid
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text("Sprite Repository").font(.headline)
                    Spacer()
                    Button(action: importAsset) {
                        Image(systemName: "plus")
                    }
                    .help("Import Assets")

                    Button(action: importTilesetAsset) {
                        Image(systemName: "square.grid.3x3")
                    }
                    .help("Import Tileset Image")

                    if !selectedAssetIds.isEmpty {
                        Button(action: duplicateSelected) {
                            Image(systemName: "plus.square.on.square")
                        }
                        .help("Duplicate Selected")

                        Button(action: deleteSelected) {
                            Image(systemName: "trash")
                        }
                        .help("Delete Selected (\(selectedAssetIds.count))")
                    }

                    Button(action: { dismissAction() }) {
                        Text("Done")
                    }
                    .keyboardShortcut(.return)
                }
                .padding(8)

                // Search
                TextField("Search assets...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 8)

                // Grid with multi-select
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                        ForEach(filteredAssets) { asset in
                            assetThumbnail(asset)
                                .onTapGesture {
                                    if NSEvent.modifierFlags.contains(.command) {
                                        // Cmd+click: toggle in multi-selection
                                        if selectedAssetIds.contains(asset.id) {
                                            selectedAssetIds.remove(asset.id)
                                        } else {
                                            selectedAssetIds.insert(asset.id)
                                        }
                                    } else {
                                        // Plain click: single select
                                        selectedAssetIds = [asset.id]
                                    }
                                }
                        }
                    }
                    .padding(8)
                }
                .onKeyPress(.delete) { deleteSelected(); return .handled }

                // Status bar
                HStack {
                    Text("\(document.document.spriteRepository.assets.count) assets")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if selectedAssetIds.count > 1 {
                        Text("(\(selectedAssetIds.count) selected)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(minWidth: 250)

            // Right: detail panel
            if selectedAssetIds.count == 1,
               let assetId = selectedAssetIds.first,
               let asset = document.document.spriteRepository.asset(byId: assetId) {
                assetDetailPanel(asset)
                    .frame(minWidth: 220)
            } else if selectedAssetIds.count > 1 {
                multiSelectionPanel
                    .frame(minWidth: 220)
            } else {
                VStack {
                    Spacer()
                    Text("Select an asset").foregroundColor(.secondary)
                    Spacer()
                }
                .frame(minWidth: 220)
            }
        }
        .frame(minWidth: 550, minHeight: 350)
        .onChange(of: selectedAssetIds) { _, newValue in
            // Whenever focus moves to a single asset, reseed both
            // the name draft and the tileset editor state from the
            // selected asset's current values.
            if newValue.count == 1,
               let id = newValue.first,
               let asset = document.document.spriteRepository.asset(byId: id) {
                assetNameDraft = asset.name
                seedTilesetState(from: asset)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectSpriteRepositoryAsset)) { notification in
            guard let assetId = notification.userInfo?["assetId"] as? UUID else { return }
            selectedAssetIds = [assetId]
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func assetThumbnail(_ asset: SpriteAsset) -> some View {
        let isSelected = selectedAssetIds.contains(asset.id)
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if asset.kind == .audioClip {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundColor(.purple)
                        .frame(width: 64, height: 64)
                } else if let img = NSImage(data: asset.data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .frame(width: 64, height: 64)
                }
                // Tileset badge: small grid-shaped marker overlaid
                // on the top-right corner so tileset assets are
                // instantly distinguishable from plain images at
                // grid-browsing time. Only drawn on classified
                // tilesets — assets flagged by filename without
                // metadata show no badge until classification is
                // committed.
                if asset.isTileSet {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Circle().fill(Color.orange))
                        .offset(x: -2, y: 2)
                        .help("Tileset \(asset.tileColumns)\u{00d7}\(asset.tileRows) of \(asset.tileWidth)\u{00d7}\(asset.tileHeight)px tiles")
                }
            }
            Text(asset.name)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .padding(4)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .cornerRadius(6)
    }

    // MARK: - Single Asset Detail Panel

    @ViewBuilder
    private func assetDetailPanel(_ asset: SpriteAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Preview
                if asset.kind == .audioClip {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                } else if let img = NSImage(data: asset.data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }

                // Editable name — uses a local @State draft that
                // is synced FROM the document when the selection
                // changes and written BACK on commit (Return key
                // or focus loss). This avoids the "name reverts"
                // bug where a live Binding triggered a document
                // mutation on every keystroke → SwiftUI rebuilt
                // the view → the TextField was reconstructed
                // before the mutation propagated through the
                // NSHostingView binding chain.
                HStack {
                    Text("Name").font(.system(size: 11)).foregroundColor(.secondary).frame(width: 40, alignment: .trailing)
                    TextField("Asset name", text: $assetNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            commitAssetName(assetId: asset.id)
                        }
                        .onChange(of: assetNameDraft) { _, newVal in
                            // Write through on every change so the
                            // thumbnail label updates in real time,
                            // but via a debounced path that doesn't
                            // fight the TextField's own state.
                            document.document.spriteRepository.updateAsset(id: asset.id) { $0.name = newVal }
                        }
                }

                // Metadata
                if asset.width > 0 {
                    Text("\(asset.width) \u{00d7} \(asset.height) px").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Text(asset.kind.rawValue).font(.system(size: 11)).foregroundColor(.secondary)
                Text("\(asset.data.count / 1024) KB").font(.system(size: 11)).foregroundColor(.secondary)

                if !asset.tags.isEmpty {
                    Text("Tags: \(asset.tags.joined(separator: ", "))").font(.system(size: 11))
                }

                if !asset.slices.isEmpty {
                    Divider()
                    Text("Slices (\(asset.slices.count))").font(.system(size: 10, weight: .bold))
                    ForEach(asset.slices) { slice in
                        Text("  \(slice.name): \(slice.rect.x),\(slice.rect.y) \(slice.rect.width)\u{00d7}\(slice.rect.height)")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }

                // Slicing controls (for image/sprite sheet assets)
                if asset.kind == .imageTexture || asset.kind == .spriteSheet || asset.kind == .tileSet {
                    Divider()
                    Text("SLICING").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)

                    HStack {
                        Text("Cols").font(.system(size: 10))
                        TextField("", value: $sliceCols, format: .number).frame(width: 40).textFieldStyle(.roundedBorder)
                        Text("Rows").font(.system(size: 10))
                        TextField("", value: $sliceRows, format: .number).frame(width: 40).textFieldStyle(.roundedBorder)
                        Button("Slice") { sliceAsset(asset, columns: sliceCols, rows: sliceRows) }
                            .font(.system(size: 10))
                    }

                    if !asset.slices.isEmpty {
                        HStack {
                            Text("FPS").font(.system(size: 10))
                            TextField("", value: $clipFps, format: .number).frame(width: 40).textFieldStyle(.roundedBorder)
                            Button("Create Animation Clip") { createClipFromSlices(asset) }
                                .font(.system(size: 10))
                        }
                    }
                }

                // Tileset classification controls — only shown on
                // image-like assets. Lets the user mark a sprite
                // sheet as a tileset and declare the tile grid
                // dimensions so `createTileMap` / `create_tilemap`
                // can read them without the user having to pass
                // tile_size, columns, rows every time.
                if asset.kind == .imageTexture || asset.kind == .spriteSheet || asset.kind == .tileSet {
                    Divider()
                    HStack {
                        Text("TILESET").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        if asset.isTileSet {
                            Text("✓ classified").font(.system(size: 10)).foregroundColor(.green)
                        } else if asset.kind == .tileSet {
                            Text("⚠ needs classification").font(.system(size: 10)).foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    // Call-to-action when the asset is flagged as a
                    // tileset but doesn't have tile dimensions yet.
                    // This is the state right after importing via
                    // the "Import Tileset" button or a filename-
                    // hinted generic import. The auto-detect
                    // heuristic has already seeded the fields below,
                    // so the user just needs to review and click
                    // "Classify as Tileset".
                    if asset.kind == .tileSet && !asset.isTileSet {
                        Text("Review the tile dimensions below and click Classify to finish setup.")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                            .padding(.vertical, 2)
                    }

                    HStack {
                        Text("Tile W").font(.system(size: 10))
                        TextField("", value: $tilesetW, format: .number).frame(width: 44).textFieldStyle(.roundedBorder)
                        Text("\u{00d7}").font(.system(size: 10))
                        TextField("", value: $tilesetH, format: .number).frame(width: 44).textFieldStyle(.roundedBorder)
                        Text("px").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Grid").font(.system(size: 10))
                        TextField("", value: $tilesetCols, format: .number).frame(width: 44).textFieldStyle(.roundedBorder)
                        Text("\u{00d7}").font(.system(size: 10))
                        TextField("", value: $tilesetRows, format: .number).frame(width: 44).textFieldStyle(.roundedBorder)
                        Text("tiles").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Auto-detect") {
                            autoDetectTileset(asset)
                        }
                        .font(.system(size: 10))
                        .help("Derive columns and rows from image dimensions and the current tile width/height")

                        Button("Classify as Tileset") {
                            classifyAsTileset(asset)
                        }
                        .font(.system(size: 10))
                        .help("Mark this asset as a tileset with the given tile dimensions")
                    }
                    if asset.isTileSet {
                        Button("Unclassify (revert to image)") {
                            unclassifyTileset(asset)
                        }
                        .font(.system(size: 10))
                    }
                }

                // Animation clips
                if !asset.animationClips.isEmpty {
                    Divider()
                    Text("Animation Clips (\(asset.animationClips.count))").font(.system(size: 10, weight: .bold))
                    ForEach(asset.animationClips) { clip in
                        Text("  \(clip.name): \(clip.frameSliceIds.count) frames @ \(Int(clip.fps)) fps")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }

                // SOURCE section — shown only for web-asset-search imports
                if let prov = asset.provenance, prov.origin == .webSearch {
                    Divider()
                    Text("SOURCE").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)

                    if !prov.attribution.creator.isEmpty {
                        Text("By: \(prov.attribution.creator)")
                            .font(.system(size: 11))
                    }

                    if !prov.attribution.providerName.isEmpty {
                        Text("Via: \(prov.attribution.providerName)")
                            .font(.system(size: 11))
                    }

                    if !prov.license.name.isEmpty {
                        Text("License: \(prov.license.identifier.uppercased())")
                            .font(.system(size: 11))
                    }

                    if !prov.attribution.sourceURL.isEmpty, let sourceURL = URL(string: prov.attribution.sourceURL) {
                        Link(destination: sourceURL) {
                            Text("Open Source Page")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        }
                    }

                    Button("Copy Attribution") {
                        let creator = prov.attribution.creator.isEmpty ? "Unknown" : prov.attribution.creator
                        let provider = prov.attribution.providerName.isEmpty ? "Unknown Provider" : prov.attribution.providerName
                        let licenseId = prov.license.identifier.isEmpty ? "Unknown License" : prov.license.identifier.uppercased()
                        let sourceURL = prov.attribution.sourceURL.isEmpty ? "n/a" : prov.attribution.sourceURL
                        let text = "\"\(asset.name)\" \u{2014} by \(creator) on \(provider) \u{2014} \(licenseId) \u{2014} \(sourceURL)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .font(.system(size: 10))
                }

                // Asset usage tracking
                let usages = findAssetUsages(assetId: asset.id)
                if !usages.isEmpty {
                    Divider()
                    Text("USAGE (\(usages.count))").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                    ForEach(usages) { usage in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\"\(usage.partName)\" → \(usage.sceneName) → \(usage.nodeType.rawValue) \"\(usage.nodeName)\"")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Button("Focus") {
                                    NotificationCenter.default.post(
                                        name: .revealSpriteNode,
                                        object: nil,
                                        userInfo: [
                                            "partId": usage.partId,
                                            "sceneId": usage.sceneId,
                                            "nodeId": usage.nodeId
                                        ]
                                    )
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))

                                Button("Node Script") {
                                    openScriptEditorWindow(
                                        document: $document,
                                        target: .node(partId: usage.partId, nodeId: usage.nodeId)
                                    )
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))

                                Button("Scene Script") {
                                    openScriptEditorWindow(
                                        document: $document,
                                        target: .scene(partId: usage.partId, sceneId: usage.sceneId)
                                    )
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                            }
                        }
                    }
                } else {
                    Text("Not used in any scene").font(.system(size: 10)).foregroundColor(.secondary)
                }

                Divider()

                // Actions
                HStack(spacing: 12) {
                    Button(action: { duplicateAsset(asset) }) {
                        HStack { Image(systemName: "plus.square.on.square"); Text("Duplicate") }
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive, action: {
                        document.document.spriteRepository.removeAsset(id: asset.id)
                        selectedAssetIds.remove(asset.id)
                        // Regenerate attribution block whenever a web-sourced asset is removed.
                        let webAssets = document.document.spriteRepository.assets.filter {
                            $0.provenance?.origin == .webSearch
                        }
                        document.document.stack.script = StackScriptAttributionSync.sync(
                            stackScript: document.document.stack.script,
                            webAssets: webAssets
                        )
                    }) {
                        HStack { Image(systemName: "trash"); Text("Delete") }
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    // MARK: - Multi-Selection Panel

    private var multiSelectionPanel: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("\(selectedAssetIds.count) assets selected")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: duplicateSelected) {
                    HStack { Image(systemName: "plus.square.on.square"); Text("Duplicate All") }
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: deleteSelected) {
                    HStack { Image(systemName: "trash"); Text("Delete All") }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            Spacer()
        }
    }

    // MARK: - Bindings

    /// Write the current name draft back to the document.
    /// Called on Return key press.
    private func commitAssetName(assetId: UUID) {
        let trimmed = assetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.document.spriteRepository.updateAsset(id: assetId) { $0.name = trimmed }
    }

    // MARK: - Actions

    private func deleteSelected() {
        for id in selectedAssetIds {
            document.document.spriteRepository.removeAsset(id: id)
        }
        selectedAssetIds.removeAll()
    }

    private func duplicateSelected() {
        let ids = selectedAssetIds
        for id in ids {
            if let asset = document.document.spriteRepository.asset(byId: id) {
                duplicateAsset(asset)
            }
        }
    }

    private func duplicateAsset(_ asset: SpriteAsset) {
        var copy = asset
        copy.id = UUID()
        copy.name = asset.name + " copy"
        // Ensure unique name
        let existingNames = Set(document.document.spriteRepository.assets.map(\.name))
        var name = copy.name
        var counter = 2
        while existingNames.contains(name) {
            name = "\(asset.name) copy \(counter)"
            counter += 1
        }
        copy.name = name
        document.document.spriteRepository.addAsset(copy)
    }

    // MARK: - Slicing

    /// Slice an asset into a grid of columns x rows, generating AssetSlice entries.
    private func sliceAsset(_ asset: SpriteAsset, columns: Int, rows: Int) {
        guard columns > 0, rows > 0, asset.width > 0, asset.height > 0 else { return }
        let frameW = asset.width / columns
        let frameH = asset.height / rows
        document.document.spriteRepository.updateAsset(id: asset.id) { asset in
            asset.slices.removeAll()
            var idx = 0
            for r in 0..<rows {
                for c in 0..<columns {
                    idx += 1
                    asset.slices.append(AssetSlice(
                        name: "frame_\(idx)",
                        rect: SliceRect(x: c * frameW, y: r * frameH, width: frameW, height: frameH)
                    ))
                }
            }
            asset.kind = .spriteSheet
        }
    }

    /// Create an AnimationClip from all slices of the given asset.
    private func createClipFromSlices(_ asset: SpriteAsset) {
        let sliceIds = asset.slices.map(\.id)
        let clip = AnimationClip(name: "\(asset.name)_anim", frameSliceIds: sliceIds, fps: clipFps, loops: true)
        document.document.spriteRepository.updateAsset(id: asset.id) { $0.animationClips.append(clip) }
    }

    // MARK: - Tileset classification

    /// Seed the tileset editor state (tileW/H/Cols/Rows) from the
    /// given asset. Called whenever the selection changes so the
    /// form fields always match the currently focused asset instead
    /// of lingering with stale values from the previous one.
    ///
    /// For unclassified images we guess: if the asset's width is
    /// already a nice multiple of 16/24/32/48/64 we pick that as a
    /// starting tile size. Otherwise we keep the user's last
    /// values. Any guess is non-binding — the user still has to
    /// click "Classify as Tileset" to commit.
    private func seedTilesetState(from asset: SpriteAsset) {
        tilesetEditingAssetId = asset.id
        if asset.isTileSet {
            tilesetW = asset.tileWidth
            tilesetH = asset.tileHeight
            tilesetCols = asset.tileColumns
            tilesetRows = asset.tileRows
            return
        }
        // Heuristic: try common tile sizes against the asset's
        // width. The smallest clean divisor >= 8 wins.
        let candidates = [8, 16, 24, 32, 48, 64]
        if asset.width > 0 {
            for c in candidates where c <= asset.width && asset.width % c == 0 {
                tilesetW = c
                tilesetH = c
                tilesetCols = asset.width / c
                tilesetRows = asset.height / c
                return
            }
        }
        // Fall back to whatever the user had set.
        if tilesetW == 0 { tilesetW = 32 }
        if tilesetH == 0 { tilesetH = 32 }
        if tilesetCols == 0, asset.width > 0 {
            tilesetCols = max(1, asset.width / max(1, tilesetW))
        }
        if tilesetRows == 0, asset.height > 0 {
            tilesetRows = max(1, asset.height / max(1, tilesetH))
        }
    }

    /// Recompute columns and rows from the asset's pixel
    /// dimensions and the currently entered tile width/height.
    /// User clicks the button when they already know the tile
    /// size but want Hype to figure out how many tiles that
    /// implies.
    private func autoDetectTileset(_ asset: SpriteAsset) {
        guard tilesetW > 0, tilesetH > 0, asset.width > 0, asset.height > 0 else { return }
        tilesetCols = max(1, asset.width / tilesetW)
        tilesetRows = max(1, asset.height / tilesetH)
    }

    /// Commit the current tile metadata values to the asset and
    /// flip its kind to `.tileSet`. After this the asset is
    /// ready to be referenced by `createTileMap` with
    /// multi-column rendering working correctly.
    private func classifyAsTileset(_ asset: SpriteAsset) {
        guard tilesetW > 0, tilesetH > 0 else { return }
        // Derive any missing columns/rows from image dimensions
        // on commit too, so a user who only sets Tile W/H and
        // clicks Classify still gets a valid result.
        var cols = tilesetCols
        var rows = tilesetRows
        if cols <= 0, asset.width > 0 { cols = max(1, asset.width / tilesetW) }
        if rows <= 0, asset.height > 0 { rows = max(1, asset.height / tilesetH) }
        document.document.spriteRepository.updateAsset(id: asset.id) { mut in
            mut.kind = .tileSet
            mut.tileWidth = tilesetW
            mut.tileHeight = tilesetH
            mut.tileColumns = cols
            mut.tileRows = rows
        }
        tilesetCols = cols
        tilesetRows = rows
    }

    /// Revert a tileset classification. Kind goes back to
    /// `.imageTexture` and the tile metadata is zeroed out.
    /// Useful if the user picked wrong tile dimensions and wants
    /// to start over.
    private func unclassifyTileset(_ asset: SpriteAsset) {
        document.document.spriteRepository.updateAsset(id: asset.id) { mut in
            mut.kind = .imageTexture
            mut.tileWidth = 0
            mut.tileHeight = 0
            mut.tileColumns = 0
            mut.tileRows = 0
        }
    }

    // MARK: - Asset Usage Tracking

    /// Find all usages of an asset across all named scenes in the document.
    private func findAssetUsages(assetId: UUID) -> [SpriteAssetUsage] {
        document.document.spriteAssetUsages(for: assetId)
    }

    // MARK: - Import

    private func importAsset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .mp3, .wav, .aiff, .mpeg4Audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            var lastImportedId: UUID?
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.lowercased()
                let isAudio = ["mp3", "wav", "aiff", "m4a", "caf"].contains(ext)

                if isAudio {
                    let mimeType: String
                    switch ext {
                    case "mp3": mimeType = "audio/mpeg"
                    case "wav": mimeType = "audio/wav"
                    case "aiff": mimeType = "audio/aiff"
                    case "m4a": mimeType = "audio/mp4"
                    case "caf": mimeType = "audio/x-caf"
                    default: mimeType = "audio/mpeg"
                    }
                    let asset = SpriteAsset(
                        name: name,
                        kind: .audioClip,
                        mimeType: mimeType,
                        data: data,
                        width: 0,
                        height: 0
                    )
                    document.document.spriteRepository.addAsset(asset)
                    lastImportedId = asset.id
                } else {
                    guard let image = NSImage(data: data) else { continue }
                    let kind: AssetKind = HypeToolExecutor.filenameLooksLikeTileset(name)
                        ? .tileSet
                        : .imageTexture
                    let asset = SpriteAsset(
                        name: name,
                        kind: kind,
                        mimeType: ext == "png" ? "image/png" : "image/jpeg",
                        data: data,
                        width: Int(image.size.width),
                        height: Int(image.size.height)
                    )
                    document.document.spriteRepository.addAsset(asset)
                    lastImportedId = asset.id
                }
            }
            // Auto-select the last imported asset so its detail
            // panel is immediately visible. For tileset-hinted
            // imports this means the TILESET classification section
            // appears right away with auto-detected dimensions.
            if let id = lastImportedId {
                selectedAssetIds = [id]
            }
        }
    }

    /// Import images specifically as tileset assets. Opens an
    /// image-only file picker (no audio), imports each file with
    /// `kind = .tileSet`, and auto-selects the last import so the
    /// detail panel's TILESET classification section is immediately
    /// visible with auto-detected tile dimensions pre-filled.
    private func importTilesetAsset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select tileset sprite sheet image(s)"
        panel.begin { response in
            guard response == .OK else { return }
            var lastImportedId: UUID?
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.lowercased()
                guard let image = NSImage(data: data) else { continue }
                let asset = SpriteAsset(
                    name: name,
                    kind: .tileSet,
                    mimeType: ext == "png" ? "image/png" : "image/jpeg",
                    data: data,
                    width: Int(image.size.width),
                    height: Int(image.size.height)
                )
                document.document.spriteRepository.addAsset(asset)
                lastImportedId = asset.id
            }
            // Auto-select so the TILESET section in the detail
            // panel is immediately visible. The `.onChange(of:
            // selectedAssetIds)` handler calls `seedTilesetState`
            // which pre-fills tile W/H/cols/rows from the image
            // dimensions. The user just needs to review and click
            // "Classify as Tileset".
            if let id = lastImportedId {
                selectedAssetIds = [id]
            }
        }
    }
}
