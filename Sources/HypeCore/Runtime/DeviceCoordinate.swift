import Foundation

/// A WGS-84 coordinate returned by the location subsystem.
///
/// This type is CoreLocation-free: it carries only primitive Double values
/// so HypeCore can use it without importing CoreLocation. The app target
/// converts `CLLocation` coordinates into `DeviceCoordinate` values before
/// handing them to the runtime.
public struct DeviceCoordinate: Sendable, Equatable {
    /// Latitude in decimal degrees, in the range [-90, 90].
    public var latitude: Double
    /// Longitude in decimal degrees, in the range [-180, 180].
    public var longitude: Double
    /// Estimated horizontal accuracy in meters; negative means the value
    /// is invalid or unavailable.
    public var horizontalAccuracy: Double

    /// Designated initializer. Does **not** validate ranges — call
    /// `validated(latitude:longitude:horizontalAccuracy:)` when constructing
    /// from untrusted input.
    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double = -1) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }

    /// Validated constructor — the only sanctioned path for creating a
    /// coordinate from untrusted values.
    ///
    /// Returns `nil` when any of the following hold:
    /// - `latitude` is not finite or outside [-90, 90]
    /// - `longitude` is not finite or outside [-180, 180]
    public static func validated(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double = -1
    ) -> DeviceCoordinate? {
        guard latitude.isFinite, longitude.isFinite,
              latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180 else {
            return nil
        }
        return DeviceCoordinate(latitude: latitude, longitude: longitude,
                                horizontalAccuracy: horizontalAccuracy)
    }

    /// The canonical HypeTalk representation: `"lat,lon"`.
    ///
    /// Uses a locale-independent `.` decimal separator so the comma always
    /// acts as the HyperTalk item delimiter. Trailing zeros are stripped,
    /// matching the interpreter's `formatNumber` semantics.
    public var hypeTalkString: String {
        "\(Self.formatComponent(latitude)),\(Self.formatComponent(longitude))"
    }

    /// Format a single coordinate component locale-independently, stripping
    /// trailing zeros the same way `Interpreter.formatNumber` does.
    private static func formatComponent(_ n: Double) -> String {
        // If the value is a whole number, emit an integer (no decimal point).
        if n == n.rounded(.towardZero), n.isFinite {
            if let i = Int(exactly: n.rounded(.towardZero)) {
                return String(i)
            }
        }
        // Use Swift's default Double→String for all other values.
        // Swift's `String(Double)` always uses "." as the decimal separator
        // regardless of locale, so this is safe.
        return String(n)
    }
}
