import Foundation

/// The result of a one-shot device-location request.
public enum LocationResult: Sendable, Equatable {
    /// A coordinate was obtained successfully.
    case success(DeviceCoordinate)
    /// The user denied location access (or it is restricted).
    case denied
    /// Location services are unavailable on this device/configuration.
    case unavailable
    /// The request exceeded the allowed time budget and was cancelled.
    case timedOut
}

/// Optional device-location surface for the `user location` HypeTalk expression.
///
/// HypeCore does not import CoreLocation; the app target injects a concrete
/// implementation backed by `CLLocationUpdate.liveUpdates()`. Tests and
/// non-UI contexts use `StubLocationProvider` which always returns `.unavailable`.
public protocol LocationProvider: Sendable {
    /// Perform a one-shot coordinate fetch.
    ///
    /// The implementation MUST NOT block indefinitely — it should enforce a
    /// timeout (10 s recommended, 30 s maximum) and return `.timedOut` when
    /// the budget is exhausted.
    func currentLocation() async -> LocationResult
}

/// A no-op `LocationProvider` suitable for tests and contexts where Core
/// Location is not available.
public struct StubLocationProvider: LocationProvider, Sendable {
    public init() {}
    public func currentLocation() async -> LocationResult { .unavailable }
}
