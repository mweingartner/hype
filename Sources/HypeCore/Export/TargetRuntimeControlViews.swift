import Foundation

#if canImport(SwiftUI)
import SwiftUI

#if canImport(AVKit)
import AVKit
#endif
#if canImport(MapKit)
import MapKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(SceneKit)
import SceneKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private struct TargetRuntimeChartView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler

    private var config: ChartConfig {
        ChartConfig.fromJSON(part.chartData) ?? ChartConfig(
            chartType: .bar,
            title: part.name,
            series: [
                ChartSeries(name: "Series", data: [
                    ChartDataPoint(name: "A", value: 3, color: "#4A90D9"),
                    ChartDataPoint(name: "B", value: 5, color: "#FF9F1C"),
                    ChartDataPoint(name: "C", value: 2, color: "#2EC4B6"),
                ]),
            ]
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                Canvas { context, size in
                    drawChart(config, context: &context, size: size)
                }
                .overlay(chartOverlay(size: proxy.size))
                .contentShape(Rectangle())
                .gesture(chartGesture(size: proxy.size))
            }
            if config.showLegend {
                TargetRuntimeChartLegend(entries: config.legendEntries())
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.78)))
    }

    @ViewBuilder
    private func chartOverlay(size: CGSize) -> some View {
        if config.chartType == .spider {
            TargetRuntimeSpiderAxisLabels(config: config, size: size)
        } else if config.showGrid {
            VStack {
                Spacer()
                HStack {
                    if !config.yAxisLabel.isEmpty {
                        Text(config.yAxisLabel)
                            .font(.caption2)
                            .rotationEffect(.degrees(-90))
                    }
                    Spacer()
                }
                if !config.xAxisLabel.isEmpty {
                    Text(config.xAxisLabel)
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func chartGesture(size: CGSize) -> some Gesture {
        #if os(tvOS)
        TapGesture().onEnded { }
        #else
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard config.chartType == .spider, config.interactable else { return }
                guard let changed = updatedSpiderChart(at: value.location, size: size) else { return }
                var updated = part
                updated.chartData = changed.config.toJSON()
                let handler = onPartChanged
                Task { await handler(updated, "chartChange") }
            }
        #endif
    }

    private func drawChart(_ config: ChartConfig, context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 12)
        guard rect.width > 8, rect.height > 8 else { return }
        switch config.chartType {
        case .pie:
            drawPie(config, context: &context, rect: rect)
        case .line, .area, .point:
            drawPlot(config, context: &context, rect: rect)
        case .rule:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            context.stroke(path, with: .color(.secondary), lineWidth: 2)
        case .spider:
            drawSpider(config, context: &context, rect: rect)
        case .bar:
            drawBars(config, context: &context, rect: rect)
        }
    }

    private func drawBars(_ config: ChartConfig, context: inout GraphicsContext, rect: CGRect) {
        let points = config.series.flatMap(\.data)
        guard !points.isEmpty else { return }
        drawAxes(context: &context, rect: rect)
        let maxValue = max(1, points.map(\.value).max() ?? 1)
        let gap: CGFloat = 3
        let width = max(2, (rect.width - gap * CGFloat(points.count - 1)) / CGFloat(points.count))
        for (index, point) in points.enumerated() {
            let h = rect.height * CGFloat(max(0, point.value) / maxValue)
            let bar = CGRect(x: rect.minX + CGFloat(index) * (width + gap), y: rect.maxY - h, width: width, height: h)
            let seriesColor = config.series.first(where: { $0.data.contains(where: { $0.id == point.id }) })?.color ?? "#4A90D9"
            context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(Color(hex: point.color.isEmpty ? seriesColor : point.color)))
        }
    }

    private func drawPlot(_ config: ChartConfig, context: inout GraphicsContext, rect: CGRect) {
        drawAxes(context: &context, rect: rect)
        for series in config.series {
            guard series.data.count >= 1 else { continue }
            let maxValue = max(1, series.data.map(\.value).max() ?? 1)
            var path = Path()
            for (index, point) in series.data.enumerated() {
                let x = rect.minX + (series.data.count == 1 ? rect.width / 2 : CGFloat(index) * rect.width / CGFloat(series.data.count - 1))
                let y = rect.maxY - rect.height * CGFloat(max(0, point.value) / maxValue)
                let p = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                if config.chartType == .point {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Color(hex: point.color.isEmpty ? series.color : point.color)))
                }
            }
            if config.chartType == .area {
                var area = path
                area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                area.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                area.closeSubpath()
                context.fill(area, with: .color(Color(hex: series.color).opacity(0.22)))
            }
            if config.chartType != .point {
                context.stroke(path, with: .color(Color(hex: series.color)), lineWidth: 2)
            }
        }
    }

    private func drawPie(_ config: ChartConfig, context: inout GraphicsContext, rect: CGRect) {
        let points = config.series.flatMap(\.data)
        let total = points.map { max(0, $0.value) }.reduce(0, +)
        guard total > 0 else { return }
        let box = CGRect(
            x: rect.midX - min(rect.width, rect.height) / 2,
            y: rect.midY - min(rect.width, rect.height) / 2,
            width: min(rect.width, rect.height),
            height: min(rect.width, rect.height)
        )
        var start = Angle.degrees(-90)
        for point in points {
            let degrees = 360 * max(0, point.value) / total
            let end = start + .degrees(degrees)
            var path = Path()
            path.move(to: CGPoint(x: box.midX, y: box.midY))
            path.addArc(center: CGPoint(x: box.midX, y: box.midY), radius: box.width / 2, startAngle: start, endAngle: end, clockwise: false)
            path.closeSubpath()
            let seriesColor = config.series.first(where: { $0.data.contains(where: { $0.id == point.id }) })?.color ?? "#4A90D9"
            context.fill(path, with: .color(Color(hex: point.color.isEmpty ? seriesColor : point.color)))
            start = end
        }
    }

    private func drawSpider(_ config: ChartConfig, context: inout GraphicsContext, rect: CGRect) {
        let seriesList = config.spiderRenderableSeries()
        let axisLabels = config.spiderAxisLabels()
        guard axisLabels.count >= 3, !seriesList.isEmpty else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.34
        let ringCount = max(ChartConfig.spiderMinimumRingCount, config.spiderRingCount)

        for ring in 1...ringCount {
            let fraction = CGFloat(ring) / CGFloat(ringCount)
            let points = spiderAxisPoints(axisCount: axisLabels.count, center: center, radius: radius * fraction)
            let path = polygonPath(points)
            if config.spiderShowSplitArea && ring % 2 == 0 {
                context.fill(path, with: .color(Color(hex: config.spiderGridColor).opacity(0.08)))
            }
            context.stroke(path, with: .color(Color(hex: config.spiderGridColor).opacity(0.85)), lineWidth: ring == ringCount ? 1.2 : 0.8)
        }
        for axis in 0..<axisLabels.count {
            let end = spiderAxisPoint(axis: axis, axisCount: axisLabels.count, center: center, radius: radius)
            var path = Path()
            path.move(to: center)
            path.addLine(to: end)
            context.stroke(path, with: .color(Color(hex: config.spiderAxisColor).opacity(0.78)), lineWidth: 0.8)
        }
        for series in seriesList {
            let points = series.data.enumerated().map { index, point in
                let normalized = config.normalizedSpiderValue(for: point)
                return spiderAxisPoint(
                    axis: index,
                    axisCount: axisLabels.count,
                    center: center,
                    radius: radius * CGFloat(normalized)
                )
            }
            let path = polygonPath(points)
            context.fill(path, with: .color(Color(hex: series.color).opacity(config.spiderFillOpacity)))
            context.stroke(path, with: .color(Color(hex: series.color)), lineWidth: 2)
            for point in points {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(Color(hex: series.color)))
            }
        }
        for ring in 0...ringCount {
            let fraction = Double(ring) / Double(ringCount)
            let tick = config.formattedSpiderValue(config.spiderRadialTickValue(fraction: fraction))
            context.draw(Text(tick).font(.caption2).foregroundColor(Color(hex: config.spiderLabelColor)), at: CGPoint(x: center.x + 8, y: center.y - radius * CGFloat(fraction)), anchor: .leading)
        }
    }

    private func drawAxes(context: inout GraphicsContext, rect: CGRect) {
        guard config.showGrid else { return }
        let axisColor = Color.secondary.opacity(0.35)
        var x = Path()
        x.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        x.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        var y = Path()
        y.move(to: CGPoint(x: rect.minX, y: rect.minY))
        y.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.stroke(x, with: .color(axisColor), lineWidth: 1)
        context.stroke(y, with: .color(axisColor), lineWidth: 1)
    }

    private func updatedSpiderChart(at location: CGPoint, size: CGSize) -> (config: ChartConfig, pointName: String)? {
        var config = config
        let seriesList = config.spiderRenderableSeries()
        guard let firstSeries = seriesList.first, firstSeries.data.count >= 3 else { return nil }
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 12)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.34
        guard radius > 0 else { return nil }
        let axisCount = firstSeries.data.count
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        var bestAxis = 0
        var bestScore = -Double.greatestFiniteMagnitude
        var bestProjection: CGFloat = 0
        for axis in 0..<axisCount {
            let end = spiderAxisPoint(axis: axis, axisCount: axisCount, center: center, radius: 1)
            let unit = CGVector(dx: end.x - center.x, dy: end.y - center.y)
            let projection = vector.dx * unit.dx + vector.dy * unit.dy
            let perpendicular = abs(vector.dx * unit.dy - vector.dy * unit.dx)
            let score = Double(projection - perpendicular * 0.65)
            if score > bestScore {
                bestScore = score
                bestAxis = axis
                bestProjection = projection
            }
        }
        let normalized = ChartConfig.clamp(Double(bestProjection / radius), min: 0, max: 1)
        guard let originalSeriesIndex = config.series.firstIndex(where: { $0.id == seriesList[0].id }) else { return nil }
        let oldPoint = config.series[originalSeriesIndex].data[bestAxis]
        let newValue = config.spiderValue(for: oldPoint, from: normalized)
        config.series[originalSeriesIndex].data[bestAxis].value = newValue
        config.normalizeForStorage()
        return (config, oldPoint.name)
    }

    private func spiderAxisPoint(axis: Int, axisCount: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -CGFloat.pi / 2 + (CGFloat(axis) / CGFloat(axisCount)) * CGFloat.pi * 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func spiderAxisPoints(axisCount: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0..<axisCount).map { spiderAxisPoint(axis: $0, axisCount: axisCount, center: center, radius: radius) }
    }

    private func polygonPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct TargetRuntimeSpiderAxisLabels: View {
    let config: ChartConfig
    let size: CGSize

    var body: some View {
        let labels = config.spiderAxisLabels()
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 12)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.42
        ZStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color(hex: config.spiderLabelColor))
                    .position(spiderAxisPoint(axis: index, axisCount: labels.count, center: center, radius: radius))
            }
        }
    }

    private func spiderAxisPoint(axis: Int, axisCount: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -CGFloat.pi / 2 + (CGFloat(axis) / CGFloat(axisCount)) * CGFloat.pi * 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

private struct TargetRuntimeChartLegend: View {
    let entries: [ChartLegendEntry]

    var body: some View {
        if !entries.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], spacing: 3) {
                ForEach(entries, id: \.name) { entry in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: entry.colorHex))
                            .frame(width: 10, height: 10)
                        Text(entry.name)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct TargetRuntimeMusicPlayerView<SystemProviderType: SystemProvider>: View {
    let part: Part
    let document: HypeDocument
    let systemProvider: SystemProviderType
    @State private var playing = false

    var body: some View {
        VStack(spacing: 6) {
            Text(part.name.isEmpty ? "Music Player" : part.name)
                .font(.caption.bold())
                .lineLimit(1)
            Button(playing ? "Stop" : "Play") {
                if playing {
                    Task {
                        await systemProvider.stopMusic()
                        playing = false
                    }
                } else {
                    playFromCenter()
                }
            }
            .buttonStyle(.borderedProminent)
            if !part.musicPatternName.isEmpty {
                Text(part.musicPatternName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: part.fillColor).opacity(0.12)))
    }

    private func playFromCenter() {
        var runtimePart = part
        runtimePart.left = 0
        runtimePart.top = 0
        let request = MusicControlInteraction.playbackRequest(
            for: runtimePart,
            document: document,
            clickPoint: CGPoint(x: runtimePart.width / 2, y: runtimePart.height / 2)
        )
        guard let request else { return }
        Task {
            await systemProvider.playMusicPattern(request.pattern, loop: request.loop, document: document)
            playing = true
        }
    }
}

private struct TargetRuntimeMusicMixerView<SystemProviderType: SystemProvider>: View {
    let part: Part
    let document: HypeDocument
    let systemProvider: SystemProviderType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(part.name.isEmpty ? "Music Mixer" : part.name)
                    .font(.caption.bold())
                Spacer()
                Button("Play") { play() }
                    .buttonStyle(.bordered)
                Button("Stop") { Task { await systemProvider.stopMusic() } }
                    .buttonStyle(.bordered)
            }
            let tracks = mixerTracks
            if tracks.isEmpty {
                Text("No tracks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                    HStack {
                        Text(track.name)
                            .font(.caption2)
                            .lineLimit(1)
                        ProgressView(value: track.volume, total: 1)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
    }

    private var mixerTracks: [MusicTrackSpec] {
        if !part.musicPatternName.isEmpty,
           let pattern = document.musicLibrary.pattern(named: part.musicPatternName) {
            return pattern.tracks
        }
        return MusicPatternSpec.singleTrack(
            name: "Preview",
            instrument: part.musicInstrumentName,
            tempo: MusicTempo.clamp(part.musicTempo),
            notes: "c4q e4q g4q c5q"
        ).tracks
    }

    private func play() {
        let request = MusicControlInteraction.playbackRequest(
            for: part,
            document: document,
            clickPoint: CGPoint(x: max(1, part.width / 2), y: max(1, part.height / 2))
        )
        guard let request else { return }
        Task { await systemProvider.playMusicPattern(request.pattern, loop: request.loop, document: document) }
    }
}

private struct TargetRuntimePianoKeyboardView<SystemProviderType: SystemProvider>: View {
    let part: Part
    let document: HypeDocument
    let systemProvider: SystemProviderType
    @State private var activeNote: String?

    var body: some View {
        GeometryReader { proxy in
            let runtimePart = runtimePart(for: proxy.size)
            let layout = MusicControlInteraction.keyboardLayout(for: runtimePart)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: part.fillColor).opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.18), lineWidth: 1))
                if MusicControlInteraction.pianoKeyboardShowsMetadata(part) {
                    HStack(spacing: 8) {
                        if part.musicShowControlType { Text("Piano Keyboard") }
                        if part.musicShowPattern, !part.musicPatternName.isEmpty { Text(part.musicPatternName) }
                        if part.musicShowInstrument { Text(part.musicInstrumentName) }
                        if part.musicShowTempo { Text("\(MusicTempo.clamp(part.musicTempo)) BPM") }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
                ForEach(layout.whiteKeys, id: \.note) { key in
                    TargetRuntimePianoKeyView(key: key, isActive: activeNote == key.note)
                }
                ForEach(layout.blackKeys, id: \.note) { key in
                    TargetRuntimePianoKeyView(key: key, isActive: activeNote == key.note)
                }
            }
            .contentShape(Rectangle())
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in playKeyboardNote(at: value.location, size: proxy.size) }
                    .onEnded { _ in
                        activeNote = nil
                        Task { await systemProvider.stopSustainedMusicNotes(forPart: part.id) }
                    }
            )
            #endif
        }
    }

    private func runtimePart(for size: CGSize) -> Part {
        var copy = part
        copy.left = 0
        copy.top = 0
        copy.width = max(1, Double(size.width))
        copy.height = max(1, Double(size.height))
        return copy
    }

    private func playKeyboardNote(at point: CGPoint, size: CGSize) {
        let runtimePart = runtimePart(for: size)
        guard let note = MusicControlInteraction.keyboardNote(at: point, for: runtimePart) else {
            if activeNote != nil {
                activeNote = nil
                Task { await systemProvider.stopSustainedMusicNotes(forPart: part.id) }
            }
            return
        }
        guard activeNote != note else { return }
        activeNote = note
        guard let request = MusicControlInteraction.playbackRequest(for: runtimePart, document: document, clickPoint: point) else { return }
        Task {
            await systemProvider.stopSustainedMusicNotes(forPart: part.id)
            if let sustainedNote = request.sustainedNote {
                await systemProvider.playSustainedMusicNote(sustainedNote, document: document)
            } else {
                await systemProvider.playMusicPattern(request.pattern, loop: request.loop, document: document)
            }
        }
    }
}

private struct TargetRuntimePianoKeyView: View {
    let key: MusicKeyboardKeyLayout
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: key.isBlack ? 3 : 4)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: key.isBlack ? 3 : 4).stroke(stroke, lineWidth: key.isBlack ? 0.7 : 0.8))
            .shadow(color: isActive ? Color.yellow.opacity(key.isBlack ? 0.7 : 0.45) : .clear, radius: isActive ? 6 : 0)
            .frame(width: key.frame.width, height: key.frame.height)
            .position(x: key.frame.midX, y: key.frame.midY)
            .zIndex(key.isBlack ? 2 : 1)
    }

    private var fill: Color {
        if key.isBlack { return isActive ? Color.yellow.opacity(0.75) : Color.black }
        return isActive ? Color.yellow.opacity(0.28) : Color.white
    }

    private var stroke: Color {
        key.isBlack ? Color.black.opacity(0.85) : Color.black.opacity(0.28)
    }
}

private struct TargetRuntimeStepSequencerView<SystemProviderType: SystemProvider>: View {
    let part: Part
    let document: HypeDocument
    let systemProvider: SystemProviderType
    @State private var activeCell: String?

    var body: some View {
        GeometryReader { proxy in
            let runtimePart = runtimePart(for: proxy.size)
            let grid = MusicControlInteraction.stepSequencerGridRect(for: runtimePart)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.16), lineWidth: 1))
                if MusicControlInteraction.musicControlShowsMetadata(part) {
                    metadata
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
                ForEach(0..<MusicControlInteraction.stepSequencerRowCount, id: \.self) { row in
                    ForEach(0..<MusicControlInteraction.stepSequencerColumnCount, id: \.self) { column in
                        let frame = cellFrame(row: row, column: column, grid: grid)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(activeCell == "\(row):\(column)" ? Color.yellow.opacity(0.55) : Color(hex: part.fillColor).opacity(0.24))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: part.strokeColor).opacity(0.35), lineWidth: 0.8))
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .contentShape(Rectangle())
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in playCell(at: value.location, size: proxy.size) }
                    .onEnded { _ in activeCell = nil }
            )
            #endif
        }
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            if part.musicShowControlType { Text("Step Sequencer") }
            if part.musicShowPattern, !part.musicPatternName.isEmpty { Text(part.musicPatternName) }
            if part.musicShowInstrument { Text(part.musicInstrumentName) }
            if part.musicShowTempo { Text("\(MusicTempo.clamp(part.musicTempo)) BPM") }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func runtimePart(for size: CGSize) -> Part {
        var copy = part
        copy.left = 0
        copy.top = 0
        copy.width = max(1, Double(size.width))
        copy.height = max(1, Double(size.height))
        return copy
    }

    private func cellFrame(row: Int, column: Int, grid: CGRect) -> CGRect {
        let w = grid.width / CGFloat(MusicControlInteraction.stepSequencerColumnCount)
        let h = grid.height / CGFloat(MusicControlInteraction.stepSequencerRowCount)
        return CGRect(x: grid.minX + CGFloat(column) * w + 2, y: grid.minY + CGFloat(row) * h + 2, width: max(2, w - 4), height: max(2, h - 4))
    }

    private func playCell(at point: CGPoint, size: CGSize) {
        let runtimePart = runtimePart(for: size)
        guard let cell = MusicControlInteraction.stepSequencerCell(at: point, for: runtimePart) else { return }
        let cellKey = "\(cell.row):\(cell.column)"
        guard activeCell != cellKey else { return }
        activeCell = cellKey
        guard let request = MusicControlInteraction.playbackRequest(for: runtimePart, document: document, clickPoint: point) else { return }
        Task { await systemProvider.playMusicPattern(request.pattern, loop: request.loop, document: document) }
    }
}

private struct TargetRuntimeAppleMusicBrowserView<SystemProviderType: SystemProvider>: View {
    let part: Part
    let document: HypeDocument
    let systemProvider: SystemProviderType
    let onPartChanged: TargetRuntimePartMutationHandler

    @State private var term: String = ""
    @State private var scope: AppleMusicSearchScope = .catalog
    @State private var kind: AppleMusicItemKind = .song
    @State private var results: [AppleMusicItemRef] = []
    @State private var statusText: String = ""

    var body: some View {
        #if os(tvOS)
        placeholder("Apple Music is not available in the tvOS runtime")
        #else
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Search Apple Music", text: $term)
                    .textFieldStyle(.roundedBorder)
                Button("Search") { search() }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Picker("Scope", selection: $scope) {
                    Text("Catalog").tag(AppleMusicSearchScope.catalog)
                    Text("Library").tag(AppleMusicSearchScope.library)
                }
                .pickerStyle(.segmented)
                Picker("Type", selection: $kind) {
                    ForEach([AppleMusicItemKind.song, .album, .artist, .playlist], id: \.self) { item in
                        Text(item.rawValue.capitalized).tag(item)
                    }
                }
            }
            .font(.caption)
            if !document.stack.appleMusicAllowed {
                Text("Apple Music is disabled for this stack.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty {
                selectedSummary
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(results, id: \.encodedSource) { item in
                            Button(item.titleSnapshot.isEmpty ? item.id : item.titleSnapshot) {
                                select(item)
                            }
                            .buttonStyle(.plain)
                            .lineLimit(1)
                        }
                    }
                }
            }
            HStack {
                Button("Play") { playSelected() }
                Button("Stop") { Task { await systemProvider.stopAppleMusic(engine: .application) } }
                if part.musicDuration > 0 {
                    Slider(value: Binding(
                        get: { min(max(0, part.musicPosition), part.musicDuration) },
                        set: { value in
                            var updated = part
                            updated.musicPosition = value
                            commit(updated, message: "positionChanged")
                            Task { try? await systemProvider.seekAppleMusic(to: value, engine: .application) }
                        }
                    ), in: 0...part.musicDuration)
                }
            }
            .font(.caption)
            if !statusText.isEmpty {
                Text(statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
        .onAppear {
            term = part.musicSearchTerm
            scope = AppleMusicSearchScope(rawValue: part.musicSearchScope) ?? .catalog
            kind = AppleMusicItemKind.parse(part.musicSourceType) ?? .song
        }
        #endif
    }

    @ViewBuilder
    private var selectedSummary: some View {
        if !part.musicSourceTitle.isEmpty {
            Text("Selected: \(part.musicSourceTitle)")
                .font(.caption2)
                .lineLimit(1)
        } else {
            Text("Choose a song, album, artist, or playlist.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func search() {
        guard document.stack.appleMusicAllowed else { return }
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = part
        updated.musicSearchTerm = trimmed
        updated.musicSearchScope = scope.rawValue
        updated.musicSourceType = kind.rawValue
        commit(updated, message: "searchSubmitted")
        Task {
            _ = await systemProvider.authorizeAppleMusic()
            do {
                results = try await systemProvider.searchAppleMusic(
                    AppleMusicSearchRequest(term: trimmed, scope: scope, itemKinds: [kind], limit: 12)
                )
                statusText = results.isEmpty ? "No results." : "\(results.count) result(s)"
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func select(_ item: AppleMusicItemRef) {
        var updated = part
        updated.musicSourceID = item.id
        updated.musicSourceKind = item.source.rawValue
        updated.musicSourceType = item.kind.rawValue
        updated.musicSourceTitle = item.titleSnapshot
        updated.musicSourceArtist = item.artistSnapshot
        updated.musicSourceAlbum = item.albumSnapshot
        updated.musicArtworkURL = item.artworkURLSnapshot
        updated.musicDuration = item.durationSnapshot ?? 0
        commit(updated, message: "selectionChanged")
    }

    private func playSelected() {
        guard let ref = appleMusicRef(from: part) else { return }
        Task {
            do {
                _ = await systemProvider.authorizeAppleMusic()
                try await systemProvider.playAppleMusic(ref, engine: .application)
                statusText = "Playing \(ref.titleSnapshot)"
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func appleMusicRef(from part: Part) -> AppleMusicItemRef? {
        guard !part.musicSourceID.isEmpty,
              let kind = AppleMusicItemKind.parse(part.musicSourceType) else { return nil }
        return AppleMusicItemRef(
            id: part.musicSourceID,
            kind: kind,
            source: MusicSourceKind.parse(part.musicSourceKind),
            titleSnapshot: part.musicSourceTitle.isEmpty ? part.musicSourceID : part.musicSourceTitle,
            artistSnapshot: part.musicSourceArtist,
            albumSnapshot: part.musicSourceAlbum,
            artworkURLSnapshot: part.musicArtworkURL,
            durationSnapshot: part.musicDuration > 0 ? part.musicDuration : nil
        )
    }

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

public typealias TargetRuntimePartMutationHandler = @Sendable (Part, String?) async -> Void

/// SwiftUI runtime renderer for controls that are safe in standalone deployed
/// stacks. It intentionally lives in HypeCore so generated iPhone/iPad shells
/// do not need to duplicate each control adapter as generated source text.
public struct TargetRuntimePartView<SystemProviderType: SystemProvider>: View {
    public let part: Part
    public let geometry: PartResolvedGeometry?
    public let document: HypeDocument
    public let systemProvider: SystemProviderType
    public let onPartChanged: TargetRuntimePartMutationHandler
    public let onMouseUp: @Sendable (Part) async -> Void

    private var left: Double { geometry?.left ?? part.left }
    private var top: Double { geometry?.top ?? part.top }
    private var width: Double { geometry?.width ?? part.width }
    private var height: Double { geometry?.height ?? part.height }

    public init(
        part: Part,
        geometry: PartResolvedGeometry?,
        document: HypeDocument,
        systemProvider: SystemProviderType,
        onPartChanged: @escaping TargetRuntimePartMutationHandler,
        onMouseUp: @escaping @Sendable (Part) async -> Void
    ) {
        self.part = part
        self.geometry = geometry
        self.document = document
        self.systemProvider = systemProvider
        self.onPartChanged = onPartChanged
        self.onMouseUp = onMouseUp
    }

    public var body: some View {
        content
            .frame(width: CGFloat(width), height: CGFloat(height))
            .position(x: CGFloat(left + width / 2), y: CGFloat(top + height / 2))
            .rotationEffect(.degrees(part.rotation))
            .opacity(part.visible ? 1 : 0)
            .allowsHitTesting(part.visible && part.enabled)
            .accessibilityLabel(part.name.isEmpty ? part.partType.rawValue : part.name)
    }

    @ViewBuilder
    private var content: some View {
        switch part.partType {
        case .button, .toggle, .link, .menu:
            TargetRuntimeButtonView(part: part, onPartChanged: onPartChanged, onMouseUp: onMouseUp)
        case .field, .searchField:
            TargetRuntimeFieldView(part: part, onPartChanged: onPartChanged)
        case .shape:
            TargetRuntimeShapeView(part: part)
        case .webpage:
            TargetRuntimeWebView(urlString: part.url)
        case .image:
            TargetRuntimeImageView(part: part)
        case .video:
            TargetRuntimeVideoView(part: part)
        case .chart:
            TargetRuntimeChartView(part: part, onPartChanged: onPartChanged)
        case .calendar:
            TargetRuntimeCalendarView(part: part, onPartChanged: onPartChanged)
        case .pdf:
            TargetRuntimePDFView(part: part)
        case .map:
            TargetRuntimeMapView(part: part)
        case .colorWell:
            TargetRuntimeColorWellView(part: part, onPartChanged: onPartChanged)
        case .stepper:
            TargetRuntimeStepperView(part: part, onPartChanged: onPartChanged)
        case .slider:
            TargetRuntimeSliderView(part: part, onPartChanged: onPartChanged)
        case .segmented:
            TargetRuntimeSegmentedView(part: part, onPartChanged: onPartChanged)
        case .scene3D:
            TargetRuntimeScene3DView(part: part, document: document)
        case .musicPlayer:
            TargetRuntimeMusicPlayerView(part: part, document: document, systemProvider: systemProvider)
        case .pianoKeyboard:
            TargetRuntimePianoKeyboardView(part: part, document: document, systemProvider: systemProvider)
        case .stepSequencer:
            TargetRuntimeStepSequencerView(part: part, document: document, systemProvider: systemProvider)
        case .musicMixer:
            TargetRuntimeMusicMixerView(part: part, document: document, systemProvider: systemProvider)
        case .appleMusicBrowser:
            TargetRuntimeAppleMusicBrowserView(part: part, document: document, systemProvider: systemProvider, onPartChanged: onPartChanged)
        case .progressView:
            TargetRuntimeProgressView(part: part)
        case .gauge:
            TargetRuntimeGaugeView(part: part)
        case .divider:
            TargetRuntimeDividerView(part: part)
        case .spriteArea, .audioRecorder, .musicQueue, .unknown:
            TargetRuntimeUnsupportedView(part: part)
        }
    }
}

private struct TargetRuntimeUnsupportedView: View {
    let part: Part

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            Text("\(part.partType.rawValue) unsupported")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(6)
        }
    }
}

private struct TargetRuntimeButtonView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler
    let onMouseUp: @Sendable (Part) async -> Void
    @Environment(\.openURL) private var openURL

    private var label: String {
        let value = part.showName ? part.name : part.textContent
        return value.isEmpty ? "Button" : value
    }

    var body: some View {
        switch part.buttonStyle {
        case .toggle, .checkBox, .radio:
            Toggle(isOn: Binding(
                get: { part.hilite || part.controlValue >= 0.5 },
                set: { newValue in
                    var updated = part
                    updated.hilite = newValue
                    updated.controlValue = newValue ? 1 : 0
                    commit(updated, message: "valueChanged")
                }
            )) {
                Text(label).lineLimit(1)
            }
            #if !os(tvOS)
            .toggleStyle(.switch)
            #endif
            .padding(.horizontal, 6)
        case .popup:
            Menu {
                ForEach(popupItems, id: \.self) { item in
                    Button(item) {
                        var updated = part
                        updated.textContent = item
                        commit(updated, message: "mouseUp")
                    }
                }
            } label: {
                Text(part.textContent.isEmpty ? label : part.textContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.bordered)
        case .link:
            Button(label) {
                if let url = URL(string: part.url), !part.url.isEmpty {
                    openURL(url)
                }
                dispatchMouseUp(part)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .underline()
        case .transparent:
            Button(label) { dispatchMouseUp(part) }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            Button(label) { dispatchMouseUp(part) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var popupItems: [String] {
        let raw = part.popupItems.isEmpty ? part.menuItems : part.popupItems
        let items = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                let label = line.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? String(line)
                return label.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return items.isEmpty ? ["Item 1", "Item 2"] : items
    }

    private func dispatchMouseUp(_ part: Part) {
        let handler = onMouseUp
        Task { await handler(part) }
    }

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

private struct TargetRuntimeFieldView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler

    var body: some View {
        Group {
            #if os(tvOS)
            Text(part.textContent.isEmpty ? part.name : part.textContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(part.wideMargins ? 10 : 5)
                .overlay(fieldBorder)
            #else
            if part.lockText {
                Text(part.textContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .padding(part.wideMargins ? 10 : 5)
            } else if part.fieldStyle == .secure {
                SecureField(part.name.isEmpty ? "Text" : part.name, text: fieldBinding(message: nil))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { dispatch(part.enterKeyEnabled ? "enterKey" : nil) }
                    .padding(4)
            } else if part.fieldStyle == .search {
                TextField(part.searchPrompt.isEmpty ? "Search" : part.searchPrompt, text: fieldBinding(message: part.searchSendsImmediately ? "searchChanged" : nil))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { dispatch("searchSubmitted") }
                    .padding(4)
            } else if part.fieldStyle == .scrolling || !part.dontWrap {
                TextEditor(text: fieldBinding(message: nil))
                    .scrollContentBackground(.hidden)
                    .padding(part.wideMargins ? 8 : 2)
                    .overlay(fieldBorder)
            } else {
                TextField(part.name.isEmpty ? "Text" : part.name, text: fieldBinding(message: nil))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { dispatch(part.enterKeyEnabled ? "enterKey" : nil) }
                    .padding(4)
            }
            #endif
        }
        .font(.system(size: max(8, part.textSize)))
        .foregroundStyle(part.fontColor.isEmpty ? Color.primary : Color(hex: part.fontColor))
        .background(fieldBackground)
    }

    private var alignment: Alignment {
        switch part.textAlign {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: part.fieldStyle == .shadow ? 8 : 4)
            .stroke(Color(hex: part.strokeColor), lineWidth: max(0, part.strokeWidth))
    }

    @ViewBuilder
    private var fieldBackground: some View {
        if part.fieldStyle == .transparent {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: part.fieldStyle == .shadow ? 8 : 4)
                .fill(Color(hex: part.fillColor))
                .shadow(color: part.fieldStyle == .shadow ? .black.opacity(0.22) : .clear, radius: 4, x: 0, y: 2)
        }
    }

    private func fieldBinding(message: String?) -> Binding<String> {
        Binding(
            get: { part.textContent },
            set: { newValue in
                var updated = part
                updated.textContent = String(newValue.prefix(65_536))
                if updated.fieldStyle == .search {
                    updated.searchText = updated.textContent
                }
                commit(updated, message: message)
            }
        )
    }

    private func dispatch(_ message: String?) {
        guard let message else { return }
        commit(part, message: message)
    }

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

private struct TargetRuntimeShapeView: View {
    let part: Part

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            Canvas { context, size in
                let path = shapePath(in: CGRect(origin: .zero, size: size))
                context.fill(path, with: .color(Color(hex: part.fillColor)))
                if part.strokeWidth > 0 {
                    context.stroke(path, with: .color(Color(hex: part.strokeColor)), lineWidth: part.strokeWidth)
                }
            }
            .contentShape(Path(rect))
        }
    }

    private func shapePath(in rect: CGRect) -> Path {
        switch part.shapeType {
        case .rectangle:
            return Path(rect)
        case .roundRect:
            return Path(roundedRect: rect, cornerRadius: min(CGFloat(part.cornerRadius), rect.width / 2, rect.height / 2))
        case .oval:
            return Path(ellipseIn: rect)
        case .line:
            var path = Path()
            if part.pathData.count >= 2 {
                let points = normalizedPathPoints(in: rect)
                path.move(to: points[0])
                path.addLine(to: points[points.count - 1])
            } else {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            return path
        case .freeform:
            var path = Path()
            let points = normalizedPathPoints(in: rect)
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        }
    }

    private func normalizedPathPoints(in rect: CGRect) -> [CGPoint] {
        guard !part.pathData.isEmpty else { return [] }
        let minX = part.pathData.map(\.x).min() ?? 0
        let minY = part.pathData.map(\.y).min() ?? 0
        let maxX = part.pathData.map(\.x).max() ?? minX + 1
        let maxY = part.pathData.map(\.y).max() ?? minY + 1
        let scaleX = rect.width / max(1, maxX - minX)
        let scaleY = rect.height / max(1, maxY - minY)
        return part.pathData.map {
            CGPoint(
                x: rect.minX + CGFloat($0.x - minX) * scaleX,
                y: rect.minY + CGFloat($0.y - minY) * scaleY
            )
        }
    }
}

private struct TargetRuntimeImageView: View {
    let part: Part

    var body: some View {
        if let data = part.imageData, let image = TargetRuntimePlatformImage(data: data) {
            TargetRuntimePlatformImageView(image: image)
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.16))
                .overlay(Text("Image").font(.caption).foregroundStyle(.secondary))
        }
    }
}

private struct TargetRuntimeVideoView: View {
    let part: Part

    var body: some View {
        #if canImport(AVKit)
        if let url = targetRuntimeURL(part.videoURL) {
            VideoPlayer(player: AVPlayer(url: url))
        } else {
            placeholder("Video")
        }
        #else
        placeholder("Video unavailable")
        #endif
    }
}

private struct TargetRuntimeCalendarView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler

    var body: some View {
        #if os(tvOS)
        Text(part.selectedDate.isEmpty ? "Date unavailable" : part.selectedDate)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        if part.calendarStyle.lowercased().contains("text") {
            picker.datePickerStyle(.compact).labelsHidden().padding(4)
        } else {
            picker.datePickerStyle(.graphical).labelsHidden().padding(4)
        }
        #endif
    }

    #if !os(tvOS)
    private var picker: some View {
        DatePicker(
            part.name.isEmpty ? "Date" : part.name,
            selection: Binding(
                get: { parseDate(part.selectedDate) ?? Date() },
                set: { date in
                    var updated = part
                    updated.selectedDate = formatDate(date)
                    updated.displayMonth = monthDate(date)
                    commit(updated, message: "dateChanged")
                }
            ),
            displayedComponents: [.date]
        )
    }
    #endif

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

private struct TargetRuntimeColorWellView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler

    var body: some View {
        #if os(tvOS)
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(hex: part.colorWellHex))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.5), lineWidth: 1))
            .padding(4)
        #else
        if part.colorWellInteractive {
            ColorPicker(part.name.isEmpty ? "Color" : part.name, selection: Binding(
                get: { Color(hex: part.colorWellHex) },
                set: { newColor in
                    var updated = part
                    updated.colorWellHex = newColor.hexString ?? part.colorWellHex
                    commit(updated, message: "colorChanged")
                }
            ))
            .labelsHidden()
            .padding(6)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: part.colorWellHex))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.5), lineWidth: 1))
                .padding(4)
        }
        #endif
    }

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

private struct TargetRuntimeStepperView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler

    var body: some View {
        #if os(tvOS)
        Text("\(part.name.isEmpty ? "Value" : part.name): \(ChartConfig.formattedValue(clampedControlValue(part)))")
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        Stepper(value: Binding(
            get: { clampedControlValue(part) },
            set: { value in
                var updated = part
                updated.controlValue = quantizedControlValue(value, part: part)
                commit(updated, message: "valueChanged")
            }
        ), in: controlRange(part), step: max(0.0001, part.controlStep)) {
            Text("\(part.name.isEmpty ? "Value" : part.name): \(ChartConfig.formattedValue(clampedControlValue(part)))")
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        #endif
    }

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

private struct TargetRuntimeSliderView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler

    var body: some View {
        #if os(tvOS)
        VStack(spacing: 4) {
            Text(part.name.isEmpty ? "Value" : part.name)
                .font(.caption)
                .lineLimit(1)
            ProgressView(value: clampedControlValue(part), total: max(1e-10, controlRange(part).upperBound))
            Text(ChartConfig.formattedValue(clampedControlValue(part)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        #else
        VStack(spacing: 4) {
            if !part.name.isEmpty {
                Text(part.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            Slider(value: Binding(
                get: { clampedControlValue(part) },
                set: { value in
                    var updated = part
                    updated.controlValue = quantizedControlValue(value, part: part)
                    commit(updated, message: "valueChanged")
                }
            ), in: controlRange(part), step: max(0.0001, part.controlStep))
            Text(ChartConfig.formattedValue(clampedControlValue(part)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        #endif
    }

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

private struct TargetRuntimeSegmentedView: View {
    let part: Part
    let onPartChanged: TargetRuntimePartMutationHandler

    private var items: [String] {
        let values = part.segmentItems
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? ["First", "Second"] : values
    }

    var body: some View {
        Picker(part.name.isEmpty ? "Selection" : part.name, selection: Binding(
            get: { min(max(0, Int(part.controlValue.rounded())), max(0, items.count - 1)) },
            set: { index in
                var updated = part
                updated.controlValue = Double(index)
                commit(updated, message: "selectionChanged")
            }
        )) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .padding(4)
    }

    private func commit(_ updated: Part, message: String?) {
        let handler = onPartChanged
        Task { await handler(updated, message) }
    }
}

private struct TargetRuntimeProgressView: View {
    let part: Part

    var body: some View {
        VStack(spacing: 5) {
            if !part.progressLabel.isEmpty {
                Text(part.progressLabel)
                    .font(.caption)
                    .lineLimit(1)
            }
            if part.progressIsIndeterminate {
                if part.progressIsCircular {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            } else {
                if part.progressIsCircular {
                    ProgressView(
                        value: max(0, min(part.progressValue, part.progressTotal)),
                        total: max(1e-10, part.progressTotal)
                    )
                    .progressViewStyle(.circular)
                    .tint(part.progressTint.isEmpty ? nil : Color(hex: part.progressTint))
                } else {
                    ProgressView(
                        value: max(0, min(part.progressValue, part.progressTotal)),
                        total: max(1e-10, part.progressTotal)
                    )
                    .progressViewStyle(.linear)
                    .tint(part.progressTint.isEmpty ? nil : Color(hex: part.progressTint))
                }
            }
        }
        .padding(6)
    }
}

private struct TargetRuntimeGaugeView: View {
    let part: Part

    var body: some View {
        #if os(tvOS)
        VStack(spacing: 4) {
            let lower = min(part.gaugeMin, part.gaugeMax - 1)
            let upper = max(part.gaugeMax, lower + 1)
            Text(part.gaugeLabel.isEmpty ? part.name : part.gaugeLabel)
                .font(.caption)
                .lineLimit(1)
            ProgressView(value: min(max(part.gaugeValue, lower), upper) - lower, total: upper - lower)
                .tint(tint)
            Text(ChartConfig.formattedValue(part.gaugeValue, decimalPlaces: max(0, part.gaugeDecimals)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        #else
        switch part.gaugeStyle.lowercased() {
        case "accessorycircular":
            gauge.gaugeStyle(.accessoryCircular).tint(tint).padding(6)
        case "accessorycircularcapacity":
            gauge.gaugeStyle(.accessoryCircularCapacity).tint(tint).padding(6)
        case "accessorylinear", "accessorylineargauge":
            gauge.gaugeStyle(.accessoryLinear).tint(tint).padding(6)
        default:
            gauge.gaugeStyle(.linearCapacity).tint(tint).padding(6)
        }
        #endif
    }

    #if !os(tvOS)
    private var gauge: some View {
        let lower = min(part.gaugeMin, part.gaugeMax - 1)
        let upper = max(part.gaugeMax, lower + 1)
        return Gauge(
            value: min(max(part.gaugeValue, lower), upper),
            in: lower...upper
        ) {
            Text(part.gaugeLabel.isEmpty ? part.name : part.gaugeLabel)
        } currentValueLabel: {
            Text(ChartConfig.formattedValue(part.gaugeValue, decimalPlaces: max(0, part.gaugeDecimals)))
        } minimumValueLabel: {
            Text(part.gaugeMinLabel.isEmpty ? ChartConfig.formattedValue(lower) : part.gaugeMinLabel)
        } maximumValueLabel: {
            Text(part.gaugeMaxLabel.isEmpty ? ChartConfig.formattedValue(upper) : part.gaugeMaxLabel)
        }
    }
    #endif

    private var tint: Color? {
        part.gaugeTint.isEmpty ? nil : Color(hex: part.gaugeTint)
    }
}

private struct TargetRuntimeDividerView: View {
    let part: Part

    var body: some View {
        Rectangle()
            .fill(part.dividerColor.isEmpty ? Color.secondary.opacity(0.45) : Color(hex: part.dividerColor))
            .frame(
                width: isVertical ? max(1, part.dividerThickness) : nil,
                height: isVertical ? nil : max(1, part.dividerThickness)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isVertical: Bool {
        part.dividerOrientation.lowercased() == "vertical" || part.height > part.width
    }
}

private struct TargetRuntimeWebView: View {
    let urlString: String

    var body: some View {
        #if canImport(WebKit)
        if let url = targetRuntimeURL(urlString), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
            TargetRuntimeWKWebView(url: url)
        } else {
            placeholder("Web page")
        }
        #else
        placeholder("Web unavailable")
        #endif
    }
}

#if canImport(WebKit) && canImport(UIKit)
private struct TargetRuntimeWKWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}
#elseif canImport(WebKit) && canImport(AppKit)
private struct TargetRuntimeWKWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
#endif

private struct TargetRuntimePDFView: View {
    let part: Part

    var body: some View {
        #if canImport(PDFKit)
        if let url = targetRuntimeURL(part.pdfURL) {
            TargetRuntimePDFKitView(url: url, part: part)
        } else {
            placeholder("PDF")
        }
        #else
        placeholder("PDF unavailable")
        #endif
    }
}

#if canImport(PDFKit) && canImport(UIKit)
private struct TargetRuntimePDFKitView: UIViewRepresentable {
    let url: URL
    let part: Part
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(frame: .zero)
        apply(to: view)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) { apply(to: uiView) }
    private func apply(to view: PDFView) {
        view.autoScales = part.pdfAutoScales
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        if let page = view.document?.page(at: max(0, part.pdfCurrentPage - 1)) {
            view.go(to: page)
        }
    }
}
#elseif canImport(PDFKit) && canImport(AppKit)
private struct TargetRuntimePDFKitView: NSViewRepresentable {
    let url: URL
    let part: Part
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(frame: .zero)
        apply(to: view)
        return view
    }
    func updateNSView(_ nsView: PDFView, context: Context) { apply(to: nsView) }
    private func apply(to view: PDFView) {
        view.autoScales = part.pdfAutoScales
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        if let page = view.document?.page(at: max(0, part.pdfCurrentPage - 1)) {
            view.go(to: page)
        }
    }
}
#endif

private struct TargetRuntimeMapView: View {
    let part: Part

    var body: some View {
        #if canImport(MapKit)
        TargetRuntimeMapKitView(part: part)
        #else
        placeholder("Map unavailable")
        #endif
    }
}

#if canImport(MapKit)
private struct TargetRuntimeMapAnnotationPayload: Decodable {
    var lat: Double?
    var latitude: Double?
    var lon: Double?
    var lng: Double?
    var longitude: Double?
    var title: String?
}

private enum TargetRuntimeMapSupport {
    @MainActor
    static func apply(_ part: Part, to mapView: MKMapView) {
        mapView.mapType = mapType(for: part.mapType)
        if part.mapCenterLat.isFinite, part.mapCenterLon.isFinite {
            let span = CLLocationDegrees(max(0.0001, abs(part.mapSpan)))
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: CLLocationDegrees(part.mapCenterLat), longitude: CLLocationDegrees(part.mapCenterLon)),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            mapView.setRegion(region, animated: false)
        }
        mapView.removeAnnotations(mapView.annotations)
        guard let data = part.mapAnnotationsJSON.data(using: .utf8),
              let payloads = try? JSONDecoder().decode([TargetRuntimeMapAnnotationPayload].self, from: data) else {
            return
        }
        let annotations = payloads.compactMap { payload -> MKPointAnnotation? in
            guard let lat = payload.lat ?? payload.latitude,
                  let lon = payload.lon ?? payload.lng ?? payload.longitude,
                  lat.isFinite,
                  lon.isFinite else {
                return nil
            }
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            annotation.title = payload.title
            return annotation
        }
        mapView.addAnnotations(annotations)
    }

    private static func mapType(for value: String) -> MKMapType {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "satellite": return .satellite
        case "hybrid": return .hybrid
        case "mutedstandard", "muted_standard", "muted-standard": return .mutedStandard
        default: return .standard
        }
    }
}
#endif

#if canImport(MapKit) && canImport(UIKit)
private struct TargetRuntimeMapKitView: UIViewRepresentable {
    let part: Part
    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView(frame: .zero)
        #if !os(tvOS)
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        #endif
        TargetRuntimeMapSupport.apply(part, to: view)
        return view
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {
        TargetRuntimeMapSupport.apply(part, to: uiView)
    }
}
#elseif canImport(MapKit) && canImport(AppKit)
private struct TargetRuntimeMapKitView: NSViewRepresentable {
    let part: Part
    func makeNSView(context: Context) -> MKMapView {
        let view = MKMapView(frame: .zero)
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        TargetRuntimeMapSupport.apply(part, to: view)
        return view
    }
    func updateNSView(_ nsView: MKMapView, context: Context) {
        TargetRuntimeMapSupport.apply(part, to: nsView)
    }
}
#endif

private struct TargetRuntimeScene3DView: View {
    let part: Part
    let document: HypeDocument

    var body: some View {
        #if canImport(SceneKit)
        TargetRuntimeSceneKitView(part: part, document: document)
        #else
        placeholder("3D scene unavailable")
        #endif
    }
}

#if canImport(SceneKit) && canImport(UIKit)
private struct TargetRuntimeSceneKitView: UIViewRepresentable {
    let part: Part
    let document: HypeDocument

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        apply(part, document: document, to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        apply(part, document: document, to: uiView)
    }
}
#elseif canImport(SceneKit) && canImport(AppKit)
private struct TargetRuntimeSceneKitView: NSViewRepresentable {
    let part: Part
    let document: HypeDocument

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        apply(part, document: document, to: view)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        apply(part, document: document, to: nsView)
    }
}
#endif

#if canImport(SceneKit)
@MainActor
private func apply(_ part: Part, document: HypeDocument, to view: SCNView) {
    view.allowsCameraControl = part.scene3DAllowsCameraControl
    view.autoenablesDefaultLighting = part.scene3DAutoLighting
    view.antialiasingMode = targetRuntimeAntialiasingMode(part.scene3DAntialiasing)
    #if os(macOS)
    view.backgroundColor = part.scene3DBackground.isEmpty ? .clear : (NSColor(hexString: part.scene3DBackground) ?? .clear)
    #elseif canImport(UIKit)
    view.backgroundColor = part.scene3DBackground.isEmpty ? .clear : UIColor(Color(hex: part.scene3DBackground))
    #endif
    guard let url = targetRuntimeSceneURL(part: part, document: document) else {
        view.scene = nil
        return
    }
    let loader = Scene3DAssetLoader()
    DispatchQueue.global(qos: .userInitiated).async {
        let scene = try? loader.load(from: url)
        DispatchQueue.main.async {
            view.scene = scene
        }
    }
}

private func targetRuntimeAntialiasingMode(_ raw: String) -> SCNAntialiasingMode {
    switch raw.lowercased() {
    case "none":
        return .none
    case "multisampling2x":
        return .multisampling2X
    case "multisampling8x":
        #if os(macOS)
        return .multisampling8X
        #else
        return .multisampling4X
        #endif
    default:
        return .multisampling4X
    }
}

private func targetRuntimeSceneURL(part: Part, document: HypeDocument) -> URL? {
    if let ref = part.scene3DAssetRef,
       let resolved = Scene3DRepositoryAssetResolver.resolvedAsset(for: ref, in: document.assetRepository) {
        let renderAsset = resolved.renderAsset
        let ext = targetRuntimeSceneExtension(for: renderAsset)
        let directory = URL.temporaryDirectory.appendingPathComponent("hype-runtime-scene3d", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(renderAsset.id.uuidString).\(ext)")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? renderAsset.data.write(to: url, options: .atomic)
        }
        return url
    }
    return targetRuntimeURL(part.scene3DURL)
}

private func targetRuntimeSceneExtension(for asset: Asset) -> String {
    let ext = (asset.name as NSString).pathExtension.lowercased()
    if Scene3DAssetLoader.supportedExtensions.contains(ext) {
        return ext
    }
    switch asset.mimeType.lowercased() {
    case "model/vnd.usdz+zip", "model/usd", "application/zip": return "usdz"
    case "model/fbx": return "fbx"
    case "model/gltf-binary", "model/gltf+json": return "glb"
    default: return "usdz"
    }
}
#endif

@ViewBuilder
private func placeholder(_ title: String) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.12))
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(6)
    }
}

private func targetRuntimeURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let url = URL(string: trimmed), url.scheme != nil {
        return url
    }
    return URL(fileURLWithPath: trimmed)
}

private func controlRange(_ part: Part) -> ClosedRange<Double> {
    let lower = min(part.controlMin, part.controlMax)
    let upper = max(part.controlMin, part.controlMax)
    return lower...max(lower + 0.0001, upper)
}

private func clampedControlValue(_ part: Part) -> Double {
    min(max(part.controlValue, min(part.controlMin, part.controlMax)), max(part.controlMin, part.controlMax))
}

private func quantizedControlValue(_ raw: Double, part: Part) -> Double {
    let clamped = min(max(raw, min(part.controlMin, part.controlMax)), max(part.controlMin, part.controlMax))
    let step = max(0.0001, abs(part.controlStep))
    return (clamped / step).rounded() * step
}

private func parseDate(_ raw: String) -> Date? {
    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return targetRuntimeDateFormatter.date(from: raw)
}

private func formatDate(_ date: Date) -> String {
    targetRuntimeDateFormatter.string(from: date)
}

private func monthDate(_ date: Date) -> String {
    var components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
    components.day = 1
    return targetRuntimeDateFormatter.string(from: Calendar(identifier: .gregorian).date(from: components) ?? date)
}

private let targetRuntimeDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

#if os(macOS)
private typealias TargetRuntimePlatformImage = NSImage
private struct TargetRuntimePlatformImageView: View {
    let image: NSImage
    var body: some View { Image(nsImage: image).resizable() }
}
#elseif canImport(UIKit)
private typealias TargetRuntimePlatformImage = UIImage
private struct TargetRuntimePlatformImageView: View {
    let image: UIImage
    var body: some View { Image(uiImage: image).resizable() }
}
#endif

private extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let normalized = trimmed.count == 3
            ? trimmed.map { "\($0)\($0)" }.joined()
            : trimmed
        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        #if os(macOS)
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((components.redComponent * 255).rounded()),
            Int((components.greenComponent * 255).rounded()),
            Int((components.blueComponent * 255).rounded())
        )
        #elseif canImport(UIKit)
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        #else
        return nil
        #endif
    }
}

#endif
