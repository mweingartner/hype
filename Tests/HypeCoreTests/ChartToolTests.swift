import Testing
import Foundation
@testable import HypeCore

/// Regression tests for the AI chart-authoring path.
///
/// Before the fix, `HypeToolExecutor.create_chart` only propagated chart
/// type and title to `ChartConfig`, so AI-created charts had empty
/// `xAxisLabel` / `yAxisLabel` fields. The `ChartHostView` then rendered
/// `.chartXAxisLabel("")` / `.chartYAxisLabel("")` which, combined with a
/// legend that was gated on `series.count > 1`, produced a chart with no
/// visible legend and no axis titles.
///
/// These tests pin the executor's behaviour so the `ChartConfig`
/// persisted in `Part.chartData` always carries what the renderer needs.
@Suite("Chart tool — axis labels and legend")
struct ChartToolTests {

    private func makeDoc() -> (HypeDocument, UUID) {
        let doc = HypeDocument.newDocument(name: "Chart Test")
        return (doc, doc.cards[0].id)
    }

    private func chartConfig(in doc: HypeDocument, named name: String) -> ChartConfig? {
        guard let part = doc.parts.first(where: { $0.name == name }) else { return nil }
        return ChartConfig.fromJSON(part.chartData)
    }

    // MARK: - create_chart plumbs axis labels + legend + grid

