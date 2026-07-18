import Testing
import Foundation
@testable import HypeCore

// Tests for `control-property-consistency` Decision 5 — one
// `displayName` mapping per enum, shared by the Properties Inspector
// (P3), exporters, and any future surface. Every switch in
// `PartDisplayNames.swift` is exhaustive with no `default`, so a new
// case fails compilation before it can fail one of these tests; this
// suite instead pins the EXACT string design-mock §2.1/§2.2 specify,
// so a well-meaning rewording doesn't silently drift from the spec.

@Suite("PartType.displayName — design-mock §2.1 table")
struct PartTypeDisplayNameTests {
    @Test("every PartType case matches the §2.1 table exactly")
    func exactTable() {
        let expected: [PartType: String] = [
            .button: "Button", .field: "Field", .shape: "Shape", .webpage: "Web Page",
            .image: "Image", .video: "Video", .chart: "Chart", .spriteArea: "Sprite Area",
            .calendar: "Calendar", .pdf: "PDF", .map: "Map", .colorWell: "Color Well",
            .stepper: "Stepper", .slider: "Slider", .toggle: "Toggle", .segmented: "Segmented Control",
            .audioRecorder: "Audio Recorder", .scene3D: "3D Scene", .musicPlayer: "Music Player",
            .pianoKeyboard: "Piano Keyboard", .stepSequencer: "Step Sequencer", .musicMixer: "Music Mixer",
            .appleMusicBrowser: "Apple Music Browser", .musicQueue: "Music Queue",
            .progressView: "Progress View", .gauge: "Gauge", .link: "Link", .menu: "Menu",
            .searchField: "Search Field", .divider: "Divider", .unknown: "Unknown",
        ]
        for type in PartType.allCases {
            #expect(type.displayName == expected[type], "\(type) displayName mismatch")
        }
        // Every case in the enum has a table entry (and vice versa) —
        // catches a case silently missing from the fixture above.
        #expect(Set(expected.keys) == Set(PartType.allCases))
    }

    @Test("no rawValue.capitalized shape leaks through (e.g. multi-word types render two words)")
    func multiWordTypesAreNotJustCapitalizedRawValue() {
        #expect(PartType.spriteArea.displayName != PartType.spriteArea.rawValue.capitalized)
        #expect(PartType.colorWell.displayName != PartType.colorWell.rawValue.capitalized)
        #expect(PartType.musicPlayer.displayName != PartType.musicPlayer.rawValue.capitalized)
        #expect(PartType.audioRecorder.displayName != PartType.audioRecorder.rawValue.capitalized)
        #expect(PartType.scene3D.displayName != PartType.scene3D.rawValue.capitalized)
    }
}

@Suite("Enum-case displayName — design-mock §2.2 tables")
struct EnumCaseDisplayNameTests {
    @Test("ButtonStyle matches the §2.2 table exactly")
    func buttonStyle() {
        let expected: [ButtonStyle: String] = [
            .standard: "Standard", .default: "Default", .shadow: "Shadow", .transparent: "Transparent",
            .oval: "Oval", .toggle: "Toggle", .link: "Link", .checkBox: "Check Box",
            .popup: "Popup", .radio: "Radio", .opaque: "Opaque", .roundRect: "Round Rect",
        ]
        for style in ButtonStyle.allCases {
            #expect(style.displayName == expected[style], "\(style) displayName mismatch")
        }
        #expect(Set(expected.keys) == Set(ButtonStyle.allCases))
    }

    @Test("FieldStyle matches the §2.2 table exactly")
    func fieldStyle() {
        let expected: [FieldStyle: String] = [
            .transparent: "Transparent", .rectangle: "Rectangle", .shadow: "Shadow",
            .scrolling: "Scrolling", .secure: "Secure", .search: "Search",
        ]
        for style in FieldStyle.allCases {
            #expect(style.displayName == expected[style], "\(style) displayName mismatch")
        }
        #expect(Set(expected.keys) == Set(FieldStyle.allCases))
    }

    @Test("ShapeType matches the §2.2 table exactly")
    func shapeType() {
        let expected: [ShapeType: String] = [
            .rectangle: "Rectangle", .roundRect: "Round Rect", .oval: "Oval",
            .line: "Line", .freeform: "Freeform",
        ]
        for type in ShapeType.allCases {
            #expect(type.displayName == expected[type], "\(type) displayName mismatch")
        }
        #expect(Set(expected.keys) == Set(ShapeType.allCases))
    }

    @Test("SpriteShapeType uses its real cases (rect/circle/ellipse/path) — Design Review erratum fix")
    func spriteShapeType() {
        let expected: [SpriteShapeType: String] = [
            .rect: "Rectangle", .circle: "Circle", .ellipse: "Ellipse", .path: "Path",
        ]
        for type in SpriteShapeType.allCases {
            #expect(type.displayName == expected[type], "\(type) displayName mismatch")
        }
        #expect(Set(expected.keys) == Set(SpriteShapeType.allCases))
        // The Review's explicit "not a false cognate" call-out: circle and
        // ellipse must stay visually distinct words, never both "Oval".
        #expect(SpriteShapeType.circle.displayName != SpriteShapeType.ellipse.displayName)
        #expect(SpriteShapeType.ellipse.displayName == "Ellipse")
    }

    @Test("ChartType matches the §2.2 table exactly (hand-written, not .capitalized)")
    func chartType() {
        let expected: [ChartType: String] = [
            .bar: "Bar", .line: "Line", .area: "Area", .point: "Point",
            .pie: "Pie", .rule: "Rule", .spider: "Spider",
        ]
        for type in ChartType.allCases {
            #expect(type.displayName == expected[type], "\(type) displayName mismatch")
        }
        #expect(Set(expected.keys) == Set(ChartType.allCases))
    }

    @Test("SceneScaleMode matches the §2.2 table exactly (hand-written, not .capitalized)")
    func sceneScaleMode() {
        let expected: [SceneScaleMode: String] = [
            .fill: "Fill", .aspectFill: "Aspect Fill", .aspectFit: "Aspect Fit", .resizeFill: "Resize Fill",
        ]
        for mode in SceneScaleMode.allCases {
            #expect(mode.displayName == expected[mode], "\(mode) displayName mismatch")
        }
        #expect(Set(expected.keys) == Set(SceneScaleMode.allCases))
    }
}
