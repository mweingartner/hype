import Foundation
#if canImport(AppKit)
import AppKit

/// Renders button parts using Core Graphics.
public enum ButtonRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect, theme: HypeTheme? = nil) {
        ctx.saveGState()

        // When the theme opts into Liquid Glass, override the standard
        // / opaque / roundRect / oval branches to render through
        // `GlassRenderer.fillRoundedRect`. Specialized branches
        // (checkBox, radio, toggle, popup, link, shadow, default) keep
        // their bespoke geometry — those signatures are recognizable
        // shapes that reading as "glass" requires the same passes
        // applied IN ADDITION to the base draw, so we let the existing
        // code handle them and overlay the glass treatment via the
        // helper paths below where it makes sense.
        let useGlass = GlassRenderer.shouldUseGlass(for: theme)

        // Theme-derived palette. When a theme is supplied, every
        // accent / fill / border / foreground color comes from the
        // theme so the rendered button reflects the user's chosen
        // aesthetic (Sunset's orange, Neon's magenta, Liquid Glass's
        // system blue, etc.) rather than always-the-system-accent.
        // Without a theme, the previous system-color behavior
        // (`controlAccentColor`, `controlBackgroundColor`,
        // `labelColor`) is preserved so legacy callers and tests
        // see the same output as before.
        let accentNS:    NSColor = theme?.accent.nsColor          ?? NSColor.controlAccentColor
        let buttonBgNS:  NSColor = theme?.buttonBackground.nsColor ?? NSColor.controlBackgroundColor
        let buttonHiNS:  NSColor = theme?.buttonHilite.nsColor    ?? NSColor.controlAccentColor
        let buttonFgNS:  NSColor = theme?.buttonForeground.nsColor ?? NSColor.labelColor
        let cardBgNS:    NSColor = theme?.cardBackground.nsColor   ?? NSColor.controlBackgroundColor
        let cardFgNS:    NSColor = theme?.cardForeground.nsColor   ?? NSColor.labelColor
        let borderNS:    NSColor = theme?.buttonBorder.nsColor    ?? NSColor.separatorColor

        // Body fill for the standard / opaque / oval / roundRect
        // / shadow.face cases. Hilite swaps to the theme's hilite
        // color; rest uses the theme's button background.
        let fillColor = part.hilite ? buttonHiNS.cgColor : buttonBgNS.cgColor

        // Label color for the body cases. When hilited, pick a
        // contrast-aware color over the hilite fill so the text is
        // readable regardless of what tint the theme chose
        // (Sunset's orange + dark text; Neon's magenta + light text).
        // When not hilited, use the theme's button foreground.
        let computedTextColor: CGColor
        switch part.buttonStyle {
        case .checkBox, .toggle:
            // Indicator-style controls (check / switch). The label
            // floats next to the indicator on the part background,
            // not over the hilite — use the theme's foreground.
            computedTextColor = part.enabled ? cardFgNS.cgColor : NSColor.disabledControlTextColor.cgColor
        default:
            if part.hilite {
                computedTextColor = ColorContrast.readableTextColor(for: buttonHiNS).cgColor
            } else {
                computedTextColor = part.enabled ? buttonFgNS.cgColor : NSColor.disabledControlTextColor.cgColor
            }
        }
        // Explicit `part.fontColor` overrides the computed contrast-
        // aware default when set. Empty string is the "auto" sentinel
        // — keeps the previous behavior for parts that haven't opted
        // into a custom font color.
        let textColor: CGColor = {
            if !part.fontColor.isEmpty,
               let parsed = NSColor(hexString: part.fontColor) {
                return parsed.cgColor
            }
            return computedTextColor
        }()

