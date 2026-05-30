import Foundation

/// Supported chart types.
public enum ChartType: String, Codable, Sendable, CaseIterable {
    case bar, line, area, point, pie, rule, spider

    public static func fromUserValue(_ value: String) -> ChartType? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "spider", "spiderchart", "spider_chart", "radar", "radarchart", "radar_chart":
            return .spider
        default:
            return ChartType(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let type = Self.fromUserValue(raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown chart type '\(raw)'")
            )
        }
        self = type
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A complete chart configuration stored as JSON in Part.chartData.
public struct ChartConfig: Codable, Sendable {
    public static let spiderMinimumRingCount = 3
    public static let spiderMaximumRingCount = 12
    public static let spiderMinimumDecimalPlaces = 0
    public static let spiderMaximumDecimalPlaces = 6

    public var chartType: ChartType
    public var title: String
    public var series: [ChartSeries]
    public var showLegend: Bool
    public var showGrid: Bool
    public var xAxisLabel: String
    public var yAxisLabel: String
    public var interactable: Bool
    public var spiderRingCount: Int
    public var spiderGridColor: String
    public var spiderAxisColor: String
    public var spiderLabelColor: String
    public var spiderFillOpacity: Double
    public var spiderPointRadius: Double
    public var spiderShowValueLabels: Bool
    public var spiderDecimalPlaces: Int
    /// When `true` and `showGrid` is enabled, alternating ring bands are drawn
    /// behind the ring strokes — even-index bands are lightly filled, odd-index
    /// bands are clear — producing an ECharts-style "split area" effect.
    public var spiderShowSplitArea: Bool
    /// When `true`, the background ring grid is drawn as circles instead of
    /// polygons. Axis spokes and the data series polygons are always polygonal
    /// regardless of this setting.
    public var spiderCircularGrid: Bool

    public init(
        chartType: ChartType = .bar,
        title: String = "",
        series: [ChartSeries] = [],
        showLegend: Bool = true,
        showGrid: Bool = true,
        xAxisLabel: String = "",
        yAxisLabel: String = "",
        interactable: Bool = false,
        spiderRingCount: Int = 5,
        spiderGridColor: String = "#C9CDD3",
        spiderAxisColor: String = "#AEB4BE",
        spiderLabelColor: String = "#111827",
        spiderFillOpacity: Double = 0.24,
        spiderPointRadius: Double = 2,
        spiderShowValueLabels: Bool = false,
        spiderDecimalPlaces: Int = 0,
        spiderShowSplitArea: Bool = false,
        spiderCircularGrid: Bool = false
    ) {
        self.chartType = chartType
        self.title = title
        self.series = series
        self.showLegend = showLegend
        self.showGrid = showGrid
        self.xAxisLabel = xAxisLabel
        self.yAxisLabel = yAxisLabel
        self.interactable = interactable
        self.spiderRingCount = spiderRingCount
        self.spiderGridColor = Self.normalizedHex(spiderGridColor, fallback: "#C9CDD3")
        self.spiderAxisColor = Self.normalizedHex(spiderAxisColor, fallback: "#AEB4BE")
        self.spiderLabelColor = Self.normalizedHex(spiderLabelColor, fallback: "#111827")
        self.spiderFillOpacity = Self.clamp(spiderFillOpacity, min: 0, max: 1)
        self.spiderPointRadius = Self.clamp(spiderPointRadius, min: 1, max: 12)
        self.spiderShowValueLabels = spiderShowValueLabels
        self.spiderDecimalPlaces = spiderDecimalPlaces
        self.spiderShowSplitArea = spiderShowSplitArea
        self.spiderCircularGrid = spiderCircularGrid
        normalizeSpiderDisplay()
        normalizeSpiderValuesToPrecision()
    }

