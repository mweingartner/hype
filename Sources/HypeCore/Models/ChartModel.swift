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

/// A single data point with optional per-point color override.
public struct ChartDataPoint: Codable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var value: Double
    public var color: String?  // Optional per-point color (hex). Nil uses series color.

    public init(id: UUID = UUID(), label: String = "", value: Double = 0, color: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.color = color
    }
}