    @Test("create_chart stores x/y axis labels from tool arguments")
    func createChartPropagatesAxisLabels() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Sales Chart",
                "chart_type": "bar",
                "title": "Monthly Sales",
                "left": "50", "top": "50",
                "width": "400", "height": "300",
                "data": "Jan=120,Feb=150,Mar=180",
                "x_axis_label": "Month",
                "y_axis_label": "Sales ($)",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("Created chart"))
        let config = chartConfig(in: doc, named: "Sales Chart")
        #expect(config != nil)
        #expect(config?.xAxisLabel == "Month")
        #expect(config?.yAxisLabel == "Sales ($)")
        #expect(config?.title == "Monthly Sales")
        #expect(config?.chartType == .bar)
        // Legend should default to true so the rendered chart always shows one
        // unless the caller explicitly asks to hide it.
        #expect(config?.showLegend == true)
        #expect(config?.showGrid == true)
    }

    @Test("create_chart defaults showLegend to true when the flag is omitted")
    func createChartDefaultsLegendOn() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Default Legend",
                "chart_type": "line",
                "left": "0", "top": "0",
                "width": "200", "height": "150",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let config = chartConfig(in: doc, named: "Default Legend")
        #expect(config?.showLegend == true)
        #expect(config?.showGrid == true)
    }

    @Test("create_chart respects show_legend='false' to hide the legend")
    func createChartHonoursShowLegendFalse() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Hidden Legend",
                "chart_type": "bar",
                "left": "0", "top": "0",
                "width": "200", "height": "150",
                "show_legend": "false",
                "show_grid": "false",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let config = chartConfig(in: doc, named: "Hidden Legend")
        #expect(config?.showLegend == false)
        #expect(config?.showGrid == false)
    }

    @Test("create_chart axis labels work alongside series_name and series_color")
    func createChartWithFullStylingSet() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Styled",
                "chart_type": "line",
                "title": "Temperature",
                "left": "10", "top": "10",
                "width": "300", "height": "200",
                "data": "Mon=60,Tue=65,Wed=70,Thu=68,Fri=72",
                "series_name": "Degrees F",
                "series_color": "#FF6B6B",
                "x_axis_label": "Day",
                "y_axis_label": "Temperature (°F)",
            ],
            document: &doc,
            currentCardId: cardId
        )

        let config = chartConfig(in: doc, named: "Styled")
        #expect(config?.xAxisLabel == "Day")
        #expect(config?.yAxisLabel == "Temperature (°F)")
        #expect(config?.series.count == 1)
        #expect(config?.series.first?.name == "Degrees F")
        #expect(config?.series.first?.color == "#FF6B6B")
        #expect(config?.series.first?.data.count == 5)
    }

    // MARK: - set_part_property edits axis labels + legend + grid

    @Test("set_part_property can set x_axis_label on an existing chart")
    func setPartPropertyUpdatesXAxisLabel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()

        // Create a chart without axis labels.
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Bare",
                "chart_type": "bar",
                "left": "0", "top": "0",
                "width": "200", "height": "150",
                "data": "A=1,B=2",
            ],
            document: &doc,
            currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Bare")?.xAxisLabel == "")

        // Follow-up: set the x axis label.
        let result = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "Bare",
                "property": "x_axis_label",
                "value": "Category",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(result.contains("Set"))
        #expect(chartConfig(in: doc, named: "Bare")?.xAxisLabel == "Category")
        // And the rest of the config survives the update.
        #expect(chartConfig(in: doc, named: "Bare")?.series.first?.data.count == 2)
        #expect(chartConfig(in: doc, named: "Bare")?.chartType == .bar)
    }

    @Test("set_part_property can set y_axis_label on an existing chart")
    func setPartPropertyUpdatesYAxisLabel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Chart Y",
                "chart_type": "line",
                "left": "0", "top": "0",
                "width": "200", "height": "150",
                "data": "1=10,2=20",
            ],
            document: &doc,
            currentCardId: cardId
        )

        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: [
                "part_name": "Chart Y",
                "property": "y_axis_label",
                "value": "Revenue",
            ],
            document: &doc,
            currentCardId: cardId
        )

        #expect(chartConfig(in: doc, named: "Chart Y")?.yAxisLabel == "Revenue")
    }

    @Test("set_part_property accepts snake_case, camelCase, and short forms")
    func setPartPropertyAxisLabelAliases() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Alias", "chart_type": "bar",
                "left": "0", "top": "0", "width": "100", "height": "100",
                "data": "A=1",
            ],
            document: &doc, currentCardId: cardId
        )

        // snake_case with full name.
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "Alias", "property": "x_axis_label", "value": "X1"],
            document: &doc, currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Alias")?.xAxisLabel == "X1")

        // camelCase.
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "Alias", "property": "xaxislabel", "value": "X2"],
            document: &doc, currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Alias")?.xAxisLabel == "X2")

        // Short form.
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "Alias", "property": "x_label", "value": "X3"],
            document: &doc, currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Alias")?.xAxisLabel == "X3")

        // Same coverage for the Y axis.
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "Alias", "property": "ylabel", "value": "Y1"],
            document: &doc, currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Alias")?.yAxisLabel == "Y1")
    }

    @Test("set_part_property toggles show_legend on an existing chart")
    func setPartPropertyUpdatesShowLegend() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Legendable", "chart_type": "bar",
                "left": "0", "top": "0", "width": "100", "height": "100",
                "data": "A=1",
            ],
            document: &doc, currentCardId: cardId
        )

        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "Legendable", "property": "show_legend", "value": "false"],
            document: &doc, currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Legendable")?.showLegend == false)

        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "Legendable", "property": "show_legend", "value": "true"],
            document: &doc, currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Legendable")?.showLegend == true)
    }

    @Test("set_part_property toggles show_grid on an existing chart")
    func setPartPropertyUpdatesShowGrid() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Gridded", "chart_type": "line",
                "left": "0", "top": "0", "width": "100", "height": "100",
                "data": "A=1",
            ],
            document: &doc, currentCardId: cardId
        )

        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "Gridded", "property": "show_grid", "value": "false"],
            document: &doc, currentCardId: cardId
        )
        #expect(chartConfig(in: doc, named: "Gridded")?.showGrid == false)
    }

    // MARK: - ChartConfig round-trips

    @Test("ChartConfig JSON round-trip preserves axis labels and legend flags")
    func chartConfigRoundTripPreservesAllFields() throws {
        let original = ChartConfig(
            chartType: .line,
            title: "Growth",
            series: [
                ChartSeries(name: "Revenue", color: "#00AA00", data: [
                    ChartDataPoint(name: "Q1", value: 100),
                    ChartDataPoint(name: "Q2", value: 150),
                ])
            ],
            showLegend: true,
            showGrid: false,
            xAxisLabel: "Quarter",
            yAxisLabel: "Revenue"
        )

        let json = original.toJSON()
        let roundTripped = ChartConfig.fromJSON(json)
        #expect(roundTripped != nil)
        #expect(roundTripped?.xAxisLabel == "Quarter")
        #expect(roundTripped?.yAxisLabel == "Revenue")
        #expect(roundTripped?.showLegend == true)
        #expect(roundTripped?.showGrid == false)
        #expect(roundTripped?.series.first?.name == "Revenue")
        #expect(roundTripped?.series.first?.data.count == 2)
    }

    @Test("ChartConfig defaults: empty xAxisLabel/yAxisLabel, legend on, grid on")
    func chartConfigDefaultsAreSane() {
        let config = ChartConfig()
        #expect(config.xAxisLabel == "")
        #expect(config.yAxisLabel == "")
        #expect(config.showLegend == true)
        #expect(config.showGrid == true)
    }
}

