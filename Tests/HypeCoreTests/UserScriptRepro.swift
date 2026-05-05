import Testing
import Foundation
@testable import HypeCore

/// Regression probe for the user's failing idle script.
///
/// User report: "I tried the following script attached to a chart
/// and to the card on which it resides. Neither case triggered
/// idle events." The script rotates per-data-point colors on a
/// chart every idle tick.
///
/// These tests reproduce each of the specific grammar forms the
/// user's script relied on and assert whether they parse today.
/// They're also the regression lock for the fixes we apply: after
/// we extend the grammar and the error-reporting path, every test
/// in this suite should pass and the user's exact script should
/// dispatch successfully.
@Suite("User script — idle rainbow chart", .serialized)
struct UserScriptReproTests {

    /// The user's exact script text, verbatim.
    static let userScript = """
        on idle
          global colors, currentIndex
          if colors is empty then
            put "#FF0000, #FF7F00, #FFFF00, #00FF00, #0000FF, #4B0082, #8B00FF" into colors
            put 1 into currentIndex
          end if

          get the items currentIndex to currentIndex of colors into currentColor

          get the number of points in chart "QTD Sales" into numPoints
          answer numPoints

          repeat with i = 1 to numPoints
            put (currentIndex + i - 2) mod 7 + 1 into colorIdx
            get the item colorIdx of colors into nextColor
            set the color of point i in chart "QTD Sales" to nextColor
          end repeat

          add 1 to currentIndex
          if currentIndex > 7 then put 1 into currentIndex
        end idle
        """

    /// Try to parse an arbitrary script fragment and return the
    /// resulting parse error (if any) or `nil` on success.
    private func parseError(_ source: String) -> String? {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return nil
        } catch let error as ParseError {
            return error.errorDescription ?? String(describing: error)
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Full script

    @Test("the user's exact script parses as a complete handler")
    func userScriptParses() {
        let err = parseError(Self.userScript)
        #expect(err == nil, "user script failed to parse: \(err ?? "")")
    }

    // MARK: - Individual grammar forms the script depends on

    @Test("'get <expr> into <target>' parses as sugar for 'put <expr> into <target>'")
    func getIntoForm() {
        let err = parseError("""
            on test
              get the item 1 of "a,b,c" into first
            end test
            """)
        #expect(err == nil, "get X into Y failed: \(err ?? "")")
    }

    @Test("chunk range 'items N to M of X' parses as a chunk expression")
    func chunkRangeItems() {
        let err = parseError("""
            on test
              put the items 2 to 4 of "a,b,c,d,e" into mid
            end test
            """)
        #expect(err == nil, "items N to M of X failed: \(err ?? "")")
    }

    @Test("chunk range 'item N to M of X' (singular) parses")
    func chunkRangeItemSingular() {
        let err = parseError("""
            on test
              put the item 2 to 4 of "a,b,c,d,e" into mid
            end test
            """)
        #expect(err == nil, "item N to M of X failed: \(err ?? "")")
    }

    @Test("chunk range 'words N to M of X' parses")
    func chunkRangeWords() {
        let err = parseError("""
            on test
              put the words 1 to 2 of "alpha beta gamma" into pair
            end test
            """)
        #expect(err == nil, "words N to M of X failed: \(err ?? "")")
    }

    @Test("'point N of chart X' parses (data point without the 'data' prefix)")
    func pointWithoutDataPrefix() {
        let err = parseError("""
            on test
              set the color of point 1 of chart "Sales" to "#FF0000"
            end test
            """)
        #expect(err == nil, "point N of chart X failed: \(err ?? "")")
    }

    @Test("'point N in chart X' parses ('in' as alias for 'of')")
    func pointInChart() {
        let err = parseError("""
            on test
              set the color of point 1 in chart "Sales" to "#FF0000"
            end test
            """)
        #expect(err == nil, "point N in chart X failed: \(err ?? "")")
    }

    @Test("'data point N in chart X' parses ('in' as alias for 'of' in compound refs)")
    func dataPointInChart() {
        let err = parseError("""
            on test
              set the color of data point 1 in chart "Sales" to "#FF0000"
            end test
            """)
        #expect(err == nil, "data point N in chart X failed: \(err ?? "")")
    }

    @Test("'the number of points in chart X' parses as a property reference")
    func numberOfPointsInChart() {
        let err = parseError("""
            on test
              put the number of points in chart "Sales" into n
            end test
            """)
        #expect(err == nil, "number of points in chart X failed: \(err ?? "")")
    }

    @Test("'the number of data points of chart X' parses")
    func numberOfDataPointsOfChart() {
        let err = parseError("""
            on test
              put the number of data points of chart "Sales" into n
            end test
            """)
        #expect(err == nil, "number of data points of chart X failed: \(err ?? "")")
    }

    // MARK: - End-to-end dispatch

    /// Build a document with a card-attached rainbow idle handler
    /// and a chart whose per-point colors should rotate on each
    /// idle tick. Mirrors the user's actual configuration.
    private func makeDocWithRainbowScript() -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Rainbow Test")
        let cardId = doc.cards[0].id

        // Attach the user's exact script to the card.
        let cardIndex = doc.cards.firstIndex(where: { $0.id == cardId })!
        doc.cards[cardIndex].script = Self.userScript

        // Give the card a chart with seven data points to rotate.
        var config = ChartConfig(
            chartType: .bar,
            title: "QTD Sales",
            series: [
                ChartSeries(name: "Revenue", color: "#4A90D9", data: [
                    ChartDataPoint(name: "W1", value: 10),
                    ChartDataPoint(name: "W2", value: 20),
                    ChartDataPoint(name: "W3", value: 30),
                    ChartDataPoint(name: "W4", value: 40),
                    ChartDataPoint(name: "W5", value: 50),
                    ChartDataPoint(name: "W6", value: 60),
                    ChartDataPoint(name: "W7", value: 70),
                ])
            ]
        )
        _ = config
        var chart = Part(
            partType: .chart,
            cardId: cardId,
            name: "QTD Sales",
            left: 20, top: 20, width: 400, height: 300
        )
        chart.chartData = config.toJSON()
        doc.addPart(chart)
        return (doc, cardId)
    }

    @Test("user's rainbow idle handler mutates per-point colors on each tick") func userScriptIdleMutatesColors() async {
        let (doc, cardId) = makeDocWithRainbowScript()
        let dispatcher = MessageDispatcher()
        // Use a no-op dialog provider so `answer` doesn't block a test run.
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "idle",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId,
            dialogProvider: StubDialogProvider(),
            drawingProvider: StubDrawingProvider()
        ) }
        #expect(result.status == .completed,
                "idle dispatch didn't complete: status=\(result.status)")
        #expect(result.modifiedDocument != nil,
                "idle handler ran but modifiedDocument is nil — fix the parse error path")

        guard let modified = result.modifiedDocument,
              let chart = modified.parts.first(where: { $0.name == "QTD Sales" }),
              let updated = ChartConfig.fromJSON(chart.chartData),
              let series = updated.series.first else {
            Issue.record("chart missing from modified document")
            return
        }
        // At least one data point should now have a non-empty color
        // (the handler sets every point to a rainbow slot).
        #expect(series.data.contains { !$0.color.isEmpty },
                "after idle tick, no data point received a color")
    }
}
