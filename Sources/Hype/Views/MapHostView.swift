import AppKit
import MapKit
import HypeCore

/// AppKit-hosted MapKit view for `map` parts.
///
/// Re-renders annotations whenever `mapAnnotationsJSON` changes;
/// re-centers/zooms whenever the part's center/span fields change.
/// Map type updates apply on the next frame.
///
/// `showsUserLocation` is intentionally NOT exposed in v1 — that
/// path requires `NSLocationUsageDescription` and a Core Location
/// authorization round-trip we'd rather not add to every Hype
/// install. v2 can add it as an opt-in property.
final class MapHostNSView: NSView, MKMapViewDelegate {

    let mapView = MKMapView()
    private var loadedAnnotationsJSON: String = ""

    /// Fired after a successful forward-geocode. The closure
    /// receives the resolved (lat, lon) which the coordinator
    /// writes back into the part so HypeTalk reads + save/load
    /// see the new authoritative coords. Mirrors
    /// `CalendarHostNSView.onDateChange` and
    /// `ColorWellHostNSView.onColorChange`.
    var onLocationResolved: ((Double, Double) -> Void)?

    /// Last-applied normalized location string — compare-and-skip
    /// so apply() doesn't re-issue a geocode on every redraw.
    private var appliedLocation: String = ""

    /// Last-applied lat/lon/span. Without these, `apply()` would
    /// unconditionally `setRegion(...)` on every redraw — including
    /// the apply() call that arrives mid-geocode while the user is
    /// still typing in the Location field. That snaps the map back
    /// to whatever stale lat/lon is stored in the document and
    /// clobbers the just-geocoded coordinates from
    /// `applyResolvedCoordinate(...)`. Tracking applied state lets
    /// us skip the redundant setRegion when the coords haven't
    /// actually changed.
    private var appliedLat: Double = .nan
    private var appliedLon: Double = .nan
    private var appliedSpan: Double = .nan
    private var appliedMapType: String = ""

    /// Active in-flight `MKLocalSearch`, if any. `MKLocalSearch`
    /// replaces `CLGeocoder` (which Apple deprecated in macOS 26
    /// with the explicit advice "Use MapKit"). Held as an instance
    /// property so we can `cancel()` if the host is torn down or
    /// the user types a new address before the previous resolves.
    private var activeSearch: MKLocalSearch?

    /// Debounce timer — the inspector's TextField binding writes
    /// back on every keystroke, so without debouncing we'd issue
    /// an MKLocalSearch request per character ("E" → "Ei" → "Eif"
    /// → ...) and Apple's rate limiter would silently fail most of
    /// them. We wait `debounceInterval` seconds after the last
    /// change before actually calling the search.
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        if part.mapType != appliedMapType {
            mapView.mapType = Self.mapType(for: part.mapType)
            appliedMapType = part.mapType
        }

        // Compare-and-skip the region update. Without this, every
        // keystroke in the inspector's Location field re-triggers
        // apply() and snaps the map back to whatever lat/lon is in
        // the doc — clobbering the just-geocoded coordinates from
        // `applyResolvedCoordinate(...)`. We only call setRegion
        // when the doc's lat/lon/span changed since we last applied.
        let needsRegionUpdate =
            part.mapCenterLat != appliedLat ||
            part.mapCenterLon != appliedLon ||
            part.mapSpan != appliedSpan
        if needsRegionUpdate {
            let center = CLLocationCoordinate2D(latitude: part.mapCenterLat, longitude: part.mapCenterLon)
            let span = MKCoordinateSpan(
                latitudeDelta: max(0.0001, part.mapSpan),
                longitudeDelta: max(0.0001, part.mapSpan)
            )
            mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
            appliedLat = part.mapCenterLat
            appliedLon = part.mapCenterLon
            appliedSpan = part.mapSpan
        }

        // Forward-geocode the user-entered location string whenever
        // it changes from what we last applied. The cache (process-
        // singleton, 60s negative TTL) absorbs repeat opens and
        // navigation-induced host recreations so we don't hammer
        // Apple. The compare-and-skip on `appliedLocation` is
        // initialized to "" on host creation, so the first apply
        // with a non-empty location WILL fire a geocode — necessary
        // because the host is destroyed/recreated on card transitions
        // and inspector toggles, and the user expects the displayed
        // map to match the part's stored location string regardless.
        let normalizedLocation = MapGeocodeCache.normalize(part.mapLocation)
        if normalizedLocation != appliedLocation {
            appliedLocation = normalizedLocation
            if !normalizedLocation.isEmpty {
                scheduleGeocode(part.mapLocation)
            } else {
                // Cleared — cancel any pending debounce.
                debounceTimer?.invalidate()
                debounceTimer = nil
            }
        }