        switch part.buttonStyle {
        case .transparent:
            break // No background

        case .opaque:
            if useGlass, let t = theme {
                GlassRenderer.fillRoundedRect(
                    ctx: ctx, rect: rect,
                    fillHex: part.hilite ? t.buttonHilite.rawDescription : t.buttonBackground.rawDescription,
                    cornerRadius: CGFloat(t.cornerRadiusMedium),
                    strokeHex: t.buttonBorder.rawDescription,
                    strokeWidth: CGFloat(t.strokeWidthThin),
                    shadowOpacity: CGFloat(t.shadowOpacity),
                    shadowRadius: CGFloat(t.shadowRadius)
                )
            } else {
                ctx.setFillColor(fillColor)
                ctx.fill(rect)
            }

        case .standard:
            if useGlass, let t = theme {
                GlassRenderer.fillRoundedRect(
                    ctx: ctx, rect: rect,
                    fillHex: part.hilite ? t.buttonHilite.rawDescription : t.buttonBackground.rawDescription,
                    cornerRadius: CGFloat(t.cornerRadiusLarge),
                    strokeHex: t.buttonBorder.rawDescription,
                    strokeWidth: CGFloat(t.strokeWidthThin),
                    shadowOpacity: CGFloat(t.shadowOpacity),
                    shadowRadius: CGFloat(t.shadowRadius)
                )
            } else {
                ctx.setFillColor(fillColor)
                ctx.fill(rect)
                ctx.setStrokeColor(borderNS.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(rect)
            }

        case .roundRect:
            if useGlass, let t = theme {
                GlassRenderer.fillRoundedRect(
                    ctx: ctx, rect: rect,
                    fillHex: part.hilite ? t.buttonHilite.rawDescription : t.buttonBackground.rawDescription,
                    cornerRadius: CGFloat(t.cornerRadiusLarge),
                    strokeHex: t.buttonBorder.rawDescription,
                    strokeWidth: CGFloat(t.strokeWidthThin),
                    shadowOpacity: CGFloat(t.shadowOpacity),
                    shadowRadius: CGFloat(t.shadowRadius)
                )
            } else {
                let cornerR = theme.map { CGFloat($0.cornerRadiusMedium) } ?? 8
                // Script geometry may be zero/negative/NaN; route through
                // RenderGeometry so CGPath preconditions are always met.
                let path = RenderGeometry.roundedRectPath(in: rect, cornerRadius: cornerR)
                ctx.addPath(path)
                ctx.setFillColor(fillColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(borderNS.cgColor)
                ctx.setLineWidth(1)
                ctx.strokePath()
            }

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
            ctx.setStrokeColor(borderNS.cgColor)
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
                    align: align,
                    textStyle: part.textStyle
                )
            }
            ctx.restoreGState()
            return

        case .checkBox:
            // Always draw a clearly visible rectangle where the check
            // belongs — even in the unchecked state — so users can
            // see exactly where the click target is and what the
            // checkbox style looks like at rest.
            let boxSize: CGFloat = 16
            let boxY = rect.midY - boxSize / 2
            let boxRect = CGRect(x: rect.minX + 4, y: boxY, width: boxSize, height: boxSize)
            ctx.setFillColor(cardBgNS.cgColor)
            ctx.fill(boxRect)
            ctx.setStrokeColor(cardFgNS.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(boxRect)
            // When checked (hilite), draw a checkmark V-shape inside
            // the box using the theme's accent color so a Sunset /
            // Neon / Liquid Glass theme highlights the check in its
            // signature tint.
            if part.hilite {
                ctx.setStrokeColor(accentNS.cgColor)
                ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: boxRect.minX + 3, y: boxRect.midY))
                ctx.addLine(to: CGPoint(x: boxRect.midX - 1, y: boxRect.maxY - 3))
                ctx.addLine(to: CGPoint(x: boxRect.maxX - 3, y: boxRect.minY + 3))
                ctx.strokePath()
            }
            // Label
            drawLabel(ctx: ctx, text: part.showName ? part.name : part.textContent,
                     at: CGPoint(x: rect.minX + boxSize + 8, y: rect.midY),
                     font: part.textFont, size: part.textSize, color: textColor, align: .left,
                     textStyle: part.textStyle)
            ctx.restoreGState()
            return

        case .default:
            // The "default action" button. Apple's HIG paints this in
            // the system accent so the user can spot the primary
            // action at a glance — e.g. the OK button in a dialog.
            // We honor the same intent, but read the accent from the
            // active theme so a Sunset / Neon / Liquid Glass / user-
            // authored theme actually shows up here. Falls back to
            // the system accent when no theme is supplied (legacy
            // callers, tests).
            let cornerR = theme.map { CGFloat($0.cornerRadiusLarge) } ?? 10
            if useGlass, let t = theme {
                GlassRenderer.fillRoundedRect(
                    ctx: ctx, rect: rect,
                    fillHex: t.accent.rawDescription,
                    cornerRadius: cornerR,
                    strokeHex: nil,
                    strokeWidth: 0,
                    shadowOpacity: CGFloat(t.shadowOpacity),
                    shadowRadius: CGFloat(t.shadowRadius)
                )
            } else {
                // Script geometry may be zero/negative/NaN; route through
                // RenderGeometry so CGPath preconditions are always met.
                let outerPath = RenderGeometry.roundedRectPath(in: rect, cornerRadius: cornerR)
                ctx.addPath(outerPath)
                ctx.setFillColor(accentNS.cgColor)
                ctx.fillPath()
            }
            // Text color is contrast-aware against the resolved
            // accent so a light accent (Sunset orange / Liquid Glass
            // pale blue) gets dark text and a dark accent (Neon
            // magenta) gets light text. Without this, a theme that
            // picked a light accent rendered as white-on-light = an
            // unreadable button.
            let label = part.showName ? part.name : part.textContent
            // `part.fontColor` overrides the contrast-aware default
            // here too — author-set color wins when explicit.
            let labelColor: CGColor = {
                if !part.fontColor.isEmpty,
                   let parsed = NSColor(hexString: part.fontColor) {
                    return parsed.cgColor
                }
                return ColorContrast.readableTextColor(for: accentNS).cgColor
            }()
            drawLabel(ctx: ctx, text: label, at: CGPoint(x: rect.midX, y: rect.midY),
                     font: part.textFont, size: part.textSize, color: labelColor, align: .center,
                     textStyle: part.textStyle)
            ctx.restoreGState()
            return

