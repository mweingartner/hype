import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for audio-recorder parts. Shows a mic icon
/// + duration + recording-state indicator. The live host view does
/// the same thing visually, so the placeholder closely matches what
/// the user will see in browse mode.
public enum AudioRecorderRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Background.
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Mic icon — stylized capsule + base.
        let isRecording = part.audioRecording
        let iconColor: NSColor = isRecording ? .systemRed : .secondaryLabelColor
        let micCenterX = rect.minX + 22
        let micCenterY = rect.midY
        let capsuleRect = CGRect(x: micCenterX - 6, y: micCenterY - 12, width: 12, height: 18)
        let capsulePath = CGPath(roundedRect: capsuleRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setFillColor(iconColor.cgColor)
        ctx.addPath(capsulePath)
        ctx.fillPath()
        // Stand.
        ctx.setStrokeColor(iconColor.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: micCenterX - 8, y: micCenterY + 8))
        ctx.addLine(to: CGPoint(x: micCenterX + 8, y: micCenterY + 8))
        ctx.move(to: CGPoint(x: micCenterX, y: micCenterY + 8))
        ctx.addLine(to: CGPoint(x: micCenterX, y: micCenterY + 14))
        ctx.strokePath()

        // Recording dot blinks (rendered solid for the placeholder).
        if isRecording {
            ctx.setFillColor(NSColor.systemRed.cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.maxX - 18, y: rect.minY + 6, width: 8, height: 8))
        }

        // Duration text right of the mic.
        let durationText = formatDuration(part.audioDuration)
        let durationRect = CGRect(
            x: micCenterX + 16,
            y: rect.midY - 8,
            width: rect.width - (micCenterX + 16) - 24,
            height: 16
        )
        let durFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: durFont, .foregroundColor: NSColor.labelColor]
        (durationText as NSString).draw(at: CGPoint(x: durationRect.minX, y: durationRect.midY - 8), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mm = total / 60
        let ss = total % 60
        return String(format: "%02d:%02d", mm, ss)
    }
}
#endif
