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
        let style = TargetRuntimeCalendarStyle(rawOrAlias: part.calendarStyle)

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

        if style == .textual {
            drawTextualPlaceholder(ctx: ctx, part: part, rect: rect)
            ctx.restoreGState()
            return
        }

        let calendarRect: CGRect
        let clockRect: CGRect?
        if style.persistsTime && rect.width >= 180 {
            let splitWidth = rect.width * 0.62
            calendarRect = CGRect(x: rect.minX, y: rect.minY, width: splitWidth, height: rect.height)
            clockRect = CGRect(
                x: calendarRect.maxX + 4,
                y: rect.minY + 8,
                width: max(0, rect.maxX - calendarRect.maxX - 8),
                height: max(0, rect.height - 16)
            )
        } else {
            calendarRect = rect
            clockRect = nil
        }

        // Header strip (top 28pt) with the visible month/year.
        let headerHeight: CGFloat = min(28, rect.height * 0.25)
        let header = CGRect(
            x: calendarRect.minX,
            y: calendarRect.minY,
            width: calendarRect.width,
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
            x: calendarRect.minX,
            y: dowStripY,
            width: calendarRect.width,
            height: dowHeight
        )
        let initials = ["S", "M", "T", "W", "T", "F", "S"]
        let cellWidth = calendarRect.width / 7
        for (i, letter) in initials.enumerated() {
            let cell = CGRect(
                x: calendarRect.minX + cellWidth * CGFloat(i),
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
        let gridBottom = calendarRect.maxY - 4
        let rowCount: CGFloat = 6
        let rowHeight = max(8, (gridBottom - gridTop) / rowCount)
        let dotRadius: CGFloat = min(2.0, rowHeight * 0.18)

        ctx.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        for row in 0..<6 {
            for col in 0..<7 {
                let cx = calendarRect.minX + cellWidth * (CGFloat(col) + 0.5)
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
           let highlight = highlightedDayCell(for: part, gridTop: gridTop, rowHeight: rowHeight, cellWidth: cellWidth, in: calendarRect) {
            ctx.setFillColor(NSColor.systemBlue.cgColor)
            let dot = CGRect(
                x: highlight.x - dotRadius * 1.6,
                y: highlight.y - dotRadius * 1.6,
                width: dotRadius * 3.2,
                height: dotRadius * 3.2
            )
            ctx.fillEllipse(in: dot)
        }

        if let clockRect {
            drawClock(ctx: ctx, part: part, rect: clockRect)
        }

        ctx.restoreGState()
    }

    private static func drawTextualPlaceholder(ctx: CGContext, part: Part, rect: CGRect) {
        let inset = rect.insetBy(dx: 8, dy: max(6, rect.height * 0.18))
        let fieldPath = CGPath(roundedRect: inset, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(fieldPath)
        ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
        ctx.fillPath()
        ctx.addPath(fieldPath)
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        let stepperWidth: CGFloat = min(28, inset.width * 0.24)
        let stepperRect = CGRect(x: inset.maxX - stepperWidth, y: inset.minY, width: stepperWidth, height: inset.height)
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(stepperRect)
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.stroke(stepperRect)
        drawCenteredText("^\nv", in: stepperRect.insetBy(dx: 2, dy: 2), font: NSFont.systemFont(ofSize: 8), color: NSColor.secondaryLabelColor, ctx: ctx)

        let value = part.selectedDate.isEmpty ? "Select date" : part.selectedDate
        drawCenteredText(value, in: CGRect(x: inset.minX + 6, y: inset.minY, width: inset.width - stepperWidth - 12, height: inset.height), font: NSFont.systemFont(ofSize: 11), color: NSColor.labelColor, ctx: ctx)
    }

    private static func drawClock(ctx: CGContext, part: Part, rect: CGRect) {
        guard rect.width > 20, rect.height > 20 else { return }
        let labelHeight: CGFloat = 20
        let diameter = max(18, min(rect.width, rect.height - labelHeight))
        let clockRect = CGRect(
            x: rect.midX - diameter / 2,
            y: rect.minY + max(0, (rect.height - labelHeight - diameter) / 2),
            width: diameter,
            height: diameter
        )
        ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
        ctx.fillEllipse(in: clockRect)
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: clockRect)

        let center = CGPoint(x: clockRect.midX, y: clockRect.midY)
        let radius = diameter / 2
        for tick in 0..<12 {
            let angle = CGFloat(tick) / 12 * .pi * 2 - .pi / 2
            let outer = CGPoint(x: center.x + cos(angle) * radius * 0.84, y: center.y + sin(angle) * radius * 0.84)
            let inner = CGPoint(x: center.x + cos(angle) * radius * 0.72, y: center.y + sin(angle) * radius * 0.72)
            ctx.move(to: inner)
            ctx.addLine(to: outer)
        }
        ctx.strokePath()

        let time = parsedTime(part.selectedTime)
        let minuteAngle = CGFloat(time.minute) / 60 * .pi * 2 - .pi / 2
        let hourAngle = (CGFloat(time.hour % 12) + CGFloat(time.minute) / 60) / 12 * .pi * 2 - .pi / 2
        ctx.setStrokeColor(NSColor.labelColor.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + cos(hourAngle) * radius * 0.42, y: center.y + sin(hourAngle) * radius * 0.42))
        ctx.strokePath()
        ctx.setLineWidth(1.5)
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + cos(minuteAngle) * radius * 0.62, y: center.y + sin(minuteAngle) * radius * 0.62))
        ctx.strokePath()
        ctx.setFillColor(NSColor.labelColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))

        drawCenteredText(time.label, in: CGRect(x: rect.minX, y: clockRect.maxY + 2, width: rect.width, height: labelHeight), font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), color: NSColor.secondaryLabelColor, ctx: ctx)
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

    private static func parsedTime(_ string: String) -> (hour: Int, minute: Int, label: String) {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        let hour = parts.isEmpty ? 0 : max(0, min(23, parts[0]))
        let minute = parts.count < 2 ? 0 : max(0, min(59, parts[1]))
        return (hour, minute, String(format: "%02d:%02d", hour, minute))
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
