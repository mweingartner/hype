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
    public var layoutPolicy: TargetLayoutPolicy
    public var canvasWidth: Double
    public var canvasHeight: Double
    public var safeContentLeft: Double
    public var safeContentTop: Double
    public var safeContentWidth: Double
    public var safeContentHeight: Double
    /// The safe-area-relative projection transform components.
    ///
    /// `contentScaleX`/`contentScaleY` are the per-axis scale factors from
    /// source-design space into the target safe-area space. `contentOffsetX`/
    /// `contentOffsetY` are the centering offsets (non-zero only for
    /// `.scaleToFit` when the subordinate axis is padded).
    ///
    /// Consumed by:
    ///   - `TargetPreviewCanvasView` (editor emulation overlay)
    ///   - `preview_layout_profile` AI layout-preview tool
    public var contentScaleX: Double
    public var contentScaleY: Double
    public var contentOffsetX: Double
    public var contentOffsetY: Double
    public var geometries: [UUID: PartResolvedGeometry]

    public init(
        profile: HypeDeviceProfile,
        layoutPolicy: TargetLayoutPolicy = .fixed,
        canvasWidth: Double,
        canvasHeight: Double,
        safeContentLeft: Double,
        safeContentTop: Double,
        safeContentWidth: Double,
        safeContentHeight: Double,
        contentScaleX: Double = 1,
        contentScaleY: Double = 1,
        contentOffsetX: Double = 0,
        contentOffsetY: Double = 0,
        geometries: [UUID: PartResolvedGeometry]
    ) {
        self.profile = profile
        self.layoutPolicy = layoutPolicy
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.safeContentLeft = safeContentLeft
        self.safeContentTop = safeContentTop
        self.safeContentWidth = safeContentWidth
        self.safeContentHeight = safeContentHeight
        self.contentScaleX = contentScaleX
        self.contentScaleY = contentScaleY
        self.contentOffsetX = contentOffsetX
        self.contentOffsetY = contentOffsetY
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
        profile: HypeDeviceProfile,
        sourceCanvasWidth: Double? = nil,
        sourceCanvasHeight: Double? = nil,
        policy: TargetLayoutPolicy = .fixed
    ) -> LayoutResolution {
        let safeLeft = profile.safeArea.left
        let safeTop = profile.safeArea.top
        let safeWidth = max(1, Double(profile.width) - profile.safeArea.left - profile.safeArea.right)
        let safeHeight = max(1, Double(profile.height) - profile.safeArea.top - profile.safeArea.bottom)
        let sourceWidth = max(1, sourceCanvasWidth ?? Double(profile.width))
        let sourceHeight = max(1, sourceCanvasHeight ?? Double(profile.height))
        let projection = projectionMetrics(
            policy: policy,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            safeWidth: safeWidth,
            safeHeight: safeHeight
        )
        let projectedParts = parts.map { part in
            projectedPart(part, metrics: projection)
        }

        let solver = ConstraintSolver()
        let updates = solver.solve(
            constraints: constraints,
            parts: projectedParts,
            canvasWidth: safeWidth,
            canvasHeight: safeHeight
        )

        var geometries: [UUID: PartResolvedGeometry] = [:]
        for part in projectedParts {
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
            layoutPolicy: policy,
            canvasWidth: Double(profile.width),
            canvasHeight: Double(profile.height),
            safeContentLeft: safeLeft,
            safeContentTop: safeTop,
            safeContentWidth: safeWidth,
            safeContentHeight: safeHeight,
            contentScaleX: projection.scaleX,
            contentScaleY: projection.scaleY,
            contentOffsetX: projection.offsetX,
            contentOffsetY: projection.offsetY,
            geometries: geometries
        )
    }

    public func resolve(document: HypeDocument, profile: HypeDeviceProfile, cardId: UUID) -> LayoutResolution {
        let parts = document.effectivePartsForCard(cardId)
        return resolve(
            parts: parts,
            constraints: document.constraints,
            profile: profile,
            sourceCanvasWidth: Double(document.stack.width),
            sourceCanvasHeight: Double(document.stack.height),
            policy: document.stack.deploymentTargets.layoutPolicy
        )
    }

    private func projectionMetrics(
        policy: TargetLayoutPolicy,
        sourceWidth: Double,
        sourceHeight: Double,
        safeWidth: Double,
        safeHeight: Double
    ) -> (scaleX: Double, scaleY: Double, offsetX: Double, offsetY: Double) {
        switch policy {
        case .fixed:
            // Identity transform: coordinates are preserved as authored.
            return (1, 1, 0, 0)
        case .scaleToFit:
            // Uniform scale so the dominant axis fills; the subordinate axis
            // is centered within the safe area. Offsets are non-negative.
            let scale = min(safeWidth / sourceWidth, safeHeight / sourceHeight)
            let offsetX = (safeWidth - sourceWidth * scale) / 2
            let offsetY = (safeHeight - sourceHeight * scale) / 2
            return (scale, scale, offsetX, offsetY)
        case .stretchToFill:
            // Independent per-axis scale maps source exactly to safe area;
            // both axes fill so centering offsets are intentionally 0.
            return (safeWidth / sourceWidth, safeHeight / sourceHeight, 0, 0)
        }
    }

    private func projectedPart(
        _ part: Part,
        metrics: (scaleX: Double, scaleY: Double, offsetX: Double, offsetY: Double)
    ) -> Part {
        var projected = part
        projected.left = metrics.offsetX + part.left * metrics.scaleX
        projected.top = metrics.offsetY + part.top * metrics.scaleY
        projected.width = part.width * metrics.scaleX
        projected.height = part.height * metrics.scaleY
        return projected
    }
}
