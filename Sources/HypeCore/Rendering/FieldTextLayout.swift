import Foundation

#if canImport(AppKit)
import AppKit

/// Shared field text layout and color resolution for the static Core Graphics
/// renderer and the live AppKit inline editor.
public enum FieldTextLayout {
    public static let defaultPadding: CGFloat = 4
    public static let widePadding: CGFloat = 8
    public static let searchLeadingInset: CGFloat = 24
    public static let scrollingTrailingInset: CGFloat = 16

    public static func padding(wideMargins: Bool) -> CGFloat {
        wideMargins ? widePadding : defaultPadding
    }

    public static func leadingInset(fieldStyle: FieldStyle) -> CGFloat {
        fieldStyle == .search ? searchLeadingInset : 0
    }

    public static func trailingInset(fieldStyle: FieldStyle) -> CGFloat {
        fieldStyle == .scrolling ? scrollingTrailingInset : 0
    }

    public static func contentRect(
        in rect: CGRect,
        wideMargins: Bool,
        fieldStyle: FieldStyle
    ) -> CGRect {
        let inset = padding(wideMargins: wideMargins)
        let leading = leadingInset(fieldStyle: fieldStyle)
        let trailing = trailingInset(fieldStyle: fieldStyle)
        return CGRect(
            x: rect.minX + inset + leading,
            y: rect.minY + inset,
            width: max(0, rect.width - inset * 2 - leading - trailing),
            height: max(0, rect.height - inset * 2)
        )
    }

    public static func verticallyCenteredTextRect(
        in rect: CGRect,
        wideMargins: Bool,
        fieldStyle: FieldStyle,
        attributedString: NSAttributedString,
        fallbackFont: NSFont?
    ) -> CGRect {
        let content = contentRect(in: rect, wideMargins: wideMargins, fieldStyle: fieldStyle)
        return verticallyCenteredTextRect(
            in: content,
            attributedString: attributedString,
            fallbackFont: fallbackFont
        )
    }

    public static func verticallyCenteredTextRect(
        in contentRect: CGRect,
        attributedString: NSAttributedString,
        fallbackFont: NSFont?
    ) -> CGRect {
        guard contentRect.width > 0, contentRect.height > 0 else { return contentRect }

        let measuredHeight = textBlockHeight(
            for: attributedString,
            width: contentRect.width,
            fallbackFont: fallbackFont
        )
        let height = min(contentRect.height, max(1, ceil(measuredHeight)))
        let y = contentRect.minY + max(0, floor((contentRect.height - height) / 2))

        return CGRect(
            x: contentRect.minX,
            y: y,
            width: contentRect.width,
            height: height
        )
    }

    public static func textBlockHeight(
        for attributedString: NSAttributedString,
        width: CGFloat,
        fallbackFont: NSFont?
    ) -> CGFloat {
        let measuringString: NSAttributedString
        if attributedString.length == 0 {
            let font = fallbackFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            measuringString = NSAttributedString(string: " ", attributes: [.font: font])
        } else {
            measuringString = attributedString
        }

        let bounds = measuringString.boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        if bounds.height > 0 {
            return bounds.height
        }

        let font = fallbackFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil(font.ascender - font.descender + font.leading)
    }
}

public struct FieldRenderPalette {
    public let fill: NSColor
    public let stroke: NSColor
    public let text: NSColor
    public let searchIcon: NSColor
    public let scrollbarTrack: NSColor

    public init(
        fill: NSColor,
        stroke: NSColor,
        text: NSColor,
        searchIcon: NSColor,
        scrollbarTrack: NSColor
    ) {
        self.fill = fill
        self.stroke = stroke
        self.text = text
        self.searchIcon = searchIcon
        self.scrollbarTrack = scrollbarTrack
    }
}

public extension FieldTextLayout {
    static func palette(for part: Part, theme: HypeTheme?) -> FieldRenderPalette {
        let partFill = NSColor(hexString: part.fillColor) ?? .white
        let partStroke = NSColor(hexString: part.strokeColor) ?? .black
        let usesDefaultFill = normalizedHex(part.fillColor) == "#FFFFFF"
        let usesDefaultStroke = normalizedHex(part.strokeColor) == "#000000"
        let explicitText = !part.fontColor.isEmpty ? NSColor(hexString: part.fontColor) : nil

        let fill: NSColor
        let stroke: NSColor
        let defaultText: NSColor

        switch part.fieldStyle {
        case .transparent:
            fill = partFill
            stroke = if let theme, usesDefaultStroke {
                theme.fieldBorder.nsColor
            } else {
                partStroke
            }
            defaultText = theme?.cardForeground.nsColor ?? ColorContrast.readableTextColor(forFillHex: part.fillColor)
        case .search:
            fill = if let theme, usesDefaultFill {
                theme.fieldBackground.nsColor
            } else {
                partFill
            }
            stroke = if let theme, usesDefaultStroke {
                theme.fieldBorder.nsColor
            } else if usesDefaultStroke {
                NSColor.separatorColor
            } else {
                partStroke
            }
            if let theme, usesDefaultFill {
                defaultText = theme.fieldForeground.nsColor
            } else {
                defaultText = ColorContrast.readableTextColor(for: fill)
            }
        default:
            fill = if let theme, usesDefaultFill {
                theme.fieldBackground.nsColor
            } else {
                partFill
            }
            stroke = if let theme, usesDefaultStroke {
                theme.fieldBorder.nsColor
            } else {
                partStroke
            }
            if let theme, usesDefaultFill {
                defaultText = theme.fieldForeground.nsColor
            } else {
                defaultText = ColorContrast.readableTextColor(for: fill)
            }
        }

        let text = explicitText ?? defaultText
        let searchIcon = explicitText ?? theme?.fieldForeground.nsColor ?? NSColor.secondaryLabelColor
        let scrollbarTrack = theme?.panelDivider.nsColor ?? NSColor.controlColor
        return FieldRenderPalette(
            fill: fill,
            stroke: stroke,
            text: text,
            searchIcon: searchIcon,
            scrollbarTrack: scrollbarTrack
        )
    }

    private static func normalizedHex(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6,
              s.allSatisfy({ "0123456789ABCDEF".contains($0) })
        else { return nil }
        return "#\(s)"
    }
}
#endif