    enum CodingKeys: String, CodingKey {
        case chartType, title, series, showLegend, showGrid, xAxisLabel, yAxisLabel
        case interactable
        // Legacy decode-only keys from the earlier spider chart model.
        case spiderMinimumValue, spiderMaximumValue, spiderAutoScale, spiderRingCount
        case spiderGridColor, spiderAxisColor, spiderLabelColor, spiderFillOpacity
        case spiderPointRadius, spiderShowValueLabels, spiderDecimalPlaces
        case spiderShowSplitArea, spiderCircularGrid
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chartType = try c.decodeIfPresent(ChartType.self, forKey: .chartType) ?? .bar
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        series = try c.decodeIfPresent([ChartSeries].self, forKey: .series) ?? []
        showLegend = try c.decodeIfPresent(Bool.self, forKey: .showLegend) ?? true
        showGrid = try c.decodeIfPresent(Bool.self, forKey: .showGrid) ?? true
        xAxisLabel = try c.decodeIfPresent(String.self, forKey: .xAxisLabel) ?? ""
        yAxisLabel = try c.decodeIfPresent(String.self, forKey: .yAxisLabel) ?? ""
        interactable = try c.decodeIfPresent(Bool.self, forKey: .interactable) ?? false
        let legacySpiderMinimumValue = try c.decodeIfPresent(Double.self, forKey: .spiderMinimumValue)
        let legacySpiderMaximumValue = try c.decodeIfPresent(Double.self, forKey: .spiderMaximumValue)
        spiderRingCount = try c.decodeIfPresent(Int.self, forKey: .spiderRingCount) ?? 5
        spiderGridColor = Self.normalizedHex(
            try c.decodeIfPresent(String.self, forKey: .spiderGridColor) ?? "#C9CDD3",
            fallback: "#C9CDD3"
        )
        spiderAxisColor = Self.normalizedHex(
            try c.decodeIfPresent(String.self, forKey: .spiderAxisColor) ?? "#AEB4BE",
            fallback: "#AEB4BE"
        )
        spiderLabelColor = Self.normalizedHex(
            try c.decodeIfPresent(String.self, forKey: .spiderLabelColor) ?? "#111827",
            fallback: "#111827"
        )
        spiderFillOpacity = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .spiderFillOpacity) ?? 0.24,
            min: 0,
            max: 1
        )
        spiderPointRadius = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .spiderPointRadius) ?? 2,
            min: 1,
            max: 12
        )
        spiderShowValueLabels = try c.decodeIfPresent(Bool.self, forKey: .spiderShowValueLabels) ?? false
        spiderDecimalPlaces = try c.decodeIfPresent(Int.self, forKey: .spiderDecimalPlaces) ?? 0
        spiderShowSplitArea = try c.decodeIfPresent(Bool.self, forKey: .spiderShowSplitArea) ?? false
        spiderCircularGrid = try c.decodeIfPresent(Bool.self, forKey: .spiderCircularGrid) ?? false
        normalizeSpiderDisplay()
        if chartType == .spider,
           legacySpiderMinimumValue != nil || legacySpiderMaximumValue != nil {
            applyLegacySpiderRange(
                min: legacySpiderMinimumValue ?? 0,
                max: legacySpiderMaximumValue ?? 100
            )
        } else {
            normalizeDataPointRanges(includeCurrentValue: true)
        }
        normalizeSpiderValuesToPrecision()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chartType, forKey: .chartType)
        try c.encode(title, forKey: .title)
        try c.encode(series, forKey: .series)
        try c.encode(showLegend, forKey: .showLegend)
        try c.encode(showGrid, forKey: .showGrid)
        try c.encode(xAxisLabel, forKey: .xAxisLabel)
        try c.encode(yAxisLabel, forKey: .yAxisLabel)
        try c.encode(interactable, forKey: .interactable)
        try c.encode(spiderRingCount, forKey: .spiderRingCount)
        try c.encode(spiderGridColor, forKey: .spiderGridColor)
        try c.encode(spiderAxisColor, forKey: .spiderAxisColor)
        try c.encode(spiderLabelColor, forKey: .spiderLabelColor)
        try c.encode(spiderFillOpacity, forKey: .spiderFillOpacity)
        try c.encode(spiderPointRadius, forKey: .spiderPointRadius)
        try c.encode(spiderShowValueLabels, forKey: .spiderShowValueLabels)
        try c.encode(spiderDecimalPlaces, forKey: .spiderDecimalPlaces)
        try c.encode(spiderShowSplitArea, forKey: .spiderShowSplitArea)
        try c.encode(spiderCircularGrid, forKey: .spiderCircularGrid)
    }

    private mutating func normalizeSpiderDisplay() {
        spiderRingCount = Int(Self.clamp(
            Double(spiderRingCount),
            min: Double(Self.spiderMinimumRingCount),
            max: Double(Self.spiderMaximumRingCount)
        ))
        spiderDecimalPlaces = Int(Self.clamp(
            Double(spiderDecimalPlaces),
            min: Double(Self.spiderMinimumDecimalPlaces),
            max: Double(Self.spiderMaximumDecimalPlaces)
        ))
    }

    private mutating func normalizeDataPointRanges(includeCurrentValue: Bool) {
        for seriesIndex in series.indices {
            for pointIndex in series[seriesIndex].data.indices {
                series[seriesIndex].data[pointIndex].normalizeRangeAndValue(includeCurrentValue: includeCurrentValue)
            }
        }
    }

    private mutating func applyLegacySpiderRange(min: Double, max: Double) {
        let range = ChartDataPoint.normalizedRange(min: min, max: max)
        for seriesIndex in series.indices {
            for pointIndex in series[seriesIndex].data.indices {
                series[seriesIndex].data[pointIndex].minimumValue = range.min
                series[seriesIndex].data[pointIndex].maximumValue = range.max
                series[seriesIndex].data[pointIndex].value = series[seriesIndex].data[pointIndex].clampedValue(
                    series[seriesIndex].data[pointIndex].value
                )
            }
        }
    }

    public mutating func normalizeForStorage() {
        normalizeSpiderDisplay()
        normalizeDataPointRanges(includeCurrentValue: true)
        normalizeSpiderValuesToPrecision()
    }

    private mutating func normalizeSpiderValuesToPrecision() {
        guard chartType == .spider else { return }
        for seriesIndex in series.indices {
            for pointIndex in series[seriesIndex].data.indices {
                var point = series[seriesIndex].data[pointIndex]
                point.value = Self.quantizedValue(
                    point.clampedValue(point.value),
                    decimalPlaces: spiderDecimalPlaces
                )
                point.value = point.clampedValue(point.value)
                series[seriesIndex].data[pointIndex] = point
            }
        }
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
        var copy = self
        copy.normalizeForStorage()
        return JSONCodec.encode(copy)
    }

    public func spiderAxisLabels() -> [String] {
        let count = spiderAxisCount()
        guard count > 0 else { return [] }
        let renderable = spiderRenderableSeries()
        return (0..<count).map { index in
            for series in renderable where index < series.data.count {
                let name = series.data[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
            return "Axis \(index + 1)"
        }
    }

    /// The axis count for spider charts. The first series with at
    /// least three data points establishes the axes; additional
    /// series must match this count to render as a comparable layer.
    public func spiderAxisCount() -> Int {
        series.first(where: { $0.data.count >= 3 })?.data.count ?? 0
    }

    /// Series that can be drawn as spider/radar polygons. Incomplete
    /// series remain in the document for editing but are intentionally
    /// skipped by rendering, legends, labels, and hit testing because
    /// a partial series cannot map cleanly onto the established axes.
    public func spiderRenderableSeries() -> [ChartSeries] {
        let count = spiderAxisCount()
        guard count >= 3 else { return [] }
        return series.filter { $0.data.count == count }
    }

    /// Aggregate range across all renderable spider/radar points. This remains
    /// useful for diagnostics and legacy callers, but rendering and dragging use
    /// each `ChartDataPoint`'s own min/max so every vector is editable across
    /// its full configured range.
    public func spiderValueScale() -> (minimum: Double, maximum: Double) {
        let points = spiderRenderableSeries().flatMap(\.data)
        guard !points.isEmpty else { return (0, 1) }

        let rawMinimum = points
            .map { Swift.min($0.minimumValue, $0.value) }
            .min() ?? 0
        let rawMaximum = points
            .map { Swift.max($0.maximumValue, $0.value) }
            .max() ?? 1

        let visualMinimum = rawMinimum >= 0 ? 0 : rawMinimum
        let visualMaximum = rawMaximum <= visualMinimum
            ? visualMinimum + 1
            : rawMaximum
        return (visualMinimum, visualMaximum)
    }

    /// Value displayed beside the radial grid for the reference axis. Spider
    /// charts have per-point ranges, so tick labels describe the first visible
    /// axis rather than pretending there is one chart-level min/max scale.
    public func spiderRadialTickValue(fraction: Double, axisIndex: Int = 0) -> Double {
        let renderable = spiderRenderableSeries()
        guard let first = renderable.first, axisIndex >= 0, axisIndex < first.data.count else {
            return fraction
        }
        let point = first.data[axisIndex]
        return clampedSpiderValue(point.value(fromNormalized: fraction), for: point)
    }

    public func normalizedSpiderValue(for point: ChartDataPoint, value: Double? = nil) -> Double {
        let safe = clampedSpiderValue(value ?? point.value, for: point)
        return point.normalizedValue(safe)
    }

    public func spiderValue(for point: ChartDataPoint, from normalizedValue: Double) -> Double {
        clampedSpiderValue(point.value(fromNormalized: normalizedValue), for: point)
    }

    public func clampedSpiderValue(_ value: Double, for point: ChartDataPoint) -> Double {
        let clamped = point.clampedValue(value)
        let rounded = Self.quantizedValue(clamped, decimalPlaces: spiderDecimalPlaces)
        return point.clampedValue(rounded)
    }

    public func formattedSpiderValue(_ value: Double) -> String {
        Self.formattedValue(value, decimalPlaces: spiderDecimalPlaces)
    }

    public static func quantizedValue(_ value: Double, decimalPlaces: Int) -> Double {
        guard value.isFinite else { return value }
        let places = Int(Self.clamp(
            Double(decimalPlaces),
            min: Double(Self.spiderMinimumDecimalPlaces),
            max: Double(Self.spiderMaximumDecimalPlaces)
        ))
        guard places > 0 else { return value.rounded() }
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }

    public static func normalizedHex(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard body.count == 6, UInt64(body, radix: 16) != nil else {
            return fallback
        }
        return "#\(body.uppercased())"
    }

    public static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        guard value.isFinite else { return minValue }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }
}

