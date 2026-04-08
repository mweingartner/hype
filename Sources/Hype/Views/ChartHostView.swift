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

    @ViewBuilder
    private var standardChart: some View {
        Chart {
            ForEach(config.series) { series in
                ForEach(series.data) { point in
                    switch config.chartType {
                    case .bar:
                        BarMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(Color(hex: series.color))
                    case .line:
                        LineMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(Color(hex: series.color))
                    case .area:
                        AreaMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(Color(hex: series.color).opacity(0.3))
                    case .point:
                        PointMark(
                            x: .value(config.xAxisLabel.isEmpty ? "Category" : config.xAxisLabel, point.label),
                            y: .value(config.yAxisLabel.isEmpty ? "Value" : config.yAxisLabel, point.value)
                        )
                        .foregroundStyle(Color(hex: series.color))
                    case .rule:
                        RuleMark(y: .value("Value", point.value))
                            .foregroundStyle(Color(hex: series.color))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    case .pie:
                        // Handled separately
                        let _ = point  // suppress unused warning
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
                .foregroundStyle(by: .value("Category", point.label))
                .cornerRadius(4)
            }
            .chartLegend(config.showLegend ? .visible : .hidden)
        }
    }
}
