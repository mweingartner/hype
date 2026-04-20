import Foundation

// MARK: - WebAssetSession

/// Per-chat-panel actor that caches `WebAssetSearchResult` entries against
/// short candidate-id strings, and enforces a per-turn soft cap on web-asset
/// tool dispatches.
///
/// **Lifetime**: one session per open chat panel instance. Destroyed on panel
/// close. `reset()` called by `clearChat()`.
///
/// **Per-turn soft cap** (Security Finding 11): `beginTurn()` is called by
/// `HypeToolExecutor` / `AIChatPanel.processWithTools` once at the start of
/// each tool-loop invocation. `shouldAllowDispatch()` is called inside each
/// web-asset tool branch and returns `false` once the per-turn ceiling is
/// reached, preventing runaway tool loops.
public actor WebAssetSession {

    /// Per-turn soft cap on web-asset tool dispatches.
    public static let maxDispatchesPerTurn: Int = 20

    // MARK: - Candidate cache

    /// Maps candidate-id → search result.
    private var candidateByID: [String: WebAssetSearchResult] = [:]
    /// Maps candidate-id → originating query (used to populate `searchQuery` in provenance).
    private var queryByID: [String: String] = [:]
    /// Maps query → list of candidate-ids from that search.
    private var idsByQuery: [String: [String]] = [:]

    // MARK: - Per-turn dispatch counter

    private var dispatchesThisTurn: Int = 0

    // MARK: - Init

    public init() {}

    // MARK: - Candidate management

    /// Record a set of search results, associating each with `query`.
    ///
    /// - Returns: The candidate-id strings assigned to the results, in the same order.
    public func recordSearch(query: String, results: [WebAssetSearchResult]) -> [String] {
        let ids = results.map { $0.id }
        // Index each result
        for result in results {
            candidateByID[result.id] = result
            queryByID[result.id] = query
        }
        idsByQuery[query] = ids
        return ids
    }

    /// Return the search result for a candidate-id, or nil if unknown.
    public func candidate(id: String) -> WebAssetSearchResult? {
        candidateByID[id]
    }

    /// Return the originating search query for a candidate-id, or nil if unknown.
    public func queryForCandidate(id: String) -> String? {
        queryByID[id]
    }

    /// Return all candidates recorded for a given query.
    public func candidates(forQuery query: String) -> [WebAssetSearchResult] {
        (idsByQuery[query] ?? []).compactMap { candidateByID[$0] }
    }

    /// Clear all candidate data and reset the per-turn counter.
    public func reset() {
        candidateByID.removeAll()
        queryByID.removeAll()
        idsByQuery.removeAll()
        dispatchesThisTurn = 0
    }

    // MARK: - Per-turn soft cap

    /// Reset the per-turn dispatch counter to zero.
    ///
    /// Called by `AIChatPanel.processWithTools` (or its executor) at the start
    /// of each `processWithTools` invocation — before the tool dispatch loop.
    public func beginTurn() {
        dispatchesThisTurn = 0
    }

    /// Check whether a web-asset dispatch is allowed in the current turn.
    ///
    /// Increments the counter and returns `true` while the per-turn ceiling
    /// has not been reached. Returns `false` (without incrementing) once
    /// `maxDispatchesPerTurn` dispatches have already occurred.
    ///
    /// - Returns: `true` if the dispatch should proceed; `false` if the soft
    ///   cap has been hit and the caller should return the refusal string.
    public func shouldAllowDispatch() -> Bool {
        if dispatchesThisTurn >= Self.maxDispatchesPerTurn { return false }
        dispatchesThisTurn += 1
        return true
    }
}
