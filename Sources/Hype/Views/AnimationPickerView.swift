import SwiftUI
import HypeCore

// MARK: - AnimationPickerView

/// SwiftUI sheet for picking a Meshy animation action.
///
/// Presented after `RigAndAnimateFlow.runRigging` completes. Lists all entries
/// from `MeshyAnimationCatalog` grouped by category, with type-to-search
/// filtering by name / subcategory / category.
///
/// Per user decision #4, animations are user-selected — this sheet is the gate.
/// The user can also press "Skip animation" to keep just the rigged base model
/// with its built-in walk/run clips (i.e. `onPick(nil)`).
///
/// No preview GIFs are fetched in Phase 3 — rows show action id, display name,
/// and subcategory only. Phase 4 may add lazy GIF loading.
///
/// State machine:
///   `.loading` — catalog is being loaded from the bundle (typically < 50 ms)
///   `.ready`   — showing the picker list
///   `.error(message)` — catalog failed to load (bundle resource missing / malformed)
public struct AnimationPickerView: View {

    /// Called when the user confirms a pick. `nil` means "skip animation"
    /// (proceed with the rigged base model only).
    public var onPick: (MeshyAnimationEntry?) -> Void
    /// Called when the user cancels the flow entirely (dismisses without picking).
    public var onCancel: () -> Void

    // MARK: - View state

    @State private var phase: Phase = .loading
    @State private var searchText: String = ""
    @State private var selectedId: MeshyActionId? = nil
    @State private var loadError: String? = nil

    // MARK: - State machine

    enum Phase: Equatable {
        case loading
        case ready
        case error(String)
    }

    // MARK: - Init

    public init(
        onPick: @escaping (MeshyAnimationEntry?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                Text("Pick an Animation")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // MARK: Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search animations…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: Body
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading animations…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready:
                    catalogBody()

                case .error(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            loadCatalog()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // MARK: Footer
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button("Skip animation") {
                    onPick(nil)
                }
                .help("Use the rigged model without an additional animation")
                Button("Apply") {
                    applySelection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedId == nil)
            }
            .padding()
        }
        .frame(width: 640, height: 540)
        .task {
            loadCatalog()
        }
    }

    // MARK: - Catalog list body

    @ViewBuilder
    private func catalogBody() -> some View {
        let groups = filteredGroups()
        if groups.isEmpty {
            VStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("No animations match \"\(searchText)\"")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.category) { group in
                        DisclosureGroup(
                            isExpanded: .constant(true),
                            content: {
                                ForEach(group.entries, id: \.id) { entry in
                                    animationRow(entry)
                                }
                            },
                            label: {
                                Text(group.category)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func animationRow(_ entry: MeshyAnimationEntry) -> some View {
        let isSelected = selectedId == entry.id
        HStack(spacing: 8) {
            // Action id badge
            Text("\(entry.id.value)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)

            // Display name (underscores → spaces)
            Text(entry.displayName)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Subcategory
            Text(entry.subCategory)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Checkmark for selected
            Image(systemName: isSelected ? "checkmark" : "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedId = entry.id
        }
    }

    // MARK: - Filtering

    /// Filter entries by `searchText` (case-insensitive substring) and
    /// return grouped results, preserving the catalog's category order.
    ///
    /// Called synchronously from the view body — the catalog is pre-loaded
    /// and held in `MeshyAnimationCatalog.shared` (actor) via the `.task`
    /// startup. Because the actor is read via `filteredGroups()` on the
    /// main actor, we access the snapshot loaded during `loadCatalog`.
    private func filteredGroups() -> [(category: String, entries: [MeshyAnimationEntry])] {
        guard case .ready = phase else { return [] }
        guard let groups = _loadedGroups else { return [] }
        guard !searchText.isEmpty else { return groups }
        let lower = searchText.lowercased()
        return groups.compactMap { group in
            let filtered = group.entries.filter {
                $0.name.lowercased().contains(lower)
                || $0.subCategory.lowercased().contains(lower)
                || $0.category.lowercased().contains(lower)
            }
            return filtered.isEmpty ? nil : (category: group.category, entries: filtered)
        }
    }

    // MARK: - Private state for pre-loaded groups

    /// Snapshot of grouped entries, loaded once from the actor.
    @State private var _loadedGroups: [(category: String, entries: [MeshyAnimationEntry])]? = nil

    // MARK: - Actions

    private func loadCatalog() {
        phase = .loading
        Task {
            do {
                let groups = try await MeshyAnimationCatalog.shared.grouped()
                await MainActor.run {
                    _loadedGroups = groups
                    phase = .ready
                }
            } catch {
                await MainActor.run {
                    phase = .error("The animation catalog couldn't be loaded. Reinstall Hype to restore it.")
                }
            }
        }
    }

    private func applySelection() {
        guard let id = selectedId else { return }
        Task {
            if let entry = try? await MeshyAnimationCatalog.shared.entry(forActionId: id) {
                await MainActor.run {
                    onPick(entry)
                }
            }
        }
    }
}
