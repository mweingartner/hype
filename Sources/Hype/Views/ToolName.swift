import Foundation

public enum ToolName: String, CaseIterable, Sendable {
    case browse, button, field, shape, webpage, image, video, chart, spriteArea
    case calendar, pdf, map, colorWell
    case stepper, slider, toggle, segmented, audioRecorder, scene3D, select
    case pencil, line, rect, oval, spray, bucket, eraser, text

    var systemImageName: String {
        switch self {
        case .browse: return "hand.point.up"
        case .button: return "rectangle"
        case .field: return "text.alignleft"
        case .shape: return "diamond"
        case .webpage: return "globe"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .chart: return "chart.bar"
        case .spriteArea: return "gamecontroller"
        case .calendar: return "calendar"
        case .pdf: return "doc.richtext"
        case .map: return "map"
        case .colorWell: return "paintpalette"
        case .stepper: return "plus.slash.minus"
        case .slider: return "slider.horizontal.3"
        case .toggle: return "switch.2"
        case .segmented: return "rectangle.split.3x1"
        case .audioRecorder: return "mic.circle"
        case .scene3D: return "cube.transparent"
        case .select: return "cursor.rays"
        case .pencil: return "pencil"
        case .line: return "line.diagonal"
        case .rect: return "rectangle.portrait"
        case .oval: return "circle"
        case .spray: return "aqi.medium"
        case .bucket: return "drop"
        case .eraser: return "eraser"
        case .text: return "textformat"
        }
    }
}
