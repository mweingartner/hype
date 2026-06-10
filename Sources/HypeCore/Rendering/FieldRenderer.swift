import Foundation
#if canImport(AppKit)
import AppKit

/// Renders field parts using Core Graphics.
public enum FieldRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect, theme: HypeTheme? = nil) {
        ctx.saveGState()
        // When the active theme opts into Liquid Glass, replace the
        // flat fill+stroke pair with a translucent glass pill in
        // the .rectangle / .scrolling / .secure / .opaque branches.
        // .transparent and .shadow keep their bespoke geometry.
        // .search is the search-pill which is already rounded —
        // glass alpha + sheen still applies cleanly.
        let useGlass = GlassRenderer.shouldUseGlass(for: theme)

        let palette = FieldTextLayout.palette(for: part, theme: theme)
        let fillColor = palette.fill.cgColor
        let strokeColor = palette.stroke.cgColor
        let strokeWidth = max(0, CGFloat(part.strokeWidth))

        func strokeFieldRect(_ targetRect: CGRect) {
            guard strokeWidth > 0 else { return }
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(strokeWidth)
            let inset = strokeWidth / 2
            ctx.stroke(targetRect.insetBy(dx: inset, dy: inset))
        }

        switch part.fieldStyle {
        case .transparent:
            break
        case .rectangle:
            // Filled background plus a 1px frame. The legacy
            // `.opaque` style was a duplicate of this case (same
            // bytes, same behavior); `.opaque` migrates to
            // `.rectangle` via `FieldStyle.resolved(rawOrAlias:)`.
            if useGlass, let t = theme {
                GlassRenderer.fillRoundedRect(
                    ctx: ctx, rect: rect,
                    fillHex: t.fieldBackground.rawDescription,
                    cornerRadius: CGFloat(t.cornerRadiusMedium),
                    strokeHex: t.fieldBorder.rawDescription,
                    strokeWidth: CGFloat(t.strokeWidthThin),
                    shadowOpacity: CGFloat(t.shadowOpacity) * 0.5,
                    shadowRadius: CGFloat(t.shadowRadius) * 0.5
                )
            } else {
                ctx.setFillColor(fillColor)
                ctx.fill(rect)
                strokeFieldRect(rect)
            }
        case .shadow:
            let shadowRect = rect.offsetBy(dx: 2, dy: -2)
            ctx.setFillColor(NSColor.shadowColor.withAlphaComponent(0.2).cgColor)
            ctx.fill(shadowRect)
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
        case .scrolling:
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
            // Scrollbar track
            let trackWidth = FieldTextLayout.scrollingTrailingInset
            let scrollRect = CGRect(x: rect.maxX - trackWidth, y: rect.minY, width: trackWidth, height: rect.height)
            ctx.setFillColor(palette.scrollbarTrack.cgColor)
            ctx.fill(scrollRect)
            strokeFieldRect(scrollRect)
        case .secure:
            // Secure fields look like rectangle fields but mask text as bullets.
            ctx.setFillColor(fillColor)
            ctx.fill(rect)
            strokeFieldRect(rect)
        case .search:
            // Pill-shaped field with a leading magnifying-glass icon.
            // Mirrors NSSearchField's macOS look so edit-mode and
            // run-mode are visually consistent.
            // Clamp radius to both half-height AND half-width so a very
            // narrow script-authored field (e.g. width 5) doesn't violate
            // CGPath's cornerWidth ≤ w/2 precondition.
            let radius = min(rect.width / 2, rect.height / 2, 12)
            // Route through RenderGeometry for the full NaN/negative guard.
            let pillPath = RenderGeometry.roundedRectPath(in: rect, cornerRadius: radius)
            ctx.addPath(pillPath)
            ctx.setFillColor(fillColor)
            ctx.fillPath()
            ctx.addPath(pillPath)
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            // Magnifying glass — circle + diagonal handle.
            let iconSize: CGFloat = 12
            let iconCenter = CGPoint(x: rect.minX + 8 + iconSize / 2,
                                     y: rect.midY)
            ctx.setStrokeColor(palette.searchIcon.cgColor)
            ctx.setLineWidth(1.4)
            let circleRadius = iconSize / 2 - 1
            ctx.strokeEllipse(in: CGRect(x: iconCenter.x - circleRadius,
                                         y: iconCenter.y - circleRadius,
                                         width: circleRadius * 2,
                                         height: circleRadius * 2))
            // Handle line (45° down-right from circle's edge)
            let handleStart = CGPoint(x: iconCenter.x + circleRadius * 0.7,
                                      y: iconCenter.y - circleRadius * 0.7)
            let handleEnd = CGPoint(x: iconCenter.x + circleRadius * 1.4,
                                    y: iconCenter.y - circleRadius * 1.4)
            ctx.move(to: handleStart)
            ctx.addLine(to: handleEnd)
            ctx.strokePath()
        }

        if part.visible && part.fieldStyle == .transparent {
            strokeFieldRect(rect)
        }

        // Draw text content
        if !part.textContent.isEmpty {
            let nsFont = NSFont(name: part.textFont, size: CGFloat(part.textSize)) ?? NSFont.systemFont(ofSize: CGFloat(part.textSize))
            let alignment: NSTextAlignment = part.textAlign == .center ? .center : part.textAlign == .right ? .right : .left
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            paragraphStyle.lineBreakMode = part.dontWrap ? .byClipping : .byWordWrapping

            // Apply textStyle traits (bold / italic) to the font and
            // emit underline / strikethrough as attributed-string
            // keys. `TextStyleFlags` parses every form HypeCard
            // accepts ("plain", "bold,italic", etc.) into a flat
            // bool struct.
            let flags = TextStyleFlags(string: part.textStyle)
            var styledFont = nsFont
            if flags.bold {
                styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .boldFontMask)
            }
            if flags.italic {
                styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .italicFontMask)
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: styledFont,
                .foregroundColor: palette.text,
                .paragraphStyle: paragraphStyle,
            ]
            if flags.underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if flags.strikethrough {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }

            // Secure fields render bullets instead of the raw text (security condition 2).
            let displayText: String
            if part.fieldStyle == .secure {
                displayText = String(repeating: "●", count: min(part.textContent.count, 50))
            } else {
                displayText = String(part.textContent.prefix(10_000))
            }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let attributedText = NSAttributedString(string: displayText, attributes: attrs)
            let drawRect = FieldTextLayout.verticallyCenteredTextRect(
                in: rect,
                wideMargins: part.wideMargins,
                fieldStyle: part.fieldStyle,
                attributedString: attributedText,
                fallbackFont: styledFont
            )
            attributedText.draw(in: drawRect)
            NSGraphicsContext.restoreGraphicsState()
        }

        ctx.restoreGState()
    }
}
#endif
