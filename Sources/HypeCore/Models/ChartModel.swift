import Foundation

/// Supported chart types.
public enum ChartType: String, Codable, Sendable, CaseIterable {
    case bar, line, area, point, pie, rule
}

/// A complete chart configuration stored as JSON in Part.chartData.
public struct ChartConfig: Codable, Sendable {
    public var chartType: ChartType
    public var title: String
    public var series: [ChartSeries]
    public var showLegend: Bool
    public var showGrid: Bool
    public var xAxisLabel: String
    public var yAxisLabel: String

    public init(
        chartType: ChartType = .bar,
        title: String = "",
        series: [ChartSeries] = [],
        showLegend: Bool = true,
        showGrid: Bool = true,
        xAxisLabel: String = "",
        yAxisLabel: String = ""
    ) {
        self.chartType = chartType
        self.title = title
        self.series = series
        self.showLegend = showLegend
        self.showGrid = showGrid
        self.xAxisLabel = xAxisLabel
        self.yAxisLabel = yAxisLabel
    }

    /// Parse from JSON string.
    public static func fromJSON(_ json: String) -> ChartConfig? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChartConfig.self, from: data)
    }

    /// Serialize to JSON string.
    public func toJSON() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// A data series within a chart.
public struct ChartSeries: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: String  // hex color (default for all data points)
    public var data: [ChartDataPoint]

    public init(id: UUID = UUID(), name: String = "Series", color: String = "#4A90D9", data: [ChartDataPoint] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.data = data
    }
}

/// A single data point with name, value, and color.
public struct ChartDataPoint: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var value: Double
    public var color: String  // hex color, e.g. "#FF6B6B"

    enum CodingKeys: String, CodingKey {
        case id, name, value, color
        case label  // backward compat
    }

    public init(id: UUID = UUID(), name: String = "", value: Double = 0, color: String = "") {
        self.id = id
        self.name = name
        self.value = value
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // Accept both "name" and legacy "label"
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .label)
            ?? ""
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(value, forKey: .value)
        try c.encode(color, forKey: .color)
    }
}

// MARK: - Legend Entry Computation

/// A single visible row in a chart's legend — one name + one hex color.
///
/// Computing legend entries lives in HypeCore (not in the SwiftUI view) so
/// that the logic is unit-testable without instantiating `ChartHostView`
/// or importing SwiftUI / Charts. The rendering layer walks this list and
/// builds a grid of colored swatches.
public struct ChartLegendEntry: Sendable, Equatable {
    public var name: String
    /// Hex color string like "#FF6B6B". Always non-empty — empty inputs
    /// resolve to the series color, and series always have a default color.
    public var colorHex: String

    public init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }
}

extension ChartConfig {
    /// The legend entries that should appear for this chart.
    ///
    /// Policy:
    ///
    /// - **Empty chart** (no series): returns `[]`.
    /// - **Single series with per-point colors** (at least one
    ///   `ChartDataPoint.color` is non-empty): returns one entry per
    ///   data point, using the point's effective color (per-point color
    ///   overrides the series color; empty falls back to the series
    ///   color). This is what the user sees when they — or the AI —
    ///   explicitly colored individual points.
    /// - **Single series without per-point colors**: returns a single
    ///   entry for the series (name + series color). Without this guard
    ///   the legend would be N identical swatches for a chart whose
    ///   points all share the series default color.
    /// - **Multiple series**: returns one entry per series using the
    ///   series color. In a multi-series chart the primary
    ///   disambiguation is "which series?", and building a cross-series
    ///   per-point legend would require compound keys and get noisy
    ///   very quickly.
    ///
    /// Per-point colors in multi-series charts are still rendered
    /// correctly on the chart itself (each mark uses its own resolved
    /// color), the legend just groups by series.
    ///
    /// Callers should still honour `showLegend` before displaying the
    /// returned entries; this method does not consult that flag.
    public func legendEntries() -> [ChartLegendEntry] {
        if series.isEmpty { return [] }

        if series.count == 1, let only = series.first {
            let hasAnyPerPointColor = only.data.contains { !$0.color.isEmpty }
            if hasAnyPerPointColor {
                return only.data.map { point in
                    let effective = point.color.isEmpty ? only.color : point.color
                    return ChartLegendEntry(name: point.name, colorHex: effective)
                }
            }
            return [ChartLegendEntry(name: only.name, colorHex: only.color)]
        }

        return series.map { ChartLegendEntry(name: $0.name, colorHex: $0.color) }
    }
}
