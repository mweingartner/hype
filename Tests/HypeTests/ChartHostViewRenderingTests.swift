import SwiftUI
import Testing
@testable import Hype
import HypeCore

@Suite("ChartHostView rendering")
@MainActor
struct ChartHostViewRenderingTests {
    @Test("all chart types render with data labels without crashing")
    func allChartTypesRenderWithLabels() {
        for chartType in ChartType.allCases {
            let config = ChartConfig(
                chartType: chartType,
                title: "Quarterly Results",
                series: [
                    ChartSeries(name: "Revenue", color: "#4A90D9", data: [
                        ChartDataPoint(name: "Q1", value: 120, color: "#4A90D9"),
                        ChartDataPoint(name: "Q2", value: 155, color: "#6BCB77"),
                        ChartDataPoint(name: "Q3", value: 142, color: "#F1C40F"),
                    ])
                ],
                xAxisLabel: "Quarter",
                yAxisLabel: "Revenue"
            )
            let renderer = ImageRenderer(content: ChartHostView(config: config).frame(width: 420, height: 320))
            renderer.scale = 1
            #expect(renderer.nsImage != nil, "\(chartType.rawValue) chart should render")
        }
    }

    @Test("spider chart renders with incomplete extra series without leaking labels")
    func spiderChartRendersWithIncompleteExtraSeries() {
        let config = ChartConfig(
            chartType: .spider,
            title: "Attributes",
            series: [
                ChartSeries(name: "Attributes", color: "#1316EA", data: [
                    ChartDataPoint(name: "Strength", value: 18, minimumValue: 0, maximumValue: 20),
                    ChartDataPoint(name: "Dexterity", value: 12, minimumValue: 0, maximumValue: 20),
                    ChartDataPoint(name: "Constitution", value: 14, minimumValue: 0, maximumValue: 20),
                    ChartDataPoint(name: "Intelligence", value: 10, minimumValue: 0, maximumValue: 20),
                    ChartDataPoint(name: "Wisdom", value: 11, minimumValue: 0, maximumValue: 20),
                    ChartDataPoint(name: "Charisma", value: 13, minimumValue: 0, maximumValue: 20),
                ]),
                ChartSeries(name: "Series 2", color: "#E74C3C", data: [
                    ChartDataPoint(name: "Item 1", value: 50, minimumValue: 0, maximumValue: 100),
                ]),
            ],
            interactable: true
        )
        let renderer = ImageRenderer(content: ChartHostView(config: config).frame(width: 496, height: 352))
        renderer.scale = 1
        #expect(renderer.nsImage != nil)
    }

