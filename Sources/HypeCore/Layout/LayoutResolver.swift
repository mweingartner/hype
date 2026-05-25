import Foundation

public struct PartResolvedGeometry: Sendable, Equatable {
    public var partId: UUID
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double

    public init(partId: UUID, left: Double, top: Double, width: Double, height: Double) {
        self.partId = partId
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}

public struct LayoutResolution: Sendable, Equatable {
    public var profile: HypeDeviceProfile
    public var canvasWidth: Double
    public var canvasHeight: Double
    public var safeContentLeft: Double
    public var safeContentTop: Double
    public var safeContentWidth: Double
    public var safeContentHeight: Double
    public var geometries: [UUID: PartResolvedGeometry]

    public init(
        profile: HypeDeviceProfile,
        canvasWidth: Double,
        canvasHeight: Double,
        safeContentLeft: Double,
        safeContentTop: Double,
        safeContentWidth: Double,
        safeContentHeight: Double,
        geometries: [UUID: PartResolvedGeometry]
    ) {
        self.profile = profile
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.safeContentLeft = safeContentLeft
        self.safeContentTop = safeContentTop
        self.safeContentWidth = safeContentWidth
        self.safeContentHeight = safeContentHeight
        self.geometries = geometries
    }
}

/// Projects persisted card/background parts into a target-device coordinate
/// space without storing live platform views.
///
/// Today the resolver preserves absolute geometry and applies explicit
/// `LayoutConstraint` values against the target profile's safe content area.
/// Responsive variants can build on this type without changing the renderer or
/// the persisted document's value-model boundary.
public struct LayoutResolver: Sendable {
    public init() {}

    public func resolve(
        parts: [Part],
        constraints: [LayoutConstraint],
        profile: HypeDeviceProfile
    ) -> LayoutResolution {
        let safeLeft = profile.safeArea.left
        let safeTop = profile.safeArea.top
        let safeWidth = max(1, Double(profile.width) - profile.safeArea.left - profile.safeArea.right)
        let safeHeight = max(1, Double(profile.height) - profile.safeArea.top - profile.safeArea.bottom)

        let solver = ConstraintSolver()
        let updates = solver.solve(
            constraints: constraints,
            parts: parts,
            canvasWidth: safeWidth,
            canvasHeight: safeHeight
        )

        var geometries: [UUID: PartResolvedGeometry] = [:]
        for part in parts {
            let updated = updates[part.id]
            let left = (updated?.left ?? part.left) + safeLeft
            let top = (updated?.top ?? part.top) + safeTop
            geometries[part.id] = PartResolvedGeometry(
                partId: part.id,
                left: left,
                top: top,
                width: updated?.width ?? part.width,
                height: updated?.height ?? part.height
            )
        }

        return LayoutResolution(
            profile: profile,
            canvasWidth: Double(profile.width),
            canvasHeight: Double(profile.height),
            safeContentLeft: safeLeft,
            safeContentTop: safeTop,
            safeContentWidth: safeWidth,
            safeContentHeight: safeHeight,
            geometries: geometries
        )
    }
}
