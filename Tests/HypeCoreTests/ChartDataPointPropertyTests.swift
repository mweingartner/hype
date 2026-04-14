import Testing
import Foundation
@testable import HypeCore

/// Regression tests for the chart data-point property surface:
/// reading and writing per-point colors (and value / name) from
/// HypeTalk scripts and from the AI tool layer.
///
/// Coverage:
///
/// - **Parser**: `data point <ref> of [series <ref> of] chart <ref>`
///   produces a `chartDataPointRef` expression; bare `data` still
///   parses as a variable; `chart "X"` parses as a single-level
///   object reference.
/// - **Interpreter get**: `put the color of data point ... of chart
///   ... into x` returns the effective color (per-point override or
///   series fallback). Also covers `rawcolor`, `value`, `name`.
/// - **Interpreter set**: `set the color of data point ... of chart
///   ... to "#RRGGBB"` mutates the ChartDataPoint inside the chart
///   part's serialized ChartConfig.
/// - **Chart-level properties**: `the title / xAxisLabel / yAxisLabel
///   / showLegend / showGrid / chartType of chart "X"` (get + set).
/// - **AI tool**: `set_chart_data_point_color` and
///   `get_chart_data_points` round-trip.
/// - **Error paths**: unknown chart, unknown series, unknown point,
///   out-of-range index, no-op on malformed names.
@Suite("Chart data-point properties", .serialized)
struct ChartDataPointPropertyTests {

    // MARK: - Helpers

    /// Build a document containing a single chart part named `"Sales"`
    /// with one series of three colored data points.
    private func makeDocWithColoredChart() -> (HypeDocument, UUID, UUID) {
        var doc = HypeDocument.newDocument(name: "Chart Test")
        let cardId = doc.cards[0].id

        let config = ChartConfig(
            chartType: .bar,
            title: "Monthly Sales",
            series: [
                ChartSeries(name: "Revenue", color: "#4A90D9", data: [
                    ChartDataPoint(name: "Jan", value: 120, color: "#FF0000"),
                    ChartDataPoint(name: "Feb", value: 150, color: "#00FF00"),
                    ChartDataPoint(name: "Mar", value: 180, color: "#0000FF"),
                ])
            ],
            xAxisLabel: "Month",
            yAxisLabel: "Dollars"
        )
        var chart = Part(
            partType: .chart,
            cardId: cardId,
            name: "Sales",
            left: 20, top: 20, width: 400, height: 300
        )
        chart.chartData = config.toJSON()
        doc.addPart(chart)
        return (doc, cardId, chart.id)
    }

    /// Build a document with a single-series chart whose points have
    /// no per-point color overrides — used to verify the series-color
    /// fallback.
    private func makeDocWithUncoloredPoints() -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Chart Test")
        let cardId = doc.cards[0].id