        case .popup:
            // macOS-style popup button with rounded corners. Theme-
            // aware: bg is the field background (so it reads as a
            // user-input control), border is the field border, and
            // chevrons + label are the card foreground. Falls back
            // to system defaults when no theme is supplied.
            let cornerR = theme.map { CGFloat($0.cornerRadiusMedium) } ?? 6
            // Script geometry may be zero/negative/NaN; route through
            // RenderGeometry so CGPath preconditions are always met.
            let popupPath = RenderGeometry.roundedRectPath(in: rect, cornerRadius: cornerR)
            ctx.addPath(popupPath)
            ctx.setFillColor((theme?.fieldBackground.nsColor ?? NSColor.textBackgroundColor).cgColor)
            ctx.fillPath()
            ctx.addPath(popupPath)
            ctx.setStrokeColor((theme?.fieldBorder.nsColor ?? NSColor.separatorColor).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            // Draw unfilled dropdown chevron arrows (up/down)
            let arrowX = rect.maxX - 18
            let arrowCY = rect.midY
            ctx.setStrokeColor(cardFgNS.cgColor)
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
                     font: part.textFont, size: part.textSize, color: textColor, align: .left,
                     textStyle: part.textStyle)
            ctx.restoreGState()
            return

        case .oval:
            ctx.addEllipse(in: rect)
            ctx.setFillColor(fillColor)
            ctx.fillPath()
            ctx.addEllipse(in: rect)
            ctx.setStrokeColor(borderNS.cgColor)
            ctx.strokePath()

        case .toggle:
            // macOS-style toggle switch. Track-on uses the theme's
            // accent so the active toggle reads in the theme tint;
            // track-off stays a translucent gray (it's an "absence
            // of accent" state and a tinted off-state would be
            // confusingly close to on). Knob uses the theme card
            // background so it pops on both light and dark themes.
            let trackWidth: CGFloat = 44
            let trackHeight: CGFloat = 24
            let trackX = rect.minX + 4
            let trackY = rect.midY - trackHeight / 2
            let trackRect = CGRect(x: trackX, y: trackY, width: trackWidth, height: trackHeight)
            // trackRect is sized from a fixed constant (44×24) and capped
            // by the renderer above; route through RenderGeometry to guard
            // against any script-authored rect that reaches this path.
            let trackPath = RenderGeometry.roundedRectPath(in: trackRect, cornerRadius: trackHeight / 2)

            ctx.addPath(trackPath)
            ctx.setFillColor(part.hilite ? accentNS.cgColor : NSColor.systemGray.withAlphaComponent(0.3).cgColor)
            ctx.fillPath()

