import Foundation

/// Normalized style values used by standalone target-runtime adapters.
///
/// These helpers keep the authoring UI, exported iPhone/iPad runtime shell,
/// and regression tests aligned without storing any live platform view state.
public enum TargetRuntimeCalendarStyle: String, CaseIterable, Sendable {
    case graphical
    case textual
    case clockAndCalendar

    public init(rawOrAlias raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "textual", "textfield", "textfieldandstepper", "textualwithstepper":
            self = .textual
        case "clockandcalendar", "clock_and_calendar", "dateandtime", "date_time", "datetime":
            self = .clockAndCalendar
        default:
            self = .graphical
        }
    }

    public var persistsTime: Bool {
        self == .clockAndCalendar
    }

    public var usesCompactPicker: Bool {
        self == .textual
    }
}

public enum TargetRuntimeButtonRenderKind: String, Sendable {
    case transparent
    case filledRectangle
    case roundedRectangle
    case prominentDefault
    case shadow
    case oval
    case toggle
    case checkBox
    case radio
    case popup
    case link

    public init(style: ButtonStyle) {
        switch style {
        case .transparent:
            self = .transparent
        case .opaque, .standard:
            self = .filledRectangle
        case .roundRect:
            self = .roundedRectangle
        case .default:
            self = .prominentDefault
        case .shadow:
            self = .shadow
        case .oval:
            self = .oval
        case .toggle:
            self = .toggle
        case .checkBox:
            self = .checkBox
        case .radio:
            self = .radio
        case .popup:
            self = .popup
        case .link:
            self = .link
        }
    }
}