        let config = ChartConfig(
            chartType: .bar,
            series: [
                ChartSeries(name: "Sales", color: "#4A90D9", data: [
                    ChartDataPoint(name: "Q1", value: 100),
                    ChartDataPoint(name: "Q2", value: 200),
                ])
            ]
        )
        var chart = Part(
            partType: .chart,
            cardId: cardId,
            name: "Quarters",
            left: 20, top: 20, width: 400, height: 300
        )
        chart.chartData = config.toJSON()
        doc.addPart(chart)
        return (doc, cardId)
    }

    /// Run a HypeTalk script against a document and return the
    /// modified document plus the value of `it` after execution.
    private func runScript(
        _ source: String,
        on document: HypeDocument,
        currentCardId: UUID
    ) throws -> (document: HypeDocument, itValue: String) {
        let wrapped = "on test\n\(source)\nend test"
        var lexer = Lexer(source: wrapped)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let script = try parser.parse()
        let handler = script.handlers.first!

        let context = ExecutionContext(
            targetId: document.cards[0].id,
            currentCardId: currentCardId,
            document: document
        )
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        return (result.modifiedDocument ?? document, result.returnValue ?? "")
    }

    private func chartConfig(in doc: HypeDocument, named name: String) -> ChartConfig? {
        guard let part = doc.parts.first(where: { $0.name == name }) else { return nil }
        return ChartConfig.fromJSON(part.chartData)
    }

    // MARK: - Parser: grammar recognition

    @Test("parser recognizes 'data point N of chart X' without explicit series")
    func parserRecognizesDataPointWithoutSeries() throws {
        let source = """
        on test
          put the color of data point 1 of chart "Sales" into c
        end test
        """
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        // If the parser produced a .put statement with a propertyAccess
        // whose target is a .chartDataPointRef, we're good.
        guard case .put(let source, _, _) = script.handlers[0].body[0] else {
            Issue.record("expected put statement")
            return
        }
        guard case .propertyAccess(let prop, let target) = source else {
            Issue.record("expected propertyAccess expression")
            return
        }
        #expect(prop.lowercased() == "color")
        guard case .chartDataPointRef = target else {
            Issue.record("expected chartDataPointRef target, got \(String(describing: target))")
            return
        }
    }

    @Test("parser recognizes 'data point N of series N of chart X' with explicit series")
    func parserRecognizesDataPointWithSeries() throws {
        let source = """
        on test
          put the color of data point 2 of series 1 of chart "Sales" into c
        end test
        """
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        guard case .put(let src, _, _) = script.handlers[0].body[0],
              case .propertyAccess(_, let target) = src,
              case .chartDataPointRef(let chart, let series, let point) = target else {
            Issue.record("expected chartDataPointRef in put source")
            return
        }
        // Chart expr should evaluate to "Sales", series to "1", point to "2".
        if case .literal(let v) = chart { #expect(v == "Sales") } else {
            Issue.record("chart not a literal")
        }
        if case .literal(let v) = series { #expect(v == "1") } else {
            Issue.record("series not a literal")
        }
        if case .literal(let v) = point { #expect(v == "2") } else {
            Issue.record("point not a literal")
        }
    }

    @Test("parser still accepts 'data' as a bare variable name")
    func parserAllowsDataAsVariable() throws {
        // Without a following "point" keyword, `data` is treated as
        // an ordinary variable identifier — existing scripts using
        // "data" as a variable continue to work.
        let source = """
        on test
          put "hello" into data
          put data into result
        end test
        """
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].body.count == 2)
    }

    @Test("parser recognizes 'chart \"X\"' as a single-level object ref")
    func parserRecognizesChartObjectRef() throws {
        let source = """
        on test
          put the title of chart "Sales" into t
        end test
        """
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        guard case .put(let src, _, _) = script.handlers[0].body[0],
              case .propertyAccess(let prop, let target) = src,
              case .objectRef(let ref) = target else {
            Issue.record("expected propertyAccess → objectRef")
            return
        }
        #expect(prop.lowercased() == "title")
        #expect(ref.objectType == "chart")
    }

    @Test("parser recognizes point name as a string literal")
    func parserRecognizesNamedPointRef() throws {
        let source = """
        on test
          put the color of data point "Jan" of chart "Sales" into c
        end test
        """
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        let script = try parser.parse()
        guard case .put(let src, _, _) = script.handlers[0].body[0],
              case .propertyAccess(_, let target) = src,
              case .chartDataPointRef(_, _, let pointExpr) = target else {
            Issue.record("expected chartDataPointRef")
            return
        }
        if case .literal(let v) = pointExpr { #expect(v == "Jan") } else {
            Issue.record("point not a literal")
        }
    }

    // MARK: - Interpreter: get path

    @Test("reads per-point color by 1-based index")
    func readsPerPointColorByIndex() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (_, it) = try runScript(
            """
            put the color of data point 1 of chart "Sales" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(it == "#FF0000")
    }

    @Test("reads per-point color by name")
    func readsPerPointColorByName() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (_, it) = try runScript(
            """
            put the color of data point "Feb" of chart "Sales" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(it == "#00FF00")
    }

    @Test("reads per-point color through explicit series reference")
    func readsWithExplicitSeries() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (_, it) = try runScript(
            """
            put the color of data point 3 of series 1 of chart "Sales" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(it == "#0000FF")
    }

    @Test("color falls back to series color when point has no override")
    func readsFallsBackToSeriesColor() throws {
        let (doc, cardId) = makeDocWithUncoloredPoints()
        let (_, it) = try runScript(
            """
            put the color of data point 1 of chart "Quarters" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(it == "#4A90D9")
    }

    @Test("rawcolor returns the literal per-point color (empty if none set)")
    func readsRawColor() throws {
        let (doc, cardId) = makeDocWithUncoloredPoints()
        let (_, it) = try runScript(
            """
            put the rawcolor of data point 1 of chart "Quarters" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(it == "")
    }

    @Test("reads data point value and name")
    func readsValueAndName() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (_, value) = try runScript(
            """
            put the value of data point 2 of chart "Sales" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(value == "150")

        let (_, name) = try runScript(
            """
            put the name of data point 2 of chart "Sales" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(name == "Feb")
    }

    // MARK: - Interpreter: set path

    @Test("sets per-point color by 1-based index")
    func setsPerPointColorByIndex() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the color of data point 1 of chart "Sales" to "#ABCDEF"
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.series[0].data[0].color == "#ABCDEF")
        // Untouched points keep their colors.
        #expect(config?.series[0].data[1].color == "#00FF00")
        #expect(config?.series[0].data[2].color == "#0000FF")
    }

    @Test("sets per-point color by name")
    func setsPerPointColorByName() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the color of data point "Mar" of chart "Sales" to "#123456"
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.series[0].data[2].color == "#123456")
    }

    @Test("sets per-point color with explicit series reference")
    func setsWithExplicitSeries() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the color of data point 2 of series 1 of chart "Sales" to "#DEADBE"
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.series[0].data[1].color == "#DEADBE")
    }

    @Test("sets data point value and name")
    func setsValueAndName() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var modified = doc
        (modified, _) = try runScript(
            """
            set the value of data point 1 of chart "Sales" to 999
            """,
            on: modified, currentCardId: cardId
        )
        (modified, _) = try runScript(
            """
            set the name of data point 1 of chart "Sales" to "January"
            """,
            on: modified, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.series[0].data[0].value == 999)
        #expect(config?.series[0].data[0].name == "January")
    }

    @Test("set followed by get round-trips correctly")
    func setThenGetRoundTrips() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var modified = doc
        (modified, _) = try runScript(
            """
            set the color of data point "Jan" of chart "Sales" to "#AABBCC"
            """,
            on: modified, currentCardId: cardId
        )
        let (_, readBack) = try runScript(
            """
            put the color of data point "Jan" of chart "Sales" into it
            """,
            on: modified, currentCardId: cardId
        )
        #expect(readBack == "#AABBCC")
    }

    @Test("unknown chart silently returns empty string on get")
    func getOnUnknownChartReturnsEmpty() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (_, it) = try runScript(
            """
            put the color of data point 1 of chart "Missing" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(it == "")
    }

    @Test("out-of-range point index returns empty and does not crash set")
    func outOfRangePointIsSafe() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (_, it) = try runScript(
            """
            put the color of data point 99 of chart "Sales" into it
            """,
            on: doc, currentCardId: cardId
        )
        #expect(it == "")

        let (modified, _) = try runScript(
            """
            set the color of data point 99 of chart "Sales" to "#000000"
            """,
            on: doc, currentCardId: cardId
        )
        // Chart data unchanged.
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.series[0].data[0].color == "#FF0000")
        #expect(config?.series[0].data[1].color == "#00FF00")
        #expect(config?.series[0].data[2].color == "#0000FF")
    }

    // MARK: - Chart-level properties

    @Test("reads chart-level title, axis labels, legend, grid, type")
    func readsChartLevelProperties() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let tests: [(String, String)] = [
            ("the title of chart \"Sales\"", "Monthly Sales"),
            ("the xAxisLabel of chart \"Sales\"", "Month"),
            ("the yAxisLabel of chart \"Sales\"", "Dollars"),
            ("the showLegend of chart \"Sales\"", "true"),
            ("the showGrid of chart \"Sales\"", "true"),
            ("the chartType of chart \"Sales\"", "bar"),
        ]
        for (expr, expected) in tests {
            let (_, result) = try runScript(
                "put \(expr) into it",
                on: doc, currentCardId: cardId
            )
            #expect(result == expected, "reading '\(expr)' returned '\(result)' (expected '\(expected)')")
        }
    }

    @Test("sets chart-level title")
    func setsChartLevelTitle() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the title of chart "Sales" to "Q4 2026 Sales"
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.title == "Q4 2026 Sales")
    }

    @Test("sets chart-level xAxisLabel")
    func setsChartLevelXAxisLabel() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the xAxisLabel of chart "Sales" to "Quarter"
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.xAxisLabel == "Quarter")
    }

    @Test("toggles chart showLegend")
    func togglesChartShowLegend() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the showLegend of chart "Sales" to false
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.showLegend == false)
    }

    @Test("changes chart type by name")
    func changesChartType() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the chartType of chart "Sales" to "line"
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.chartType == .line)
    }

    @Test("chart-level property set preserves series and per-point colors")
    func chartLevelSetPreservesSeries() throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        let (modified, _) = try runScript(
            """
            set the title of chart "Sales" to "Updated"
            """,
            on: doc, currentCardId: cardId
        )
        let config = chartConfig(in: modified, named: "Sales")
        #expect(config?.title == "Updated")
        // Data points are untouched.
        #expect(config?.series[0].data[0].color == "#FF0000")
        #expect(config?.series[0].data[1].color == "#00FF00")
        #expect(config?.series[0].data[2].color == "#0000FF")
        #expect(config?.series[0].data.count == 3)
    }

    // MARK: - AI tool path

    @Test("set_chart_data_point_color sets a point color by index")
    func toolSetsByIndex() async {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var mutable = doc
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_chart_data_point_color",
            arguments: [
                "chart_name": "Sales",
                "series": "1",
                "point": "2",
                "color": "#998877",
            ],
            document: &mutable,
            currentCardId: cardId
        )
        #expect(result.contains("Set color of 'Feb'"))
        let config = chartConfig(in: mutable, named: "Sales")
        #expect(config?.series[0].data[1].color == "#998877")
    }

    @Test("set_chart_data_point_color sets a point color by name")
    func toolSetsByName() async {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var mutable = doc
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_chart_data_point_color",
            arguments: [
                "chart_name": "Sales",
                "point": "Mar",   // omit series — defaults to 1
                "color": "#112233",
            ],
            document: &mutable,
            currentCardId: cardId
        )
        let config = chartConfig(in: mutable, named: "Sales")
        #expect(config?.series[0].data[2].color == "#112233")
    }

    @Test("set_chart_data_point_color reports unknown chart")
    func toolRejectsUnknownChart() async {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var mutable = doc
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_chart_data_point_color",
            arguments: [
                "chart_name": "Missing",
                "point": "1",
                "color": "#000000",
            ],
            document: &mutable,
            currentCardId: cardId
        )
        #expect(result.contains("not found"))
    }

    @Test("set_chart_data_point_color reports unknown point")
    func toolRejectsUnknownPoint() async {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var mutable = doc
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_chart_data_point_color",
            arguments: [
                "chart_name": "Sales",
                "point": "December",
                "color": "#000000",
            ],
            document: &mutable,
            currentCardId: cardId
        )
        #expect(result.contains("not found"))
    }

    @Test("get_chart_data_points lists every series and point with effective color")
    func toolListsDataPoints() async {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var mutable = doc
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_chart_data_points",
            arguments: ["chart_name": "Sales"],
            document: &mutable,
            currentCardId: cardId
        )
        // Should mention the series and each data point with its color.
        #expect(result.contains("Revenue"))
        #expect(result.contains("Jan"))
        #expect(result.contains("#FF0000"))
        #expect(result.contains("Feb"))
        #expect(result.contains("#00FF00"))
        #expect(result.contains("Mar"))
        #expect(result.contains("#0000FF"))
    }

    @Test("get_chart_data_points marks inherited colors as inherited")
    func toolFlagsInheritedColors() async {
        let (doc, cardId) = makeDocWithUncoloredPoints()
        var mutable = doc
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_chart_data_points",
            arguments: ["chart_name": "Quarters"],
            document: &mutable,
            currentCardId: cardId
        )
        #expect(result.contains("inherited"))
    }

    // MARK: - AI + HypeTalk coexistence

    @Test("AI tool and HypeTalk see the same per-point color")
    func aiToolAndHypeTalkAgree() async throws {
        let (doc, cardId, _) = makeDocWithColoredChart()
        var mutable = doc
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_chart_data_point_color",
            arguments: [
                "chart_name": "Sales",
                "point": "1",
                "color": "#DEADBE",
            ],
            document: &mutable,
            currentCardId: cardId
        )
        // HypeTalk read should see the AI tool's mutation.
        let (_, it) = try runScript(
            """
            put the color of data point 1 of chart "Sales" into it
            """,
            on: mutable, currentCardId: cardId
        )
        #expect(it == "#DEADBE")
    }
}
