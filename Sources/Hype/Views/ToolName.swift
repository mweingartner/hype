import Foundation

public enum ToolName: String, CaseIterable, Sendable {
    case browse, button, field, shape, webpage, image, video, chart, spriteArea, select
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
