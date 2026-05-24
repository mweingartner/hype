import Foundation
import HypeCore

struct ObjectToolSection: Identifiable, Sendable {
    var id: String { title }
    let title: String
    let tools: [ToolName]
}

/// Canonical left-panel catalog.
///
/// The panel intentionally exposes one creation tool per persisted part type.
/// Visual variants such as transparent text annotations, search fields, ovals,
/// and line shapes are styles/properties of Field or Shape, not separate tools.
enum ObjectToolCatalog {
    static let selectionTools: [ToolName] = [.browse, .select]

    static let basicTools: [ToolName] = [
        .button, .field, .shape, .image,
        .webpage, .video, .chart,
    ]

    static let frameworkTools: [ToolName] = [
        .calendar, .pdf, .map, .colorWell, .audioRecorder,
        .scene3D, .spriteArea,
    ]

    static let formControlTools: [ToolName] = [
        .stepper, .slider, .segmented,
        .progressView, .gauge, .divider,
    ]

    static let paintTools: [ToolName] = [
        .pencil, .spray, .bucket, .eraser,
    ]

    static let authoringSections: [ObjectToolSection] = [
        ObjectToolSection(title: "Select", tools: selectionTools),
        ObjectToolSection(title: "Objects", tools: basicTools),
        ObjectToolSection(title: "Framework", tools: frameworkTools),
        ObjectToolSection(title: "Form", tools: formControlTools),
        ObjectToolSection(title: "Paint", tools: paintTools),
    ]

    static var creationTools: [ToolName] {
        basicTools + frameworkTools + formControlTools
    }

    static var panelTools: [ToolName] {
        authoringSections.flatMap(\.tools)
    }

    static func createdPartType(for tool: ToolName) -> PartType? {
        switch tool {
        case .button: return .button
        case .field: return .field
        case .shape: return .shape
        case .webpage: return .webpage
        case .image: return .image
        case .video: return .video
        case .chart: return .chart
        case .spriteArea: return .spriteArea
        case .calendar: return .calendar
        case .pdf: return .pdf
        case .map: return .map
        case .colorWell: return .colorWell
        case .stepper: return .stepper
        case .slider: return .slider
        case .segmented: return .segmented
        case .audioRecorder: return .audioRecorder
        case .scene3D: return .scene3D
        case .progressView: return .progressView
        case .gauge: return .gauge
        case .divider: return .divider
        case .browse, .select, .pencil, .spray, .bucket, .eraser:
            return nil
        }
    }

    static func styleSummary(for tool: ToolName) -> String? {
        switch tool {
        case .button:
            return "Common styles: standard push buttons, toggles, checkboxes, radio choices, links, pop-up menus, and icon buttons."
        case .field:
            return "Common styles: bordered entry boxes, transparent labels, scrolling text, search boxes, password-style entry, and list-style fields."
        case .shape:
            return "Common styles: rectangles, rounded rectangles, ovals, straight lines, and editable freeform shapes."
        case .chart:
            return "Common styles: bar, line, area, point, and pie charts."
        case .calendar:
            return "Common styles: full calendar, compact date entry, and date-with-time entry."
        case .progressView:
            return "Common styles: horizontal progress bars, circular progress, and indeterminate loading indicators."
        case .gauge:
            return "Common styles: horizontal gauges and circular gauges."
        case .divider:
            return "Common styles: horizontal and vertical separator lines."
        default:
            return nil
        }
    }

    static func propertySummary(for tool: ToolName) -> String? {
        switch tool {
        case .button:
            return "You can edit its label, style, icon, link target, choices, highlight behavior, script, and hover help."
        case .field:
            return "You can edit its text, style, wrapping, margins, lock state, font, size, color, alignment, script, and hover help."
        case .shape:
            return "You can edit its shape, fill, border color, border width, rounded corners, rotation, custom outline, and hover help."
        case .webpage:
            return "You can edit the web address, connect it to a field, and add hover help."
        case .image:
            return "You can choose the picture, control animation, remove simple backgrounds, apply visual filters, invert on click, and add hover help."
        case .video:
            return "You can choose the movie source and add hover help."
        case .chart:
            return "You can edit the data, chart type, title, series, script, and hover help."
        case .spriteArea:
            return "You can choose scenes, add sprites and tile maps, configure motion and collisions, run game templates, attach scripts, and add hover help."
        case .calendar:
            return "You can edit the selected date, visible month, allowed date range, display style, script, and hover help."
        case .pdf:
            return "You can choose the document, set the current page, adjust the viewing style, and add hover help."
        case .map:
            return "You can set a place or coordinates, choose the zoom and map style, add pins, and add hover help."
        case .colorWell:
            return "You can choose the color, decide whether users can change it, attach a script, and add hover help."
        case .stepper, .slider:
            return "You can edit the current value, minimum, maximum, step size, script, and hover help."
        case .segmented:
            return "You can edit the choice labels, selected choice, script, and hover help."
        case .audioRecorder:
            return "You can start or stop recording, play the last recording, choose the recording format, save recordings inside the stack, attach scripts, and add hover help."
        case .scene3D:
            return "You can choose a model, use a stack asset, adjust viewing controls and background, attach scripts, and add hover help."
        case .progressView:
            return "You can edit the current progress, total, label, color, display style, precision, script, and hover help."
        case .gauge:
            return "You can edit the current value, range, labels, color, display style, precision, script, and hover help."
        case .divider:
            return "You can edit the direction, thickness, color, and hover help."
        case .browse, .select, .pencil, .spray, .bucket, .eraser:
            return nil
        }
    }

    static func tooltipBody(for tool: ToolName) -> String {
        var lines = [tool.description]
        if let styleSummary = styleSummary(for: tool) {
            lines.append(styleSummary)
        }
        if let propertySummary = propertySummary(for: tool) {
            lines.append(propertySummary)
        }
        return lines.joined(separator: "\n\n")
    }
}
