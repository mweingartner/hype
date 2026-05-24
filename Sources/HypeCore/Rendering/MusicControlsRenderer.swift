import Foundation
#if canImport(AppKit)
import AppKit

public enum MusicControlsRenderer {
    public static func draw(_ kind: PartType, ctx: CGContext, part: Part, rect: CGRect, theme: HypeTheme? = nil) {
        ctx.saveGState()

        let radius: CGFloat = 10
        let bg = theme?.fieldBackground.nsColor ?? NSColor.controlBackgroundColor
        ctx.setFillColor(bg.cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor((NSColor(hexString: part.strokeColor) ?? NSColor.separatorColor).cgColor)
        ctx.setLineWidth(max(1, part.strokeWidth))
        ctx.addPath(path)
        ctx.strokePath()

        switch kind {
        case .pianoKeyboard:
            drawKeyboard(ctx: ctx, rect: rect)
        case .stepSequencer:
            drawStepGrid(ctx: ctx, rect: rect)
        case .musicMixer:
            drawMixer(ctx: ctx, rect: rect)
        default:
            drawPlayer(ctx: ctx, part: part, rect: rect)
        }

        drawTitle(kind, ctx: ctx, part: part, rect: rect)
        ctx.restoreGState()
    }

    private static func drawTitle(_ kind: PartType, ctx: CGContext, part: Part, rect: CGRect) {
        let title: String
        switch kind {
        case .pianoKeyboard: title = "Piano Keyboard"
        case .stepSequencer: title = "Step Sequencer"
        case .musicMixer: title = "Music Mixer"
        default: title = "Music Player"
        }
        let pattern = part.musicPatternName.isEmpty ? "No pattern" : part.musicPatternName
        let subtitle = "\(pattern)  \(part.musicInstrumentName)  \(Int(part.musicTempo.rounded())) BPM"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (title as NSString).draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 8), withAttributes: titleAttrs)
        (subtitle as NSString).draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 25), withAttributes: subAttrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawPlayer(ctx: CGContext, part: Part, rect: CGRect) {
        let y = rect.midY + 8
        let playRect = CGRect(x: rect.minX + 14, y: y, width: 26, height: 26)
        ctx.setFillColor(NSColor.controlAccentColor.cgColor)
        ctx.fillEllipse(in: playRect)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.move(to: CGPoint(x: playRect.minX + 10, y: playRect.minY + 7))
        ctx.addLine(to: CGPoint(x: playRect.minX + 10, y: playRect.maxY - 7))
        ctx.addLine(to: CGPoint(x: playRect.maxX - 7, y: playRect.midY))
        ctx.closePath()
        ctx.fillPath()

        let barRect = CGRect(x: playRect.maxX + 14, y: y + 11, width: max(24, rect.width - 86), height: 5)
        ctx.setFillColor(NSColor.separatorColor.cgColor)
        ctx.fill(CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width, height: barRect.height))
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(part.musicVolume).cgColor)
        ctx.fill(CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width * CGFloat(part.musicVolume), height: barRect.height))
    }

    private static func drawKeyboard(ctx: CGContext, rect: CGRect) {
        let keyboardRect = MusicControlInteraction.keyboardRect(in: rect)
        guard keyboardRect.width > 20, keyboardRect.height > 18 else { return }
        let whiteKeys = 14
        let keyWidth = keyboardRect.width / CGFloat(whiteKeys)
        for index in 0..<whiteKeys {
            let key = CGRect(x: keyboardRect.minX + CGFloat(index) * keyWidth, y: keyboardRect.minY, width: keyWidth, height: keyboardRect.height)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(key)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.stroke(key)
        }
        let blackOffsets: Set<Int> = [0, 1, 3, 4, 5, 7, 8, 10, 11, 12]
        for index in blackOffsets {
            let key = CGRect(
                x: keyboardRect.minX + CGFloat(index + 1) * keyWidth - keyWidth * 0.28,
                y: keyboardRect.minY,
                width: keyWidth * 0.56,
                height: keyboardRect.height * 0.62
            )
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(key)
        }
    }

    private static func drawStepGrid(ctx: CGContext, rect: CGRect) {
        let grid = MusicControlInteraction.stepSequencerGridRect(in: rect)
        guard grid.width > 20, grid.height > 18 else { return }
        let columns = MusicControlInteraction.stepSequencerColumnCount
        let rows = MusicControlInteraction.stepSequencerRowCount
        let cellW = grid.width / CGFloat(columns)
        let cellH = grid.height / CGFloat(rows)
        for row in 0..<rows {
            for col in 0..<columns {
                let cell = CGRect(
                    x: grid.minX + CGFloat(col) * cellW + 2,
                    y: grid.minY + CGFloat(row) * cellH + 2,
                    width: max(1, cellW - 4),
                    height: max(1, cellH - 4)
                )
                let active = (row + col) % 5 == 0
                ctx.setFillColor((active ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).cgColor)
                ctx.addPath(CGPath(roundedRect: cell, cornerWidth: 3, cornerHeight: 3, transform: nil))
                ctx.fillPath()
            }
        }
    }

    private static func drawMixer(ctx: CGContext, rect: CGRect) {
        let mixer = rect.insetBy(dx: 16, dy: 42)
        guard mixer.width > 20, mixer.height > 18 else { return }
        let strips = 4
        let stripW = mixer.width / CGFloat(strips)
        for index in 0..<strips {
            let x = mixer.minX + CGFloat(index) * stripW + stripW / 2
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(4)
            ctx.move(to: CGPoint(x: x, y: mixer.minY + 6))
            ctx.addLine(to: CGPoint(x: x, y: mixer.maxY - 6))
            ctx.strokePath()
            let knobY = mixer.maxY - CGFloat(index + 1) * mixer.height / CGFloat(strips + 1)
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 7, y: knobY - 7, width: 14, height: 14))
        }
    }
}
#endif