/// Regression tests for `ChartConfig.legendEntries()` and for the
/// per-data-point color pipeline through `create_chart`.
///
/// Context: an earlier fix replaced direct `.foregroundStyle(Color)` calls
/// in `ChartHostView` with `.foregroundStyle(by: .value("Series", …))` and
/// a series-level `chartForegroundStyleScale`. That made SwiftUI Charts
/// auto-generate a legend, but it also clobbered the per-data-point color
/// set on `ChartDataPoint.color` (every bar rendered with the series
/// default color). The rendering path has been reverted to direct
/// per-mark colors, and the legend is now computed in HypeCore via
/// `ChartConfig.legendEntries()` so the logic can be unit-tested without
/// instantiating a SwiftUI view.
@Suite("Chart legend entries and per-point colors")
struct ChartLegendTests {

    // MARK: - legendEntries() policy

    @Test("empty chart has no legend entries")
    func emptyChartHasNoEntries() {
        let config = ChartConfig()  // no series
        #expect(config.legendEntries().isEmpty)
    }

    @Test("single series with no per-point colors → one legend entry per data point")
    func singleSeriesWithoutPerPointColors() {
        let config = ChartConfig(
            chartType: .bar,
            series: [
                ChartSeries(name: "Sales", color: "#4A90D9", data: [
                    ChartDataPoint(name: "Jan", value: 120),
                    ChartDataPoint(name: "Feb", value: 150),
                    ChartDataPoint(name: "Mar", value: 180),
                ])
            ]
        )
        let entries = config.legendEntries()
        #expect(entries.count == 3)
        #expect(entries[0] == ChartLegendEntry(name: "Jan", colorHex: "#4A90D9"))
        #expect(entries[1] == ChartLegendEntry(name: "Feb", colorHex: "#4A90D9"))
        #expect(entries[2] == ChartLegendEntry(name: "Mar", colorHex: "#4A90D9"))
    }

    @Test("single series with per-point colors → one entry per data point")
    func singleSeriesWithPerPointColors() {
        let config = ChartConfig(
            chartType: .bar,
            series: [
                ChartSeries(name: "Sales", color: "#4A90D9", data: [
                    ChartDataPoint(name: "Jan", value: 120, color: "#FF0000"),
                    ChartDataPoint(name: "Feb", value: 150, color: "#00FF00"),
                    ChartDataPoint(name: "Mar", value: 180, color: "#0000FF"),
                ])
            ]
        )
        let entries = config.legendEntries()
        #expect(entries.count == 3)
        #expect(entries[0] == ChartLegendEntry(name: "Jan", colorHex: "#FF0000"))
        #expect(entries[1] == ChartLegendEntry(name: "Feb", colorHex: "#00FF00"))
        #expect(entries[2] == ChartLegendEntry(name: "Mar", colorHex: "#0000FF"))
    }

