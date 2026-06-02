import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Shared authoring-grid behavior for card and background layout editing.
///
/// These helpers intentionally update absolute part geometry only. Persisted
/// `LayoutConstraint` values are created by explicit constraint-authoring UI,
/// not by ordinary snapping during create/move/resize gestures.
public enum LayoutGrid {
    public static let spacing: Double = 8
    public static let standardNudge: Double = 8
    public static let fineNudge: Double = 1
    public static let explicitCreationDragThreshold: Double = 8
    public static let canvasMargin: Double = 20

    public static func snap(_ value: Double, enabled: Bool = true, spacing: Double = spacing) -> Double {
        guard enabled, spacing > 0 else { return value }
        return (value / spacing).rounded() * spacing
    }

    public static func snapDelta(for value: Double, enabled: Bool = true, spacing: Double = spacing) -> Double {
        snap(value, enabled: enabled, spacing: spacing) - value
    }

    public static func snappedSize(_ value: Double, minimum: Double = 10, enabled: Bool = true) -> Double {
        max(minimum, snap(value, enabled: enabled))
    }
}

public struct PartDefaultSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct PartCreationToolSpec: Equatable, Sendable {
    public var partType: PartType
    public var extras: [String: String]

    public init(partType: PartType, extras: [String: String] = [:]) {
        self.partType = partType
        self.extras = extras
    }
}

/// Centralized creation metadata for the object palette, menu commands, and
/// mouse-handler tests.
public enum PartCreationDefaults {
    public static func toolSpec(for toolName: String) -> PartCreationToolSpec? {
        switch toolName {
        case "button": return PartCreationToolSpec(partType: .button)
        case "field": return PartCreationToolSpec(partType: .field)
        case "shape": return PartCreationToolSpec(partType: .shape, extras: ["shapeType": "rectangle"])
        case "webpage": return PartCreationToolSpec(partType: .webpage)
        case "image": return PartCreationToolSpec(partType: .image)
        case "video": return PartCreationToolSpec(partType: .video)
        case "chart": return PartCreationToolSpec(partType: .chart)
        case "spriteArea": return PartCreationToolSpec(partType: .spriteArea)
        case "calendar": return PartCreationToolSpec(partType: .calendar)
        case "pdf": return PartCreationToolSpec(partType: .pdf)
        case "map": return PartCreationToolSpec(partType: .map)
        case "colorWell": return PartCreationToolSpec(partType: .colorWell)
        case "stepper": return PartCreationToolSpec(partType: .stepper)
        case "slider": return PartCreationToolSpec(partType: .slider)
        case "segmented": return PartCreationToolSpec(partType: .segmented)
        case "audioRecorder": return PartCreationToolSpec(partType: .audioRecorder)
        case "musicPlayer": return PartCreationToolSpec(partType: .musicPlayer)
        case "pianoKeyboard": return PartCreationToolSpec(partType: .pianoKeyboard)
        case "stepSequencer": return PartCreationToolSpec(partType: .stepSequencer)
        case "musicMixer": return PartCreationToolSpec(partType: .musicMixer)
        case "appleMusicBrowser": return PartCreationToolSpec(partType: .appleMusicBrowser)
        case "scene3D": return PartCreationToolSpec(partType: .scene3D)
        case "progressView": return PartCreationToolSpec(partType: .progressView)
        case "gauge": return PartCreationToolSpec(partType: .gauge)
        case "divider": return PartCreationToolSpec(partType: .divider)
        default: return nil
        }
    }

    public static func defaultSize(for partType: PartType) -> PartDefaultSize {
        switch partType {
        case .button:
            return PartDefaultSize(width: 88, height: 24)
        case .field:
            return PartDefaultSize(width: 96, height: 22)
        case .slider:
            return PartDefaultSize(width: 96, height: 16)
        case .progressView:
            return PartDefaultSize(width: 96, height: 14)
        case .spriteArea, .scene3D, .pdf, .map:
            return PartDefaultSize(width: 320, height: 240)
        case .calendar:
            return PartDefaultSize(width: 320, height: 260)
        case .webpage, .video, .chart:
            return PartDefaultSize(width: 320, height: 180)
        case .image:
            return PartDefaultSize(width: 160, height: 120)
        case .shape:
            return PartDefaultSize(width: 120, height: 80)
        case .colorWell:
            return PartDefaultSize(width: 44, height: 24)
        case .stepper:
            return PartDefaultSize(width: 80, height: 22)
        case .segmented:
            return PartDefaultSize(width: 180, height: 24)
        case .audioRecorder:
            return PartDefaultSize(width: 220, height: 80)
        case .musicPlayer:
            return PartDefaultSize(width: 240, height: 72)
        case .pianoKeyboard:
            return PartDefaultSize(width: 320, height: 96)
        case .stepSequencer, .musicMixer, .appleMusicBrowser, .musicQueue:
            return PartDefaultSize(width: 320, height: 180)
        case .gauge:
            return PartDefaultSize(width: 160, height: 60)
        case .divider:
            return PartDefaultSize(width: 160, height: 8)
        case .toggle:
            return PartDefaultSize(width: 120, height: 18)
        case .link:
            return PartDefaultSize(width: 120, height: 24)
        case .menu:
            return PartDefaultSize(width: 140, height: 24)
        case .searchField:
            return PartDefaultSize(width: 160, height: 22)
        case .unknown:
            return PartDefaultSize(width: 120, height: 40)
        }
    }

    #if canImport(CoreGraphics)
    public static func creationRect(
        for partType: PartType,
        dragStart: CGPoint?,
        currentPoint: CGPoint,
        fineControl: Bool = false
    ) -> CGRect {
        if let dragStart {
            let dragWidth = abs(Double(currentPoint.x - dragStart.x))
            let dragHeight = abs(Double(currentPoint.y - dragStart.y))
            let isExplicitCustomRect = dragWidth >= LayoutGrid.explicitCreationDragThreshold
                && dragHeight >= LayoutGrid.explicitCreationDragThreshold

            if isExplicitCustomRect {
                let x = min(Double(dragStart.x), Double(currentPoint.x))
                let y = min(Double(dragStart.y), Double(currentPoint.y))
                let width = max(10, dragWidth)
                let height = max(10, dragHeight)
                return CGRect(
                    x: LayoutGrid.snap(x, enabled: !fineControl),
                    y: LayoutGrid.snap(y, enabled: !fineControl),
                    width: LayoutGrid.snappedSize(width, enabled: !fineControl),
                    height: LayoutGrid.snappedSize(height, enabled: !fineControl)
                )
            }
        }

        let defaultSize = defaultSize(for: partType)
        return CGRect(
            x: LayoutGrid.snap(Double(currentPoint.x), enabled: !fineControl),
            y: LayoutGrid.snap(Double(currentPoint.y), enabled: !fineControl),
            width: defaultSize.width,
            height: defaultSize.height
        )
    }
    #endif
}
