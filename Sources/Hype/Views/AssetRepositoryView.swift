import SwiftUI
import HypeCore
import UniformTypeIdentifiers
import AVKit

/// A SwiftUI view for browsing, importing, and managing stack assets in the repository.
///
/// Presentation is handled by the caller. The legacy pattern
/// (`.sheet(isPresented:) { AssetRepositoryView(document:) }`)
/// stays supported — dismiss is inferred from the environment when
/// `onDone` is nil. When the view is hosted in a standalone NSWindow
/// via `openAssetRepositoryWindow`, the caller passes an `onDone`
/// closure that closes the window instead, since `@Environment(\.dismiss)`
/// doesn't reach NSHostingView contexts.
struct AssetRepositoryView: View {
    @Binding var document: HypeDocumentWrapper
    /// Optional close callback. When non-nil, the Done button calls
    /// this instead of the SwiftUI `dismiss` environment action. Used
    /// by `openAssetRepositoryWindow` to close the detached window.
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var selectedAssetIds: Set<UUID> = []
    @State private var previewPlayAssetId: UUID?
    @State private var previewPlayRequestId: UUID?
    @State private var searchText: String = ""
    @State private var selectedCategory: AssetCategory = .all
    @State private var selectedSource: AssetSourceFilter = .all
    @State private var selectedStatus: AssetStatusFilter = .all
    @State private var selectedSort: AssetSort = .nameAscending
    @State private var assetFilterCacheKey: AssetFilterCacheKey?
    @State private var cachedFilteredAssets: [Asset] = []
    @State private var cachedAssetGridItems: [AssetGridItemModel] = []
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

    // MARK: - Meshy 3D generation state
    @State private var showGenerate3DSheet: Bool = false
    @State private var showGenerate3DEnableConfirm: Bool = false
    @State private var showGenerate3DKeyMissingAlert: Bool = false
    /// Pre-fetched from Keychain on `.onAppear` and after Save/Delete.
    /// Used by `openGenerate3DSheet()` to avoid a synchronous Keychain
    /// probe on the main thread (security M4).
    @State private var meshyKeyIsSet: Bool = false

    // MARK: - Rig & Animate state (Phase 3)
    /// Source asset for the Rig & Animate sheet. Set to non-nil to trigger
    /// the `.sheet(item:)` presentation of `RigAndAnimateCoordinator`.
    @State private var rigAndAnimateSourceAsset: Asset? = nil

    // MARK: - Remesh & Retexture state (Phase 4)
    /// Selection driving `RemeshAndRetextureCoordinator`. Non-nil opens the sheet.
    @State private var remeshOrRetextureSource: RemeshOrRetextureSelection? = nil

    // MARK: - Tileset classification state
    // Local state for the classify panel. Seeded from the selected
    // asset when focus changes, so the user can tweak values before
    // committing them with the "Classify as tileset" button.
    @State private var tilesetW: Int = 32
    @State private var tilesetH: Int = 32
    @State private var tilesetCols: Int = 0
    @State private var tilesetRows: Int = 0
    @State private var tilesetEditingAssetId: UUID? = nil

    // MARK: - Remesh / Retexture selection type

    /// Small wrapper that is `Identifiable` so it can drive `.sheet(item:)`.
    private struct RemeshOrRetextureSelection: Identifiable {
        /// The asset id is stable and unique — use it as the selection id.
        var id: UUID { asset.id }
        let asset: Asset
        let mode: RemeshAndRetextureCoordinator.Mode
    }

    private enum AssetSourceFilter: String, CaseIterable, Identifiable {
        case all
        case imported
        case web
        case ai
        case meshy

        var id: Self { self }

        var label: String {
            switch self {
            case .all: return "Any Source"
            case .imported: return "Imported"
            case .web: return "Web"
            case .ai: return "AI"
            case .meshy: return "Meshy"
            }
        }
    }

    private enum AssetStatusFilter: String, CaseIterable, Identifiable {
        case all
        case used
        case unused
        case tilesets
        case needsTilesetSetup
        case rigged
        case unriggedModels

        var id: Self { self }

        var label: String {
            switch self {
            case .all: return "Any Status"
            case .used: return "Used"
            case .unused: return "Unused"
            case .tilesets: return "Tilesets"
            case .needsTilesetSetup: return "Needs Tileset Setup"
            case .rigged: return "Rigged"
            case .unriggedModels: return "Unrigged Models"
            }
        }
    }

    private enum AssetSort: String, CaseIterable, Identifiable {
        case nameAscending
        case kind
        case newest
        case largest

        var id: Self { self }

        var label: String {
            switch self {
            case .nameAscending: return "Name"
            case .kind: return "Type"
            case .newest: return "Newest"
            case .largest: return "Largest"
            }
        }
    }

    private static let assetGridMinimumCellWidth: CGFloat = 80
    private static let assetGridMaximumCellWidth: CGFloat = 96
    private static let assetGridSpacing: CGFloat = 8

    private struct AssetFilterCacheKey: Equatable {
        let searchText: String
        let category: AssetCategory
        let source: AssetSourceFilter
        let status: AssetStatusFilter
        let sort: AssetSort
        let repositoryRevision: Int
    }

    private struct AssetGridItemModel: Identifiable, Equatable {
        let id: UUID
        let name: String
        let kind: AssetKind
        let mimeType: String
        let thumbnailImage: NSImage?
        let contentIdentity: String
        let isTileSet: Bool
        let tileColumns: Int
        let tileRows: Int
        let tileWidth: Int
        let tileHeight: Int
        let isPlayable: Bool

        var showsJSONIcon: Bool {
            kind == .placeholderAsset && (mimeType == "application/json" || mimeType.hasPrefix("text/"))
        }

        static func == (lhs: AssetGridItemModel, rhs: AssetGridItemModel) -> Bool {
            lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.kind == rhs.kind &&
            lhs.mimeType == rhs.mimeType &&
            lhs.contentIdentity == rhs.contentIdentity &&
            lhs.isTileSet == rhs.isTileSet &&
            lhs.tileColumns == rhs.tileColumns &&
            lhs.tileRows == rhs.tileRows &&
            lhs.tileWidth == rhs.tileWidth &&
            lhs.tileHeight == rhs.tileHeight &&
            lhs.isPlayable == rhs.isPlayable
        }
    }

    private struct AssetThumbnailView: View, Equatable {
        let item: AssetGridItemModel
        let isSelected: Bool