    @Test("single series with mixed per-point colors → per-point, uncolored fall back to series color")
    func singleSeriesWithMixedPerPointColors() {
        let config = ChartConfig(
            chartType: .bar,
            series: [
                ChartSeries(name: "Scores", color: "#4A90D9", data: [
                    ChartDataPoint(name: "Alice", value: 90, color: "#FF6B6B"),
                    ChartDataPoint(name: "Bob",   value: 85),  // no color → series color
                    ChartDataPoint(name: "Carol", value: 92, color: "#6BCB77"),
                ])
            ]
        )
        let entries = config.legendEntries()
        #expect(entries.count == 3)
        #expect(entries[0] == ChartLegendEntry(name: "Alice", colorHex: "#FF6B6B"))
        #expect(entries[1] == ChartLegendEntry(name: "Bob",   colorHex: "#4A90D9"))
        #expect(entries[2] == ChartLegendEntry(name: "Carol", colorHex: "#6BCB77"))
    }

    @Test("two series → one entry per series, using series color")
    func twoSeriesReturnsPerSeriesEntries() {
        let config = ChartConfig(
            chartType: .line,
            series: [
                ChartSeries(name: "Revenue", color: "#00AA00", data: [
                    ChartDataPoint(name: "Q1", value: 100),
                    ChartDataPoint(name: "Q2", value: 150),
                ]),
                ChartSeries(name: "Cost", color: "#FF6B6B", data: [
                    ChartDataPoint(name: "Q1", value: 60),
                    ChartDataPoint(name: "Q2", value: 80),
                ])
            ]
        )
        let entries = config.legendEntries()
        #expect(entries.count == 2)
        #expect(entries[0] == ChartLegendEntry(name: "Revenue", colorHex: "#00AA00"))
        #expect(entries[1] == ChartLegendEntry(name: "Cost", colorHex: "#FF6B6B"))
    }

    @Test("three series → one entry per series")
    func threeSeriesReturnsThreeEntries() {
        let config = ChartConfig(
            chartType: .bar,
            series: [
                ChartSeries(name: "A", color: "#111111"),
                ChartSeries(name: "B", color: "#222222"),
                ChartSeries(name: "C", color: "#333333"),
            ]
        )
        let entries = config.legendEntries()
        #expect(entries.count == 3)
        #expect(entries.map(\.name) == ["A", "B", "C"])
        #expect(entries.map(\.colorHex) == ["#111111", "#222222", "#333333"])
    }

    @Test("multi-series with per-point colors → legend still groups by series")
    func multiSeriesWithPerPointColorsStillGroupsBySeries() {
        // In a multi-series chart the primary disambiguation is the series,
        // so per-point colors render on the marks but the legend collapses
        // to one row per series. This is a deliberate trade-off — the
        // alternative (per-point entries in a multi-series chart) requires
        // compound keys and becomes unreadable very quickly.
        let config = ChartConfig(
            chartType: .bar,
            series: [
                ChartSeries(name: "A", color: "#4A90D9", data: [
                    ChartDataPoint(name: "X", value: 1, color: "#FF0000"),
                    ChartDataPoint(name: "Y", value: 2, color: "#00FF00"),
                ]),
                ChartSeries(name: "B", color: "#FF6B6B", data: [
                    ChartDataPoint(name: "X", value: 3),
                    ChartDataPoint(name: "Y", value: 4),
                ]),
            ]
        )
        let entries = config.legendEntries()
        #expect(entries.count == 2)
        #expect(entries[0].name == "A")
        #expect(entries[0].colorHex == "#4A90D9")
        #expect(entries[1].name == "B")
        #expect(entries[1].colorHex == "#FF6B6B")
    }

