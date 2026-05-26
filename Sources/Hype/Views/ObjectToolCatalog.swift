import Foundation
import HypeCore

struct ObjectToolSection: Identifiable, Sendable {
    var id: String { title }
    let title: String
    let tools: [ToolName]
}

enum ToolSelectionNotification {
    static let preserveSelectionUserInfoKey = "preserveSelection"
}

/// Canonical left-panel catalog.
///
/// The panel intentionally exposes one creation tool per persisted part type.
/// Visual variants such as transparent text annotations, search fields, ovals,
/// and line shapes are styles/properties of Field or Shape, not separate tools.
enum ObjectToolCatalog {
    static let dragPasteboardTypeRaw = "com.hype.object-tool"
    static let dragStringPrefix = "hype-object-tool:"

    static let selectionTools: [ToolName] = [.browse, .select]

    static let basicTools: [ToolName] = [
        .button, .field, .shape, .image,
        .webpage, .video, .chart,
    ]

    static let frameworkTools: [ToolName] = [
        .calendar, .pdf, .map, .colorWell, .audioRecorder,
        .musicPlayer, .pianoKeyboard, .stepSequencer, .musicMixer,
        .appleMusicBrowser,
        .scene3D, .spriteArea,
    ]

    static let formControlTools: [ToolName] = [
        .stepper, .slider, .segmented,
        .progressView, .gauge, .divider,
    ]

    static let objectTools: [ToolName] = basicTools + formControlTools

    static let paintTools: [ToolName] = [
        .pencil, .spray, .bucket, .eraser,
    ]

    static let authoringSections: [ObjectToolSection] = [
        ObjectToolSection(title: "Select", tools: selectionTools),
        ObjectToolSection(title: "Objects", tools: objectTools),
        ObjectToolSection(title: "Framework", tools: frameworkTools),
        ObjectToolSection(title: "Paint", tools: paintTools),
    ]

    static var creationTools: [ToolName] {
        basicTools + frameworkTools + formControlTools
    }

    static var panelTools: [ToolName] {
        authoringSections.flatMap(\.tools)
    }

    static func authoringSections(for targetPlatforms: [HypeTargetPlatform]) -> [ObjectToolSection] {
        authoringSections.compactMap { section in
            let filteredTools = section.tools.filter { tool in
                guard let partType = createdPartType(for: tool) else {
                    return true
                }
                return PartAvailabilityCatalog.supports(partType, across: targetPlatforms)
            }
            guard !filteredTools.isEmpty else { return nil }
            return ObjectToolSection(title: section.title, tools: filteredTools)
        }
    }

    static func creationTools(for targetPlatforms: [HypeTargetPlatform]) -> [ToolName] {
        creationTools.filter { tool in
            guard let partType = createdPartType(for: tool) else { return false }
            return PartAvailabilityCatalog.supports(partType, across: targetPlatforms)
        }
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
        case .musicPlayer: return .musicPlayer
        case .pianoKeyboard: return .pianoKeyboard
        case .stepSequencer: return .stepSequencer
        case .musicMixer: return .musicMixer
        case .appleMusicBrowser: return .appleMusicBrowser
        case .scene3D: return .scene3D
        case .progressView: return .progressView
        case .gauge: return .gauge
        case .divider: return .divider
        case .musicQueue, .browse, .select, .pencil, .spray, .bucket, .eraser:
            return nil
        }
    }

    static func dragPayload(for tool: ToolName) -> String {
        "\(dragStringPrefix)\(tool.rawValue)"
    }

    static func toolName(fromDragPayload payload: String) -> ToolName? {
        let rawValue: String
        if payload.hasPrefix(dragStringPrefix) {
            rawValue = String(payload.dropFirst(dragStringPrefix.count))
        } else {
            rawValue = payload
        }
        guard let tool = ToolName(rawValue: rawValue),
              PartCreationDefaults.toolSpec(for: tool.rawValue) != nil else {
            return nil
        }
        return tool
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
        case .musicPlayer, .pianoKeyboard, .stepSequencer, .musicMixer:
            return "You can choose a stack-contained Hype music pattern, instrument, tempo, looping behavior, volume, attach scripts, and store generated audio inside the stack."
        case .appleMusicBrowser:
            return "You can search Apple Music, choose songs, albums, singers, or playlists, play or stop playback, seek through a song, store selected IDs in the stack, and attach scripts."
        case .musicQueue:
            return "Legacy queue controls remain readable in older stacks. New stacks should use AudioKit controls for stack-contained music and MusicKit Search for Apple Music lookup."
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
