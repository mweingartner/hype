import Foundation
import HypeCore
import Testing
@testable import Hype

@Suite("Object tool catalog")
struct ObjectToolCatalogTests {
    @Test("left panel exposes one canonical creation tool per supported part type")
    func leftPanelHasOneCreationToolPerPartType() throws {
        let expectedOrder = [
            "button", "field", "shape", "image", "webpage", "video", "chart",
            "calendar", "pdf", "map", "colorWell", "audioRecorder",
            "musicPlayer", "pianoKeyboard", "stepSequencer", "musicMixer",
            "scene3D", "spriteArea",
            "stepper", "slider", "segmented", "progressView", "gauge", "divider",
        ]
        #expect(ObjectToolCatalog.creationTools.map(\.rawValue) == expectedOrder)

        var toolByPartType: [String: String] = [:]
        for tool in ObjectToolCatalog.creationTools {
            let partType = try #require(ObjectToolCatalog.createdPartType(for: tool))
            #expect(toolByPartType[partType.rawValue] == nil, "duplicate creation entry for part type \(partType.rawValue)")
            toolByPartType[partType.rawValue] = tool.rawValue
        }

        #expect(toolByPartType.keys.sorted() == expectedOrder.sorted())
        #expect(ObjectToolCatalog.basicTools.filter { ObjectToolCatalog.createdPartType(for: $0) == .field }.count == 1)
        #expect(ObjectToolCatalog.basicTools.filter { ObjectToolCatalog.createdPartType(for: $0) == .shape }.count == 1)
    }

    @Test("left panel combines basic and form controls under Objects without duplicates")
    func leftPanelCombinesObjectsAndFormControls() throws {
        let sectionTitles = ObjectToolCatalog.authoringSections.map(\.title)
        #expect(sectionTitles == ["Select", "Objects", "Framework", "Paint"])
        #expect(!sectionTitles.contains("Form"))

        let objectsSection = try #require(ObjectToolCatalog.authoringSections.first { $0.title == "Objects" })
        #expect(objectsSection.tools == ObjectToolCatalog.basicTools + ObjectToolCatalog.formControlTools)
        #expect(objectsSection.tools.contains(.field))
        #expect(objectsSection.tools.contains(.stepper))
        #expect(objectsSection.tools.contains(.progressView))

        let panelTools = ObjectToolCatalog.panelTools
        #expect(Set(panelTools).count == panelTools.count, "left panel must not expose duplicate tool buttons")
    }

    @Test("legacy duplicate object tools are absent from the panel catalog")
    func legacyDuplicateToolsAreAbsent() {
        let panelToolNames = Set(ObjectToolCatalog.panelTools.map(\.rawValue))
        let removedAliases = ["text", "rect", "oval", "line", "toggle", "link", "menu", "searchField"]

        for alias in removedAliases {
            #expect(!panelToolNames.contains(alias), "\(alias) must be a style/property, not a separate panel tool")
        }
    }

    @Test("every left panel tool exposes hover help")
    func everyPanelToolExposesHoverHelp() {
        for tool in ObjectToolCatalog.panelTools {
            let tooltip = ObjectToolCatalog.tooltipBody(for: tool)
            #expect(!tool.displayTitle.isEmpty)
            #expect(!tool.description.isEmpty)
            #expect(!tooltip.isEmpty, "\(tool.rawValue) must provide hover help text")
            #expect(tooltip.contains(tool.description), "\(tool.rawValue) hover help must include the tool description")
        }
    }

    @Test("creation tools expose user-friendly guidance")
    func creationToolsExposeUserFriendlyGuidance() {
        for tool in ObjectToolCatalog.creationTools {
            let tooltip = ObjectToolCatalog.tooltipBody(for: tool)
            #expect(!tooltip.isEmpty)
            #expect(tooltip.contains("You can") || tooltip.contains("Common styles:"), "\(tool.rawValue) must explain what users can do with it")
        }

        let fieldStyleSummary = ObjectToolCatalog.styleSummary(for: .field) ?? ""
        #expect(fieldStyleSummary.contains("transparent labels"))
        #expect(fieldStyleSummary.contains("search boxes"))
        #expect(fieldStyleSummary.contains("password-style entry"))

        let shapeStyleSummary = ObjectToolCatalog.styleSummary(for: .shape) ?? ""
        #expect(shapeStyleSummary.contains("rounded rectangles"))
        #expect(shapeStyleSummary.contains("editable freeform shapes"))

        let buttonStyleSummary = ObjectToolCatalog.styleSummary(for: .button) ?? ""
        #expect(buttonStyleSummary.contains("toggles"))
        #expect(buttonStyleSummary.contains("checkboxes"))
        #expect(buttonStyleSummary.contains("pop-up menus"))
    }

    @Test("hover help does not expose implementation details")
    func hoverHelpDoesNotExposeImplementationDetails() {
        let forbiddenTerms = [
            "WebKit", "PDFKit", "MapKit", "MKMapView", "AVKit", "AVFoundation",
            "SceneKit", "SpriteKit", "SwiftUI", "NSDatePicker", "NSColorWell",
            "NSStepper", "NSSlider", "NSSegmentedControl", "CoreImage",
            "AudioKit", "FileManager", "Key properties:", "textContent", "pdfURL",
            "mapCenterLat", "audioOutputPath", "scene3DSourceURL"
        ]

        for tool in ObjectToolCatalog.panelTools {
            let tooltip = ObjectToolCatalog.tooltipBody(for: tool)
            for term in forbiddenTerms {
                #expect(!tooltip.contains(term), "\(tool.rawValue) hover help must not expose \(term)")
            }
        }
    }

    @Test("Objects menu does not reintroduce duplicate field or shape creation commands")
    func objectsMenuHasOnlyCanonicalCreationCommands() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Hype/Views/GoMenuCommands.swift"), encoding: .utf8)

        #expect(!source.contains("Button(\"Text Annotation\")"))
        #expect(!source.contains("Button(\"Rectangle\")"))
        #expect(!source.contains("Button(\"Oval\")"))
        #expect(!source.contains("Button(\"Line\")"))
        #expect(source.contains("Button(\"Field\")"))
        #expect(source.contains("Button(\"Shape\")"))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
