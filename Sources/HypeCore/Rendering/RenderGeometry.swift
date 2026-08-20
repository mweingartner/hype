import Foundation
#if canImport(AppKit)
import AppKit

/// Shared CGPath construction helpers that cannot trip CoreGraphics preconditions.
///
/// Part geometry is script-settable — a HypeTalk script can write
/// `set the width of btn "OK" to 5`, `set the width of x to -10`,
/// or even `set the width of x to "nan"` (the interpreter coerces
/// the string to `Double.nan`). `CGPath(roundedRect:cornerWidth:
/// cornerHeight:)` has hard preconditions:
///
/// - The rect must be non-empty (width ≥ 0, height ≥ 0) after
///   standardization; CoreGraphics traps on negative-dimension rects.
/// - cornerWidth ≤ rect.width/2 and cornerHeight ≤ rect.height/2;
///   oversized corners also produce a trap.
/// - No NaN/infinite component anywhere.
///
/// Because a stack script must never be able to crash the app, every
/// rounded-rect path construction goes through this helper.
public enum RenderGeometry {

    // MARK: - Safe rect

    /// Return a CoreGraphics-safe version of `rect`.
    ///
    /// - NaN or infinite origin/size components are replaced with 0.
    /// - Negative sizes are standardized to non-negative via
    ///   `CGRect.standardized`.
    /// - The resulting width and height are clamped to ≥ 0 as a final
    ///   guard against floating-point edge cases.
    public static func safeRect(_ rect: CGRect) -> CGRect {
        // Replace any non-finite component with 0 before standardizing,
        // because CGRect.standardized is undefined for NaN inputs.
        let x = rect.origin.x.isFinite  ? rect.origin.x  : 0
        let y = rect.origin.y.isFinite  ? rect.origin.y  : 0
        let w = rect.size.width.isFinite ? rect.size.width  : 0
        let h = rect.size.height.isFinite ? rect.size.height : 0
        let cleaned = CGRect(x: x, y: y, width: w, height: h).standardized
        return CGRect(
            x: cleaned.origin.x,
            y: cleaned.origin.y,
            width: max(0, cleaned.size.width),
            height: max(0, cleaned.size.height)
        )
    }

    // MARK: - Rounded-rect paths

    /// Return a CGPath for a rounded rectangle with corners clamped to
    /// the safe range `[0, w/2] × [0, h/2]`.
    ///
    /// - The input rect is first canonicalized via `safeRect(_:)`.
    /// - NaN corner values are treated as 0 (no rounding).
    /// - When the canonicalized rect is empty (zero width or height),
    ///   a plain `CGPath(rect:)` is returned — `CGPath(roundedRect:)`
    ///   is undefined for empty rects on some OS versions.
    public static func roundedRectPath(
        in rect: CGRect,
        cornerWidth: CGFloat,
        cornerHeight: CGFloat
    ) -> CGPath {
        let safe = safeRect(rect)
        let w = safe.width
        let h = safe.height
        // Degenerate rect — rounded-rect path is undefined; fall back to
        // a plain rect so callers always receive a valid, drawable path.
        guard w > 0, h > 0 else {
            return CGPath(rect: safe, transform: nil)
        }
        // NaN corner inputs become 0 (flat corners) — defensive against
        // script-authored values parsed from user input.
        let cw = cornerWidth.isFinite  ? cornerWidth  : 0
        let ch = cornerHeight.isFinite ? cornerHeight : 0
        // Clamp to the CoreGraphics precondition: corner ≤ half-dimension.
        let clampedW = max(0, min(cw, w / 2))
        let clampedH = max(0, min(ch, h / 2))
        return CGPath(roundedRect: safe, cornerWidth: clampedW, cornerHeight: clampedH, transform: nil)
    }

    /// Convenience overload for symmetric corner radius.
    public static func roundedRectPath(
        in rect: CGRect,
        cornerRadius: CGFloat
    ) -> CGPath {
        roundedRectPath(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    }

    // MARK: - Freeform contract (turtle-graphics D8, §5.2)

    /// Whether `part` is an **open stroke** (a pen trail, no fill) rather
    /// than a closed, filled polygon.
    ///
    /// `fillColor == ""` is the app-wide "none" sentinel (shared with
    /// `fontColor`/`HexColor`); the turtle engine emits it for stroke
    /// parts (§5.1) and leaves every other freeform-creation path on its
    /// existing non-empty default (`"#FFFFFF"`), so this check is
    /// additive and never reclassifies an existing part.
    public static func freeformIsOpenStroke(_ part: Part) -> Bool {
        part.fillColor.isEmpty
    }

    /// Translate `part.pathData` into local, origin-anchored coordinates:
    /// the tight bounding box of the points — expanded by
    /// `strokeWidth / 2` on every side, matching `TurtleEngine`'s frame
    /// math (§5.1) — is moved to sit at `(0, 0)`. Coordinates stay
    /// y-down, matching card-space `pathData`.
    ///
    /// Anchoring the drawing to a frame-independent local origin (rather
    /// than to `part.left`/`part.top` directly) is what lets a renderer
    /// draw at `rect.origin + localPoint` and have the visible shape
    /// translate rigidly whenever the part's frame moves — including for
    /// legacy freeforms whose stored frame had drifted from their path
    /// bounds.
    ///
    /// NaN-safe like `safeRect(_:)`: non-finite point components and a
    /// non-finite `strokeWidth` are treated as 0 rather than propagating
    /// NaN into every returned point.
    public static func freeformLocalPoints(_ part: Part) -> [CGPoint] {
        let points = part.pathData
        guard let first = points.first else { return [] }

        func finite(_ value: Double) -> CGFloat {
            let converted = CGFloat(value)
            return converted.isFinite ? converted : 0
        }

        var minX = finite(first.x)
        var maxX = minX
        var minY = finite(first.y)
        var maxY = minY
        for point in points.dropFirst() {
            let x = finite(point.x)
            let y = finite(point.y)
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }

        let pad = finite(part.strokeWidth) / 2
        let originX = minX - pad
        let originY = minY - pad
        return points.map { CGPoint(x: finite($0.x) - originX, y: finite($0.y) - originY) }
    }
}
#endif