    @Test("legendEntries round-trips through JSON unchanged")
    func legendEntriesSurviveJSONRoundTrip() {
        let original = ChartConfig(
            chartType: .pie,
            title: "Distribution",
            series: [
                ChartSeries(name: "Share", color: "#4A90D9", data: [
                    ChartDataPoint(name: "Apple",  value: 40, color: "#E63946"),
                    ChartDataPoint(name: "Banana", value: 35, color: "#F1C40F"),
                    ChartDataPoint(name: "Cherry", value: 25, color: "#C0392B"),
                ])
            ]
        )
        let json = original.toJSON()
        let decoded = ChartConfig.fromJSON(json)
        #expect(decoded != nil)
        let entries = decoded?.legendEntries() ?? []
        #expect(entries.count == 3)
        #expect(entries[0] == ChartLegendEntry(name: "Apple",  colorHex: "#E63946"))
        #expect(entries[1] == ChartLegendEntry(name: "Banana", colorHex: "#F1C40F"))
        #expect(entries[2] == ChartLegendEntry(name: "Cherry", colorHex: "#C0392B"))
    }

    // MARK: - Per-point colors through create_chart data_json

    private func makeDoc() -> (HypeDocument, UUID) {
        let doc = HypeDocument.newDocument(name: "Chart Color Test")
        return (doc, doc.cards[0].id)
    }

