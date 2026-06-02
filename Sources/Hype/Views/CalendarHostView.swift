import AppKit
import HypeCore

/// AppKit-hosted live calendar — replaces the CG placeholder
/// `CalendarRenderer` produces in edit mode. Mirrors how
/// `ChartHostView` and the SKView for sprite-area parts work.
///
/// Wraps an `NSDatePicker`. The three Hype calendar styles map to
/// distinct AppKit configurations so they're visually different
/// from each other (the previous mapping had "graphical" and
/// "clockAndCalendar" both produce identical UI):
///
/// - **graphical**       → `.clockAndCalendar` style + `[.yearMonthDay]`
///                         elements → calendar grid only.
/// - **textual**         → `.textFieldAndStepper` style + `[.yearMonthDay]`
///                         elements → compact "12/25/2026 ⬆⬇" form.
/// - **clockAndCalendar** → `.clockAndCalendar` style + `[.yearMonthDay,
///                         .hourMinuteSecond]` elements → calendar grid
///                         AND analog clock face.
///
/// `apply(_:)` is idempotent and side-effect-minimised: each
/// property write goes through a compare-and-skip guard so a draw
/// cycle doesn't keep resetting the user's interactive selection.
final class CalendarHostNSView: NSView {

    let datePicker: NSDatePicker = {
        let p = NSDatePicker()
        p.translatesAutoresizingMaskIntoConstraints = false
        p.datePickerElements = [.yearMonthDay]
        p.datePickerStyle = .clockAndCalendar
        return p
    }()

    /// Closure fired after the user changes the selected date. The
    /// String is ISO 8601 (yyyy-MM-dd) — what HypeTalk + AI tools
    /// store on `Part.selectedDate`.
    var onDateChange: ((String, String?) -> Void)?

    /// Last-applied style/elements/dates so apply() can compare-and-
    /// skip. Without these guards, every draw cycle reset the live
    /// dateValue back to what's in the document, which interrupted
    /// the user's interactive picking.
    private var appliedStyle: NSDatePicker.Style?
    private var appliedElements: NSDatePicker.ElementFlags = []
    private var appliedCalendarStyle: TargetRuntimeCalendarStyle = .graphical
    private var appliedSelectedISO: String? = nil
    private var appliedSelectedTimeISO: String? = nil
    private var appliedMinISO: String? = nil
    private var appliedMaxISO: String? = nil

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            datePicker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            datePicker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            datePicker.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        datePicker.target = self
        datePicker.action = #selector(dateDidChange)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Apply the latest `Part` config to the live picker.
    ///
    /// Each setter is gated by a compare-and-skip so we don't
    /// thrash the picker on every redraw. In particular, resetting
    /// `dateValue` mid-interaction (which previously happened on
    /// every redraw) would clobber the user's selection.
    func apply(_ part: Part) {
        let calendarStyle = TargetRuntimeCalendarStyle(rawOrAlias: part.calendarStyle)
        let style = Self.pickerStyle(for: calendarStyle)
        let elements = Self.elementFlags(for: calendarStyle)
        appliedCalendarStyle = calendarStyle

        if style != appliedStyle {
            datePicker.datePickerStyle = style
            appliedStyle = style
            // Style changes invalidate intrinsic content size and
            // demand a re-layout.
            datePicker.invalidateIntrinsicContentSize()
            datePicker.needsLayout = true
            self.needsLayout = true
            self.needsDisplay = true
        }
        if elements != appliedElements {
            datePicker.datePickerElements = elements
            appliedElements = elements
            datePicker.needsDisplay = true
        }

        // Date binding — only update when the SOURCE OF TRUTH (the
        // part's stored value) actually changed. This protects the
        // user's interactive picking from being reset on every draw.
        if part.selectedDate != appliedSelectedISO || (calendarStyle.persistsTime && part.selectedTime != appliedSelectedTimeISO) {
            if let selected = Self.parseDateAndTime(date: part.selectedDate, time: calendarStyle.persistsTime ? part.selectedTime : "") {
                datePicker.dateValue = selected
            } else if let displayed = Self.parseISO(part.displayMonth) {
                datePicker.dateValue = displayed
            } else {
                datePicker.dateValue = Date()
            }
            appliedSelectedISO = part.selectedDate
            appliedSelectedTimeISO = part.selectedTime
        }

        if part.minDate != appliedMinISO {
            datePicker.minDate = Self.parseISO(part.minDate)
            appliedMinISO = part.minDate
        }
        if part.maxDate != appliedMaxISO {
            datePicker.maxDate = Self.parseISO(part.maxDate)
            appliedMaxISO = part.maxDate
        }
    }

    @objc private func dateDidChange() {
        let iso = Self.formatISO(datePicker.dateValue)
        let time = appliedCalendarStyle.persistsTime ? Self.formatTime(datePicker.dateValue) : nil
        // Update the cached "last-applied" so the next apply()
        // doesn't see a "change" and clobber the live value.
        appliedSelectedISO = iso
        if let time {
            appliedSelectedTimeISO = time
        }
        onDateChange?(iso, time)
    }

    // MARK: - Style mapping

    /// Map Hype's friendly style name to NSDatePicker.Style. Only
    /// `.textFieldAndStepper` and `.clockAndCalendar` are real AppKit
    /// styles; "graphical" and "clockAndCalendar" both use the
    /// `.clockAndCalendar` style, but `elementFlags(for:)` discriminates
    /// them by which elements (date/time) are visible.
    private static func pickerStyle(for style: TargetRuntimeCalendarStyle) -> NSDatePicker.Style {
        switch style {
        case .textual:
            return .textFieldAndStepper
        case .graphical, .clockAndCalendar:
            return .clockAndCalendar
        }
    }

    /// Element flags for each named style. "graphical" hides the
    /// clock face (date only); "clockAndCalendar" enables it.
    private static func elementFlags(for style: TargetRuntimeCalendarStyle) -> NSDatePicker.ElementFlags {
        switch style {
        case .clockAndCalendar:
            return [.yearMonthDay, .hourMinuteSecond]
        case .graphical, .textual:
            return [.yearMonthDay]
        }
    }

    private static func parseDateAndTime(date: String, time: String) -> Date? {
        guard let day = parseISO(date) else { return nil }
        guard !time.isEmpty else { return day }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = max(0, min(23, parts[0]))
        components.minute = max(0, min(59, parts[1]))
        components.second = parts.count >= 3 ? max(0, min(59, parts[2])) : 0
        return calendar.date(from: components)
    }

    private static func parseISO(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)
    }

    private static func formatISO(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    private static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}
