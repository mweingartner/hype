import SwiftUI
import Charts
import HypeCore

enum SpiderChartPointChangePhase: Sendable {
    case began, changed, ended
}

struct SpiderChartPointChange: Sendable {
    var chartPartId: UUID?
    var seriesId: UUID
    var seriesName: String
    var pointId: UUID
    var pointName: String
    var value: Double
    var phase: SpiderChartPointChangePhase
}

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
///
/// - Spider/radar charts are rendered by Hype's native canvas, not Apple
///   Charts. They use one layered polygon per series, one color per series,
///   and per-data-point min/current/max values for each radial axis.
///
/// - Marks draw compact labels from `ChartConfig.dataPointLabel(for:in:)`.
///   Single-series labels show point name + value; multi-series labels include
///   the series name so the chart remains understandable without relying on
///   color alone.
struct ChartHostView: View {
    let config: ChartConfig
    let onSpiderPointChange: ((SpiderChartPointChange) -> Void)?

    init(
        config: ChartConfig,
        onSpiderPointChange: ((SpiderChartPointChange) -> Void)? = nil
    ) {
        self.config = config
        self.onSpiderPointChange = onSpiderPointChange
    }

    var body: some View {
        if config.chartType == .spider {
            spiderHostBody
        } else {
            standardChartHostBody
        }
    }

    private var standardChartHostBody: some View {
        VStack(spacing: 6) {
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
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
        // The chart canvas is intentionally white. Force light chart chrome so
        // axes, axis titles, and legend text remain visible when macOS is in
        // Dark Mode.
        .environment(\.colorScheme, .light)
    }

    private var spiderHostBody: some View {
        GeometryReader { geometry in
            let entries = config.showLegend ? config.legendEntries() : []
            let canvasRect = Self.spiderCanvasRect(in: geometry.size, config: config)
            let legendRect = Self.spiderLegendRect(in: geometry.size, config: config)

            ZStack(alignment: .topLeading) {
                Color.white

                if !config.title.isEmpty {
                    Text(config.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(
                            width: max(1, geometry.size.width - Self.spiderOuterPadding * 2),
                            height: Self.spiderTitleHeight,
                            alignment: .center
                        )
                        .position(
                            x: geometry.size.width / 2,
                            y: Self.spiderOuterPadding + Self.spiderTitleHeight / 2
                        )
                }

                SpiderChartCanvas(
                    config: config,
                    onPointChange: onSpiderPointChange
                )
                .frame(width: canvasRect.width, height: canvasRect.height)
                .position(x: canvasRect.midX, y: canvasRect.midY)

                if let legendRect, !entries.isEmpty {
                    legend(for: entries)
                        .frame(width: legendRect.width, height: legendRect.height, alignment: .topLeading)
                        .position(x: legendRect.midX, y: legendRect.midY)
                }
            }
        }
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    static let spiderOuterPadding: CGFloat = 10
    static let spiderVerticalSpacing: CGFloat = 6
    static let spiderTitleHeight: CGFloat = 24
    static let spiderLegendRowHeight: CGFloat = 18

    static func spiderCanvasRect(in size: CGSize, config: ChartConfig) -> CGRect {
        let width = max(1, size.width - spiderOuterPadding * 2)
        let titleBlock = config.title.isEmpty ? 0 : spiderTitleHeight + spiderVerticalSpacing
        let legendHeight = spiderLegendRect(in: size, config: config)?.height ?? 0
        let legendBlock = legendHeight > 0 ? legendHeight + spiderVerticalSpacing : 0
        let height = max(80, size.height - spiderOuterPadding * 2 - titleBlock - legendBlock)
        return CGRect(
            x: spiderOuterPadding,
            y: spiderOuterPadding + titleBlock,
            width: width,
            height: height
        )
    }

    static func spiderLegendRect(in size: CGSize, config: ChartConfig) -> CGRect? {
        guard config.showLegend else { return nil }
        let entries = config.legendEntries()
        guard !entries.isEmpty else { return nil }
        let width = max(1, size.width - spiderOuterPadding * 2)
        let columnCount = max(1, Int((width + 10) / 90))
        let rowCount = Int(ceil(Double(entries.count) / Double(columnCount)))
        let height = CGFloat(rowCount) * spiderLegendRowHeight + 4
        return CGRect(
            x: spiderOuterPadding,
            y: max(spiderOuterPadding, size.height - spiderOuterPadding - height),
            width: width,
            height: height
        )
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
        case .spider: spiderChart
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
                    .position(by: .value("Series", series.name), axis: .horizontal)
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        dataLabel(for: point, in: series)
                    }
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
                        y: .value(yLabel, point.value),
                        series: .value("Series", series.name)
                    )
                    .foregroundStyle(resolveColor(point, series))
                    PointMark(
                        x: .value(xLabel, point.name),
                        y: .value(yLabel, point.value)
                    )
                    .foregroundStyle(resolveColor(point, series))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        dataLabel(for: point, in: series)
                    }
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
                    PointMark(
                        x: .value(xLabel, point.name),
                        y: .value(yLabel, point.value)
                    )
                    .foregroundStyle(resolveColor(point, series))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        dataLabel(for: point, in: series)
                    }
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
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        dataLabel(for: point, in: series)
                    }
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
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            dataLabel(for: point, in: series)
                        }
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
                    .annotation(position: .overlay, alignment: .center, spacing: 0) {
                        pieLabel(for: point, in: series)
                    }
                }
                .chartLegend(.hidden)
            }
        }
    }

    private var spiderChart: some View {
        SpiderChartCanvas(
            config: config,
            onPointChange: onSpiderPointChange
        )
        .frame(minHeight: 180)
    }

    // MARK: - Mark labels

    private func dataLabel(for point: ChartDataPoint, in series: ChartSeries) -> some View {
        Text(config.dataPointLabel(for: point, in: series))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.86))
                    .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
            )
    }

    private func pieLabel(for point: ChartDataPoint, in series: ChartSeries) -> some View {
        Text(config.dataPointLabel(for: point, in: series))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.35))
            )
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
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 4)
    }
}