/// A data series within a chart.
public struct ChartSeries: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: String  // hex color (default for all data points)
    public var data: [ChartDataPoint]

    enum CodingKeys: String, CodingKey {
        case id, name, color, data
    }

    public init(id: UUID = UUID(), name: String = "Series", color: String = "#4A90D9", data: [ChartDataPoint] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Series"
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#4A90D9"
        data = try c.decodeIfPresent([ChartDataPoint].self, forKey: .data) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(data, forKey: .data)
    }
}

/// A single data point with name, value, optional color, and a
/// per-axis range used by spider/radar charts.
public struct ChartDataPoint: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var value: Double
    public var color: String  // hex color, e.g. "#FF6B6B"
    public var minimumValue: Double
    public var maximumValue: Double

    enum CodingKeys: String, CodingKey {
        case id, name, value, color, minimumValue, maximumValue
        case min, max
        case label  // backward compat
    }

    public init(
        id: UUID = UUID(),
        name: String = "",
        value: Double = 0,
        color: String = "",
        minimumValue: Double = 0,
        maximumValue: Double = 100
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.color = color
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        normalizeRangeAndValue(includeCurrentValue: true)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // Accept both "name" and legacy "label"
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .label)
            ?? ""
        value = try Self.decodeDouble(c, keys: [.value]) ?? 0
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        minimumValue = try Self.decodeDouble(c, keys: [.minimumValue, .min]) ?? 0
        maximumValue = try Self.decodeDouble(c, keys: [.maximumValue, .max]) ?? 100
        normalizeRangeAndValue(includeCurrentValue: true)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(value, forKey: .value)
        try c.encode(color, forKey: .color)
        try c.encode(minimumValue, forKey: .minimumValue)
        try c.encode(maximumValue, forKey: .maximumValue)
    }

    public mutating func normalizeRangeAndValue(includeCurrentValue: Bool) {
        let range = Self.normalizedRange(
            min: minimumValue,
            max: maximumValue,
            including: includeCurrentValue ? value : nil
        )
        minimumValue = range.min
        maximumValue = range.max
        value = clampedValue(value)
    }

    public func normalizedValue(_ candidate: Double) -> Double {
        guard maximumValue > minimumValue else { return 0 }
        let safe = clampedValue(candidate)
        return ChartConfig.clamp((safe - minimumValue) / (maximumValue - minimumValue), min: 0, max: 1)
    }

    public func value(fromNormalized normalizedValue: Double) -> Double {
        let normalized = ChartConfig.clamp(normalizedValue, min: 0, max: 1)
        return minimumValue + normalized * (maximumValue - minimumValue)
    }

    public func clampedValue(_ candidate: Double) -> Double {
        guard candidate.isFinite else { return minimumValue }
        return ChartConfig.clamp(candidate, min: minimumValue, max: maximumValue)
    }

    public static func normalizedRange(
        min minValue: Double,
        max maxValue: Double,
        including candidate: Double? = nil
    ) -> (min: Double, max: Double) {
        var safeMin = minValue.isFinite ? minValue : 0
        var safeMax = maxValue.isFinite ? maxValue : safeMin + 100
        if let candidate, candidate.isFinite {
            safeMin = Swift.min(safeMin, candidate)
            safeMax = Swift.max(safeMax, candidate)
        }
        if safeMax <= safeMin { safeMax = safeMin + 1 }
        return (safeMin, safeMax)
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> Double? {
        for key in keys {
            if let value = try container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                return Double(value)
            }
            if let value = try container.decodeIfPresent(String.self, forKey: key),
               let parsed = Double(value) {
                return parsed
            }
        }
        return nil
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
    /// - **Spider chart**: returns one entry per series. Spider
    ///   charts are layered by series, and data points do not have
    ///   individual colors.
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

        if chartType == .spider {
            return spiderRenderableSeries().map { ChartLegendEntry(name: $0.name, colorHex: $0.color) }
        }

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

    /// User-facing value label for spider/radar chart points. Spider charts
    /// render only complete, same-axis-count series, so incomplete editable
    /// series should not force visible labels into multi-series wording.
    public func spiderDataPointLabel(for point: ChartDataPoint, in series: ChartSeries) -> String {
        let pointName = point.name.isEmpty ? "Point" : point.name
        let value = formattedSpiderValue(point.value)
        if spiderRenderableSeries().count > 1 {
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

    /// Fixed-precision formatting for spider/radar values. A precision of 0
    /// means integer data, which is the default for an omitted property.
    public static func formattedValue(_ value: Double, decimalPlaces: Int) -> String {
        guard value.isFinite else { return "\(value)" }
        let places = Int(Self.clamp(
            Double(decimalPlaces),
            min: Double(Self.spiderMinimumDecimalPlaces),
            max: Double(Self.spiderMaximumDecimalPlaces)
        ))
        let rounded = Self.quantizedValue(value, decimalPlaces: places)
        guard places > 0 else {
            if rounded >= Double(Int64.min), rounded <= Double(Int64.max) {
                return "\(Int64(rounded))"
            }
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.\(places)f", rounded)
    }
}