            // Knob
            let knobSize = trackHeight - 4
            let knobX = part.hilite ? trackX + trackWidth - knobSize - 2 : trackX + 2
            let knobY = trackY + 2
            ctx.addEllipse(in: CGRect(x: knobX, y: knobY, width: knobSize, height: knobSize))
            ctx.setFillColor(cardBgNS.cgColor)
            ctx.fillPath()
            ctx.addEllipse(in: CGRect(x: knobX, y: knobY, width: knobSize, height: knobSize))
            ctx.setStrokeColor(borderNS.cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokePath()

            // Label after toggle
            let label = part.showName ? part.name : part.textContent
            if !label.isEmpty {
                drawLabel(ctx: ctx, text: label, at: CGPoint(x: trackX + trackWidth + 8, y: rect.midY),
                         font: part.textFont, size: part.textSize, color: textColor, align: .left,
                         textStyle: part.textStyle)
            }
            ctx.restoreGState()
            return

        case .radio:
            // Radio button: hollow circle with filled dot when
            // hilited. Theme-aware — the dot uses the theme accent
            // (Sunset orange / Neon magenta / Liquid Glass blue),
            // the circle outlines in the theme card foreground, and
            // the empty fill uses the theme card background.
            let radioSize: CGFloat = min(rect.height, 18)
            let radioRect = CGRect(
                x: rect.minX + 2,
                y: rect.midY - radioSize / 2,
                width: radioSize,
                height: radioSize
            )
            ctx.setFillColor(cardBgNS.cgColor)
            ctx.fillEllipse(in: radioRect)
            ctx.setStrokeColor(cardFgNS.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: radioRect)
            if part.hilite {
                let dotSize = radioSize * 0.5
                let dotRect = CGRect(
                    x: radioRect.midX - dotSize / 2,
                    y: radioRect.midY - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                ctx.setFillColor(accentNS.cgColor)
                ctx.fillEllipse(in: dotRect)
            }
            // Label to the right of the radio circle
            let radioLabel = part.showName ? part.name : part.textContent
            if !radioLabel.isEmpty {
                drawLabel(ctx: ctx, text: radioLabel,
                          at: CGPoint(x: radioRect.maxX + 6, y: rect.midY),
                          font: part.textFont, size: part.textSize, color: textColor, align: .left,
                          textStyle: part.textStyle)
            }
            ctx.restoreGState()
            return

        case .link:
            // Underlined link styling. Theme-aware: when a theme is
            // supplied, the link tint comes from `theme.accent` so a
            // Sunset / Neon / Liquid Glass theme paints links in its
            // signature color. Without a theme, falls back to
            // `NSColor.linkColor` (the system blue link tint).
            // Click handling lives in the host view (NSWorkspace.open
            // with scheme allowlist).
            let linkText = part.textContent.isEmpty
                ? (part.url.isEmpty ? "(link)" : part.url)
                : part.textContent
            // Link text honors part.fontColor if set; else takes the
            // theme's accent (or NSColor.linkColor when no theme).
            let linkColor: CGColor = {
                if !part.fontColor.isEmpty,
                   let parsed = NSColor(hexString: part.fontColor) {
                    return parsed.cgColor
                }
                return (theme.map { $0.accent.nsColor } ?? NSColor.linkColor).cgColor
            }()
            drawLabel(ctx: ctx, text: linkText,
                      at: CGPoint(x: rect.midX, y: rect.midY),
                      font: part.textFont, size: part.textSize, color: linkColor, align: .center,
                      textStyle: part.textStyle)
            // Underline beneath the text — measure to centre the line.
            let nsfont = NSFont(name: part.textFont.isEmpty ? "Helvetica" : part.textFont,
                                size: CGFloat(part.textSize > 0 ? part.textSize : 14))
                ?? NSFont.systemFont(ofSize: 14)
            let attrs: [NSAttributedString.Key: Any] = [.font: nsfont]
            let textWidth = (linkText as NSString).size(withAttributes: attrs).width
            let lineY = rect.midY - nsfont.descender - 1
            ctx.setStrokeColor(linkColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: rect.midX - textWidth / 2, y: lineY))
            ctx.addLine(to: CGPoint(x: rect.midX + textWidth / 2, y: lineY))
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        // Draw centered label
        let label = part.showName ? part.name : part.textContent
        if !label.isEmpty {
            let align: LabelAlignment = part.textAlign == .left ? .left : part.textAlign == .right ? .right : .center
            drawLabel(ctx: ctx, text: label, at: CGPoint(x: rect.midX, y: rect.midY),
                     font: part.textFont, size: part.textSize, color: textColor, align: align,
                     textStyle: part.textStyle)
        }

        ctx.restoreGState()
    }

    enum LabelAlignment { case left, center, right }

    /// Central label-drawing routine used by every button-style
    /// branch in `draw(...)`. Consults `textStyle` (parsed via
    /// `TextStyleFlags`) so a part with `textStyle = "bold,italic,
    /// underline,strikethrough"` actually paints with bold + italic
    /// font traits AND the underline / strikethrough decorations.
    /// `textStyle` defaults to `"plain"` (no flags) so legacy
    /// callers and tests render exactly as before.
    static func drawLabel(
        ctx: CGContext,
        text: String,
        at point: CGPoint,
        font: String,
        size: Double,
        color: CGColor,
        align: LabelAlignment,
        textStyle: String = "plain"
    ) {
        let baseFont = NSFont(name: font, size: CGFloat(size)) ?? NSFont.systemFont(ofSize: CGFloat(size))
        let flags = TextStyleFlags(string: textStyle)
        // Apply bold / italic via NSFontManager — it respects the
        // base font's family + size while toggling the trait, so we
        // don't lose the chosen font face by switching to system.
        var styledFont = baseFont
        if flags.bold {
            styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .boldFontMask)
        }
        if flags.italic {
            styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .italicFontMask)
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: styledFont,
            .foregroundColor: NSColor(cgColor: color) ?? NSColor.black,
        ]
        if flags.underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if flags.strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

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
