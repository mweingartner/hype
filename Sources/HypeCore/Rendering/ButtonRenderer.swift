import Foundation
#if canImport(AppKit)
import AppKit

/// Renders button parts using Core Graphics.
public enum ButtonRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        let fillColor = part.hilite ? NSColor.controlAccentColor.cgColor : NSColor.white.cgColor
        let textColor = part.hilite ? NSColor.white.cgColor : (part.enabled ? NSColor.black.cgColor : NSColor.gray.cgColor)

        switch part.buttonStyle {
        case .transparent:
            break // No background

        case .opaque:
            ctx.setFillColor(fillColor)
            ctx.fill(rect)

        case .rectangle, .standard:
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect)

        case .roundRect:
            let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(fillColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()

        case .shadow:
            let shadowRect = rect.offsetBy(dx: 2, dy: -2)
            ctx.setFillColor(NSColor.shadowColor.withAlphaComponent(0.3).cgColor)
            ctx.fill(shadowRect)
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.stroke(rect)

        case .checkBox:
            let boxSize: CGFloat = 16
            let boxY = rect.midY - boxSize / 2
            let boxRect = CGRect(x: rect.minX + 4, y: boxY, width: boxSize, height: boxSize)
            let boxPath = CGPath(roundedRect: boxRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(boxPath)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.addPath(boxPath)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            if part.hilite {
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: boxRect.minX + 3, y: boxRect.midY))
                ctx.addLine(to: CGPoint(x: boxRect.midX - 1, y: boxRect.minY + 3))
                ctx.addLine(to: CGPoint(x: boxRect.maxX - 3, y: boxRect.maxY - 3))
                ctx.strokePath()
            }
            // Label
            drawLabel(ctx: ctx, text: part.showName ? part.name : part.textContent,
                     at: CGPoint(x: rect.minX + boxSize + 8, y: rect.midY),
                     font: part.textFont, size: part.textSize, color: textColor, align: .left)
            ctx.restoreGState()
            return

        case .radioButton:
            let radius: CGFloat = 8
            let cx = rect.minX + radius + 4
            let cy = rect.midY
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.strokePath()
            if part.hilite {
                ctx.addArc(center: CGPoint(x: cx, y: cy), radius: 4, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.setFillColor(NSColor.controlAccentColor.cgColor)
                ctx.fillPath()
            }
            drawLabel(ctx: ctx, text: part.showName ? part.name : part.textContent,
                     at: CGPoint(x: cx + radius + 6, y: cy),
                     font: part.textFont, size: part.textSize, color: textColor, align: .left)
            ctx.restoreGState()
            return

        case .default:
            let outerPath = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
            ctx.addPath(outerPath)
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            ctx.fillPath()
            let label = part.showName ? part.name : part.textContent
            drawLabel(ctx: ctx, text: label, at: CGPoint(x: rect.midX, y: rect.midY),
                     font: part.textFont, size: part.textSize, color: NSColor.white.cgColor, align: .center)
            ctx.restoreGState()
            return

        case .popup:
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.stroke(rect)
            // Draw dropdown arrow
            let arrowX = rect.maxX - 20
            ctx.move(to: CGPoint(x: arrowX, y: rect.midY + 3))
            ctx.addLine(to: CGPoint(x: arrowX + 6, y: rect.midY - 3))
            ctx.addLine(to: CGPoint(x: arrowX + 12, y: rect.midY + 3))
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokePath()
            // Show first line of textContent as selected item, or the part name
            let popupLabel: String
            let lines = part.textContent.split(separator: "\n", omittingEmptySubsequences: false)
            if let firstLine = lines.first, !firstLine.isEmpty {
                popupLabel = String(firstLine)
            } else {
                popupLabel = part.showName ? part.name : ""
            }
            if !popupLabel.isEmpty {
                drawLabel(ctx: ctx, text: popupLabel, at: CGPoint(x: rect.minX + 8, y: rect.midY),
                         font: part.textFont, size: part.textSize, color: textColor, align: .left)
            }
            ctx.restoreGState()
            return

        case .oval:
            ctx.addEllipse(in: rect)
            ctx.setFillColor(fillColor)
            ctx.fillPath()
            ctx.addEllipse(in: rect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.strokePath()

        case .toggle:
            // macOS-style toggle switch
            let trackWidth: CGFloat = 44
            let trackHeight: CGFloat = 24
            let trackX = rect.minX + 4
            let trackY = rect.midY - trackHeight / 2
            let trackRect = CGRect(x: trackX, y: trackY, width: trackWidth, height: trackHeight)
            let trackPath = CGPath(roundedRect: trackRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)

            ctx.addPath(trackPath)
            ctx.setFillColor(part.hilite ? NSColor.controlAccentColor.cgColor : NSColor.systemGray.withAlphaComponent(0.3).cgColor)
            ctx.fillPath()

            // Knob
            let knobSize = trackHeight - 4
            let knobX = part.hilite ? trackX + trackWidth - knobSize - 2 : trackX + 2
            let knobY = trackY + 2
            ctx.addEllipse(in: CGRect(x: knobX, y: knobY, width: knobSize, height: knobSize))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.addEllipse(in: CGRect(x: knobX, y: knobY, width: knobSize, height: knobSize))
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokePath()

            // Label after toggle
            let label = part.showName ? part.name : part.textContent
            if !label.isEmpty {
                drawLabel(ctx: ctx, text: label, at: CGPoint(x: trackX + trackWidth + 8, y: rect.midY),
                         font: part.textFont, size: part.textSize, color: textColor, align: .left)
            }
            ctx.restoreGState()
            return
        }

        // Draw centered label
        let label = part.showName ? part.name : part.textContent
        if !label.isEmpty {
            let align: LabelAlignment = part.textAlign == .left ? .left : part.textAlign == .right ? .right : .center
            drawLabel(ctx: ctx, text: label, at: CGPoint(x: rect.midX, y: rect.midY),
                     font: part.textFont, size: part.textSize, color: textColor, align: align)
        }

        ctx.restoreGState()
    }

    enum LabelAlignment { case left, center, right }

    static func drawLabel(ctx: CGContext, text: String, at point: CGPoint, font: String, size: Double, color: CGColor, align: LabelAlignment) {
        let nsFont = NSFont(name: font, size: CGFloat(size)) ?? NSFont.systemFont(ofSize: CGFloat(size))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: NSColor(cgColor: color) ?? NSColor.black,
        ]
        let nsText = text as NSString
        let textSize = nsText.size(withAttributes: attrs)

        let x: CGFloat
        switch align {
        case .left: x = point.x
        case .center: x = point.x - textSize.width / 2
        case .right: x = point.x - textSize.width
        }
        let y = point.y - textSize.height / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        nsText.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif
