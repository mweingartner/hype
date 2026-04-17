import Foundation
#if canImport(AppKit)
import AppKit

/// Renders button parts using Core Graphics.
public enum ButtonRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        let fillColor = part.hilite ? NSColor.controlAccentColor.cgColor : NSColor.white.cgColor
        // For checkboxes, radio buttons, and toggles, the label color stays black
        // because hilite only affects the indicator (check/dot/switch), not the label background
        let textColor: CGColor
        switch part.buttonStyle {
        case .checkBox, .toggle:
            textColor = part.enabled ? NSColor.black.cgColor : NSColor.gray.cgColor
        default:
            textColor = part.hilite ? NSColor.white.cgColor : (part.enabled ? NSColor.black.cgColor : NSColor.gray.cgColor)
        }

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
            // Shadow sits to the top-right in the resting state and
            // snaps to the bottom-left while the button is pressed
            // (hilite == true). The flipped (top-left-origin) CGContext
            // means negative dy is "up" and positive dy is "down".
            // The fill rect itself also shifts so the pressed button
            // visually depresses into its own shadow.
            let shadowOffset: CGFloat = 2
            let shadowDx: CGFloat = part.hilite ? -shadowOffset : shadowOffset
            let shadowDy: CGFloat = part.hilite ? shadowOffset : -shadowOffset
            let faceDx: CGFloat = part.hilite ? shadowOffset : 0
            let faceDy: CGFloat = part.hilite ? -shadowOffset : 0
            let shadowRect = rect.offsetBy(dx: shadowDx, dy: shadowDy)
            let faceRect = rect.offsetBy(dx: faceDx, dy: faceDy)
            ctx.setFillColor(NSColor.shadowColor.withAlphaComponent(0.3).cgColor)
            ctx.fill(shadowRect)
            ctx.setFillColor(fillColor)
            ctx.fill(faceRect)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.stroke(faceRect)
            // Label follows the face so the button visually "presses
            // into" its shadow. Shared fall-through label would use
            // the original rect and appear to float off the face.
            let label = part.showName ? part.name : part.textContent
            if !label.isEmpty {
                let align: LabelAlignment = part.textAlign == .left ? .left :
                    part.textAlign == .right ? .right : .center
                drawLabel(
                    ctx: ctx,
                    text: label,
                    at: CGPoint(x: faceRect.midX, y: faceRect.midY),
                    font: part.textFont,
                    size: part.textSize,
                    color: textColor,
                    align: align
                )
            }
            ctx.restoreGState()
            return

        case .checkBox:
            // Always draw a clearly visible rectangle where the check
            // belongs — even in the unchecked state — so users can
            // see exactly where the click target is and what the
            // checkbox style looks like at rest. The box is a 16x16
            // square with a 1px black stroke and a white fill.
            let boxSize: CGFloat = 16
            let boxY = rect.midY - boxSize / 2
            let boxRect = CGRect(x: rect.minX + 4, y: boxY, width: boxSize, height: boxSize)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(boxRect)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(boxRect)
            // When checked (hilite), draw a checkmark V-shape inside
            // the box. The outer rectangle remains visible; the check
            // sits on top of it.
            if part.hilite {
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: boxRect.minX + 3, y: boxRect.midY))
                ctx.addLine(to: CGPoint(x: boxRect.midX - 1, y: boxRect.maxY - 3))
                ctx.addLine(to: CGPoint(x: boxRect.maxX - 3, y: boxRect.minY + 3))
                ctx.strokePath()
            }
            // Label
            drawLabel(ctx: ctx, text: part.showName ? part.name : part.textContent,
                     at: CGPoint(x: rect.minX + boxSize + 8, y: rect.midY),
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
            // macOS-style popup button with rounded corners
            let popupPath = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(popupPath)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.addPath(popupPath)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            // Draw unfilled dropdown chevron arrows (up/down)
            let arrowX = rect.maxX - 18
            let arrowCY = rect.midY
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            // Up chevron
            ctx.move(to: CGPoint(x: arrowX, y: arrowCY - 2))
            ctx.addLine(to: CGPoint(x: arrowX + 4, y: arrowCY - 6))
            ctx.addLine(to: CGPoint(x: arrowX + 8, y: arrowCY - 2))
            ctx.strokePath()
            // Down chevron
            ctx.move(to: CGPoint(x: arrowX, y: arrowCY + 2))
            ctx.addLine(to: CGPoint(x: arrowX + 4, y: arrowCY + 6))
            ctx.addLine(to: CGPoint(x: arrowX + 8, y: arrowCY + 2))
            ctx.strokePath()
            // Show selected item (textContent) or first popup item, or name
            let popupLabel: String
            if !part.textContent.isEmpty {
                popupLabel = part.textContent
            } else {
                let items = part.popupItems.split(separator: "\n", omittingEmptySubsequences: true)
                if let first = items.first {
                    popupLabel = String(first)
                } else {
                    popupLabel = part.showName ? part.name : "Select..."
                }
            }
            drawLabel(ctx: ctx, text: popupLabel, at: CGPoint(x: rect.minX + 8, y: rect.midY),
                     font: part.textFont, size: part.textSize, color: textColor, align: .left)
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