struct SpiderChartDragTarget: Equatable, Sendable {
    var seriesId: UUID
    var pointId: UUID
}

struct SpiderChartLayout {
    var size: CGSize
    var center: CGPoint
    var radius: CGFloat
    var axisCount: Int

    func angle(for index: Int) -> CGFloat {
        guard axisCount > 0 else { return -.pi / 2 }
        return -.pi / 2 + CGFloat(index) * (2 * .pi / CGFloat(axisCount))
    }

    func point(axis index: Int, normalizedValue: Double) -> CGPoint {
        let angle = angle(for: index)
        let distance = radius * CGFloat(ChartConfig.clamp(normalizedValue, min: 0, max: 1))
        return CGPoint(
            x: center.x + distance * cos(angle),
            y: center.y + distance * sin(angle)
        )
    }

    func normalizedValue(for location: CGPoint, axis index: Int) -> Double {
        guard radius > 0 else { return 0 }
        let angle = angle(for: index)
        let unit = CGPoint(x: cos(angle), y: sin(angle))
        let vector = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let projected = vector.x * unit.x + vector.y * unit.y
        return ChartConfig.clamp(Double(projected / radius), min: 0, max: 1)
    }
}

struct SpiderChartInteractionResolution {
    var target: SpiderChartDragTarget
    var seriesName: String
    var pointName: String
    var pointIndex: Int
    var value: Double
}

enum SpiderChartInteractionResolver {
    static func layout(in size: CGSize, axisCount: Int) -> SpiderChartLayout {
        let labelInsetX: CGFloat = 108
        let labelInsetY: CGFloat = 72
        let usableWidth = max(40, size.width - labelInsetX * 2)
        let usableHeight = max(40, size.height - labelInsetY * 2)
        let radius = max(20, min(usableWidth, usableHeight) / 2)
        return SpiderChartLayout(
            size: size,
            center: CGPoint(x: size.width / 2, y: size.height / 2 + 2),
            radius: radius,
            axisCount: axisCount
        )
    }

