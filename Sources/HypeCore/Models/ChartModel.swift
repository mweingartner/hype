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

    /// Parse from JSON string. Routes through the shared
    /// `JSONCodec.decoder` to avoid allocating a fresh
    /// `JSONDecoder` per call (this is hot — `ChartRenderer`
    /// decodes on every draw frame, and `PropertyInspector` calls
    /// `fromJSON` in 40+ chart-binding `get` closures per render).
    public static func fromJSON(_ json: String) -> ChartConfig? {
        return JSONCodec.decode(ChartConfig.self, from: json)
    }

    /// Serialize to JSON string. Routes through the shared
    /// `JSONCodec.encoder`.
    public func toJSON() -> String {
        return JSONCodec.encode(self)
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
    /// - **Single series**: returns one entry per data point, using the
    ///   point's effective color (per-point color overrides the series
    ///   color; empty falls back to the series color). Hype charts are
    ///   authored visually, so even inherited-color points should be
    ///   named in the legend instead of collapsing to a single generic
    ///   series row.
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
            if only.data.isEmpty {
                return [ChartLegendEntry(name: only.name, colorHex: only.color)]
            }
            return only.data.map { point in
                let effective = point.color.isEmpty ? only.color : point.color
                return ChartLegendEntry(name: point.name.isEmpty ? only.name : point.name, colorHex: effective)
            }
        }

        return series.map { ChartLegendEntry(name: $0.name, colorHex: $0.color) }
    }

    /// User-facing mark label for one point. Includes the series name
    /// when more than one series is present so labels remain meaningful
    /// without relying on color alone.
    public func dataPointLabel(for point: ChartDataPoint, in series: ChartSeries) -> String {
        let pointName = point.name.isEmpty ? "Point" : point.name
        let value = Self.formattedValue(point.value)
        if self.series.count > 1 {
            let seriesName = series.name.isEmpty ? "Series" : series.name
            return "\(seriesName): \(pointName) \(value)"
        }
        return "\(pointName) \(value)"
    }

    /// Compact numeric formatting for visible chart labels.
    public static func formattedValue(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001,
           rounded >= Double(Int64.min),
           rounded <= Double(Int64.max) {
            return "\(Int64(rounded))"
        }

        var text = String(format: "%.2f", value)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }
}