    @Test("create_chart data_json preserves per-point colors")
    func createChartDataJSONPreservesPerPointColors() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let dataJSON = """
        [
          {"name":"Jan","value":120,"color":"#FF0000"},
          {"name":"Feb","value":150,"color":"#00FF00"},
          {"name":"Mar","value":180,"color":"#0000FF"}
        ]
        """
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Colorful",
                "chart_type": "bar",
                "left": "0", "top": "0",
                "width": "400", "height": "300",
                "data_json": dataJSON,
                "x_axis_label": "Month",
                "y_axis_label": "Sales",
            ],
            document: &doc,
            currentCardId: cardId
        )

        // Verify per-point colors survived into the stored ChartConfig.
        guard let part = doc.parts.first(where: { $0.name == "Colorful" }),
              let config = ChartConfig.fromJSON(part.chartData) else {
            Issue.record("Chart 'Colorful' not created or ChartConfig failed to decode")
            return
        }
        let points = config.series.first?.data ?? []
        #expect(points.count == 3)
        #expect(points[0].color == "#FF0000")
        #expect(points[1].color == "#00FF00")
        #expect(points[2].color == "#0000FF")

        // And that the legend entries pick up the per-point colors.
        let entries = config.legendEntries()
        #expect(entries.count == 3)
        #expect(entries[0] == ChartLegendEntry(name: "Jan", colorHex: "#FF0000"))
        #expect(entries[1] == ChartLegendEntry(name: "Feb", colorHex: "#00FF00"))
        #expect(entries[2] == ChartLegendEntry(name: "Mar", colorHex: "#0000FF"))
    }

    @Test("create_chart simple data format produces one legend entry per point")
    func createChartSimpleDataHasPerPointLegendEntries() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Simple",
                "chart_type": "bar",
                "left": "0", "top": "0",
                "width": "400", "height": "300",
                "data": "Jan=120,Feb=150,Mar=180",
                "series_name": "Sales",
                "series_color": "#4A90D9",
                "x_axis_label": "Month",
                "y_axis_label": "Dollars",
            ],
            document: &doc,
            currentCardId: cardId
        )

        guard let part = doc.parts.first(where: { $0.name == "Simple" }),
              let config = ChartConfig.fromJSON(part.chartData) else {
            Issue.record("Chart 'Simple' not created")
            return
        }
        let entries = config.legendEntries()
        #expect(entries.count == 3)
        #expect(entries[0] == ChartLegendEntry(name: "Jan", colorHex: "#4A90D9"))
        #expect(entries[1] == ChartLegendEntry(name: "Feb", colorHex: "#4A90D9"))
        #expect(entries[2] == ChartLegendEntry(name: "Mar", colorHex: "#4A90D9"))
    }

    @Test("data point labels include point name, value, and series name when needed")
    func dataPointLabelContent() {
        let singleSeries = ChartSeries(name: "Sales", color: "#4A90D9", data: [
            ChartDataPoint(name: "Jan", value: 120),
        ])
        let config = ChartConfig(series: [singleSeries])
        #expect(config.dataPointLabel(for: singleSeries.data[0], in: singleSeries) == "Jan 120")

        let revenue = ChartSeries(name: "Revenue", data: [
            ChartDataPoint(name: "Q1", value: 123.456),
        ])
        let cost = ChartSeries(name: "Cost", data: [
            ChartDataPoint(name: "Q1", value: 78),
        ])
        let multi = ChartConfig(series: [revenue, cost])
        #expect(multi.dataPointLabel(for: revenue.data[0], in: revenue) == "Revenue: Q1 123.46")
    }

    @Test("create_chart data_json with integer values decodes correctly")
    func createChartDataJSONIntegerValues() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        // Mix integer and floating-point values to exercise the
        // JSONSerialization number handling in the executor.
        let dataJSON = """
        [
          {"name":"A","value":1,"color":"#FF0000"},
          {"name":"B","value":2.5,"color":"#00FF00"},
          {"name":"C","value":3}
        ]
        """
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Mixed",
                "chart_type": "bar",
                "left": "0", "top": "0",
                "width": "100", "height": "100",
                "data_json": dataJSON,
            ],
            document: &doc, currentCardId: cardId
        )

        guard let part = doc.parts.first(where: { $0.name == "Mixed" }),
              let config = ChartConfig.fromJSON(part.chartData) else {
            Issue.record("Chart 'Mixed' not created")
            return
        }
        let points = config.series.first?.data ?? []
        #expect(points.count == 3)
        #expect(points[0].value == 1)
        #expect(points[1].value == 2.5)
        #expect(points[2].value == 3)
        #expect(points[0].color == "#FF0000")
        #expect(points[1].color == "#00FF00")
        #expect(points[2].color == "")  // last one had no color → empty string

        // The legend should still show per-point entries because at
        // least one point has a color.
        let entries = config.legendEntries()
        #expect(entries.count == 3)
        #expect(entries[0].colorHex == "#FF0000")
        #expect(entries[1].colorHex == "#00FF00")
        // Uncolored C falls back to the series default color.
        #expect(entries[2].colorHex == "#4A90D9")
    }

    @Test("pie chart single series with per-slice colors produces per-slice legend")
    func pieChartLegendEntriesPerSlice() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let dataJSON = """
        [
          {"name":"Red","value":30,"color":"#FF0000"},
          {"name":"Green","value":40,"color":"#00FF00"},
          {"name":"Blue","value":30,"color":"#0000FF"}
        ]
        """
        _ = await executor.execute(
            toolName: "create_chart",
            arguments: [
                "name": "Pie",
                "chart_type": "pie",
                "title": "Color Distribution",
                "left": "0", "top": "0",
                "width": "300", "height": "300",
                "data_json": dataJSON,
            ],
            document: &doc, currentCardId: cardId
        )

        let config = ChartConfig.fromJSON(doc.parts.first(where: { $0.name == "Pie" })?.chartData ?? "")
        #expect(config != nil)
        #expect(config?.chartType == .pie)
        let entries = config?.legendEntries() ?? []
        #expect(entries.count == 3)
        #expect(entries.map(\.name) == ["Red", "Green", "Blue"])
        #expect(entries.map(\.colorHex) == ["#FF0000", "#00FF00", "#0000FF"])
    }
}
