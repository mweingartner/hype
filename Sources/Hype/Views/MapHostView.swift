import AppKit
import MapKit
import CoreLocation
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

    /// Has apply() ever been called? Used to gate geocoding so
    /// values DESERIALIZED from disk (first apply()) don't trigger
    /// a network call — only INTERACTIVE changes within this
    /// session do. Without this gate, opening a hostile stack
    /// would silently ping Apple's geocoding servers on load,
    /// which is a covert-telemetry vector.
    private var hasAppliedOnce = false

    /// Active geocoder. Held as an instance property so we can
    /// `cancelGeocode()` if the part is torn down mid-request,
    /// avoiding a callback into a freed view.
    private let geocoder = CLGeocoder()

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
        mapView.mapType = Self.mapType(for: part.mapType)

        let center = CLLocationCoordinate2D(latitude: part.mapCenterLat, longitude: part.mapCenterLon)
        // Always refresh the region — cheap and idempotent.
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.0001, part.mapSpan),
            longitudeDelta: max(0.0001, part.mapSpan)
        )
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        // Forward-geocode the user-entered location string when it
        // changes — but ONLY for interactive changes within this
        // session. The first apply() (right after the host is created)
        // captures whatever mapLocation came from disk WITHOUT
        // geocoding it, so opening a hostile stack can't silently
        // beacon to Apple. Subsequent changes (inspector edits, AI
        // tool calls, HypeTalk setters) DO trigger geocoding.
        let normalizedLocation = MapGeocodeCache.normalize(part.mapLocation)
        if !hasAppliedOnce {
            appliedLocation = normalizedLocation
            hasAppliedOnce = true
        } else if normalizedLocation != appliedLocation {
            appliedLocation = normalizedLocation
            if !normalizedLocation.isEmpty {
                resolveLocation(part.mapLocation)
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

    /// Resolve a human-friendly location string into a coordinate.
    /// Cache-hit-first; falls back to CLGeocoder on a miss; records
    /// failures for 60s to dampen retry storms. Captures only
    /// `[weak self]` + the partId-bearing closure already wired in
    /// updateMapViews — no Part struct or document strong refs.
    private func resolveLocation(_ raw: String) {
        if let cached = MapGeocodeCache.shared.cachedCoordinate(for: raw) {
            applyResolvedCoordinate(cached)
            return
        }
        if MapGeocodeCache.shared.isRecentlyFailed(raw) {
            return
        }
        geocoder.geocodeAddressString(raw) { [weak self] placemarks, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let coord = placemarks?.first?.location?.coordinate {
                    MapGeocodeCache.shared.recordHit(for: raw, coordinate: coord)
                    self.applyResolvedCoordinate(coord)
                } else {
                    MapGeocodeCache.shared.recordFailure(for: raw)
                }
            }
        }
    }

    /// Re-center the live map AND notify the coordinator so the
    /// document gets the new lat/lon. Span is preserved from the
    /// current map state so we don't clobber the user's zoom.
    private func applyResolvedCoordinate(_ coord: CLLocationCoordinate2D) {
        let span = mapView.region.span
        mapView.setRegion(MKCoordinateRegion(center: coord, span: span), animated: true)
        onLocationResolved?(coord.latitude, coord.longitude)
    }

    override func removeFromSuperview() {
        geocoder.cancelGeocode()
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