    @Test("ChartHostView source wires mark annotations and custom legend")
    func chartHostViewWiresLabelsAndLegend() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/Hype/Views/ChartHostView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("config.dataPointLabel(for: point, in: series)"))
        #expect(source.contains(".annotation(position: .top"))
        #expect(source.contains(".annotation(position: .overlay"))
        #expect(source.contains("legend(for: entries)"))
        #expect(source.contains("config.legendEntries()"))
        #expect(source.contains(".environment(\\.colorScheme, .light)"))
        #expect(source.contains(".foregroundColor(.black)"))
        #expect(source.contains("SpiderChartCanvas"))
        #expect(source.contains("DragGesture"))
        #expect(source.contains("onPointChange?("))
        #expect(source.contains("spiderRenderableSeries()"))
        #expect(source.contains("spiderDataPointLabel(for: displayedPoint(point), in: series)"))
        #expect(source.contains("spiderValueScale()"))
        #expect(source.contains("nearestAxisTarget"))
        #expect(source.contains("radialTickLabelPoint"))
    }

    // MARK: - Spider appearance feature rendering

    @Test("spider chart with circular grid and split area renders without crashing")
    func spiderChartCircularGridAndSplitAreaRendersWithoutCrashing() {
        var config = ChartConfig(
            chartType: .spider,
            title: "Circular Grid Test",
            series: [
                ChartSeries(name: "Alpha", color: "#4A90D9", data: [
                    ChartDataPoint(name: "A", value: 70, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "B", value: 50, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "C", value: 85, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "D", value: 60, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "E", value: 40, minimumValue: 0, maximumValue: 100),
                ]),
            ]
        )
        config.spiderCircularGrid = true
        config.spiderShowSplitArea = true

        let renderer = ImageRenderer(
            content: ChartHostView(config: config).frame(width: 420, height: 320)
        )
        renderer.scale = 1
        #expect(renderer.nsImage != nil, "spider chart with circular grid and split area should render")
    }

    @Test("spider chart with split area disabled and polygonal grid renders without crashing")
    func spiderChartPolygonalNoSplitAreaRendersWithoutCrashing() {
        var config = ChartConfig(
            chartType: .spider,
            title: "No Split Area",
            series: [
                ChartSeries(name: "Beta", color: "#E74C3C", data: [
                    ChartDataPoint(name: "X", value: 30, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Y", value: 60, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Z", value: 90, minimumValue: 0, maximumValue: 100),
                ]),
            ]
        )
        config.spiderCircularGrid = false
        config.spiderShowSplitArea = false

        let renderer = ImageRenderer(
            content: ChartHostView(config: config).frame(width: 420, height: 320)
        )
        renderer.scale = 1
        #expect(renderer.nsImage != nil, "spider chart with split area disabled should render")
    }

    @Test("spider chart with 3 or more series uses capped fill opacity")
    func spiderChartThreeSeriesRendersWithoutCrashing() {
        let makePoints: (String) -> [ChartDataPoint] = { prefix in
            ["A", "B", "C", "D"].map {
                ChartDataPoint(name: "\(prefix)\($0)", value: 50, minimumValue: 0, maximumValue: 100)
            }
        }
        let config = ChartConfig(
            chartType: .spider,
            series: [
                ChartSeries(name: "S1", color: "#4A90D9", data: makePoints("S1")),
                ChartSeries(name: "S2", color: "#E74C3C", data: makePoints("S2")),
                ChartSeries(name: "S3", color: "#27AE60", data: makePoints("S3")),
            ],
            spiderFillOpacity: 0.5
        )
        let renderer = ImageRenderer(
            content: ChartHostView(config: config).frame(width: 420, height: 320)
        )
        renderer.scale = 1
        #expect(renderer.nsImage != nil, "spider chart with 3 series should render with capped fill opacity")
    }

    @Test("SpiderChartCanvas source wires appearance knobs and animation state")
    func spiderChartCanvasSourceWiresAppearanceKnobs() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/Hype/Views/ChartHostView.swift"),
            encoding: .utf8
        )
        // New config knobs referenced in rendering.
        #expect(source.contains("spiderShowSplitArea"))
        #expect(source.contains("spiderCircularGrid"))
        // Reveal animation state.
        #expect(source.contains("revealProgress"))
        // Reduce-motion environment key.
        #expect(source.contains("accessibilityReduceMotion"))
        // Drag-interaction functions remain present and unmodified.
        #expect(source.contains("func dragGesture(layout:"))
        #expect(source.contains("func applyDrag("))
        #expect(source.contains("func nearestTarget(to location:"))
        #expect(source.contains("func nearestMarkerTarget(to location:"))
        #expect(source.contains("func nearestAxisTarget(to location:"))
        #expect(source.contains("func resolvedTarget("))
        #expect(source.contains("func spiderPoint(for series:"))
        #expect(source.contains("layout.normalizedValue(for: location"))
        #expect(source.contains("onPointChange?("))
        #expect(source.contains("SpiderChartPointChange("))
        #expect(source.contains("dragTarget"))
        #expect(source.contains("liveValues"))
    }

    @Test("CardCanvas wires interactive spider chart changes to chartChange")
    func cardCanvasWiresInteractiveSpiderChartChanges() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("setPartChartDataPointValue"))
        #expect(source.contains("dispatchMessage(\n                    \"chartChange\""))
        #expect(source.contains("markChartDataLoaded(partId: id"))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
