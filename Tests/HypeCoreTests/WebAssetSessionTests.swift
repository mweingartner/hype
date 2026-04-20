import Testing
import Foundation
@testable import HypeCore

/// Tests for `WebAssetSession` — candidate cache and per-turn soft cap.
@Suite("WebAssetSession — candidate cache and soft cap")
struct WebAssetSessionTests {

    // MARK: - Helpers

    private func makeResult(id: String, title: String = "Test") -> WebAssetSearchResult {
        WebAssetSearchResult(
            id: id,
            title: title,
            thumbnailURL: nil,
            downloadURL: URL(string: "https://example.com/\(id).png")!,
            mimeType: "image/png",
            width: 100,
            height: 100,
            fileSizeBytes: nil,
            license: AssetLicense(name: "CC0", identifier: "cc0", url: "", isShareable: true),
            attribution: AssetAttribution(
                creator: "Author",
                title: title,
                sourceURL: "https://example.com",
                downloadURL: "https://example.com/\(id).png",
                providerName: "Openverse",
                providerIdentifier: "openverse"
            ),
            providerRaw: .openverse
        )
    }

    // MARK: - recordSearch returns IDs

    @Test("recordSearch returns candidate IDs matching the result IDs")
    func recordSearchReturnsCandidateIDs() async {
        let session = WebAssetSession()
        let results = [
            makeResult(id: "abc1"),
            makeResult(id: "def2"),
            makeResult(id: "ghi3")
        ]
        let ids = await session.recordSearch(query: "cat", results: results)
        #expect(ids == ["abc1", "def2", "ghi3"])
    }

    @Test("recordSearch with empty results returns empty array")
    func recordSearchEmptyResultsReturnsEmpty() async {
        let session = WebAssetSession()
        let ids = await session.recordSearch(query: "cat", results: [])
        #expect(ids.isEmpty)
    }

    // MARK: - candidate(id:) retrieval

    @Test("candidate(id:) returns stored result for known ID")
    func candidateForKnownIDReturnsResult() async {
        let session = WebAssetSession()
        let result = makeResult(id: "abc1", title: "A cat photo")
        _ = await session.recordSearch(query: "cat", results: [result])

        let found = await session.candidate(id: "abc1")
        #expect(found != nil)
        #expect(found?.title == "A cat photo")
        #expect(found?.id == "abc1")
    }

    @Test("candidate(id:) returns nil for unknown ID")
    func candidateForUnknownIDReturnsNil() async {
        let session = WebAssetSession()
        let found = await session.candidate(id: "unknown_id")
        #expect(found == nil)
    }

    // MARK: - queryForCandidate(id:)

    @Test("queryForCandidate returns the originating query for a known candidate")
    func queryForCandidateReturnsQuery() async {
        let session = WebAssetSession()
        let result = makeResult(id: "xyz9")
        _ = await session.recordSearch(query: "fluffy cat", results: [result])

        let query = await session.queryForCandidate(id: "xyz9")
        #expect(query == "fluffy cat")
    }

    @Test("queryForCandidate returns nil for unknown ID")
    func queryForCandidateUnknownReturnsNil() async {
        let session = WebAssetSession()
        let query = await session.queryForCandidate(id: "nonexistent")
        #expect(query == nil)
    }

    // MARK: - candidates(forQuery:)

    @Test("candidates(forQuery:) returns all results for a given query")
    func candidatesForQueryReturnsAll() async {
        let session = WebAssetSession()
        let results = [
            makeResult(id: "a1", title: "Alpha"),
            makeResult(id: "b2", title: "Beta")
        ]
        _ = await session.recordSearch(query: "test", results: results)

        let candidates = await session.candidates(forQuery: "test")
        #expect(candidates.count == 2)
        let titles = candidates.map { $0.title }.sorted()
        #expect(titles == ["Alpha", "Beta"])
    }

    @Test("candidates(forQuery:) returns empty for unknown query")
    func candidatesForUnknownQueryReturnsEmpty() async {
        let session = WebAssetSession()
        let candidates = await session.candidates(forQuery: "nonexistent query")
        #expect(candidates.isEmpty)
    }

    // MARK: - beginTurn and shouldAllowDispatch

    @Test("shouldAllowDispatch returns true for first 20 calls")
    func shouldAllowDispatch20Times() async {
        let session = WebAssetSession()
        await session.beginTurn()

        var count = 0
        for _ in 0..<20 {
            let allowed = await session.shouldAllowDispatch()
            if allowed { count += 1 }
        }
        #expect(count == 20)
    }