        // Re-build annotations only when the JSON actually changed —
        // saves an MKMapView teardown on every property tick.
        if part.mapAnnotationsJSON != loadedAnnotationsJSON {
            loadedAnnotationsJSON = part.mapAnnotationsJSON
            mapView.removeAnnotations(mapView.annotations)
            for anno in Self.parseAnnotations(part.mapAnnotationsJSON) {
                let pin = MKPointAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: anno.lat, longitude: anno.lon)
                pin.title = anno.title
                mapView.addAnnotation(pin)
            }
        }
    }

    /// Schedule a debounced geocode. Cancels any prior pending
    /// request and starts a new timer; only after `debounceInterval`
    /// seconds of quiescence do we actually hit MKLocalSearch. This
    /// keeps fast typing in the inspector field from issuing a
    /// request per keystroke and tripping Apple's rate limit.
    private func scheduleGeocode(_ raw: String) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resolveLocation(raw)
            }
        }
    }

    /// Resolve a human-friendly location string into a coordinate.
    /// Cache-hit-first; falls back to `MKLocalSearch` on a miss;
    /// records failures for 60s to dampen retry storms. Captures
    /// only `[weak self]` + the partId-bearing closure already
    /// wired in updateMapViews — no Part struct or document strong
    /// refs.
    ///
    /// We use `MKLocalSearch` rather than `CLGeocoder` because the
    /// latter was deprecated in macOS 26 with the explicit Apple
    /// advice "Use MapKit". `MKLocalSearch` accepts the same kinds
    /// of natural-language queries (place names, full addresses,
    /// US ZIP codes, points of interest) and returns
    /// `MKMapItem` results with `.placemark.coordinate`.
    private func resolveLocation(_ raw: String) {
        if let cached = MapGeocodeCache.shared.cachedCoordinate(for: raw) {
            applyResolvedCoordinate(cached)
            return
        }
        if MapGeocodeCache.shared.isRecentlyFailed(raw) {
            return
        }

        // Cancel any prior in-flight search so a slow earlier query
        // can't race ahead of the latest one and clobber the map.
        activeSearch?.cancel()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = raw
        // Bias the search toward what the map is currently showing.
        // Without a region hint, ambiguous strings (e.g. "Springfield")
        // pick essentially at random; with a hint they prefer matches
        // near the visible area.
        request.region = mapView.region

        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, error in
            // The completion handler is documented to run on the
            // main thread, but be belt-and-suspenders explicit.
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activeSearch = nil

                if let error = error {
                    let nsError = error as NSError
                    // MKError.cancelled fires when we cancel a stale
                    // request — it's expected and not a real failure.
                    if nsError.domain == MKErrorDomain,
                       nsError.code == MKError.Code.placemarkNotFound.rawValue {
                        HypeLogger.shared.info(
                            "MapHost.resolveLocation: no match for '\(raw)' (placemarkNotFound)",
                            source: "MapGeocode"
                        )
                        MapGeocodeCache.shared.recordFailure(for: raw)
                        return
                    }
                    HypeLogger.shared.error(
                        "MapHost.resolveLocation: MKLocalSearch error for '\(raw)': \(error.localizedDescription) (domain=\(nsError.domain) code=\(nsError.code))",
                        source: "MapGeocode"
                    )
                    MapGeocodeCache.shared.recordFailure(for: raw)
                    return
                }

                guard let coord = response?.mapItems.first?.placemark.coordinate else {
                    MapGeocodeCache.shared.recordFailure(for: raw)
                    return
                }

                MapGeocodeCache.shared.recordHit(for: raw, coordinate: coord)
                self.applyResolvedCoordinate(coord)
            }
        }
    }

    /// Re-center the live map AND notify the coordinator so the
    /// document gets the new lat/lon. Span is preserved from the
    /// current map state so we don't clobber the user's zoom.
    private func applyResolvedCoordinate(_ coord: CLLocationCoordinate2D) {
        let span = mapView.region.span
        mapView.setRegion(MKCoordinateRegion(center: coord, span: span), animated: true)
        // Update the cached "last-applied" coords BEFORE firing the
        // writeback. The writeback triggers a SwiftUI re-render,
        // which calls apply() again — and apply()'s compare-and-skip
        // needs to see "yes, these coords are already applied" so it
        // doesn't redundantly setRegion (which can flicker the map
        // briefly back through an animation).
        appliedLat = coord.latitude
        appliedLon = coord.longitude
        appliedSpan = span.latitudeDelta
        onLocationResolved?(coord.latitude, coord.longitude)
    }

    override func removeFromSuperview() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        activeSearch?.cancel()
        activeSearch = nil
        super.removeFromSuperview()
    }

    private struct AnnotationSpec {
        let lat: Double
        let lon: Double
        let title: String
    }

    private static func parseAnnotations(_ json: String) -> [AnnotationSpec] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let lat = (dict["lat"] as? Double) ?? Double(dict["lat"] as? String ?? ""),
                  let lon = (dict["lon"] as? Double) ?? Double(dict["lon"] as? String ?? "") else { return nil }
            let title = (dict["title"] as? String) ?? ""
            return AnnotationSpec(lat: lat, lon: lon, title: title)
        }
    }

    private static func mapType(for raw: String) -> MKMapType {
        switch raw.lowercased() {
        case "standard": return .standard
        case "satellite": return .satellite
        case "hybrid": return .hybrid
        case "satelliteflyover": return .satelliteFlyover
        case "hybridflyover": return .hybridFlyover
        case "mutedstandard": return .mutedStandard
        default: return .standard
        }
    }
}
