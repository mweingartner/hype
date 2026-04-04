import Foundation

/// A part on a card or background — button, field, shape, or webpage.
public struct Part: Identifiable, Codable, Sendable {
    public var id: UUID
    public var partType: PartType

    // Ownership (one must be set)
    public var cardId: UUID?
    public var backgroundId: UUID?

    // Identity
    public var name: String
    public var sortKey: String

    // Geometry
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double

    // State
    public var visible: Bool
    public var enabled: Bool
    public var hilite: Bool
    public var autoHilite: Bool

    // Text
    public var textContent: String
    public var textFont: String
    public var textSize: Double
    public var textStyle: String  // "plain", "bold", "italic", etc.
    public var textAlign: TextAlignment

    // Button-specific
    public var buttonStyle: ButtonStyle
    public var showName: Bool
    public var iconId: UUID?
    public var family: Int

    // Field-specific
    public var fieldStyle: FieldStyle
    public var lockText: Bool
    public var dontWrap: Bool
    public var wideMargins: Bool
    public var richText: Bool
    public var htmlContent: String

    // Shape-specific
    public var shapeType: ShapeType
    public var fillColor: String  // hex color
    public var strokeColor: String
    public var strokeWidth: Double
    public var cornerRadius: Double
    public var pathData: [PathPoint]

    // Webpage-specific
    public var url: String
    public var urlSourceFieldId: UUID?

    // Script
    public var script: String

    public init(
        id: UUID = UUID(),
        partType: PartType,
        cardId: UUID? = nil,
        backgroundId: UUID? = nil,
        name: String = "",
        sortKey: String = "a0",
        left: Double = 100,
        top: Double = 100,
        width: Double = 120,
        height: Double = 40
    ) {
        self.id = id
        self.partType = partType
        self.cardId = cardId
        self.backgroundId = backgroundId
        self.name = name
        self.sortKey = sortKey
        self.left = left
        self.top = top
        self.width = width
        self.height = height
        self.visible = true
        self.enabled = true
        self.hilite = false
        self.autoHilite = true
        self.textContent = ""
        self.textFont = "SF Pro"
        self.textSize = 14
        self.textStyle = "plain"
        self.textAlign = .center
        self.buttonStyle = .roundRect
        self.showName = true
        self.iconId = nil
        self.family = 0
        self.fieldStyle = .rectangle
        self.lockText = false
        self.dontWrap = false
        self.wideMargins = false
        self.richText = false
        self.htmlContent = ""
        self.shapeType = .rectangle
        self.fillColor = "#FFFFFF"
        self.strokeColor = "#000000"
        self.strokeWidth = 1
        self.cornerRadius = 8
        self.pathData = []
        self.url = ""
        self.urlSourceFieldId = nil
        self.script = ""
    }
}
