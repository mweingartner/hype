import Foundation

// MARK: - MeshyAnimationCatalog

/// Session-scoped catalog of Meshy animation actions.
///
/// Loads `MeshyAnimationCatalog.json` from the HypeCore module bundle on
/// first access, then holds the parsed `[MeshyAnimationEntry]` in memory for
/// the lifetime of the process. There is NO on-disk app-data cache and NO
/// pre-population at app launch — the catalog is loaded only when the user
/// first opens the animation picker (user decision #4).
///
/// Threading: actor-isolated. Concurrent calls to `entries()` are safe;
/// the JSON file is parsed at most once per process.
///
/// Memory budget: ~50 entries × ~200 bytes each ≈ 10 KB. Acceptable to
/// hold in RAM for the session lifetime.
///
/// The catalog ships with the app bundle as a static JSON resource because
/// Meshy provides no public API to enumerate available animations. The
/// resource was hand-curated from `docs.meshy.ai/en/api/animation-library`
/// on 2026-05-11 and covers the most common animation categories.
public actor MeshyAnimationCatalog {

    // MARK: - Singleton

    public static let shared = MeshyAnimationCatalog()

    // MARK: - Private state

    /// Bundle that contains `MeshyAnimationCatalog.json`. Defaults to
    /// HypeCore's module bundle; tests can inject a different bundle.
    private let bundle: Bundle
    private let resourceName: String
    private var cached: [MeshyAnimationEntry]?

    // MARK: - Init

    /// Production init — uses the HypeCore module bundle when `bundle` is nil.
    ///
    /// `Bundle.module` cannot be referenced from a public default-argument
    /// expression in Swift 6, so we resolve it inside the initializer body.
    public init(bundle: Bundle? = nil, resourceName: String = "MeshyAnimationCatalog") {
        self.bundle = bundle ?? .module
        self.resourceName = resourceName
    }

    // MARK: - Public API

    /// Returns the full list, loading from the bundle on first call.
    ///
    /// - Throws: `MeshyError.catalogUnavailable` if the JSON resource is
    ///   missing or malformed.
    public func entries() async throws -> [MeshyAnimationEntry] {
        if let cached { return cached }
        let loaded = try loadFromBundle()
        cached = loaded
        return loaded
    }

    /// Lookup by numeric action id.
    public func entry(forActionId actionId: MeshyActionId) async throws -> MeshyAnimationEntry? {
        let all = try await entries()
        return all.first { $0.id == actionId }
    }

    /// Search by name / category / subcategory (case-insensitive substring).
    /// Returns at most `limit` matches.
    public func search(query: String, limit: Int = 200) async throws -> [MeshyAnimationEntry] {
        let all = try await entries()
        guard !query.isEmpty else { return Array(all.prefix(limit)) }
        let lower = query.lowercased()
        return Array(
            all.filter {
                $0.name.lowercased().contains(lower)
                || $0.category.lowercased().contains(lower)
                || $0.subCategory.lowercased().contains(lower)
            }
            .prefix(limit)
        )
    }

    /// Group all entries by category in display order (insertion order from JSON).
    public func grouped() async throws -> [(category: String, entries: [MeshyAnimationEntry])] {
        let all = try await entries()
        // Preserve first-seen order of categories.
        var seen: [String] = []
        var groups: [String: [MeshyAnimationEntry]] = [:]
        for entry in all {
            if groups[entry.category] == nil {
                seen.append(entry.category)
                groups[entry.category] = []
            }
            groups[entry.category]!.append(entry)
        }
        return seen.compactMap { category in
            guard let entries = groups[category] else { return nil }
            return (category: category, entries: entries)
        }
    }

    /// Test-only override: inject entries directly to bypass bundle loading.
    package func setCachedEntries(_ entries: [MeshyAnimationEntry]) {
        self.cached = entries
    }

    // MARK: - Private

    private func loadFromBundle() throws -> [MeshyAnimationEntry] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw MeshyError.catalogUnavailable
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode([MeshyAnimationEntry].self, from: data)
        } catch {
            throw MeshyError.catalogUnavailable
        }
    }
}
