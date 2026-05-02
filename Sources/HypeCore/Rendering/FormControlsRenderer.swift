import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderers for the four small form-control parts:
/// stepper, slider, toggle, segmented. Each is a faithful enough
/// preview that a user looking at a card in edit mode (or in an AI
/// vision capture) can identify the control by sight.
public enum FormControlsRenderer {

    public static func draw(_ kind: PartType, ctx: CGContext, part: Part, rect: CGRect) {
        switch kind {
        case .stepper:    drawStepper(ctx: ctx, part: part, rect: rect)
        case .slider:     drawSlider(ctx: ctx, part: part, rect: rect)
        case .toggle:     drawToggle(ctx: ctx, part: part, rect: rect)
        case .segmented:  drawSegmented(ctx: ctx, part: part, rect: rect)
        default: break
        }
    }

    // MARK: - Stepper

    private static func drawStepper(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()
        // Half: value display on the left, +/- stack on the right.
        let stepperWidth: CGFloat = 28
        let valueRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(0, rect.width - stepperWidth),
            height: rect.height
        )
        let stepperRect = CGRect(
            x: valueRect.maxX,
            y: rect.minY,
            width: stepperWidth,
            height: rect.height
        )

        // Value cell.
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(valueRect)
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(valueRect)
        drawCentered(
            text: formatNumber(part.controlValue),
            in: valueRect,
            font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            color: NSColor.labelColor,
            ctx: ctx
        )

        // Stepper cell — split into top "+", bottom "−".
        ctx.setFillColor(NSColor.controlColor.cgColor)
        ctx.fill(stepperRect)
        ctx.stroke(stepperRect)
        let topCell = CGRect(x: stepperRect.minX, y: stepperRect.minY, width: stepperRect.width, height: stepperRect.height / 2)
        let bottomCell = CGRect(x: stepperRect.minX, y: stepperRect.midY, width: stepperRect.width, height: stepperRect.height / 2)
        ctx.move(to: CGPoint(x: stepperRect.minX, y: stepperRect.midY))
        ctx.addLine(to: CGPoint(x: stepperRect.maxX, y: stepperRect.midY))
        ctx.strokePath()
        drawCentered(text: "▲", in: topCell, font: NSFont.systemFont(ofSize: 9), color: NSColor.labelColor, ctx: ctx)
        drawCentered(text: "▼", in: bottomCell, font: NSFont.systemFont(ofSize: 9), color: NSColor.labelColor, ctx: ctx)
        ctx.restoreGState()
    }

    // MARK: - Slider

    private static func drawSlider(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()
        // Track centerline.
        let trackHeight: CGFloat = 4
        let trackRect = CGRect(
            x: rect.minX + 6,
            y: rect.midY - trackHeight / 2,
            width: rect.width - 12,
            height: trackHeight
        )
        ctx.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        ctx.fill(trackRect)

        // Knob position interpolated from controlValue.
        let range = max(0.0001, part.controlMax - part.controlMin)
        let pct = max(0, min(1, (part.controlValue - part.controlMin) / range))
        let knobX = trackRect.minX + trackRect.width * CGFloat(pct)
        let knobRect = CGRect(x: knobX - 8, y: rect.midY - 8, width: 16, height: 16)
        ctx.setFillColor(NSColor.controlAccentColor.cgColor)
        ctx.fillEllipse(in: knobRect)
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: knobRect)
        ctx.restoreGState()
    }

    // MARK: - Toggle

    private static func drawToggle(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()
        let isOn = part.controlValue >= 0.5
        // Pill background — green when on, gray when off.
        let pillHeight = min(rect.height, 22)
        let pillWidth = max(36, min(rect.width, 44))
        let pillRect = CGRect(
            x: rect.midX - pillWidth / 2,
            y: rect.midY - pillHeight / 2,
            width: pillWidth,
            height: pillHeight
        )
        let path = CGPath(roundedRect: pillRect, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor((isOn ? NSColor.systemGreen : NSColor.tertiaryLabelColor).cgColor)
        ctx.fillPath()

        // Knob.
        let knobDiameter = pillHeight - 4
        let knobX = isOn ? pillRect.maxX - knobDiameter - 2 : pillRect.minX + 2
        let knobRect = CGRect(x: knobX, y: pillRect.minY + 2, width: knobDiameter, height: knobDiameter)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: knobRect)
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: knobRect)
        ctx.restoreGState()
    }

    // MARK: - Segmented

    private static func drawSegmented(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()
        let items = part.segmentItems.split(separator: "|").map(String.init)
        guard !items.isEmpty else {
            ctx.restoreGState()
            return
        }
        let segWidth = rect.width / CGFloat(items.count)
        let selectedIdx = Int(part.controlValue)
        for (i, label) in items.enumerated() {
            let segRect = CGRect(x: rect.minX + segWidth * CGFloat(i), y: rect.minY, width: segWidth, height: rect.height)
            let isSel = i == selectedIdx
            ctx.setFillColor((isSel ? NSColor.controlAccentColor : NSColor.controlColor).cgColor)
            ctx.fill(segRect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(segRect)
            drawCentered(
                text: label,
                in: segRect,
                font: NSFont.systemFont(ofSize: 11),
                color: isSel ? NSColor.white : NSColor.labelColor,
                ctx: ctx
            )
        }
        ctx.restoreGState()
    }

    // MARK: - Helpers

    private static func drawCentered(text: String, in rect: CGRect, font: NSFont, color: NSColor, ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func formatNumber(_ d: Double) -> String {
        if d.rounded() == d { return String(Int(d)) }
        return String(format: "%.2f", d)
    }
}
#endif
