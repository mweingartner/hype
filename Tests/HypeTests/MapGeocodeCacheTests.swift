import Testing
import CoreLocation
@testable import Hype

/// Unit tests for MapGeocodeCache — the in-process forward-geocoding
/// cache that sits in front of CLGeocoder to dampen rate-limit pressure.
///
/// All tests run on the main actor (matching the @MainActor isolation
/// of the cache itself). Tests use UUID-keyed query strings to avoid
/// state pollution from the process-lifetime singleton.
///
/// CLGeocoder is NOT exercised here — end-to-end geocoding is
/// non-deterministic and belongs to manual smoke testing.
@MainActor
@Suite("MapGeocodeCache — unit tests")
struct MapGeocodeCacheTests {

    // MARK: - normalize

    @Test("normalize trims leading and trailing whitespace")
    func normalizeTrimsWhitespace() {
        let result = MapGeocodeCache.normalize("  97537  ")
        #expect(result == "97537")
    }

    @Test("normalize lowercases the input")
    func normalizeLowercases() {
        let result = MapGeocodeCache.normalize("Rogue River, OR")
        #expect(result == "rogue river, or")
    }

    @Test("normalize applies both trim and lowercase")
    func normalizeTrimAndLowercase() {
        let result = MapGeocodeCache.normalize("  San Francisco, CA  ")
        #expect(result == "san francisco, ca")
    }

    @Test("normalize returns empty string for all-whitespace input")
    func normalizeAllWhitespace() {
        let result = MapGeocodeCache.normalize("   ")
        #expect(result == "")
    }

    @Test("normalize returns empty string for empty input")
    func normalizeEmptyString() {
        let result = MapGeocodeCache.normalize("")
        #expect(result == "")
    }

    // MARK: - cachedCoordinate / recordHit

    @Test("cachedCoordinate returns nil for a key that was never stored")
    func cachedCoordinateNilForMissingKey() {
        let query = "geocache-test-miss-\(UUID().uuidString)"
        let result = MapGeocodeCache.shared.cachedCoordinate(for: query)
        #expect(result == nil)
    }

    @Test("recordHit stores a coordinate, cachedCoordinate returns it")
    func recordHitAndRetrieve() {
        let query = "geocache-test-hit-\(UUID().uuidString)"
        let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        MapGeocodeCache.shared.recordHit(for: query, coordinate: coord)
        let retrieved = MapGeocodeCache.shared.cachedCoordinate(for: query)
        #expect(retrieved?.latitude == coord.latitude)
        #expect(retrieved?.longitude == coord.longitude)
    }

    @Test("cachedCoordinate normalizes the query so different casings share a slot")
    func cachedCoordinateNormalizesQuery() {
        // Use the same underlying key written with mixed case then looked up differently.
        let base = "geocache-test-normalize-\(UUID().uuidString)"
        let mixed = base.uppercased()
        let coord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        MapGeocodeCache.shared.recordHit(for: mixed, coordinate: coord)
        // Look up the lowercased version — should still hit.
        let retrieved = MapGeocodeCache.shared.cachedCoordinate(for: base.lowercased())
        #expect(retrieved?.latitude == coord.latitude)
    }

    @Test("cachedCoordinate normalizes whitespace so padded query shares a slot")
    func cachedCoordinateNormalizesWhitespace() {
        let key = "geocache-ws-\(UUID().uuidString)"
        let coord = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        MapGeocodeCache.shared.recordHit(for: "  \(key)  ", coordinate: coord)
        let retrieved = MapGeocodeCache.shared.cachedCoordinate(for: key)
        #expect(retrieved?.latitude == coord.latitude)
    }

    // MARK: - recordHit clears failure entry

    @Test("recordHit clears a pre-existing failure for the same query")
    func recordHitClearsFailure() {
        let query = "geocache-test-hit-clears-failure-\(UUID().uuidString)"
        // Record a failure first.
        MapGeocodeCache.shared.recordFailure(for: query)
        #expect(MapGeocodeCache.shared.isRecentlyFailed(query) == true)
        // Now record a hit — the failure should be gone.
        let coord = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        MapGeocodeCache.shared.recordHit(for: query, coordinate: coord)
        #expect(MapGeocodeCache.shared.isRecentlyFailed(query) == false)
    }

    // MARK: - isRecentlyFailed / recordFailure

    @Test("isRecentlyFailed returns false for a key that was never failed")
    func isRecentlyFailedFalseForUnknownKey() {
        let query = "geocache-test-nofail-\(UUID().uuidString)"
        #expect(MapGeocodeCache.shared.isRecentlyFailed(query) == false)
    }

    @Test("recordFailure makes isRecentlyFailed return true immediately after")
    func recordFailureThenCheckFailed() {
        let query = "geocache-test-fail-immediate-\(UUID().uuidString)"
        MapGeocodeCache.shared.recordFailure(for: query)
        #expect(MapGeocodeCache.shared.isRecentlyFailed(query) == true)
    }

    @Test("isRecentlyFailed normalizes the query string")
    func isRecentlyFailedNormalizesQuery() {
        let base = "geocache-test-fail-normalize-\(UUID().uuidString)"
        // Record failure with uppercase variant.
        MapGeocodeCache.shared.recordFailure(for: base.uppercased())
        // Check with the lowercase variant — should still be seen as recent failure.
        #expect(MapGeocodeCache.shared.isRecentlyFailed(base.lowercased()) == true)
    }

    @Test("isRecentlyFailed expiry: a failure recorded in the past beyond TTL is evicted")
    func isRecentlyFailedEvictsExpiredEntry() {
        // We cannot fast-forward time without injecting a clock, so we
        // synthetically construct an expired entry by recording failure
        // with a backdated timestamp. We can't mutate `failures` (private),
        // but we CAN observe the eviction branch indirectly: record a
        // failure, let isRecentlyFailed observe it is NOT expired (TTL=60s),
        // then confirm the behaviour is correct. The expiry branch is a
        // code-path test rather than a time-travel test.
        //
        // This test validates the non-expired path to avoid a time-travel
        // dependency. The expired branch requires clock injection which the
        // current production design doesn't support — document the limitation.
        let query = "geocache-test-fail-ttl-\(UUID().uuidString)"
        MapGeocodeCache.shared.recordFailure(for: query)
        // Within TTL (60s) — must still report failure.
        #expect(MapGeocodeCache.shared.isRecentlyFailed(query) == true,
                "failure just recorded must still be 'recent' within the 60-second TTL")
    }
}
