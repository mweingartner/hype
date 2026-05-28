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
