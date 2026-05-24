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
            return "Styles: \(ButtonStyle.pickerCases.map(\.rawValue).joined(separator: ", "))."
        case .field:
            return "Styles: \(FieldStyle.allCases.map(\.rawValue).joined(separator: ", ")). Use transparent for text annotations and search for search-entry fields."
        case .shape:
            return "Styles: \(ShapeType.allCases.map(\.rawValue).joined(separator: ", "))."
        case .chart:
            return "Styles: \(ChartType.allCases.map(\.rawValue).joined(separator: ", "))."
        case .calendar:
            return "Styles: graphical, textual, clockAndCalendar."
        case .progressView:
            return "Styles: linear, circular, indeterminate."
        case .gauge:
            return "Styles: linear, circular."
        case .divider:
            return "Styles: horizontal, vertical."
        default:
            return nil
        }
    }

    static func propertySummary(for tool: ToolName) -> String? {
        switch tool {
        case .button:
            return "Key properties: script, style, textContent, showName, iconId, popupItems, autoHilite, url, helpText."
        case .field:
            return "Key properties: textContent, style, lockText, dontWrap, wideMargins, richText, enterKeyEnabled, textFont, textSize, textStyle, textAlign, fontColor, helpText."
        case .shape:
            return "Key properties: shapeType, fillColor, strokeColor, strokeWidth, cornerRadius, rotation, pathData, helpText."
        case .webpage:
            return "Key properties: url, urlSourceFieldId, helpText."
        case .image:
            return "Key properties: imageData, transparentBackground, invertOnClick, imageFilter, imageFilterIntensity, animated, helpText."
        case .video:
            return "Key properties: videoURL, helpText."
        case .chart:
            return "Key properties: chartData, chartType, title, series, helpText."
        case .spriteArea:
            return "Key properties: sceneSpec, activeScene, scenes, physics/debug flags, script, helpText."
        case .calendar:
            return "Key properties: selectedDate, displayMonth, minDate, maxDate, calendarStyle, helpText."
        case .pdf:
            return "Key properties: pdfURL, pdfCurrentPage, pdfDisplayMode, pdfAutoScales, helpText."
        case .map:
            return "Key properties: mapLocation, mapCenterLat, mapCenterLon, mapSpan, mapType, mapAnnotationsJSON, helpText."
        case .colorWell:
            return "Key properties: colorWellHex, colorWellInteractive, script, helpText."
        case .stepper, .slider:
            return "Key properties: controlValue, controlMin, controlMax, controlStep, script, helpText."
        case .segmented:
            return "Key properties: segmentItems, controlValue, script, helpText."
        case .audioRecorder:
            return "Key properties: audioRecording, audioPlaying, audioOutputPath, audioFormat, audioDuration, script, helpText."
        case .scene3D:
            return "Key properties: scene3DSourceURL, scene3DAssetRef, modelURL, allowsCameraControl, autoLighting, antialiasing, background, helpText."
        case .progressView:
            return "Key properties: progressValue, progressTotal, progressIsCircular, progressIsIndeterminate, progressLabel, progressTint, progressDecimals, helpText."
        case .gauge:
            return "Key properties: gaugeValue, gaugeMin, gaugeMax, gaugeStyle, gaugeTint, gaugeLabel, gaugeMinLabel, gaugeMaxLabel, gaugeDecimals, helpText."
        case .divider:
            return "Key properties: dividerOrientation, dividerThickness, dividerColor, helpText."
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
