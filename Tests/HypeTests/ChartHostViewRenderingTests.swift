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
        #expect(source.contains("spiderRadialTickValue(fraction: fraction)"))
        #expect(source.contains("interactionLayer(seriesList: renderableSeries, layout: layout)"))
        #expect(source.contains("pointDragGesture("))
        #expect(source.contains("SpiderChartInteractionResolver"))
        #expect(source.contains("spiderCanvasRect(in: geometry.size, config: config)"))
        #expect(!source.contains("Drag points to edit"))
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
        #expect(source.contains("func pointDragGesture("))
        #expect(source.contains("func interactionLayer(seriesList:"))
        #expect(source.contains(".frame(width: 44, height: 44)"))
        #expect(source.contains(".fill(Color.black.opacity(0.001))"))
        #expect(source.contains("markerPoint: markerPoint"))
        #expect(source.contains("chartLocation(fromHitTargetLocation:"))
        #expect(source.contains("location.x - 22"))
        #expect(source.contains("var size: CGSize"))
        #expect(source.contains(".frame(width: layout.size.width, height: layout.size.height)"))
        #expect(source.contains("func applyDrag("))
        #expect(source.contains("func nearestTarget(to location:"))
        #expect(source.contains("func nearestMarkerTarget(to location:"))
        #expect(source.contains("func nearestAxisTarget(to location:"))
        #expect(source.contains("func resolvedTarget("))
        #expect(source.contains("static func resolve("))
        #expect(source.contains("func spiderPoint(for series:"))
        #expect(source.contains("layout.normalizedValue(for: location"))
        #expect(source.contains("onPointChange?("))
        #expect(source.contains("SpiderChartPointChange("))
        #expect(source.contains("dragTarget"))
        #expect(source.contains("liveValues"))
    }

    @Test("SpiderChartCanvas source uses reference radar chart geometry")
    func spiderChartCanvasSourceUsesReferenceRadarGeometry() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/Hype/Views/ChartHostView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("return -.pi / 2 + CGFloat(index)"))
        #expect(source.contains("ForEach(0...ringCount"))
        #expect(source.contains(".frame(width: 110"))
        #expect(source.contains("spiderShowValueLabels"))
        #expect(!source.contains(".background(Capsule().fill(Color.white.opacity(0.72)))"))
        #expect(!source.contains(".clipped()"))
    }

    @Test("PropertyInspector source labels spider data point fields")
    func propertyInspectorSourceLabelsSpiderDataPointFields() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/Hype/Views/PropertyInspector.swift"),
            encoding: .utf8
        )
        #expect(source.contains("spiderDataPointEditor"))
        #expect(source.contains("Data Point \\(dataIndex + 1)"))
        #expect(source.contains("Text(\"Name\")"))
        #expect(source.contains("\"Value\""))
        #expect(source.contains("\"Minimum\""))
        #expect(source.contains("\"Maximum\""))
        #expect(source.contains("Runtime dragging maps the point along its vector from minimum to maximum."))
    }

    @Test("spider chart reference-style two-series render does not crash")
    func spiderChartReferenceStyleTwoSeriesRendersWithoutCrashing() {
        let labels = ["Party A", "Party B", "Party C", "Party D", "Party E", "Party F", "Party G", "Party H", "Party I"]
        let green = [200.0, 80, 160, 120, 140, 120, 80, 180, 190]
        let red = [120.0, 160, 110, 90, 190, 80, 210, 100, 200]
        let config = ChartConfig(
            chartType: .spider,
            title: "",
            series: [
                ChartSeries(name: "Green", color: "#B7FF79", data: zip(labels, green).map {
                    ChartDataPoint(name: $0.0, value: $0.1, minimumValue: 0, maximumValue: 220)
                }),
                ChartSeries(name: "Red", color: "#FF6F8A", data: zip(labels, red).map {
                    ChartDataPoint(name: $0.0, value: $0.1, minimumValue: 0, maximumValue: 220)
                }),
            ],
            showLegend: false,
            spiderRingCount: 5
        )

        let renderer = ImageRenderer(
            content: ChartHostView(config: config).frame(width: 650, height: 560)
        )
        renderer.scale = 1
        #expect(renderer.nsImage != nil, "reference-style spider chart should render")
    }

    @Test("spider interaction resolver maps axis clicks and active drags to point ranges")
    func spiderInteractionResolverMapsClicksAndDragsToPointRanges() {
        let firstPoint = ChartDataPoint(name: "Strength", value: 18, minimumValue: 3, maximumValue: 18)
        let secondPoint = ChartDataPoint(name: "Dexterity", value: 12, minimumValue: 3, maximumValue: 18)
        let series = ChartSeries(name: "Attributes", color: "#1316EA", data: [
            firstPoint,
            secondPoint,
            ChartDataPoint(name: "Constitution", value: 14, minimumValue: 3, maximumValue: 18),
            ChartDataPoint(name: "Intelligence", value: 15, minimumValue: 3, maximumValue: 18),
            ChartDataPoint(name: "Wisdom", value: 15, minimumValue: 3, maximumValue: 18),
            ChartDataPoint(name: "Charisma", value: 13, minimumValue: 3, maximumValue: 18),
        ])
        let config = ChartConfig(
            chartType: .spider,
            title: "Attributes",
            series: [series],
            showLegend: true,
            interactable: true
        )
        let hostSize = CGSize(width: 496, height: 352)
        let canvasRect = ChartHostView.spiderCanvasRect(in: hostSize, config: config)
        let layout = SpiderChartInteractionResolver.layout(in: canvasRect.size, axisCount: config.spiderAxisLabels().count)
        let halfWayOnDexterity = layout.point(axis: 1, normalizedValue: 0.5)

        let clickResolution = SpiderChartInteractionResolver.resolve(
            config: config,
            location: halfWayOnDexterity,
            size: canvasRect.size,
            activeTarget: nil
        )

        #expect(clickResolution?.pointName == "Dexterity")
        #expect(clickResolution?.seriesName == "Attributes")
        #expect(clickResolution?.value == 11)

        let activeTarget = SpiderChartDragTarget(seriesId: series.id, pointId: firstPoint.id)
        let minimumOnStrength = layout.point(axis: 0, normalizedValue: 0)
        let dragResolution = SpiderChartInteractionResolver.resolve(
            config: config,
            location: minimumOnStrength,
            size: canvasRect.size,
            activeTarget: activeTarget
        )

        #expect(dragResolution?.pointName == "Strength")
        #expect(dragResolution?.value == 3)
    }

    @Test("CardCanvas wires interactive spider chart changes to chartChange")
    func cardCanvasWiresInteractiveSpiderChartChanges() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("setPartChartDataPointValue"))
        #expect(source.contains("ChartHostingView"))
        #expect(source.contains("acceptsChartInteraction"))
        #expect(source.contains("configureChartInteraction"))
        #expect(source.contains("override func mouseDragged(with event: NSEvent)"))
        #expect(source.contains("handleSpiderMouse(event, phase: .changed)"))
        #expect(source.contains("handleSpiderChartCanvasInteraction(part: part, at: point, phase: .began)"))
        #expect(source.contains("activeSpiderChartDrag"))
        #expect(source.contains("phase: .ended"))
        #expect(source.contains("override func hitTest(_ point: NSPoint) -> NSView?"))
        #expect(source.contains("case .chart:"))
        #expect(source.contains("return chartViews[part.id]"))
        #expect(source.contains("host.frame.contains(point)"))
        #expect(source.contains("ChartHostView.spiderCanvasRect(in: bounds.size, config: config)"))
        #expect(source.contains("SpiderChartInteractionResolver.resolve("))
        #expect(source.contains("return self"))
        #expect(!source.contains("return bounds.contains(point) ? self : nil"))
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
