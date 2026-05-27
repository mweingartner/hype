import Foundation
#if canImport(AppKit)
import AppKit

public struct MusicControlRenderOptions: Sendable {
    public static let `default` = MusicControlRenderOptions()

    public var liveInstrumentPopupPartIds: Set<UUID>
    public var activeKeyboardNotesByPartId: [UUID: String]

    public init(
        liveInstrumentPopupPartIds: Set<UUID> = [],
        activeKeyboardNotesByPartId: [UUID: String] = [:]
    ) {
        self.liveInstrumentPopupPartIds = liveInstrumentPopupPartIds
        self.activeKeyboardNotesByPartId = activeKeyboardNotesByPartId
    }
}

public enum MusicControlsRenderer {
    public static func draw(
        _ kind: PartType,
        ctx: CGContext,
        part: Part,
        rect: CGRect,
        theme: HypeTheme? = nil,
        options: MusicControlRenderOptions = .default
    ) {
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
            drawKeyboard(ctx: ctx, part: part, activeNote: options.activeKeyboardNotesByPartId[part.id])
        case .stepSequencer:
            drawStepGrid(ctx: ctx, part: part, rect: rect)
        case .musicMixer:
            drawMixer(ctx: ctx, rect: rect)
        case .appleMusicBrowser:
            drawBrowser(ctx: ctx, part: part, rect: rect)
        case .musicQueue:
            drawQueue(ctx: ctx, part: part, rect: rect)
        default:
            drawPlayer(ctx: ctx, part: part, rect: rect)
        }

