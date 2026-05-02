import AppKit
import HypeCore

/// AppKit-hosted live calendar — replaces the CG placeholder
/// `CalendarRenderer` produces in edit mode. Mirrors how
/// `ChartHostView` and the SKView for sprite-area parts work.
///
/// Wraps an `NSDatePicker` configured to whatever style the part
/// requests (`graphical` / `textual` / `clockAndCalendar`). The
/// host view exposes a closure-based `onDateChange` callback so
/// `CardCanvasView` can write the selected date back to the
/// document, keeping HypeTalk reads consistent with what's on
/// screen.
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
    var onDateChange: ((String) -> Void)?

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
    func apply(_ part: Part) {
        datePicker.datePickerStyle = Self.pickerStyle(for: part.calendarStyle)

        if let selected = Self.parseISO(part.selectedDate) {
            datePicker.dateValue = selected
        } else if let displayed = Self.parseISO(part.displayMonth) {
            datePicker.dateValue = displayed
        } else {
            datePicker.dateValue = Date()
        }

        datePicker.minDate = Self.parseISO(part.minDate)
        datePicker.maxDate = Self.parseISO(part.maxDate)
    }

    @objc private func dateDidChange() {
        let iso = Self.formatISO(datePicker.dateValue)
        onDateChange?(iso)
    }

    // MARK: - Helpers

    private static func pickerStyle(for raw: String) -> NSDatePicker.Style {
        switch raw.lowercased() {
        case "graphical": return .clockAndCalendar
        case "textual", "textualwithstepper": return .textFieldAndStepper
        case "clockandcalendar": return .clockAndCalendar
        default: return .clockAndCalendar
        }
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
}
