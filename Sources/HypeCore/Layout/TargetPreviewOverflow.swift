import Foundation

/// Pure, headless helper for computing which parts overflow the target device
/// frame during `fixed`-policy emulation.
///
/// This type contains no side effects and is tested directly in unit tests.
/// It is also wired into the `TargetPreviewCanvasView` overflow indicator.
public enum TargetPreviewOverflow {

    /// Returns the IDs of parts whose resolved geometry extends outside the
    /// target profile's canvas boundary.
    ///
    /// A part overflows when any edge of its resolved frame falls outside the
    /// profile's `[0, width] × [0, height]` rect. The safe-area insets are
    /// not considered here — parts may legitimately occupy the safe-area chrome
    /// (e.g., full-bleed backgrounds). This purely reports canvas overflow.
    ///
    /// - Parameters:
    ///   - resolution: The `LayoutResolution` produced by `LayoutResolver`.
    ///   - profile: The emulated `HypeDeviceProfile` that defines canvas bounds.
    /// - Returns: Set of part UUIDs whose resolved frame extends outside the
    ///   profile canvas. Empty when no parts overflow.
    public static func overflowingPartIds(
        resolution: LayoutResolution,
        profile: HypeDeviceProfile
    ) -> Set<UUID> {
        let canvasW = Double(profile.width)
        let canvasH = Double(profile.height)

        var overflowing: Set<UUID> = []
        for (id, geometry) in resolution.geometries {
            if geometry.left < 0
                || geometry.top < 0
                || geometry.left + geometry.width > canvasW
                || geometry.top + geometry.height > canvasH {
                overflowing.insert(id)
            }
        }
        return overflowing
    }
}
