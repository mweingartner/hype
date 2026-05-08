import AppKit
import MapKit
import CoreLocation
import HypeCore

/// Process-scoped geocoder for map parts. Watches `mapLocation`
/// changes for any map part, debounces them, runs an
/// `MKLocalSearch`, and writes the resolved coordinate back into
/// the document.
///
/// Why this isn't owned by `MapHostNSView` anymore — the previous
/// design embedded the geocode flow inside the live MapKit host,
/// which only exists in browse mode (the canvas tears it down in
/// edit mode, see `CardCanvasView.updateMapViews` early-return on
/// `!isBrowseMode`). That meant: type a new address into the
/// Inspector's Location field while editing → no host → no
/// geocode → map never moves. The same bug bit any HypeTalk or
/// AI-tool setter that ran while the map's host wasn't on screen.
///
/// This service runs regardless of which view (if any) is showing
/// the map. The canvas drives it from a doc-watcher that fires on
/// every `mapLocation` change, in either mode. The renderer (live
/// MKMapView in browse mode, static `MapRenderer` in edit mode)
/// just consumes the resolved `mapCenterLat` / `mapCenterLon`.
@MainActor
final class MapLocationGeocoder {

    /// Process-scoped singleton — the cache it consults
    /// (`MapGeocodeCache.shared`) is also process-scoped, and the
    /// per-partId state we hold needs to survive view recreation
    /// across card switches and inspector toggles.
    static let shared = MapLocationGeocoder()

    /// Per-part state. We key by partId rather than by the live
    /// view because the same part can be observed by multiple
    /// views (canvas + inspector) and switch hosts at any moment.
    private struct Entry {
        /// Pending debounced fire — cancelled if a new query
        /// arrives within `debounceInterval` of the last one.
        var debounceTimer: Timer?
        /// In-flight `MKLocalSearch`. We cancel it if a newer
        /// query arrives so a slow earlier search can't race
        /// ahead of the latest one and clobber the map.
        var activeSearch: MKLocalSearch?
        /// Last query we *successfully resolved* (normalized).
        /// Used to suppress redundant work when the same query
        /// re-fires (e.g. a no-op SwiftUI re-render).
        var lastResolvedQuery: String
    }

    private var entries: [UUID: Entry] = [:]
    private let debounceInterval: TimeInterval = 0.4

    private init() {}

    /// Schedule a debounced geocode for a map part's location string.
    ///
    /// - Parameters:
    ///   - partId: the map part's UUID. Used to track per-part
    ///     debounce state so distinct map parts don't interfere.
    ///   - query: the user-entered address / place name / ZIP.
    ///     Empty string clears any pending request and is a no-op.
    ///   - onResolve: callback invoked on the main thread with the
    ///     resolved coordinate. Failures are silent (logged via
    ///     `HypeLogger`); the callback is not invoked on failure.
    ///     Idempotent: calling with the same `query` for the same
    ///     `partId` after a successful resolve is a no-op.
    func scheduleResolve(
        partId: UUID,
        query: String,
        onResolve: @escaping @Sendable (CLLocationCoordinate2D) -> Void
    ) {
        let normalized = MapGeocodeCache.normalize(query)
        var entry = entries[partId] ?? Entry(debounceTimer: nil, activeSearch: nil, lastResolvedQuery: "")

        // Cancel any prior debounce before deciding what to do.
        entry.debounceTimer?.invalidate()
        entry.debounceTimer = nil

        if normalized.isEmpty {
            // Empty query — cancel any pending work but don't
            // touch the part's coords. The user might be clearing
            // the field temporarily; the map keeps its last
            // known position.
            entries[partId] = entry
            return
        }

        if normalized == entry.lastResolvedQuery {
            // Same query we already successfully resolved.
            // Re-firing the network request would be wasted work
            // (and could trip Apple's rate limiter for hot loops).
            // The map's coords are already correct in the doc.
            entries[partId] = entry
            return
        }

        // Schedule the debounced resolve.
        entry.debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runResolve(partId: partId, query: query, onResolve: onResolve)
            }
        }
        entries[partId] = entry
    }

    /// Forget a part — cancels its pending debounce and any
    /// in-flight `MKLocalSearch`. Called when a map part is
    /// deleted so we don't hold a stale Timer / cancellation
    /// closure.
    func forget(partId: UUID) {
        guard var entry = entries[partId] else { return }
        entry.debounceTimer?.invalidate()
        entry.activeSearch?.cancel()
        entries.removeValue(forKey: partId)
    }

    // MARK: - Internals

    private func runResolve(
        partId: UUID,
        query: String,
        onResolve: @escaping @Sendable (CLLocationCoordinate2D) -> Void
    ) {
        // Cache hit: skip the network round-trip entirely.
        if let cached = MapGeocodeCache.shared.cachedCoordinate(for: query) {
            applyResolved(partId: partId, query: query, coordinate: cached, onResolve: onResolve)
            return
        }
        // Recent failure: the negative cache short-circuits retries
        // for 60s so we don't hammer Apple after a not-found result.
        if MapGeocodeCache.shared.isRecentlyFailed(query) {
            return
        }

        var entry = entries[partId] ?? Entry(debounceTimer: nil, activeSearch: nil, lastResolvedQuery: "")

        // Cancel any prior in-flight search for THIS part. Other
        // parts' searches are independent.
        entry.activeSearch?.cancel()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        let search = MKLocalSearch(request: request)
        entry.activeSearch = search
        entries[partId] = entry

        search.start { [weak self] response, error in
            // Apple documents `start(completionHandler:)` as
            // dispatching the callback on the main thread, but
            // belt-and-suspenders: hop explicitly so our actor
            // assumptions hold.
            DispatchQueue.main.async {
                guard let self = self else { return }
                // If we already cancelled this search (because a
                // newer query came in), the stored activeSearch
                // is no longer === this one. Treat it as stale and
                // do nothing — no negative-cache poisoning for a
                // query the user may still want to retry.
                let stillCurrent = (self.entries[partId]?.activeSearch === search)
                if stillCurrent {
                    self.entries[partId]?.activeSearch = nil
                } else {
                    return
                }

                if let error = error {
                    let ns = error as NSError
                    if ns.domain == MKErrorDomain,
                       ns.code == MKError.Code.placemarkNotFound.rawValue {
                        HypeLogger.shared.info(
                            "MapLocationGeocoder: no match for '\(query)'",
                            source: "MapGeocode"
                        )
                    } else {
                        HypeLogger.shared.error(
                            "MapLocationGeocoder: MKLocalSearch error for '\(query)': "
                                + "\(error.localizedDescription) "
                                + "(domain=\(ns.domain) code=\(ns.code))",
                            source: "MapGeocode"
                        )
                    }
                    MapGeocodeCache.shared.recordFailure(for: query)
                    return
                }
                guard let coord = response?.mapItems.first?.placemark.coordinate else {
                    MapGeocodeCache.shared.recordFailure(for: query)
                    return
                }
                MapGeocodeCache.shared.recordHit(for: query, coordinate: coord)
                self.applyResolved(partId: partId, query: query, coordinate: coord, onResolve: onResolve)
            }
        }
    }

    private func applyResolved(
        partId: UUID,
        query: String,
        coordinate: CLLocationCoordinate2D,
        onResolve: @Sendable (CLLocationCoordinate2D) -> Void
    ) {
        var entry = entries[partId] ?? Entry(debounceTimer: nil, activeSearch: nil, lastResolvedQuery: "")
        entry.lastResolvedQuery = MapGeocodeCache.normalize(query)
        entries[partId] = entry
        onResolve(coordinate)
    }
}