    static func point(
        for series: ChartSeries,
        dataIndex: Int,
        config: ChartConfig,
        layout: SpiderChartLayout,
        liveValue: Double? = nil
    ) -> CGPoint {
        guard dataIndex < series.data.count else {
            return layout.point(axis: dataIndex, normalizedValue: 0)
        }
        let point = series.data[dataIndex]
        return layout.point(
            axis: dataIndex,
            normalizedValue: config.normalizedSpiderValue(for: point, value: liveValue ?? point.value)
        )
    }

    static func resolve(
        config: ChartConfig,
        location: CGPoint,
        size: CGSize,
        activeTarget: SpiderChartDragTarget?
    ) -> SpiderChartInteractionResolution? {
        let axisCount = config.spiderAxisLabels().count
        guard axisCount >= 3 else { return nil }
        let layout = layout(in: size, axisCount: axisCount)
        let target = activeTarget ?? nearestTarget(to: location, config: config, layout: layout)
        guard let target,
              let resolved = resolvedTarget(target, config: config) else {
            return nil
        }
        let normalized = layout.normalizedValue(for: location, axis: resolved.pointIndex)
        let value = config.spiderValue(for: resolved.point, from: normalized)
        return SpiderChartInteractionResolution(
            target: target,
            seriesName: resolved.series.name,
            pointName: resolved.point.name.isEmpty ? "Point \(resolved.pointIndex + 1)" : resolved.point.name,
            pointIndex: resolved.pointIndex,
            value: value
        )
    }

    static func nearestTarget(
        to location: CGPoint,
        config: ChartConfig,
        layout: SpiderChartLayout
    ) -> SpiderChartDragTarget? {
        if let markerTarget = nearestMarkerTarget(to: location, config: config, layout: layout) {
            return markerTarget
        }
        return nearestAxisTarget(to: location, config: config, layout: layout)
    }

    static func nearestMarkerTarget(
        to location: CGPoint,
        config: ChartConfig,
        layout: SpiderChartLayout
    ) -> SpiderChartDragTarget? {
        var best: (target: SpiderChartDragTarget, distance: CGFloat)?
        for series in config.spiderRenderableSeries() {
            for (index, point) in series.data.enumerated() {
                let marker = self.point(for: series, dataIndex: index, config: config, layout: layout)
                let label = valueLabelPoint(markerPoint: marker, axisIndex: index, layout: layout)
                let distance = min(
                    hypot(marker.x - location.x, marker.y - location.y),
                    hypot(label.x - location.x, label.y - location.y)
                )
                if best == nil || distance < best!.distance {
                    best = (SpiderChartDragTarget(seriesId: series.id, pointId: point.id), distance)
                }
            }
        }
        guard let best, best.distance <= 34 else { return nil }
        return best.target
    }

    static func nearestAxisTarget(
        to location: CGPoint,
        config: ChartConfig,
        layout: SpiderChartLayout
    ) -> SpiderChartDragTarget? {
        let vector = CGPoint(x: location.x - layout.center.x, y: location.y - layout.center.y)
        let distance = hypot(vector.x, vector.y)
        guard layout.axisCount >= 3,
              distance > 4,
              distance <= layout.radius + 44 else {
            return nil
        }

        var bestAxis = 0
        var bestDot = -CGFloat.greatestFiniteMagnitude
        for index in 0..<layout.axisCount {
            let angle = layout.angle(for: index)
            let unit = CGPoint(x: cos(angle), y: sin(angle))
            let dot = (vector.x / distance) * unit.x + (vector.y / distance) * unit.y
            if dot > bestDot {
                bestDot = dot
                bestAxis = index
            }
        }

        let sectorThreshold = cos(.pi / CGFloat(layout.axisCount))
        guard bestDot >= sectorThreshold || distance <= 34 else { return nil }
        let projectedDistance = ChartConfig.clamp(Double(distance * bestDot / layout.radius), min: 0, max: 1)

        var best: (target: SpiderChartDragTarget, distance: Double)?
        for series in config.spiderRenderableSeries() where bestAxis < series.data.count {
            let point = series.data[bestAxis]
            let pointDistance = config.normalizedSpiderValue(for: point)
            let radialDelta = abs(pointDistance - projectedDistance)
            let target = SpiderChartDragTarget(seriesId: series.id, pointId: point.id)
            if best == nil || radialDelta < best!.distance {
                best = (target, radialDelta)
            }
        }
        return best?.target
    }