    @Test("shouldAllowDispatch returns false on the 21st call")
    func shouldAllowDispatch21stReturnsFalse() async {
        let session = WebAssetSession()
        await session.beginTurn()

        for _ in 0..<20 {
            _ = await session.shouldAllowDispatch()
        }
        let blocked = await session.shouldAllowDispatch()
        #expect(blocked == false)
    }

    @Test("shouldAllowDispatch returns false on subsequent calls past the cap")
    func shouldAllowDispatchContinuesToBlock() async {
        let session = WebAssetSession()
        await session.beginTurn()

        for _ in 0..<20 {
            _ = await session.shouldAllowDispatch()
        }
        // Multiple calls past the cap all return false
        for _ in 0..<5 {
            let allowed = await session.shouldAllowDispatch()
            #expect(allowed == false)
        }
    }

    @Test("beginTurn resets the dispatch counter to zero")
    func beginTurnResetsCounter() async {
        let session = WebAssetSession()
        await session.beginTurn()

        // Exhaust the cap
        for _ in 0..<20 {
            _ = await session.shouldAllowDispatch()
        }
        #expect(await session.shouldAllowDispatch() == false)

        // Reset
        await session.beginTurn()

        // Now counter is reset — 20 new dispatches allowed
        var count = 0
        for _ in 0..<20 {
            if await session.shouldAllowDispatch() { count += 1 }
        }
        #expect(count == 20)
    }

    @Test("maxDispatchesPerTurn is 20")
    func maxDispatchesPerTurnIs20() {
        #expect(WebAssetSession.maxDispatchesPerTurn == 20)
    }

    // MARK: - reset()

    @Test("reset() clears all candidate data")
    func resetClearsCandidates() async {
        let session = WebAssetSession()
        let result = makeResult(id: "test1")
        _ = await session.recordSearch(query: "cat", results: [result])

        // Verify it's stored
        #expect(await session.candidate(id: "test1") != nil)

        await session.reset()

        // After reset, should be gone
        #expect(await session.candidate(id: "test1") == nil)
        #expect(await session.queryForCandidate(id: "test1") == nil)
        #expect(await session.candidates(forQuery: "cat").isEmpty)
    }

    @Test("reset() resets the per-turn dispatch counter")
    func resetResetsDispatchCounter() async {
        let session = WebAssetSession()
        await session.beginTurn()

        // Exhaust cap
        for _ in 0..<20 {
            _ = await session.shouldAllowDispatch()
        }
        #expect(await session.shouldAllowDispatch() == false)

        await session.reset()

        // Counter should be reset to 0
        let allowed = await session.shouldAllowDispatch()
        #expect(allowed == true)
    }

    // MARK: - Multiple queries accumulate independently

    @Test("multiple recordSearch calls for different queries accumulate independently")
    func multipleQueriesAccumulate() async {
        let session = WebAssetSession()

        let cats = [makeResult(id: "cat1"), makeResult(id: "cat2")]
        let dogs = [makeResult(id: "dog1")]

        _ = await session.recordSearch(query: "cat", results: cats)
        _ = await session.recordSearch(query: "dog", results: dogs)

        let catCandidates = await session.candidates(forQuery: "cat")
        let dogCandidates = await session.candidates(forQuery: "dog")

        #expect(catCandidates.count == 2)
        #expect(dogCandidates.count == 1)

        // Cross-query lookups work by ID
        #expect(await session.candidate(id: "cat1") != nil)
        #expect(await session.candidate(id: "dog1") != nil)
    }

    @Test("recordSearch for same query overwrites previous IDs list")
    func recordSearchSameQueryOverwrites() async {
        let session = WebAssetSession()

        let first = [makeResult(id: "first1"), makeResult(id: "first2")]
        _ = await session.recordSearch(query: "cat", results: first)

        let second = [makeResult(id: "second1")]
        _ = await session.recordSearch(query: "cat", results: second)

        // The query index is overwritten — only second result listed for query
        let candidates = await session.candidates(forQuery: "cat")
        #expect(candidates.count == 1)
        #expect(candidates[0].id == "second1")

        // But the first results are still accessible by direct ID lookup
        // (they remain in candidateByID)
        #expect(await session.candidate(id: "first1") != nil)
    }
}
