import Foundation
import CoreLocation

/// In-process forward-geocoding cache keyed by the user-entered
/// location string (case- and whitespace-normalized). Holds
/// successfully-resolved coordinates AND a small set of recent
/// failures so we don't re-issue a request that just failed.
///
/// CLGeocoder rate-limits aggressively. Without this cache, every
/// card switch would re-resolve the same string and easily trip
/// the rate limiter, which silently fails the next N requests.
///
/// Process-lifetime only — not persisted to disk. Cleared on
/// app relaunch. The lat/lon already in the document remains
/// authoritative regardless.
@MainActor
final class MapGeocodeCache {
    static let shared = MapGeocodeCache()

    private var hits: [String: CLLocationCoordinate2D] = [:]
    private var failures: [String: Date] = [:]
    private let failureTTL: TimeInterval = 60

    private init() {}

    /// Lowercase + trim whitespace. Mirrors HypeTalk's
    /// case-insensitive name matching so "97537" and " 97537 "
    /// share a cache slot.
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func cachedCoordinate(for query: String) -> CLLocationCoordinate2D? {
        hits[Self.normalize(query)]
    }

    func recordHit(for query: String, coordinate: CLLocationCoordinate2D) {
        let key = Self.normalize(query)
        hits[key] = coordinate
        failures.removeValue(forKey: key)
    }

    func isRecentlyFailed(_ query: String) -> Bool {
        let key = Self.normalize(query)
        guard let when = failures[key] else { return false }
        if Date().timeIntervalSince(when) > failureTTL {
            failures.removeValue(forKey: key)
            return false
        }
        return true
    }

    func recordFailure(for query: String) {
        failures[Self.normalize(query)] = Date()
    }
}
