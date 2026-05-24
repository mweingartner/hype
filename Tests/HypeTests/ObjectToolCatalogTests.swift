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
            "calendar", "pdf", "map", "colorWell", "audioRecorder", "scene3D", "spriteArea",
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

    @Test("creation tools expose style and property guidance")
    func creationToolsExposeStyleAndPropertyGuidance() {
        for tool in ObjectToolCatalog.creationTools {
            let tooltip = ObjectToolCatalog.tooltipBody(for: tool)
            #expect(!tooltip.isEmpty)
            #expect(tooltip.contains("Key properties:"), "\(tool.rawValue) must document editable properties")
        }

        let fieldStyleSummary = ObjectToolCatalog.styleSummary(for: .field) ?? ""
        for style in FieldStyle.allCases {
            #expect(fieldStyleSummary.contains(style.rawValue), "Field tool must document \(style.rawValue) as a style")
        }
        #expect(fieldStyleSummary.contains("transparent for text annotations"))
        #expect(fieldStyleSummary.contains("search for search-entry fields"))

        let shapeStyleSummary = ObjectToolCatalog.styleSummary(for: .shape) ?? ""
        for style in ShapeType.allCases {
            #expect(shapeStyleSummary.contains(style.rawValue), "Shape tool must document \(style.rawValue) as a style")
        }

        let buttonStyleSummary = ObjectToolCatalog.styleSummary(for: .button) ?? ""
        for style in ButtonStyle.pickerCases {
            #expect(buttonStyleSummary.contains(style.rawValue), "Button tool must document \(style.rawValue) as a style")
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