    static func resolvedTarget(
        _ target: SpiderChartDragTarget,
        config: ChartConfig
    ) -> (series: ChartSeries, seriesIndex: Int, point: ChartDataPoint, pointIndex: Int)? {
        guard let seriesIndex = config.series.firstIndex(where: { $0.id == target.seriesId }) else {
            return nil
        }
        let series = config.series[seriesIndex]
        guard let pointIndex = series.data.firstIndex(where: { $0.id == target.pointId }) else {
            return nil
        }
        guard config.spiderRenderableSeries().contains(where: { $0.id == target.seriesId }) else {
            return nil
        }
        return (series, seriesIndex, series.data[pointIndex], pointIndex)
    }

    static func valueLabelPoint(markerPoint: CGPoint, axisIndex: Int, layout: SpiderChartLayout) -> CGPoint {
        let angle = layout.angle(for: axisIndex)
        let axisUnit = CGPoint(x: cos(angle), y: sin(angle))
        let dx = markerPoint.x - layout.center.x
        let dy = markerPoint.y - layout.center.y
        let distance = hypot(dx, dy)
        let unit = distance < 1 ? axisUnit : CGPoint(x: dx / distance, y: dy / distance)
        let labelDistance = min(layout.radius * 0.95, max(layout.radius * 0.12, distance + 14))
        return CGPoint(
            x: layout.center.x + unit.x * labelDistance,
            y: layout.center.y + unit.y * labelDistance
        )
    }
}

private struct SpiderChartCanvas: View {
    let config: ChartConfig
    let onPointChange: ((SpiderChartPointChange) -> Void)?

