import SwiftUI
import Charts
import HypeCore

/// SwiftUI view that renders a chart from a `ChartConfig`.
///
/// Rendering strategy:
///
/// - Every mark is colored with a **direct** `.foregroundStyle(Color)` call
///   driven by `resolveColor(point, series)`. This preserves the per-data-point
///   color override from `ChartDataPoint.color` — SwiftUI Charts' alternative
///   (`.foregroundStyle(by: .value(...))`) groups marks by a dimension and
///   picks colors from a scale, which fundamentally *cannot* honour per-point
///   colors. Direct styling is the only correct option for Hype's data model.
///
/// - Because direct styling does not feed SwiftUI Charts' auto-generated
///   legend, we render the legend ourselves from `config.legendEntries()`,
///   which lives in HypeCore and is fully unit-tested. The custom legend
///   is a `LazyVGrid` with adaptive columns so it wraps gracefully for
///   charts with many entries.
///
/// - Axis titles use `chartXAxisLabel(_:)` / `chartYAxisLabel(_:)` with
///   fallbacks to "Category" / "Value" so an unconfigured chart still has
///   readable axis labels instead of blank space.
struct ChartHostView: View {
    let config: ChartConfig

    var body: some View {
        VStack(spacing: 6) {
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }

            chartBody

            if config.showLegend {
                let entries = config.legendEntries()
                if !entries.isEmpty {
                    legend(for: entries)
                }
            }
        }
        .padding(10)
        .background(Color.white)
    }

    @ViewBuilder
    private var chartBody: some View {
        switch config.chartType {
        case .bar: barChart
        case .line: lineChart
        case .area: areaChart
        case .point: pointChart
        case .rule: ruleChart
        case .pie: pieChart
        }
    }

    // MARK: - Color resolution

    /// Effective color for a single mark: point color overrides series color.
    /// Any malformed hex resolves to white via `Color(hex:)` defaults.
    private func resolveColor(_ point: ChartDataPoint, _ series: ChartSeries) -> Color {
        if !point.color.isEmpty { return Color(hex: point.color) }
        return Color(hex: series.color)
    }

    // MARK: - Axis label fallbacks

    /// Displayed X-axis title. Falls back to "Category" when the caller
    /// has not set an explicit label — an unconfigured cartesian chart
    /// should still have visible axis titles.
    private var xLabel: String { config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel }

    /// Displayed Y-axis title. Falls back to "Value".
    private var yLabel: String { config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel }

    // MARK: - Chart bodies

    private var barChart: some View {
        Chart {
            ForEach(config.series) { series in
                ForEach(series.data) { point in
                    BarMark(
                        x: .value(xLabel, point.name),
                        y: .value(yLabel, point.value)
                    )
                    .foregroundStyle(resolveColor(point, series))
                }
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .chartLegend(.hidden)  // we draw our own legend below
    }

    private var lineChart: some View {
        // Note: for multi-series line charts where two series share the same
        // X values, SwiftUI Charts will connect marks in insertion order and
        // the lines may cross. Hype's primary use case is single-series
        // per-point-colored charts, so we keep the rendering path simple.
        // Multi-series distinction can be added later via a series-grouping
        // dimension that does not clobber the per-point foregroundStyle.
        Chart {
            ForEach(config.series) { series in
                ForEach(series.data) { point in
                    LineMark(
                        x: .value(xLabel, point.name),
                        y: .value(yLabel, point.value)
                    )
                    .foregroundStyle(resolveColor(point, series))
                }
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .chartLegend(.hidden)
    }

    private var areaChart: some View {
        Chart {
            ForEach(config.series) { series in
                ForEach(series.data) { point in
                    AreaMark(
                        x: .value(xLabel, point.name),
                        y: .value(yLabel, point.value)
                    )
                    .foregroundStyle(resolveColor(point, series).opacity(0.35))
                }
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .chartLegend(.hidden)
    }

    private var pointChart: some View {
        Chart {
            ForEach(config.series) { series in
                ForEach(series.data) { point in
                    PointMark(
                        x: .value(xLabel, point.name),
                        y: .value(yLabel, point.value)
                    )
                    .foregroundStyle(resolveColor(point, series))
                }
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .chartLegend(.hidden)
    }

    private var ruleChart: some View {
        Chart {
            ForEach(config.series) { series in
                ForEach(series.data) { point in
                    RuleMark(y: .value(yLabel, point.value))
                        .foregroundStyle(resolveColor(point, series))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .chartLegend(.hidden)
    }

    private var pieChart: some View {
        Group {
            if let series = config.series.first {
                Chart(series.data) { point in
                    SectorMark(
                        angle: .value("Value", point.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(resolveColor(point, series))
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
            }
        }
    }

    // MARK: - Custom legend

    /// Build a colored legend from `ChartLegendEntry` rows.
    ///
    /// Uses `LazyVGrid` with adaptive columns (minimum 80pt, maximum
    /// 160pt) so the legend wraps naturally for charts with many
    /// entries (e.g. 12 months) without being forced onto a single
    /// horizontal line or into a fixed column count.
    @ViewBuilder
    private func legend(for entries: [ChartLegendEntry]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 80, maximum: 160), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: entry.colorHex))
                        .frame(width: 12, height: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                        )
                    Text(entry.name)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 4)
    }
}
