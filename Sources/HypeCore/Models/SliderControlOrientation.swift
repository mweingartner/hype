import Foundation

/// Visual axis for slider controls.
///
/// Slider direction is derived from the part's current bounds rather than
/// persisted separately: the longest dimension is the interactive axis.
public enum SliderControlOrientation: String, Sendable, Equatable {
    case horizontal
    case vertical
}

public extension Part {
    /// Sliders render vertically when their height is greater than their width.
    /// Equal dimensions fall back to horizontal to preserve the default macOS
    /// slider appearance for ambiguous square controls.
    var sliderControlOrientation: SliderControlOrientation {
        Part.sliderControlOrientation(width: width, height: height)
    }

    static func sliderControlOrientation(width: Double, height: Double) -> SliderControlOrientation {
        abs(height) > abs(width) ? .vertical : .horizontal
    }
}
