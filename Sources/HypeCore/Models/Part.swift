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
    /// Rotation in degrees, clockwise, applied around the part's
    /// centre. Settable and readable via HypeTalk as
    /// `the rotation of <part>` / `set the rotation of <part> to N`.
    ///
    /// Currently only honoured by the shape and image renderers —
    /// rotating buttons, fields, and other interactive parts
    /// would break hit-testing and native-control overlays so
    /// those types ignore the value. The field still lives on
    /// every Part for uniform get/set, and `0` (the default) is
    /// equivalent to "not rotated".
    public var rotation: Double

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
    // Deprecated: `family` is kept for backward compatibility with
    // older .hype documents but is no longer used by any renderer
    // or click handler.
    public var family: Int
    /// Newline-separated list of items for popup buttons. First item is the selected value.
    public var popupItems: String

    // Field-specific
    public var fieldStyle: FieldStyle
    public var lockText: Bool
    public var dontWrap: Bool
    public var wideMargins: Bool
    public var richText: Bool
    /// Whether the enterKey event is enabled for this field.
    public var enterKeyEnabled: Bool
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

    // Video-specific
    public var videoURL: String

    // Chart-specific
    public var chartData: String  // JSON-encoded ChartConfig

    // Image-specific
    public var imageData: Data?
    public var invertOnClick: Bool
    /// When the part's image is an animated GIF, controls whether
    /// playback starts automatically. Ignored for static JPEG/PNG.
    /// Defaults to `true` so newly added GIFs animate without
    /// explicit opt-in.
    public var animated: Bool
    /// When `true`, the renderer treats the image's dominant
    /// corner-pixel color as transparent (alpha=0) so whatever is
    /// behind the image shows through. Useful for JPGs and indexed
    /// GIFs whose "background" is a solid color rather than
    /// genuine alpha.
    ///
    /// PNGs with a real alpha channel always honor that channel
    /// regardless of this flag — so a PNG with semi-transparent
    /// edges still draws correctly when this is `false`.
    ///
    /// Default `false` so newly added images render exactly as
    /// they did before this property existed (and as their pixel
    /// data dictates).
    public var transparentBackground: Bool

    // SpriteKit scene-specific
    public var sceneSpec: String  // JSON-encoded SceneSpec or SpriteAreaSpec

    // Calendar-specific
    /// Currently-selected date as ISO 8601 (yyyy-MM-dd). Empty
    /// string means no date selected — the underlying NSDatePicker
    /// will fall back to today's date for display purposes only.
    public var selectedDate: String
    /// Visible month as ISO 8601 (yyyy-MM-01). Empty = follow
    /// `selectedDate`. Lets a user navigate the calendar without
    /// changing the selection.
    public var displayMonth: String
    /// Earliest date the user may pick, ISO 8601. Empty = no min.
    public var minDate: String
    /// Latest date the user may pick, ISO 8601. Empty = no max.
    public var maxDate: String
    /// Visual style: "graphical" (month grid, default), "textual"
    /// (compact text + stepper), "clockAndCalendar" (graphical
    /// month + analog clock).
    public var calendarStyle: String

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
        self.rotation = 0
        self.visible = true
        self.enabled = true
        self.hilite = false
        self.autoHilite = true
        self.textContent = ""
        self.textFont = "Apple Braille"
        self.textSize = 14
        self.textStyle = "plain"
        self.textAlign = (partType == .field) ? .left : .center
        self.buttonStyle = .default
        self.showName = true
        self.iconId = nil
        self.family = 0
        self.popupItems = ""
        self.fieldStyle = .rectangle
        self.lockText = false
        self.dontWrap = false
        self.wideMargins = false
        self.richText = false
        self.enterKeyEnabled = false
        self.htmlContent = ""
        self.shapeType = .rectangle
        self.fillColor = "#FFFFFF"
        self.strokeColor = "#000000"
        self.strokeWidth = 1
        self.cornerRadius = 8
        self.pathData = []
        self.url = partType == .webpage ? "http://" : ""
        self.urlSourceFieldId = nil
        self.videoURL = ""
        self.chartData = ""
        self.imageData = nil
        self.invertOnClick = false
        self.animated = true
        self.transparentBackground = false
        self.sceneSpec = ""
        self.selectedDate = ""
        self.displayMonth = ""
        self.minDate = ""
        self.maxDate = ""
        self.calendarStyle = "graphical"
        self.script = ""
    }

    // Custom decoder for backward compatibility with documents lacking enterKeyEnabled.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        partType = try container.decode(PartType.self, forKey: .partType)
        cardId = try container.decodeIfPresent(UUID.self, forKey: .cardId)
        backgroundId = try container.decodeIfPresent(UUID.self, forKey: .backgroundId)
        name = try container.decode(String.self, forKey: .name)
        sortKey = try container.decode(String.self, forKey: .sortKey)
        left = try container.decode(Double.self, forKey: .left)
        top = try container.decode(Double.self, forKey: .top)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        // `rotation` was added after the initial Part schema —
        // accept missing values and default to 0 so older .hype
        // files still load.
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        visible = try container.decode(Bool.self, forKey: .visible)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        hilite = try container.decode(Bool.self, forKey: .hilite)
        autoHilite = try container.decode(Bool.self, forKey: .autoHilite)
        textContent = try container.decode(String.self, forKey: .textContent)
        textFont = try container.decode(String.self, forKey: .textFont)
        textSize = try container.decode(Double.self, forKey: .textSize)
        textStyle = try container.decode(String.self, forKey: .textStyle)
        textAlign = try container.decode(TextAlignment.self, forKey: .textAlign)
        buttonStyle = try container.decode(ButtonStyle.self, forKey: .buttonStyle)
        showName = try container.decode(Bool.self, forKey: .showName)
        iconId = try container.decodeIfPresent(UUID.self, forKey: .iconId)
        family = try container.decode(Int.self, forKey: .family)
        popupItems = try container.decodeIfPresent(String.self, forKey: .popupItems) ?? ""
        fieldStyle = try container.decode(FieldStyle.self, forKey: .fieldStyle)
        lockText = try container.decode(Bool.self, forKey: .lockText)
        dontWrap = try container.decode(Bool.self, forKey: .dontWrap)
        wideMargins = try container.decode(Bool.self, forKey: .wideMargins)
        richText = try container.decode(Bool.self, forKey: .richText)
        enterKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .enterKeyEnabled) ?? false
        htmlContent = try container.decode(String.self, forKey: .htmlContent)
        shapeType = try container.decode(ShapeType.self, forKey: .shapeType)
        fillColor = try container.decode(String.self, forKey: .fillColor)
        strokeColor = try container.decode(String.self, forKey: .strokeColor)
        strokeWidth = try container.decode(Double.self, forKey: .strokeWidth)
        cornerRadius = try container.decode(Double.self, forKey: .cornerRadius)
        pathData = try container.decode([PathPoint].self, forKey: .pathData)
        url = try container.decode(String.self, forKey: .url)
        urlSourceFieldId = try container.decodeIfPresent(UUID.self, forKey: .urlSourceFieldId)
        videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL) ?? ""
        chartData = try container.decodeIfPresent(String.self, forKey: .chartData) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        invertOnClick = try container.decodeIfPresent(Bool.self, forKey: .invertOnClick) ?? false
        // `animated` was added after the initial Part schema —
        // accept missing values and default to true so older .hype
        // files still load and GIFs animate automatically.
        animated = try container.decodeIfPresent(Bool.self, forKey: .animated) ?? true
        // Backward-compatible: pre-transparent-background documents
        // default this flag to false so existing images render the
        // same way they did before the feature shipped.
        transparentBackground = try container.decodeIfPresent(Bool.self, forKey: .transparentBackground) ?? false
        sceneSpec = try container.decodeIfPresent(String.self, forKey: .sceneSpec) ?? ""
        // Calendar fields — added later, all backward-compat optional.
        selectedDate = try container.decodeIfPresent(String.self, forKey: .selectedDate) ?? ""
        displayMonth = try container.decodeIfPresent(String.self, forKey: .displayMonth) ?? ""
        minDate = try container.decodeIfPresent(String.self, forKey: .minDate) ?? ""
        maxDate = try container.decodeIfPresent(String.self, forKey: .maxDate) ?? ""
        calendarStyle = try container.decodeIfPresent(String.self, forKey: .calendarStyle) ?? "graphical"
        script = try container.decode(String.self, forKey: .script)
    }
}
