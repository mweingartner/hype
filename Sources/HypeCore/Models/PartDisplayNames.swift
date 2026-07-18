import Foundation

// MARK: - Display names (control-property-consistency, Decision 5)
//
// One source of truth for every user-facing rendering of a `PartType`
// or part-scoped enum's raw value. Every switch here is exhaustive
// with no `default` case, so the compiler forces this file to be
// updated the moment a new case is added anywhere in the model —
// closing off the class of bug the audit found (`.rawValue`,
// `.capitalized`, and ad-hoc string literals drifting out of sync
// across the Properties Inspector, HypeTalk docs, and the AI tools).
//
// Placed in HypeCore (not the app target) so the Inspector, exporters,
// and any future surface share exactly one mapping.

public extension PartType {
    /// The user-facing name for this part type — used by the
    /// Properties Inspector headline, its "Type" row, and anywhere
    /// else a part's kind is described to the author. Design-mock
    /// §2.1.
    var displayName: String {
        switch self {
        case .button: return "Button"
        case .field: return "Field"
        case .shape: return "Shape"
        case .webpage: return "Web Page"
        case .image: return "Image"
        case .video: return "Video"
        case .chart: return "Chart"
        case .spriteArea: return "Sprite Area"
        case .calendar: return "Calendar"
        case .pdf: return "PDF"
        case .map: return "Map"
        case .colorWell: return "Color Well"
        case .stepper: return "Stepper"
        case .slider: return "Slider"
        case .toggle: return "Toggle"
        case .segmented: return "Segmented Control"
        case .audioRecorder: return "Audio Recorder"
        case .scene3D: return "3D Scene"
        case .musicPlayer: return "Music Player"
        case .pianoKeyboard: return "Piano Keyboard"
        case .stepSequencer: return "Step Sequencer"
        case .musicMixer: return "Music Mixer"
        case .appleMusicBrowser: return "Apple Music Browser"
        case .musicQueue: return "Music Queue"
        case .progressView: return "Progress View"
        case .gauge: return "Gauge"
        case .link: return "Link"
        case .menu: return "Menu"
        case .searchField: return "Search Field"
        case .divider: return "Divider"
        case .unknown: return "Unknown"
        }
    }
}

public extension ButtonStyle {
    /// Design-mock §2.2 — picker order preserved; non-picker cases
    /// (`opaque`, `roundRect`) included for completeness so the
    /// switch stays exhaustive.
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .default: return "Default"
        case .shadow: return "Shadow"
        case .transparent: return "Transparent"
        case .oval: return "Oval"
        case .toggle: return "Toggle"
        case .link: return "Link"
        case .checkBox: return "Check Box"
        case .popup: return "Popup"
        case .radio: return "Radio"
        case .opaque: return "Opaque"
        case .roundRect: return "Round Rect"
        }
    }
}

public extension FieldStyle {
    /// Design-mock §2.2 — matches classic field-style vocabulary.
    var displayName: String {
        switch self {
        case .transparent: return "Transparent"
        case .rectangle: return "Rectangle"
        case .shadow: return "Shadow"
        case .scrolling: return "Scrolling"
        case .secure: return "Secure"
        case .search: return "Search"
        }
    }
}

public extension ShapeType {
    /// Design-mock §2.2.
    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .roundRect: return "Round Rect"
        case .oval: return "Oval"
        case .line: return "Line"
        case .freeform: return "Freeform"
        }
    }
}

public extension SpriteShapeType {
    /// Design-mock §2.2, corrected at Design Review: the sprite shape
    /// node's real cases are `rect, circle, ellipse, path`
    /// (`SceneSpec.swift:605`), not the part-level `ShapeType` list.
    /// "Ellipse" is deliberately NOT renamed "Oval" — the sprite layer
    /// distinguishes circle from ellipse as separate cases, and
    /// reusing the classic part word here would create a false
    /// cognate.
    var displayName: String {
        switch self {
        case .rect: return "Rectangle"
        case .circle: return "Circle"
        case .ellipse: return "Ellipse"
        case .path: return "Path"
        }
    }
}

public extension ChartType {
    /// Design-mock §2.2 — hand-written Title Case per case (no
    /// `.capitalized`), so adding a new chart type without an entry
    /// here fails to compile instead of silently rendering a
    /// lowercase raw value.
    var displayName: String {
        switch self {
        case .bar: return "Bar"
        case .line: return "Line"
        case .area: return "Area"
        case .point: return "Point"
        case .pie: return "Pie"
        case .rule: return "Rule"
        case .spider: return "Spider"
        }
    }
}

public extension SceneScaleMode {
    /// Design-mock §2.2 — hand-written Title Case per case.
    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .aspectFill: return "Aspect Fill"
        case .aspectFit: return "Aspect Fit"
        case .resizeFill: return "Resize Fill"
        }
    }
}