        var body: some View {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    thumbnailContent

                    // Tileset badge: small grid-shaped marker overlaid
                    // on the top-right corner so tileset assets are
                    // instantly distinguishable from plain images at
                    // grid-browsing time. Only drawn on classified
                    // tilesets — assets flagged by filename without
                    // metadata show no badge until classification is
                    // committed.
                    if item.isTileSet {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Circle().fill(Color.orange))
                            .offset(x: -2, y: 2)
                    }
                }
                Text(item.name)
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

        @ViewBuilder
        private var thumbnailContent: some View {
            if item.kind == .model3D {
                symbol("cube.transparent", color: .indigo)
            } else if item.kind == .audioClip {
                symbol("waveform", color: .purple)
            } else if item.kind == .videoClip {
                symbol("film", color: .blue)
            } else if item.kind == .particlePreset {
                symbol("sparkles", color: .orange)
            } else if item.showsJSONIcon {
                symbol("curlybraces.square", color: .secondary)
            } else if let img = item.thumbnailImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .id(item.contentIdentity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .frame(width: 64, height: 64)
            }
        }

        private func symbol(_ systemName: String, color: Color) -> some View {
            Image(systemName: systemName)
                .font(.system(size: 32))
                .foregroundColor(color)
                .frame(width: 64, height: 64)
        }
    }

    private var currentAssetFilterCacheKey: AssetFilterCacheKey {
        AssetFilterCacheKey(
            searchText: searchText,
            category: selectedCategory,
            source: selectedSource,
            status: selectedStatus,
            sort: selectedSort,
            repositoryRevision: assetRepositoryRevision
        )
    }

    private var assetRepositoryRevision: Int {
        var hasher = Hasher()
        for asset in document.document.assetRepository.assets {
            hasher.combine(asset.id)
            hasher.combine(asset.name)
            hasher.combine(asset.kind.rawValue)
            hasher.combine(asset.mimeType)
            hasher.combine(asset.data.count)
            hasher.combine(asset.totalEmbeddedByteCount)
            hasher.combine(asset.width)
            hasher.combine(asset.height)
            hasher.combine(asset.tags)
            hasher.combine(asset.isTileSet)
            hasher.combine(asset.tileWidth)
            hasher.combine(asset.tileHeight)
            hasher.combine(asset.tileColumns)
            hasher.combine(asset.tileRows)
        }
        return hasher.finalize()
    }

    private func computeFilteredAssets() -> [Asset] {
        document.document.assetRepository
            .searchAssets(named: searchText, category: selectedCategory)
            .filter(matchesSource)
            .filter(matchesStatus)
            .sorted(by: sortAssets)
    }

    private var filteredAssetGridItems: [AssetGridItemModel] {
        cachedAssetGridItems
    }

    private var assetCountsByCategory: [AssetCategory: Int] {
        Dictionary(grouping: document.document.assetRepository.assets, by: { $0.kind.category })
            .mapValues(\.count)
    }

    /// Dispatch the close action: prefer the explicit `onDone`
    /// callback (set by `openAssetRepositoryWindow`) and fall back
    /// to SwiftUI's environment dismiss for legacy sheet-based
    /// presentations.
    private func dismissAction() {
        if let onDone = onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private func categoryLabel(_ category: AssetCategory) -> String {
        if category == .all {
            return "\(category.displayName) \(document.document.assetRepository.assets.count)"
        }
        return "\(category.displayName) \(assetCountsByCategory[category, default: 0])"
    }

    private var filtersAreActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        selectedCategory != .all ||
        selectedSource != .all ||
        selectedStatus != .all ||
        selectedSort != .nameAscending
    }

    private func clearAssetFilters() {
        searchText = ""
        selectedCategory = .all
        selectedSource = .all
        selectedStatus = .all
        selectedSort = .nameAscending
    }

    private func refreshAssetFilterCache(pruneSelection: Bool = false) {
        let key = currentAssetFilterCacheKey
        guard assetFilterCacheKey != key else { return }
        let assets = computeFilteredAssets()
        cachedFilteredAssets = assets
        cachedAssetGridItems = assets.map(makeGridItemModel)
        assetFilterCacheKey = key
        if pruneSelection {
            let visibleIds = Set(assets.map(\.id))
            selectedAssetIds = selectedAssetIds.intersection(visibleIds)
        }
    }

    private func scheduleAssetFilterCacheRefresh(pruneSelection: Bool = false) {
        DispatchQueue.main.async {
            refreshAssetFilterCache(pruneSelection: pruneSelection)
        }
    }

    var body: some View {
        HSplitView {
            // Left: asset grid
            VStack(spacing: 0) {
                assetHeader

                // Grid with multi-select
                GeometryReader { geometry in
                    ScrollView {
                        if cachedFilteredAssets.isEmpty {
                            VStack(spacing: 8) {
                                Spacer(minLength: 48)
                                Image(systemName: filtersAreActive ? "line.3.horizontal.decrease.circle" : "photo.on.rectangle.angled")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                                Text(filtersAreActive ? "No assets match the current filters" : "No assets imported")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if filtersAreActive {
                                    Button("Clear Filters") {
                                        clearAssetFilters()
                                    }
                                    .font(.system(size: 11))
                                }
                                Spacer(minLength: 48)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        } else {
                            LazyVGrid(columns: assetGridColumns(for: geometry.size.width - 16), spacing: Self.assetGridSpacing) {
                                ForEach(filteredAssetGridItems) { item in
                                    assetThumbnail(item)
                                        .onTapGesture {
                                            if NSEvent.modifierFlags.contains(.command) {
                                                // Cmd+click: toggle in multi-selection
                                                if selectedAssetIds.contains(item.id) {
                                                    selectedAssetIds.remove(item.id)
                                                } else {
                                                    selectedAssetIds.insert(item.id)
                                                }
                                            } else {
                                                // Plain click: single select
                                                selectedAssetIds = [item.id]
                                            }
                                        }
                                        .onTapGesture(count: 2) {
                                            playAssetInPreview(assetId: item.id)
                                        }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .onKeyPress(.delete) { deleteSelected(); return .handled }

                // Status bar
                HStack {
                    Text(assetStatusText)
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

            // Right: detail panel + repository-scoped AI chat.
            VStack(spacing: 0) {
                Group {
                    if selectedAssetIds.count == 1,
                       let assetId = selectedAssetIds.first,
                       let asset = document.document.assetRepository.asset(byId: assetId) {
                        assetDetailPanel(asset)
                    } else if selectedAssetIds.count > 1 {
                        multiSelectionPanel
                    } else {
                        VStack {
                            Spacer()
                            Text("Select an asset").foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .frame(minWidth: 260, maxHeight: .infinity)

                Divider()

                AssetRepositoryAIChatView(
                    document: $document,
                    selectedAssetIds: $selectedAssetIds
                )
                .frame(minWidth: 260, minHeight: 240, idealHeight: 280, maxHeight: 340)
            }
            .frame(minWidth: 300)
        }
        .frame(minWidth: 550, minHeight: 350)
        // Repository window surface — themed so the whole window
        // (toolbar + grid + detail panel) follows the active theme.
        // Asset thumbnails themselves are intentional content and
        // keep their original tinting; only the surrounding chrome
        // is retinted.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so labels in the search bar,
        // status strip, and detail rows stay readable on the
        // themed bg regardless of macOS appearance.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .onChange(of: selectedAssetIds) { _, newValue in
            // Whenever focus moves to a single asset, reseed both
            // the name draft and the tileset editor state from the
            // selected asset's current values.
            if newValue.count == 1,
               let id = newValue.first,
               let asset = document.document.assetRepository.asset(byId: id) {
                assetNameDraft = asset.name
                seedTilesetState(from: asset)
            }
        }
        .onChange(of: searchText) { _, _ in scheduleAssetFilterCacheRefresh(pruneSelection: true) }
        .onChange(of: selectedCategory) { _, _ in scheduleAssetFilterCacheRefresh(pruneSelection: true) }
        .onChange(of: selectedSource) { _, _ in scheduleAssetFilterCacheRefresh(pruneSelection: true) }
        .onChange(of: selectedStatus) { _, _ in scheduleAssetFilterCacheRefresh(pruneSelection: true) }
        .onChange(of: selectedSort) { _, _ in scheduleAssetFilterCacheRefresh(pruneSelection: true) }
        .onChange(of: assetRepositoryRevision) { _, _ in scheduleAssetFilterCacheRefresh(pruneSelection: true) }
        .onReceive(NotificationCenter.default.publisher(for: .selectAssetRepositoryAsset)) { notification in
            guard let assetId = notification.userInfo?["assetId"] as? UUID else { return }
            selectedAssetIds = [assetId]
        }
        .onAppear {
            refreshAssetFilterCache()
            meshyKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        }
        .sheet(isPresented: $showGenerate3DSheet) {
            Generate3DSheet(
                document: $document,
                targetPartId: nil,
                onAssetImported: { ref in
                    selectedAssetIds = [ref.id]
                },
                onDismiss: { showGenerate3DSheet = false }
            )
        }
        .sheet(item: $rigAndAnimateSourceAsset) { asset in
            RigAndAnimateCoordinator(
                document: $document,
                sourceAsset: asset,
                onDismiss: { rigAndAnimateSourceAsset = nil },
                onAssetsImported: { ids in
                    if let first = ids.first {
                        selectedAssetIds = [first]
                    }
                }
            )
        }
        // Phase 4: Remesh / Retexture coordinator sheet.
        .sheet(item: $remeshOrRetextureSource) { selection in
            RemeshAndRetextureCoordinator(
                document: $document,
                sourceAsset: selection.asset,
                mode: selection.mode,
                onDismiss: { remeshOrRetextureSource = nil },
                onAssetImported: { id in
                    selectedAssetIds = [id]
                }
            )
        }
        .alert("Enable 3D generation for this stack?", isPresented: $showGenerate3DEnableConfirm) {
            Button("Enable") {
                document.document.stack.meshyEnabled = true
                showGenerate3DSheet = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generated 3D models will be downloaded from api.meshy.ai and embedded in this stack. You can disable this in Preferences \u{2192} Meshy.ai.")
        }
        .alert("Meshy API key required", isPresented: $showGenerate3DKeyMissingAlert) {
            Button("Open Preferences\u{2026}") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add your Meshy.ai API key in Preferences \u{2192} Meshy.ai before generating 3D models.")
        }
    }

    // MARK: - Header and Filtering

    @ViewBuilder
    private var assetHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Asset Repository")
                        .font(.headline)
                    Text(assetStatusText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: importAsset) {
                    Image(systemName: "plus")
                }
                .help("Import Assets")

                Button(action: importTilesetAsset) {
                    Image(systemName: "square.grid.3x3")
                }
                .help("Import Tileset Image")

                Button(action: openGenerate3DSheet) {
                    Image(systemName: "cube.transparent")
                }
                .help("Generate 3D\u{2026}")

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

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Search names, tags, kind, source, provider, MIME\u{2026}", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Clear Search")
                }
            }

            Picker("Asset Type", selection: $selectedCategory) {
                ForEach(AssetCategory.allCases, id: \.self) { category in
                    Text(categoryLabel(category)).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Picker("Source", selection: $selectedSource) {
                    ForEach(AssetSourceFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .help("Filter by where assets came from")

                Picker("Status", selection: $selectedStatus) {
                    ForEach(AssetStatusFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 170)
                .help("Filter by usage or setup state")

                Picker("Sort", selection: $selectedSort) {
                    ForEach(AssetSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 115)
                .help("Sort assets")

                Spacer(minLength: 4)

                if filtersAreActive {
                    Button("Clear") {
                        clearAssetFilters()
                    }
                    .font(.system(size: 11))
                    .help("Clear Search and Filters")
                }
            }
        }
        .padding(8)
        .background(hypeTheme.inspectorBackground.swiftUIColor)
    }

    private var assetStatusText: String {
        let total = document.document.assetRepository.assets.count
        let shown = cachedFilteredAssets.count
        if shown == total {
            return "\(total) assets"
        }
        return "\(shown) of \(total) assets"
    }

    private func matchesSource(_ asset: Asset) -> Bool {
        switch selectedSource {
        case .all:
            return true
        case .imported:
            return asset.provenance == nil || asset.provenance?.origin == .userImport
        case .web:
            return asset.provenance?.origin == .webSearch
        case .ai:
            return asset.provenance?.origin == .aiGenerated || asset.provenance?.origin == .aiContext
        case .meshy:
            return asset.provenance?.attribution.providerIdentifier == "meshy"
        }
    }

    private func matchesStatus(_ asset: Asset) -> Bool {
        switch selectedStatus {
        case .all:
            return true
        case .used:
            return !document.document.assetUsages(for: asset.id).isEmpty
        case .unused:
            return document.document.assetUsages(for: asset.id).isEmpty
        case .tilesets:
            return asset.kind == .tileSet
        case .needsTilesetSetup:
            return asset.kind == .tileSet && !asset.isTileSet
        case .rigged:
            return asset.kind == .model3D && asset.isRigged
        case .unriggedModels:
            return asset.kind == .model3D && !asset.isRigged
        }
    }

    private func sortAssets(_ lhs: Asset, _ rhs: Asset) -> Bool {
        switch selectedSort {
        case .nameAscending:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .kind:
            if lhs.kind.rawValue == rhs.kind.rawValue {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        case .newest:
            return repositoryIndex(of: lhs.id) > repositoryIndex(of: rhs.id)
        case .largest:
            if lhs.totalEmbeddedByteCount == rhs.totalEmbeddedByteCount {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.totalEmbeddedByteCount > rhs.totalEmbeddedByteCount
        }
    }

    private func repositoryIndex(of id: UUID) -> Int {
        document.document.assetRepository.assets.firstIndex { $0.id == id } ?? 0
    }

    private func makeGridItemModel(for asset: Asset) -> AssetGridItemModel {
        AssetGridItemModel(
            id: asset.id,
            name: asset.name,
            kind: asset.kind,
            mimeType: asset.mimeType,
            thumbnailImage: asset.kind == .placeholderAsset && (asset.mimeType == "application/json" || asset.mimeType.hasPrefix("text/"))
                ? nil
                : AssetPreviewData.thumbnail(for: asset, size: CGSize(width: 64, height: 64)),
            contentIdentity: AssetPreviewData.contentIdentity(for: asset),
            isTileSet: asset.isTileSet,
            tileColumns: asset.tileColumns,
            tileRows: asset.tileRows,
            tileWidth: asset.tileWidth,
            tileHeight: asset.tileHeight,
            isPlayable: AssetPreviewData.playableFile(for: asset) != nil
        )
    }

    private func assetGridColumns(for width: CGFloat) -> [GridItem] {
        let cellWidth = Self.assetGridMinimumCellWidth
        let spacing = Self.assetGridSpacing
        let count = max(1, Int((max(width, cellWidth) + spacing) / (cellWidth + spacing)))
        return Array(
            repeating: GridItem(
                .flexible(minimum: Self.assetGridMinimumCellWidth, maximum: Self.assetGridMaximumCellWidth),
                spacing: spacing
            ),
            count: count
        )
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func assetThumbnail(_ item: AssetGridItemModel) -> some View {
        AssetThumbnailView(item: item, isSelected: selectedAssetIds.contains(item.id))
            .equatable()
    }

    // MARK: - Single Asset Detail Panel

    @ViewBuilder
    private func assetDetailPanel(_ asset: Asset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                AssetPreviewPane(
                    asset: asset,
                    playRequestId: previewPlayAssetId == asset.id ? previewPlayRequestId : nil
                )

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
                            document.document.assetRepository.updateAsset(id: asset.id) { $0.name = newVal }
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
                    document.document.assetRepository.removeAsset(id: asset.id)
                        selectedAssetIds.remove(asset.id)
                        // Regenerate attribution block whenever a web-sourced asset is removed.
                        let webAssets = document.document.assetRepository.assets.filter {
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

                // Rig & Animate / Animate actions (Phase 3)
                // "Rig & Animate…" — only for unrigged Meshy-generated models.
                // "Animate…"       — only for rigged models without a baked animation.
                if asset.kind == .model3D {
                    let hasMeshyTaskId = !(asset.provenance?.attribution.taskId ?? "").isEmpty
                    let isMeshy = asset.provenance?.attribution.providerIdentifier == "meshy"

                    if !asset.isRigged && hasMeshyTaskId && isMeshy {
                        Button {
                            rigAndAnimateSourceAsset = asset
                        } label: {
                            HStack {
                                Image(systemName: "person.bust")
                                Text("Rig & Animate\u{2026}")
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Auto-rig this model with Meshy.ai, then optionally bake in an animation.")
                    }

                    if asset.isRigged && asset.animationActionId == nil {
                        // The asset is a rigged base model (no animation baked in yet).
                        // Only allow animating if it has a Meshy rigging task id.
                        let hasRigTaskId = !(asset.provenance?.attribution.taskId ?? "").isEmpty
                        if hasRigTaskId {
                            Button {
                                rigAndAnimateSourceAsset = asset
                            } label: {
                                HStack {
                                    Image(systemName: "figure.run")
                                    Text("Animate\u{2026}")
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Apply a Meshy animation to this rigged model.")
                        }
                    }

                    // Phase 4: Remesh, Retexture, and Open in AR.
                    // Remesh / Retexture: only for Meshy-generated models with a task id.
                    if hasMeshyTaskId && isMeshy {
                        Button {
                            remeshOrRetextureSource = RemeshOrRetextureSelection(
                                asset: asset,
                                mode: .remesh
                            )
                        } label: {
                            HStack {
                                Image(systemName: "cylinder.split.1x2")
                                Text("Remesh\u{2026}")
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Create a lower-poly (or re-topologized) version of this model using Meshy.ai.")

                        Button {
                            remeshOrRetextureSource = RemeshOrRetextureSelection(
                                asset: asset,
                                mode: .retexture
                            )
                        } label: {
                            HStack {
                                Image(systemName: "paintbrush.pointed")
                                Text("Retexture\u{2026}")
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Apply a new texture to this model via a text prompt, using Meshy.ai.")
                    }

                    // Open in AR: available for any model3D on macOS 13+.
                    OpenInARButton(asset: asset)
                }

                // Transparent Background — same one-click chroma-key
                // available in the multi-selection panel, surfaced
                // here so the user doesn't need to multi-select a
                // single asset to reach it. Only meaningful for image
                // kinds; hidden for audio and 3D models.
                if asset.kind != .audioClip && asset.kind != .model3D {
                    Button(action: makeSelectedImagesTransparent) {
                        HStack { Image(systemName: "square.dashed"); Text("Transparent Background") }
                    }
                    .buttonStyle(.plain)
                    .help("Detect the dominant background color of this image and replace it with transparency. Re-encodes as PNG so the transparency is permanent.")
                }
            }
            .padding()
        }
    }

    // MARK: - Multi-Selection Panel

    private var multiSelectionPanel: some View {
        // Count just the image-kind assets in the selection so the
        // Transparent Background button reflects what'll actually be
        // processed (audio clips and the like are skipped).
        let imageCount = selectedImageAssetCount
        return VStack(spacing: 12) {
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

            // Transparent Background — runs the same dominant-corner
            // chroma-key the renderer uses, but writes PNG bytes
            // back to the asset's `data` so the transparency is
            // permanent. Disabled when the selection contains zero
            // image-kind assets (e.g. audio-only multi-select).
            Button(action: makeSelectedImagesTransparent) {
                HStack {
                    Image(systemName: "square.dashed")
                    Text(imageCount == selectedAssetIds.count
                        ? "Transparent Background"
                        : "Transparent Background (\(imageCount))")
                }
            }
            .buttonStyle(.bordered)
            .disabled(imageCount == 0)
            .help("Detect the dominant background color and replace it with transparency. Skips audio assets. Always re-encodes as PNG.")
            Spacer()
        }
    }

    // MARK: - Bindings

    /// Write the current name draft back to the document.
    /// Called on Return key press.
    private func commitAssetName(assetId: UUID) {
        let trimmed = assetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.document.assetRepository.updateAsset(id: assetId) { $0.name = trimmed }
    }

    // MARK: - Actions

    /// Check the Meshy gate and either show the Generate 3D sheet or
    /// an appropriate alert directing the user to enable the feature or
    /// add an API key.
    private func openGenerate3DSheet() {
        switch Meshy3DGate.status(for: document.document, keyIsSet: meshyKeyIsSet) {
        case .ready:
            showGenerate3DSheet = true
        case .stackDisabled:
            showGenerate3DEnableConfirm = true
        case .apiKeyMissing:
            showGenerate3DKeyMissingAlert = true
        }
    }

    private func deleteSelected() {
        for id in selectedAssetIds {
            document.document.assetRepository.removeAsset(id: id)
        }
        selectedAssetIds.removeAll()
        previewPlayAssetId = nil
        previewPlayRequestId = nil
    }

    private func duplicateSelected() {
        let ids = selectedAssetIds
        for id in ids {
            if let asset = document.document.assetRepository.asset(byId: id) {
                duplicateAsset(asset)
            }
        }
    }

    /// Number of currently-selected assets that are image-kinded
    /// (and therefore eligible for the Transparent Background
    /// action). Used by the multi-selection panel to label the
    /// button accurately and disable it when the selection is
    /// audio-only.
    private var selectedImageAssetCount: Int {
        selectedAssetIds.reduce(0) { count, id in
            guard let asset = document.document.assetRepository.asset(byId: id) else { return count }
            return Self.isImageKind(asset.kind) ? count + 1 : count
        }
    }

    /// Image-kinds eligible for chroma-key processing. We accept
    /// imageTexture, spriteSheet, and tileSet — all of those are
    /// pixel data with a meaningful background to mask. We exclude
    /// audioClip / videoClip / document / particlePreset / placeholderAsset
    /// (the chroma-key would either error or produce nonsense).
    private static func isImageKind(_ kind: AssetKind) -> Bool {
        switch kind {
        case .imageTexture, .spriteSheet, .tileSet:
            return true
        case .audioClip, .videoClip, .document, .particlePreset, .placeholderAsset, .model3D:
            return false
        }
    }

    /// Replace each selected image asset's `data` with a
    /// chroma-keyed PNG that has the dominant background color
    /// masked to transparent. Skips non-image-kinded assets in
    /// the selection (so a mixed audio+image multi-select still
    /// processes the images and leaves the audio alone). On
    /// failure the asset is left untouched — this is a best-
    /// effort, lossless-on-failure operation.
    ///
    /// Re-encodes to PNG regardless of source format because JPEG
    /// can't represent per-pixel alpha. The asset's `mimeType` is
    /// updated accordingly so downstream code that branches on
    /// MIME (renderer's image-decoder picks, AI export paths)
    /// stays consistent.
    private func makeSelectedImagesTransparent() {
        for id in selectedAssetIds {
            guard let asset = document.document.assetRepository.asset(byId: id),
                  Self.isImageKind(asset.kind),
                  let pngData = ImageChromaKey.makeTransparentPNG(from: asset.data)
            else { continue }
            document.document.assetRepository.updateAsset(id: id) { mut in
                mut.data = pngData
                mut.mimeType = "image/png"
            }
        }
    }

    private func duplicateAsset(_ asset: Asset) {
        var copy = asset
        copy.id = UUID()
        copy.name = asset.name + " copy"
        // Ensure unique name
        let existingNames = Set(document.document.assetRepository.assets.map(\.name))
        var name = copy.name
        var counter = 2
        while existingNames.contains(name) {
            name = "\(asset.name) copy \(counter)"
            counter += 1
        }
        copy.name = name
        document.document.assetRepository.addAsset(copy)
    }

    private func playAssetInPreview(assetId: UUID) {
        guard let asset = document.document.assetRepository.asset(byId: assetId) else { return }
        guard AssetPreviewData.playableFile(for: asset) != nil else { return }
        selectedAssetIds = [asset.id]
        previewPlayAssetId = asset.id
        previewPlayRequestId = UUID()
    }

    // MARK: - Slicing

    /// Slice an asset into a grid of columns x rows, generating AssetSlice entries.
    private func sliceAsset(_ asset: Asset, columns: Int, rows: Int) {
        guard columns > 0, rows > 0, asset.width > 0, asset.height > 0 else { return }
        let frameW = asset.width / columns
        let frameH = asset.height / rows
        document.document.assetRepository.updateAsset(id: asset.id) { asset in
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
    private func createClipFromSlices(_ asset: Asset) {
        let sliceIds = asset.slices.map(\.id)
        let clip = AnimationClip(name: "\(asset.name)_anim", frameSliceIds: sliceIds, fps: clipFps, loops: true)
        document.document.assetRepository.updateAsset(id: asset.id) { $0.animationClips.append(clip) }
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
    private func seedTilesetState(from asset: Asset) {
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
    private func autoDetectTileset(_ asset: Asset) {
        guard tilesetW > 0, tilesetH > 0, asset.width > 0, asset.height > 0 else { return }
        tilesetCols = max(1, asset.width / tilesetW)
        tilesetRows = max(1, asset.height / tilesetH)
    }

    /// Commit the current tile metadata values to the asset and
    /// flip its kind to `.tileSet`. After this the asset is
    /// ready to be referenced by `createTileMap` with
    /// multi-column rendering working correctly.
    private func classifyAsTileset(_ asset: Asset) {
        guard tilesetW > 0, tilesetH > 0 else { return }
        // Derive any missing columns/rows from image dimensions
        // on commit too, so a user who only sets Tile W/H and
        // clicks Classify still gets a valid result.
        var cols = tilesetCols
        var rows = tilesetRows
        if cols <= 0, asset.width > 0 { cols = max(1, asset.width / tilesetW) }
        if rows <= 0, asset.height > 0 { rows = max(1, asset.height / tilesetH) }
        document.document.assetRepository.updateAsset(id: asset.id) { mut in
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
    private func unclassifyTileset(_ asset: Asset) {
        document.document.assetRepository.updateAsset(id: asset.id) { mut in
            mut.kind = .imageTexture
            mut.tileWidth = 0
            mut.tileHeight = 0
            mut.tileColumns = 0
            mut.tileRows = 0
        }
    }

    // MARK: - Asset Usage Tracking

    /// Find all usages of an asset across all named scenes in the document.
    private func findAssetUsages(assetId: UUID) -> [AssetUsage] {
        document.document.assetUsages(for: assetId)
    }

    // MARK: - Import

    private func importAsset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.importableAssetContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select image, audio, video, 3D model, or particle assets"
        panel.begin { response in
            guard response == .OK else { return }
            var lastImportedId: UUID?
            for url in panel.urls {
                guard let asset = Self.makeImportedAsset(from: url) else { continue }
                document.document.assetRepository.addAsset(asset)
                lastImportedId = asset.id
            }
            // Auto-select the last imported asset so its detail
            // panel is immediately visible. For tileset-hinted
            // imports this means the TILESET classification section
            // appears right away with auto-detected dimensions.
            if let id = lastImportedId {
                selectedAssetIds = [id]
            }
            if lastImportedId != nil {
                HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
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
        panel.message = "Select tileset image assets"
        panel.begin { response in
            guard response == .OK else { return }
            var lastImportedId: UUID?
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.lowercased()
                guard let image = NSImage(data: data) else { continue }
                let tags = HypeToolExecutor.suggestTagsFromFilename(name)
                let asset = Asset(
                    name: name,
                    kind: .tileSet,
                    mimeType: ext == "png" ? "image/png" : "image/jpeg",
                    data: data,
                    width: Int(image.size.width),
                    height: Int(image.size.height),
                    tags: tags
                )
                document.document.assetRepository.addAsset(asset)
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
            if lastImportedId != nil {
                HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
            }
        }
    }

    private static var importableAssetContentTypes: [UTType] {
        let builtIns: [UTType?] = [
            .png, .jpeg, .gif, UTType(filenameExtension: "webp"),
            .mp3, .wav, .aiff, .mpeg4Audio, UTType(filenameExtension: "caf"),
            .mpeg4Movie, .movie, .quickTimeMovie,
            UTType(filenameExtension: "glb"), UTType(filenameExtension: "usdz"),
            UTType(filenameExtension: "usd"), UTType(filenameExtension: "scn"),
            UTType(filenameExtension: "dae"), UTType(filenameExtension: "obj"),
            UTType(filenameExtension: "stl"), UTType(filenameExtension: "ply"),
            UTType(filenameExtension: "abc"), UTType(filenameExtension: "fbx"),
            UTType(filenameExtension: "sks")
        ]
        return builtIns.compactMap { $0 }
    }

    private static func makeImportedAsset(from url: URL) -> Asset? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()

        if let audioMime = audioMimeType(forExtension: ext) {
            return Asset(name: name, kind: .audioClip, mimeType: audioMime, data: data)
        }

        if let videoMime = videoMimeType(forExtension: ext) {
            return Asset(name: name, kind: .videoClip, mimeType: videoMime, data: data)
        }

        if let modelMime = modelMimeType(forExtension: ext) {
            return Asset(name: name, kind: .model3D, mimeType: modelMime, data: data)
        }

        if ext == "sks" {
            return Asset(name: name, kind: .particlePreset, mimeType: "application/x-spritekit-particle", data: data)
        }

        guard let image = NSImage(data: data) else { return nil }
        let imageWidth = Int(image.size.width)
        let imageHeight = Int(image.size.height)
        let filenameTags = HypeToolExecutor.suggestTagsFromFilename(name)
        let resourceTags = HypeToolExecutor.suggestTagsFromResource(ext: ext, width: imageWidth, height: imageHeight)
        let tags = filenameTags + resourceTags
        let kind: AssetKind
        if HypeToolExecutor.filenameLooksLikeTileset(name) {
            kind = .tileSet
        } else if HypeToolExecutor.filenameLooksLikeSpriteSheet(name) {
            kind = .spriteSheet
        } else {
            kind = .imageTexture
        }
        return Asset(
            name: name,
            kind: kind,
            mimeType: imageMimeType(forExtension: ext),
            data: data,
            width: Int(image.size.width),
            height: Int(image.size.height),
            tags: tags
        )
    }

    private static func imageMimeType(forExtension ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        default: return "image/png"
        }
    }

    private static func audioMimeType(forExtension ext: String) -> String? {
        switch ext {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aif", "aiff": return "audio/aiff"
        case "m4a": return "audio/mp4"
        case "caf": return "audio/x-caf"
        default: return nil
        }
    }

    private static func videoMimeType(forExtension ext: String) -> String? {
        switch ext {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return nil
        }
    }

    private static func modelMimeType(forExtension ext: String) -> String? {
        switch ext {
        case "glb": return "model/gltf-binary"
        case "gltf": return "model/gltf+json"
        case "usdz": return "model/vnd.usdz+zip"
        case "usd": return "model/vnd.usd"
        case "fbx": return "model/vnd.autodesk.fbx"
        case "obj": return "model/obj"
        case "stl": return "model/stl"
        case "dae": return "model/vnd.collada+xml"
        case "scn": return "model/vnd.scenekit.scene"
        case "ply": return "model/ply"
        case "abc": return "model/vnd.alembic"
        default: return nil
        }
    }
}

@MainActor
fileprivate enum AssetPreviewData {
    private static let imageCache = NSCache<NSString, NSImage>()
    private static let thumbnailCache = NSCache<NSString, NSImage>()

    static func image(for asset: Asset) -> NSImage? {
        let cacheKey = imageCacheKey(for: asset)
        if let cached = imageCache.object(forKey: cacheKey as NSString) {
            return cached
        }
        for file in imageCandidateFiles(for: asset) {
            if let image = NSImage(data: file.data) {
                imageCache.setObject(image, forKey: cacheKey as NSString)
                return image
            }
        }
        return nil
    }

    static func thumbnail(for asset: Asset, size: CGSize) -> NSImage? {
        let cacheKey = thumbnailCacheKey(for: asset, size: size)
        if let cached = thumbnailCache.object(forKey: cacheKey as NSString) {
            return cached
        }
        guard let image = image(for: asset) else { return nil }
        let thumbnail = makeThumbnail(from: image, size: size)
        thumbnailCache.setObject(thumbnail, forKey: cacheKey as NSString)
        return thumbnail
    }

    static func contentIdentity(for asset: Asset) -> String {
        let fileIdentity = asset.files.map { file in
            "\(file.id.uuidString):\(file.role.rawValue):\(file.mimeType):\(file.data.count)"
        }.joined(separator: "|")
        return "\(asset.id.uuidString):\(asset.kind.rawValue):\(asset.mimeType):\(asset.data.count):\(fileIdentity)"
    }

    static func playableFile(for asset: Asset) -> AssetFile? {
        if asset.kind == .audioClip || asset.kind == .videoClip {
            return asset.primaryFile
        }
        return orderedFiles(for: asset).first { file in
            isAudio(file) || isVideo(file)
        }
    }

    static func placeholderTitle(for asset: Asset) -> String {
        guard asset.kind == .placeholderAsset else { return asset.kind.rawValue }
        let type = metadataValue("resource_type", in: asset)
        let id = metadataValue("resource_id", in: asset)
        if !type.isEmpty, !id.isEmpty {
            return "StackImport \(type.capitalized) Resource \(id)"
        }
        if asset.mimeType == "application/json" {
            return "JSON Resource"
        }
        if asset.mimeType.hasPrefix("text/") {
            return "Text Resource"
        }
        return "Placeholder Asset"
    }

    static func placeholderSummary(for asset: Asset) -> String? {
        let path = metadataValue("resource_path", in: asset)
        let sourceStack = metadataValue("shared_from_content_stack", in: asset)
        let linkedAssetId = metadataValue("shared_from_asset_id", in: asset)
        var fields: [String] = []
        if !path.isEmpty {
            fields.append(path)
        }
        if !sourceStack.isEmpty {
            fields.append("shared from \(sourceStack)")
        }
        if !linkedAssetId.isEmpty {
            fields.append("linked asset \(linkedAssetId)")
        }
        return fields.isEmpty ? nil : fields.joined(separator: " - ")
    }

    static func textPreview(for asset: Asset) -> String? {
        if asset.mimeType == "application/json" || asset.mimeType.hasPrefix("text/") {
            return String(data: asset.data, encoding: .utf8)
        }
        if let entry = asset.metadata.first(where: { entry in
            entry.mimeType == "application/json" || entry.mimeType.hasPrefix("text/")
        }) {
            return entry.value
        }
        return nil
    }

    private static func orderedFiles(for asset: Asset) -> [AssetFile] {
        asset.allFiles.sorted { lhs, rhs in
            if rolePriority(lhs.role) != rolePriority(rhs.role) {
                return rolePriority(lhs.role) < rolePriority(rhs.role)
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func imageCandidateFiles(for asset: Asset) -> [AssetFile] {
        orderedFiles(for: asset).filter { file in
            isImage(file) || (file.role == .primary && isImageKind(asset.kind))
        }
    }

    private static func imageCacheKey(for asset: Asset) -> String {
        let files = imageCandidateFiles(for: asset).map { file in
            "\(file.id.uuidString):\(file.mimeType):\(file.data.count)"
        }.joined(separator: "|")
        return "image:\(asset.id.uuidString):\(asset.kind.rawValue):\(asset.mimeType):\(asset.data.count):\(files)"
    }

    private static func thumbnailCacheKey(for asset: Asset, size: CGSize) -> String {
        "thumbnail:\(Int(size.width))x\(Int(size.height)):\(imageCacheKey(for: asset))"
    }

    private static func makeThumbnail(from image: NSImage, size: CGSize) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        defer { output.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return output }
        let scale = min(size.width / sourceSize.width, size.height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = NSRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        return output
    }

    private static func rolePriority(_ role: AssetFileRole) -> Int {
        switch role {
        case .preview:
            return 0
        case .primary:
            return 1
        default:
            return 2
        }
    }

    private static func isImage(_ file: AssetFile) -> Bool {
        file.mimeType.hasPrefix("image/")
    }

    private static func isImageKind(_ kind: AssetKind) -> Bool {
        switch kind {
        case .imageTexture, .spriteSheet, .tileSet:
            return true
        case .audioClip, .videoClip, .document, .particlePreset, .placeholderAsset, .model3D:
            return false
        }
    }

    private static func isAudio(_ file: AssetFile) -> Bool {
        file.mimeType.hasPrefix("audio/")
    }

    private static func isVideo(_ file: AssetFile) -> Bool {
        file.mimeType.hasPrefix("video/")
    }

    private static func metadataValue(_ key: String, in asset: Asset) -> String {
        asset.metadata.first { $0.key == key }?.value ?? ""
    }
}

private struct AssetPreviewPane: View {
    let asset: Asset
    let playRequestId: UUID?

    @State private var mediaURL: URL?
    @State private var mediaError: String?
    @State private var pendingPlayRequestId: UUID?

    private var previewIdentity: String {
        AssetPreviewData.contentIdentity(for: asset)
    }

    private var previewFilenameStem: String {
        previewIdentity.map { character in
            character.isLetter || character.isNumber || character == "-" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    private var playableFile: AssetFile? {
        AssetPreviewData.playableFile(for: asset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: previewIconName)
                    .font(.system(size: 12))
                    .foregroundColor(previewIconColor)
                Text("Preview")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            previewContent
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .onAppear {
            pendingPlayRequestId = playRequestId
            prepareMediaPreviewIfNeeded()
        }
        .onChange(of: previewIdentity) { _, _ in
            cleanupMediaPreview()
            pendingPlayRequestId = playRequestId
            prepareMediaPreviewIfNeeded()
        }
        .onChange(of: playRequestId) { _, newValue in
            guard newValue != nil else { return }
            pendingPlayRequestId = newValue
            prepareMediaPreviewIfNeeded()
        }
        .onDisappear(perform: cleanupMediaPreview)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch asset.kind {
        case .imageTexture, .spriteSheet, .tileSet:
            imagePreviewOrPlaceholder
        case .audioClip:
            if let mediaURL {
                AssetPreviewPlayer(url: mediaURL, showsVideo: false, playRequestId: pendingPlayRequestId)
                    .frame(height: 96)
                    .id(mediaURL)
            } else {
                placeholder(title: mediaError ?? "Audio preview unavailable", systemImage: "waveform")
                    .frame(height: 96)
            }
        case .videoClip:
            if let mediaURL {
                AssetPreviewPlayer(url: mediaURL, showsVideo: true, playRequestId: pendingPlayRequestId)
                    .frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
                    .id(mediaURL)
            } else {
                placeholder(title: mediaError ?? "Movie preview unavailable", systemImage: "film")
                    .frame(height: 140)
            }
        case .model3D:
            placeholder(
                title: "3D Model",
                subtitle: ByteCountFormatter.string(fromByteCount: Int64(asset.data.count), countStyle: .file),
                systemImage: "cube.transparent",
                color: .indigo
            )
            .frame(height: 120)
        case .particlePreset:
            placeholder(
                title: "Particle Preset",
                subtitle: ByteCountFormatter.string(fromByteCount: Int64(asset.data.count), countStyle: .file),
                systemImage: "sparkles",
                color: .orange
            )
            .frame(height: 120)
        case .placeholderAsset, .document:
            if AssetPreviewData.image(for: asset) != nil {
                imagePreviewOrPlaceholder
            } else if let playableFile, playableFile.mimeType.hasPrefix("audio/") {
                if let mediaURL {
                    AssetPreviewPlayer(url: mediaURL, showsVideo: false, playRequestId: pendingPlayRequestId)
                        .frame(height: 96)
                        .id(mediaURL)
                } else {
                    placeholder(title: mediaError ?? "Audio preview unavailable", systemImage: "waveform")
                        .frame(height: 96)
                }
            } else if let playableFile, playableFile.mimeType.hasPrefix("video/") {
                if let mediaURL {
                    AssetPreviewPlayer(url: mediaURL, showsVideo: true, playRequestId: pendingPlayRequestId)
                        .frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
                        .id(mediaURL)
                } else {
                    placeholder(title: mediaError ?? "Movie preview unavailable", systemImage: "film")
                        .frame(height: 140)
                }
            } else {
                placeholderResourcePreview
            }
        }
    }

    private var imagePreviewOrPlaceholder: some View {
        Group {
            if let image = AssetPreviewData.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
                    .padding(8)
                    .id(previewIdentity)
            } else {
                placeholder(title: "Image preview unavailable", systemImage: "photo")
                    .frame(height: 120)
            }
        }
    }

    private var placeholderResourcePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: asset.mimeType == "application/json" ? "curlybraces.square" : "doc.text")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AssetPreviewData.placeholderTitle(for: asset))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(asset.totalEmbeddedByteCount), countStyle: .file))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if let summary = AssetPreviewData.placeholderSummary(for: asset), !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if let text = AssetPreviewData.textPreview(for: asset), !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewIconName: String {
        switch asset.kind {
        case .imageTexture, .spriteSheet, .tileSet:
            return "photo"
        case .audioClip:
            return "waveform"
        case .videoClip:
            return "film"
        case .model3D:
            return "cube.transparent"
        case .particlePreset:
            return "sparkles"
        case .placeholderAsset:
            return "doc"
        case .document:
            return "doc.text"
        }
    }

    private var previewIconColor: Color {
        switch asset.kind {
        case .audioClip:
            return .purple
        case .videoClip:
            return .blue
        case .model3D:
            return .indigo
        case .particlePreset:
            return .orange
        default:
            return .secondary
        }
    }

    private func placeholder(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        color: Color = .secondary
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    private func prepareMediaPreviewIfNeeded() {
        guard playableFile != nil else { return }
        guard mediaURL == nil else { return }
        do {
            mediaURL = try writeMediaPreviewFile()
            mediaError = nil
        } catch {
            mediaURL = nil
            mediaError = error.localizedDescription
        }
    }

    private func cleanupMediaPreview() {
        guard let url = mediaURL else { return }
        mediaURL = nil
        pendingPlayRequestId = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func writeMediaPreviewFile() throws -> URL {
        guard let playableFile else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeAssetRepositoryPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(previewFilenameStem)
            .appendingPathExtension(Self.fileExtension(for: playableFile))
        try playableFile.data.write(to: url, options: [.atomic])
        return url
    }

    private static func fileExtension(for file: AssetFile) -> String {
        if let contentType = UTType(mimeType: file.mimeType),
           let ext = contentType.preferredFilenameExtension {
            return ext
        }
        if file.mimeType.hasPrefix("audio/") {
            if file.mimeType == "audio/wav" { return "wav" }
            if file.mimeType == "audio/aiff" { return "aiff" }
            if file.mimeType == "audio/mp4" { return "m4a" }
            if file.mimeType == "audio/x-caf" { return "caf" }
            return "mp3"
        }
        if file.mimeType.hasPrefix("video/") {
            if file.mimeType == "video/quicktime" { return "mov" }
            return "mp4"
        }
        return "bin"
    }
}

private struct AssetPreviewPlayer: NSViewRepresentable {
    let url: URL
    let showsVideo: Bool
    let playRequestId: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = showsVideo ? .resizeAspect : .resizeAspect
        view.showsFullScreenToggleButton = showsVideo
        view.allowsPictureInPicturePlayback = showsVideo
        configure(view, context: context)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        configure(nsView, context: context)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        nsView.player = nil
        coordinator.player = nil
        coordinator.url = nil
        coordinator.playRequestId = nil
    }

    private func configure(_ view: AVPlayerView, context: Context) {
        let player: AVPlayer
        if context.coordinator.url == url, let existingPlayer = context.coordinator.player {
            player = existingPlayer
        } else {
            context.coordinator.player?.pause()
            player = AVPlayer(url: url)
            view.player = player
            context.coordinator.player = player
            context.coordinator.url = url
            context.coordinator.playRequestId = nil
        }

        if let playRequestId, context.coordinator.playRequestId != playRequestId {
            context.coordinator.playRequestId = playRequestId
            player.play()
        }
    }

    final class Coordinator {
        var url: URL?
        var player: AVPlayer?
        var playRequestId: UUID?
    }
}