        drawTitle(kind, ctx: ctx, part: part, rect: rect, options: options)
        ctx.restoreGState()
    }

    private static func drawTitle(
        _ kind: PartType,
        ctx: CGContext,
        part: Part,
        rect: CGRect,
        options: MusicControlRenderOptions
    ) {
        if kind == .pianoKeyboard || kind == .stepSequencer {
            drawOptionalMusicControlChrome(kind, ctx: ctx, part: part, rect: rect, options: options)
            return
        }

        let title: String
        switch kind {
        case .stepSequencer: title = "Step Sequencer"
        case .musicMixer: title = "Music Mixer"
        case .appleMusicBrowser: title = "MusicKit Search"
        case .musicQueue: title = "Music Queue"
        default: title = "Music Player"
        }
        let subtitle: String
        if kind == .appleMusicBrowser {
            let query = part.musicSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = part.musicSourceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppleMusicItemKind.song.rawValue
                : part.musicSourceType
            subtitle = "\(part.musicSearchScope) \(type)" + (query.isEmpty ? "" : "  \"\(query)\"")
        } else if kind == .musicQueue {
            subtitle = part.musicQueueData.isEmpty ? "Legacy queue" : part.musicQueueData
        } else {
            let pattern = part.musicPatternName.isEmpty ? "No pattern" : part.musicPatternName
            subtitle = "\(pattern)  \(part.musicInstrumentName)  \(MusicTempo.clamp(part.musicTempo)) BPM"
        }
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

    private static func drawOptionalMusicControlChrome(
        _ kind: PartType,
        ctx: CGContext,
        part: Part,
        rect: CGRect,
        options: MusicControlRenderOptions
    ) {
        guard MusicControlInteraction.musicControlShowsMetadata(part) else { return }

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
        if part.musicShowControlType {
            (optionalChromeTitle(for: kind) as NSString).draw(
                at: CGPoint(x: rect.minX + 12, y: rect.minY + 8),
                withAttributes: titleAttrs
            )
        }

        let details = optionalChromeDetailStrings(for: part)
        if !details.isEmpty {
            let y = part.musicShowControlType ? rect.minY + 25 : rect.minY + 8
            (details.joined(separator: "  ") as NSString).draw(
                at: CGPoint(x: rect.minX + 12, y: y),
                withAttributes: subAttrs
            )
        }

        if part.musicShowInstrument && !options.liveInstrumentPopupPartIds.contains(part.id) {
            drawInstrumentPopupPlaceholder(part: part, attrs: subAttrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func optionalChromeTitle(for kind: PartType) -> String {
        switch kind {
        case .stepSequencer: "Step Sequencer"
        default: "Piano Keyboard"
        }
    }

    private static func optionalChromeDetailStrings(for part: Part) -> [String] {
        var strings: [String] = []
        if part.musicShowPattern {
            strings.append(part.musicPatternName.isEmpty ? "No pattern" : part.musicPatternName)
        }
        if part.musicShowTempo {
            strings.append("\(MusicTempo.clamp(part.musicTempo)) BPM")
        }
        return strings
    }

    private static func drawInstrumentPopupPlaceholder(part: Part, attrs: [NSAttributedString.Key: Any]) {
        let popup = MusicControlInteraction.musicInstrumentPopupRect(for: part)
        guard !popup.isEmpty else { return }
        let path = NSBezierPath(roundedRect: popup, xRadius: 5, yRadius: 5)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let instrument = MusicInstrumentCatalog.resolve(part.musicInstrumentName).name
        let textRect = popup.insetBy(dx: 8, dy: 5)
        (instrument as NSString).draw(in: textRect, withAttributes: attrs)
        let chevron = "v" as NSString
        chevron.draw(
            at: CGPoint(x: popup.maxX - 16, y: popup.minY + 5),
            withAttributes: attrs
        )
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

    private static func drawKeyboard(ctx: CGContext, part: Part, activeNote: String?) {
        let keyboardRect = MusicControlInteraction.keyboardRect(for: part)
        guard keyboardRect.width > 20, keyboardRect.height > 18 else { return }

        let layout = MusicControlInteraction.keyboardLayout(for: part)
        let whiteStroke = NSColor(calibratedWhite: 0.62, alpha: 1)
        let whiteFill = NSColor(calibratedWhite: 0.985, alpha: 1)
        let whitePressed = NSColor.controlAccentColor.withAlphaComponent(0.22)
        let blackFill = NSColor(calibratedWhite: 0.055, alpha: 1)
        let blackTop = NSColor(calibratedWhite: 0.24, alpha: 1)
        let active = activeNote?.lowercased()

        for key in layout.whiteKeys {
            let isActive = key.note.lowercased() == active
            let rect = key.frame.insetBy(dx: 0.35, dy: 0.35)
            if isActive {
                drawKeyGlow(ctx: ctx, rect: rect, color: NSColor.controlAccentColor.withAlphaComponent(0.36))
            }
            let path = CGPath(roundedRect: rect, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor((isActive ? whitePressed.blended(withFraction: 0.72, of: whiteFill) ?? whitePressed : whiteFill).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor((isActive ? NSColor.controlAccentColor : whiteStroke).cgColor)
            ctx.setLineWidth(isActive ? 1.25 : 0.8)
            ctx.strokePath()

            let shine = CGRect(x: rect.minX + 1, y: rect.minY + 2, width: max(1, rect.width - 2), height: max(1, rect.height * 0.18))
            ctx.setFillColor(NSColor.white.withAlphaComponent(isActive ? 0.46 : 0.34).cgColor)
            ctx.fill(shine)
        }

        for key in layout.blackKeys {
            let isActive = key.note.lowercased() == active
            let rect = key.frame.insetBy(dx: 0.3, dy: 0.2)
            if isActive {
                drawKeyGlow(ctx: ctx, rect: rect, color: NSColor.controlAccentColor.withAlphaComponent(0.48))
            }
            let path = CGPath(roundedRect: rect, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor((isActive ? NSColor.controlAccentColor.blended(withFraction: 0.56, of: blackFill) ?? NSColor.controlAccentColor : blackFill).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor((isActive ? NSColor.controlAccentColor : NSColor.black).cgColor)
            ctx.setLineWidth(isActive ? 1.15 : 0.8)
            ctx.strokePath()

            let top = CGRect(x: rect.minX + 1, y: rect.minY + 1, width: max(1, rect.width - 2), height: max(1, rect.height * 0.16))
            ctx.setFillColor((isActive ? NSColor.white.withAlphaComponent(0.28) : blackTop).cgColor)
            ctx.fill(top)
        }
    }

    private static func drawKeyGlow(ctx: CGContext, rect: CGRect, color: NSColor) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 7, color: color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawStepGrid(ctx: CGContext, part: Part, rect: CGRect) {
        let grid = MusicControlInteraction.stepSequencerGridRect(for: part)
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

    private static func drawBrowser(ctx: CGContext, part: Part, rect: CGRect) {
        let search = rect.insetBy(dx: 16, dy: 48)
        let field = CGRect(x: search.minX, y: search.minY, width: search.width, height: 28)
        ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
        ctx.addPath(CGPath(roundedRect: field, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.stroke(field)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let query = part.musicSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = query.isEmpty ? "Search Apple Music..." : query
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: query.isEmpty ? NSColor.placeholderTextColor : NSColor.labelColor,
        ]
        (text as NSString).draw(at: CGPoint(x: field.minX + 8, y: field.minY + 7), withAttributes: attrs)
        let chips = "\(part.musicSearchScope)  \(part.musicSourceType)"
        (chips as NSString).draw(
            at: CGPoint(x: search.minX, y: field.maxY + 14),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        if !part.musicSourceID.isEmpty {
            let title = part.musicSourceTitle.isEmpty ? part.musicSourceID : part.musicSourceTitle
            let artist = part.musicSourceArtist.isEmpty ? "" : " - \(part.musicSourceArtist)"
            ("Selected: \(title)\(artist)" as NSString).draw(
                at: CGPoint(x: search.minX, y: field.maxY + 30),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            if part.musicDuration > 0 {
                let progressWidth = max(24, search.width)
                let progress = CGFloat(min(1, max(0, part.musicPosition / part.musicDuration)))
                let bar = CGRect(x: search.minX, y: field.maxY + 48, width: progressWidth, height: 4)
                ctx.setFillColor(NSColor.separatorColor.cgColor)
                ctx.fill(bar)
                ctx.setFillColor(NSColor.controlAccentColor.cgColor)
                ctx.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width * progress, height: bar.height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawQueue(ctx: CGContext, part: Part, rect: CGRect) {
        let queue = rect.insetBy(dx: 16, dy: 48)
        let rows = 4
        for index in 0..<rows {
            let y = queue.minY + CGFloat(index) * 26
            ctx.setFillColor((index == 0 ? NSColor.controlAccentColor.withAlphaComponent(0.45) : NSColor.quaternaryLabelColor).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: queue.minX, y: y, width: queue.width, height: 20), cornerWidth: 5, cornerHeight: 5, transform: nil))
            ctx.fillPath()
        }
    }
}
#endif