    @State private var dragTarget: SpiderChartDragTarget?
    @State private var liveValues: [UUID: Double] = [:]
    /// Drives the grow-from-center reveal animation on first appear.
    /// Starts at 0 (invisible/collapsed) and animates to 1 (full size).
    @State private var revealProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let labels = config.spiderAxisLabels()
            let layout = SpiderChartInteractionResolver.layout(in: geometry.size, axisCount: labels.count)
            if config.interactable {
                content(labels: labels, layout: layout)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(layout: layout))
            } else {
                content(labels: labels, layout: layout)
            }
        }
    }

    private func content(labels: [String], layout: SpiderChartLayout) -> some View {
        let renderableSeries = config.spiderRenderableSeries()
        return ZStack {
            if layout.axisCount < 3 || renderableSeries.isEmpty {
                Text("Spider charts need at least 3 matching data points per series")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.7))
            } else {
                gridLayer(labels: labels, layout: layout)
                seriesLayer(seriesList: renderableSeries, layout: layout)
                    // Grow-from-center reveal on first appear (reduce-motion safe).
                    .scaleEffect(reduceMotion ? 1 : revealProgress, anchor: .center)
                    .opacity(reduceMotion ? 1 : revealProgress)
                    // Animate data changes smoothly; suppress during live drag so
                    // the cursor tracks 1:1 with no lag.
                    .animation(
                        (reduceMotion || dragTarget != nil) ? nil : .easeInOut(duration: 0.3),
                        value: config.toJSON()
                    )
                if config.spiderShowValueLabels {
                    valueLabelLayer(seriesList: renderableSeries, layout: layout)
                }
                if config.interactable {
                    interactionLayer(seriesList: renderableSeries, layout: layout)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spider chart: \(labels.count) axes, \(renderableSeries.count) series")
        .onAppear {
            guard revealProgress == 0 else { return }
            if reduceMotion {
                revealProgress = 1
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    revealProgress = 1
                }
            }
        }
        .onChange(of: config.toJSON()) { _, _ in
            liveValues.removeAll(keepingCapacity: true)
            dragTarget = nil
        }
    }

    private func gridLayer(labels: [String], layout: SpiderChartLayout) -> some View {
        ZStack {
            if config.showGrid {
                let ringCount = max(ChartConfig.spiderMinimumRingCount, config.spiderRingCount)

                // Split-area alternating filled bands — drawn largest-to-smallest
                // so smaller rings paint over the centers, yielding visible bands.
                if config.spiderShowSplitArea {
                    ForEach((1...ringCount).reversed(), id: \.self) { ring in
                        let fraction = Double(ring) / Double(ringCount)
                        // Even-index rings (0-based: 0, 2, 4 …) get a subtle fill;
                        // odd-index rings are clear. Ring index is (ring - 1).
                        let bandOpacity: Double = (ring % 2 == 0) ? 0.04 : 0.0
                        if config.spiderCircularGrid {
                            Circle()
                                .inset(by: 0)
                                .path(in: CGRect(
                                    x: layout.center.x - layout.radius * CGFloat(fraction),
                                    y: layout.center.y - layout.radius * CGFloat(fraction),
                                    width: layout.radius * CGFloat(fraction) * 2,
                                    height: layout.radius * CGFloat(fraction) * 2
                                ))
                                .fill(Color(hex: config.spiderGridColor).opacity(bandOpacity))
                        } else {
                            Path { path in
                                polygonPath(&path, layout: layout, normalizedValue: fraction)
                            }
                            .fill(Color(hex: config.spiderGridColor).opacity(bandOpacity))
                        }
                    }
                }

                ForEach(1...ringCount, id: \.self) { ring in
                    let fraction = Double(ring) / Double(ringCount)
                    // Ring strokes — drawn on top of any split-area fills.
                    if config.spiderCircularGrid {
                        Circle()
                            .path(in: CGRect(
                                x: layout.center.x - layout.radius * CGFloat(fraction),
                                y: layout.center.y - layout.radius * CGFloat(fraction),
                                width: layout.radius * CGFloat(fraction) * 2,
                                height: layout.radius * CGFloat(fraction) * 2
                            ))
                            .stroke(
                                Color(hex: config.spiderGridColor).opacity(ring == ringCount ? 0.95 : 0.78),
                                lineWidth: ring == ringCount ? 1.2 : 0.9
                            )
                    } else {
                        Path { path in
                            polygonPath(&path, layout: layout, normalizedValue: fraction)
                        }
                        .stroke(
                            Color(hex: config.spiderGridColor).opacity(ring == ringCount ? 0.95 : 0.78),
                            lineWidth: ring == ringCount ? 1.2 : 0.9
                        )
                    }

                }
            }

            ForEach(0..<layout.axisCount, id: \.self) { index in
                Path { path in
                    path.move(to: layout.center)
                    path.addLine(to: layout.point(axis: index, normalizedValue: 1.0))
                }
                .stroke(Color(hex: config.spiderAxisColor).opacity(0.8), lineWidth: 0.95)
            }

            if config.showGrid {
                let ringCount = max(ChartConfig.spiderMinimumRingCount, config.spiderRingCount)
                ForEach(0...ringCount, id: \.self) { ring in
                    let fraction = Double(ring) / Double(ringCount)
                    Text(config.formattedSpiderValue(config.spiderRadialTickValue(fraction: fraction)))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: config.spiderLabelColor).opacity(0.9))
                        .position(radialTickLabelPoint(fraction: fraction, layout: layout))
                }
            }

            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let endpoint = layout.point(axis: index, normalizedValue: 1.0)
                let labelPoint = axisLabelPoint(endpoint: endpoint, center: layout.center)
                // Angle-aware alignment: right-side labels left-align,
                // left-side labels right-align, top/bottom labels center.
                let cosA = cos(layout.angle(for: index))
                let side: Int = cosA > 0.25 ? 1 : (cosA < -0.25 ? -1 : 0)
                let alignment: Alignment = side > 0 ? .leading : (side < 0 ? .trailing : .center)
                let nudgedX = labelPoint.x + CGFloat(side) * 8
                Text(label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(hex: config.spiderLabelColor))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .frame(width: 110, alignment: alignment)
                    .position(x: nudgedX, y: labelPoint.y)
            }
        }
    }

    private func seriesLayer(seriesList: [ChartSeries], layout: SpiderChartLayout) -> some View {
        // When three or more series stack on top of each other the fills can
        // become muddy. Cap the effective fill opacity at 0.16 so the stroke
        // remains the primary visual discriminator.
        let effectiveFillOpacity = seriesList.count >= 3
            ? min(config.spiderFillOpacity, 0.16)
            : config.spiderFillOpacity
        return ZStack {
            ForEach(seriesList) { series in
                Path { path in
                    for index in 0..<layout.axisCount {
                        let point = spiderPoint(for: series, dataIndex: index, layout: layout)
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    path.closeSubpath()
                }
                .fill(Color(hex: series.color).opacity(effectiveFillOpacity))

                Path { path in
                    for index in 0..<layout.axisCount {
                        let point = spiderPoint(for: series, dataIndex: index, layout: layout)
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    path.closeSubpath()
                }
                .stroke(
                    Color(hex: series.color),
                    style: StrokeStyle(lineWidth: 2.8, lineJoin: .round)
                )

                if config.interactable {
                    ForEach(Array(series.data.enumerated()), id: \.element.id) { index, point in
                        let markerPoint = spiderPoint(for: series, dataIndex: index, layout: layout)
                        Circle()
                            .fill(Color(hex: series.color))
                            .frame(width: markerDiameter(for: point), height: markerDiameter(for: point))
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.2))
                            .shadow(color: markerShadow(for: point), radius: 5, x: 0, y: 0)
                            .position(markerPoint)
                    }
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private func interactionLayer(seriesList: [ChartSeries], layout: SpiderChartLayout) -> some View {
        ZStack {
            ForEach(seriesList) { series in
                ForEach(Array(series.data.enumerated()), id: \.element.id) { index, point in
                    let markerPoint = spiderPoint(for: series, dataIndex: index, layout: layout)
                    Circle()
                        // A nearly transparent fill gives SwiftUI a real hit
                        // region without drawing a visible affordance over the
                        // chart. The visible marker can remain compact while
                        // the pointer target follows macOS' practical 44pt hit
                        // area for drag handles.
                        .fill(Color.black.opacity(0.001))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .position(markerPoint)
                        .accessibilityLabel("Drag \(point.name.isEmpty ? "Point \(index + 1)" : point.name)")
                        .accessibilityValue(config.formattedSpiderValue(liveValues[point.id] ?? point.value))
                        .gesture(pointDragGesture(
                            target: SpiderChartDragTarget(seriesId: series.id, pointId: point.id),
                            markerPoint: markerPoint,
                            layout: layout
                        ))
                }
            }
        }
    }

    private func valueLabelLayer(seriesList: [ChartSeries], layout: SpiderChartLayout) -> some View {
        ZStack {
            ForEach(seriesList) { series in
                ForEach(Array(series.data.enumerated()), id: \.element.id) { index, point in
                    let markerPoint = spiderPoint(for: series, dataIndex: index, layout: layout)
                    let labelPoint = valueLabelPoint(markerPoint: markerPoint, axisIndex: index, layout: layout)
                    Text(config.spiderDataPointLabel(for: displayedPoint(point), in: series))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.82))
                                .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                        )
                        .position(labelPoint)
                }
            }
        }
    }

    private func pointDragGesture(
        target: SpiderChartDragTarget,
        markerPoint: CGPoint,
        layout: SpiderChartLayout
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard layout.axisCount >= 3,
                      dragTarget == nil || dragTarget == target,
                      let resolved = resolvedTarget(target) else { return }
                let chartLocation = chartLocation(fromHitTargetLocation: value.location, markerPoint: markerPoint)
                if dragTarget == nil {
                    dragTarget = target
                    applyDrag(
                        target: target,
                        resolved: resolved,
                        location: chartLocation,
                        layout: layout,
                        phase: .began
                    )
                } else {
                    applyDrag(
                        target: target,
                        resolved: resolved,
                        location: chartLocation,
                        layout: layout,
                        phase: .changed
                    )
                }
            }
            .onEnded { value in
                guard dragTarget == nil || dragTarget == target,
                      let resolved = resolvedTarget(target) else {
                    dragTarget = nil
                    return
                }
                let chartLocation = chartLocation(fromHitTargetLocation: value.location, markerPoint: markerPoint)
                applyDrag(
                    target: target,
                    resolved: resolved,
                    location: chartLocation,
                    layout: layout,
                    phase: .ended
                )
                dragTarget = nil
            }
    }

    private func chartLocation(fromHitTargetLocation location: CGPoint, markerPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: markerPoint.x + location.x - 22,
            y: markerPoint.y + location.y - 22
        )
    }

    private func dragGesture(layout: SpiderChartLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard layout.axisCount >= 3 else { return }
                let target = dragTarget ?? nearestTarget(to: value.location, layout: layout)
                guard let target,
                      let resolved = resolvedTarget(target) else { return }
                if dragTarget == nil {
                    dragTarget = target
                    applyDrag(
                        target: target,
                        resolved: resolved,
                        location: value.location,
                        layout: layout,
                        phase: .began
                    )
                } else {
                    applyDrag(
                        target: target,
                        resolved: resolved,
                        location: value.location,
                        layout: layout,
                        phase: .changed
                    )
                }
            }
            .onEnded { value in
                guard let target = dragTarget,
                      let resolved = resolvedTarget(target) else {
                    dragTarget = nil
                    return
                }
                applyDrag(
                    target: target,
                    resolved: resolved,
                    location: value.location,
                    layout: layout,
                    phase: .ended
                )
                dragTarget = nil
            }
    }

    private func applyDrag(
        target: SpiderChartDragTarget,
        resolved: (series: ChartSeries, seriesIndex: Int, point: ChartDataPoint, pointIndex: Int),
        location: CGPoint,
        layout: SpiderChartLayout,
        phase: SpiderChartPointChangePhase
    ) {
        let normalized = layout.normalizedValue(for: location, axis: resolved.pointIndex)
        let value = config.spiderValue(for: resolved.point, from: normalized)
        liveValues[target.pointId] = value
        onPointChange?(
            SpiderChartPointChange(
                chartPartId: nil,
                seriesId: target.seriesId,
                seriesName: resolved.series.name,
                pointId: target.pointId,
                pointName: resolved.point.name.isEmpty ? "Point \(resolved.pointIndex + 1)" : resolved.point.name,
                value: value,
                phase: phase
            )
        )
    }

    private func nearestTarget(to location: CGPoint, layout: SpiderChartLayout) -> SpiderChartDragTarget? {
        if let markerTarget = nearestMarkerTarget(to: location, layout: layout) {
            return markerTarget
        }
        return nearestAxisTarget(to: location, layout: layout)
    }

    private func nearestMarkerTarget(to location: CGPoint, layout: SpiderChartLayout) -> SpiderChartDragTarget? {
        var best: (target: SpiderChartDragTarget, distance: CGFloat)?
        for series in config.spiderRenderableSeries() {
            for (index, point) in series.data.enumerated() {
                let marker = spiderPoint(for: series, dataIndex: index, layout: layout)
                let label = valueLabelPoint(markerPoint: marker, axisIndex: index, layout: layout)
                let distance = min(
                    hypot(marker.x - location.x, marker.y - location.y),
                    hypot(label.x - location.x, label.y - location.y)
                )
                if best == nil || distance < best!.distance {
                    best = (SpiderChartDragTarget(seriesId: series.id, pointId: point.id), distance)
                }
            }
        }
        guard let best, best.distance <= 34 else { return nil }
        return best.target
    }

    private func nearestAxisTarget(to location: CGPoint, layout: SpiderChartLayout) -> SpiderChartDragTarget? {
        let vector = CGPoint(x: location.x - layout.center.x, y: location.y - layout.center.y)
        let distance = hypot(vector.x, vector.y)
        guard layout.axisCount >= 3,
              distance > 4,
              distance <= layout.radius + 44 else {
            return nil
        }

        var bestAxis = 0
        var bestDot = -CGFloat.greatestFiniteMagnitude
        for index in 0..<layout.axisCount {
            let angle = layout.angle(for: index)
            let unit = CGPoint(x: cos(angle), y: sin(angle))
            let dot = (vector.x / distance) * unit.x + (vector.y / distance) * unit.y
            if dot > bestDot {
                bestDot = dot
                bestAxis = index
            }
        }

        let sectorThreshold = cos(.pi / CGFloat(layout.axisCount))
        guard bestDot >= sectorThreshold || distance <= 34 else { return nil }
        let projectedDistance = ChartConfig.clamp(Double(distance * bestDot / layout.radius), min: 0, max: 1)

        var best: (target: SpiderChartDragTarget, distance: Double)?
        for series in config.spiderRenderableSeries() where bestAxis < series.data.count {
            let point = series.data[bestAxis]
            let pointDistance = config.normalizedSpiderValue(for: point)
            let radialDelta = abs(pointDistance - projectedDistance)
            let target = SpiderChartDragTarget(seriesId: series.id, pointId: point.id)
            if best == nil || radialDelta < best!.distance {
                best = (target, radialDelta)
            }
        }
        return best?.target
    }

    private func resolvedTarget(
        _ target: SpiderChartDragTarget
    ) -> (series: ChartSeries, seriesIndex: Int, point: ChartDataPoint, pointIndex: Int)? {
        SpiderChartInteractionResolver.resolvedTarget(target, config: config)
    }

    private func spiderPoint(for series: ChartSeries, dataIndex: Int, layout: SpiderChartLayout) -> CGPoint {
        SpiderChartInteractionResolver.point(
            for: series,
            dataIndex: dataIndex,
            config: config,
            layout: layout,
            liveValue: dataIndex < series.data.count ? liveValues[series.data[dataIndex].id] : nil
        )
    }

    private func displayedPoint(_ point: ChartDataPoint) -> ChartDataPoint {
        guard let live = liveValues[point.id] else { return point }
        var copy = point
        copy.value = live
        return copy
    }

    private func markerDiameter(for point: ChartDataPoint) -> CGFloat {
        let selected = dragTarget?.pointId == point.id
        return CGFloat(config.spiderPointRadius) * (selected ? 2.6 : 1.2)
    }

    private func markerShadow(for point: ChartDataPoint) -> Color {
        dragTarget?.pointId == point.id ? Color(hex: config.spiderAxisColor).opacity(0.45) : .clear
    }

    private func polygonPath(_ path: inout Path, layout: SpiderChartLayout, normalizedValue: Double) {
        for index in 0..<layout.axisCount {
            let point = layout.point(axis: index, normalizedValue: normalizedValue)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
    }

    private func axisLabelPoint(endpoint: CGPoint, center: CGPoint) -> CGPoint {
        let dx = endpoint.x - center.x
        let dy = endpoint.y - center.y
        let distance = max(1, hypot(dx, dy))
        return CGPoint(
            x: endpoint.x + dx / distance * 38,
            y: endpoint.y + dy / distance * 34
        )
    }

    private func radialTickLabelPoint(fraction: Double, layout: SpiderChartLayout) -> CGPoint {
        let point = layout.point(axis: 0, normalizedValue: fraction)
        return CGPoint(x: layout.center.x + 18, y: point.y)
    }

    private func valueLabelPoint(markerPoint: CGPoint, axisIndex: Int, layout: SpiderChartLayout) -> CGPoint {
        SpiderChartInteractionResolver.valueLabelPoint(markerPoint: markerPoint, axisIndex: axisIndex, layout: layout)
    }

    private static func layout(in size: CGSize, axisCount: Int) -> SpiderChartLayout {
        SpiderChartInteractionResolver.layout(in: size, axisCount: axisCount)
    }
}
