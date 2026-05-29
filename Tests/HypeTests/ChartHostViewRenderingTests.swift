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
