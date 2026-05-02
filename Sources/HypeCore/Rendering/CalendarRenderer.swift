import Foundation
#if canImport(AppKit)
import AppKit

/// CG fallback renderer for calendar parts.
///
/// Calendar parts are backed at runtime by an AppKit `NSDatePicker`
/// hosted as a subview in browse mode (similar to how chart and
/// sprite-area parts work). This renderer is the **placeholder** that
/// shows in edit mode AND inside `CardRenderer.renderToImage` (used
/// for transitions and the AI vision-capture tool).
///
/// The placeholder draws a stylized month-grid icon plus the
/// part's selectedDate (or "today" if unset) so the user sees what
/// the calendar represents without the live picker pixels.
public enum CalendarRenderer {

    public static func draw(ctx: CGContext, part: Part, rect: CGRect) {
        ctx.saveGState()

        // Background — light surface with rounded corners.
        let bg = NSColor.controlBackgroundColor.cgColor
        ctx.setFillColor(bg)
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        // 1pt border to distinguish from card surface.
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Header strip (top 28pt) with the visible month/year.
        let headerHeight: CGFloat = min(28, rect.height * 0.25)
        let header = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: headerHeight
        )
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.12).cgColor)
        ctx.fill(header)

        let displayString = monthYearLabel(for: part)
        drawCenteredText(
            displayString,
            in: header,
            font: NSFont.systemFont(ofSize: 11, weight: .medium),
            color: NSColor.labelColor,
            ctx: ctx
        )

        // Day-of-week initials row (S M T W T F S).
        let dowStripY = rect.minY + headerHeight + 2
        let dowHeight: CGFloat = 14
        let dowRect = CGRect(
            x: rect.minX,
            y: dowStripY,
            width: rect.width,
            height: dowHeight
        )
        let initials = ["S", "M", "T", "W", "T", "F", "S"]
        let cellWidth = rect.width / 7
        for (i, letter) in initials.enumerated() {
            let cell = CGRect(
                x: rect.minX + cellWidth * CGFloat(i),
                y: dowStripY,
                width: cellWidth,
                height: dowHeight
            )
            drawCenteredText(
                letter,
                in: cell,
                font: NSFont.systemFont(ofSize: 9, weight: .regular),
                color: NSColor.secondaryLabelColor,
                ctx: ctx
            )
        }
        _ = dowRect

        // Day grid below — 6 rows × 7 columns of dots.
        let gridTop = dowStripY + dowHeight + 4
        let gridBottom = rect.maxY - 4
        let rowCount: CGFloat = 6
        let rowHeight = max(8, (gridBottom - gridTop) / rowCount)
        let dotRadius: CGFloat = min(2.0, rowHeight * 0.18)

        ctx.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        for row in 0..<6 {
            for col in 0..<7 {
                let cx = rect.minX + cellWidth * (CGFloat(col) + 0.5)
                let cy = gridTop + rowHeight * (CGFloat(row) + 0.5)
                let dot = CGRect(
                    x: cx - dotRadius,
                    y: cy - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                ctx.fillEllipse(in: dot)
            }
        }

        // If a selected date is set, highlight its dot.
        if !part.selectedDate.isEmpty,
           let highlight = highlightedDayCell(for: part, gridTop: gridTop, rowHeight: rowHeight, cellWidth: cellWidth, in: rect) {
            ctx.setFillColor(NSColor.systemBlue.cgColor)
            let dot = CGRect(
                x: highlight.x - dotRadius * 1.6,
                y: highlight.y - dotRadius * 1.6,
                width: dotRadius * 3.2,
                height: dotRadius * 3.2
            )
            ctx.fillEllipse(in: dot)
        }

        ctx.restoreGState()
    }

    private static func monthYearLabel(for part: Part) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let isoMonth = !part.displayMonth.isEmpty ? part.displayMonth : part.selectedDate
        if !isoMonth.isEmpty,
           let date = isoDate(from: isoMonth) {
            return formatter.string(from: date)
        }
        return formatter.string(from: Date())
    }

    private static func highlightedDayCell(
        for part: Part,
        gridTop: CGFloat,
        rowHeight: CGFloat,
        cellWidth: CGFloat,
        in rect: CGRect
    ) -> (x: CGFloat, y: CGFloat)? {
        guard let date = isoDate(from: part.selectedDate) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1  // Sunday
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let day = components.day else { return nil }

        // Compute first weekday of the visible month.
        guard let monthStart = calendar.date(from: DateComponents(
            year: components.year, month: components.month, day: 1)
        ) else { return nil }
        let firstWeekday = calendar.component(.weekday, from: monthStart)  // 1...7, Sun = 1

        let cellIndex = (firstWeekday - 1) + (day - 1)
        let row = cellIndex / 7
        let col = cellIndex % 7
        guard row < 6 else { return nil }

        let cx = rect.minX + cellWidth * (CGFloat(col) + 0.5)
        let cy = gridTop + rowHeight * (CGFloat(row) + 0.5)
        return (cx, cy)
    }

    private static func isoDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: string)
    }

    private static func drawCenteredText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        ctx: CGContext
    ) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif
