import Foundation
import HypeCore
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Live Core Location provider for the `user location` HypeTalk expression.
///
/// Uses `CLLocationUpdate.liveUpdates()` (macOS 14+) to request a single
/// device coordinate and returns it as a `LocationResult`. The request races
/// against a 10-second timeout implemented with a `TaskGroup`; the loser is
/// cancelled immediately.
///
/// One-shot guarantee: the async-sequence iteration stops after the first
/// usable result or error-condition update — the session is never left
/// streaming.
actor RuntimeLocationProvider: LocationProvider {
    static let shared = RuntimeLocationProvider()

    private init() {}

    // MARK: - LocationProvider

    func currentLocation() async -> LocationResult {
#if canImport(CoreLocation)
        guard #available(macOS 14, iOS 17, *) else { return .unavailable }
        return await fetchLocationWithTimeout(seconds: 10)
#else
        return .unavailable
#endif
    }

    // MARK: - Private helpers

#if canImport(CoreLocation)
    @available(macOS 14, iOS 17, *)
    private func fetchLocationWithTimeout(seconds: TimeInterval) async -> LocationResult {
        await withTaskGroup(of: LocationResult.self) { group in
            // Race: location fetch vs. timeout
            group.addTask {
                await self.fetchOneUpdate()
            }
            group.addTask {
                let capped = min(max(seconds, 1), 30)
                do {
                    try await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))
                } catch {
                    // Task was cancelled (the location task won) — treat as
                    // a clean cancellation, not a timeout.
                    return .unavailable
                }
                return .timedOut
            }

            // The first completed child determines the result; cancel the other.
            let result = await group.next() ?? .unavailable
            group.cancelAll()
            return result
        }
    }

    @available(macOS 14, iOS 17, *)
    private func fetchOneUpdate() async -> LocationResult {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                // Authorization-denied states — stop immediately.
                if update.authorizationDenied
                    || update.authorizationDeniedGlobally
                    || update.authorizationRestricted {
                    return .denied
                }

                // Unavailable states — stop immediately.
                if update.locationUnavailable
                    || update.insufficientlyInUse
                    || update.serviceSessionRequired {
                    return .unavailable
                }

                // Authorization prompt is showing — wait for the next update.
                if update.authorizationRequestInProgress {
                    continue
                }

                // We have a location — validate and return.
                if let loc = update.location {
                    if let coord = DeviceCoordinate.validated(
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        horizontalAccuracy: loc.horizontalAccuracy
                    ) {
                        return .success(coord)
                    } else {
                        // Coordinate out of valid WGS-84 range — treat as unavailable.
                        return .unavailable
                    }
                }
                // Any other update (e.g. accuracy-limited with no location yet) — keep waiting.
            }
            // Sequence ended without producing a usable result.
            return .unavailable
        } catch {
            return .unavailable
        }
    }
#endif
}
