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
