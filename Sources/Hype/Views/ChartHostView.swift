import SwiftUI
import Charts
import HypeCore

/// SwiftUI view that renders a chart from ChartConfig data.
struct ChartHostView: View {
    let config: ChartConfig

    var body: some View {
        VStack(spacing: 4) {
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            if config.chartType == .pie {
                pieChart
            } else {
                standardChart
            }
        }
        .padding(8)
        .background(Color.white)
    }

    /// Resolve the color for a data point: use point color if set, otherwise series color.
    private func pointColor(_ point: ChartDataPoint, series: ChartSeries) -> Color {
        if let pc = point.color, !pc.isEmpty {
            return Color(hex: pc)
        }
        return Color(hex: series.color)
    }

    @ViewBuilder
    private var standardChart: some View {
        Chart {
            ForEach(config.series) { series in
                ForEach(series.data) { point in
                    let color = pointColor(point, series: series)
                    switch config.chartType {
                    case .bar:
                        BarMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(color)
                    case .line:
                        LineMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(color)
                    case .area:
                        AreaMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(color.opacity(0.3))
                    case .point:
                        PointMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(color)
                    case .rule:
                        RuleMark(y: .value("Value", point.value))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    case .pie:
                        let _ = point
                    }
                }
            }
        }
        .chartLegend(config.showLegend ? .visible : .hidden)
    }

    @ViewBuilder
    private var pieChart: some View {
        if let series = config.series.first {
            Chart(series.data) { point in
                SectorMark(
                    angle: .value("Value", point.value),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(pointColor(point, series: series))
                .cornerRadius(4)
            }
            .chartLegend(config.showLegend ? .visible : .hidden)
        }
    }
}
