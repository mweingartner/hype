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

    // PDF-specific
    /// File path or HTTP URL of the PDF to display. Empty when no
    /// document is loaded — the renderer shows a placeholder.
    public var pdfURL: String
    /// 1-based page index currently shown by `PDFView`.
    public var pdfCurrentPage: Int
    /// Display mode: "single" (one page at a time), "continuous"
    /// (vertical scroll through all pages, default), "twoUp" (two
    /// pages side-by-side).
    public var pdfDisplayMode: String
    /// When true, `PDFView` autoScales each page to fit the part's
    /// rect. Defaults to true.
    public var pdfAutoScales: Bool

    // Map-specific
    /// Latitude of the map center, decimal degrees.
    public var mapCenterLat: Double
    /// Longitude of the map center, decimal degrees.
    public var mapCenterLon: Double
    /// Zoom level expressed as a span in degrees (smaller = more
    /// zoomed in). Default 0.05 ≈ city blocks.
    public var mapSpan: Double
    /// "standard" (street map, default), "satellite", "hybrid"
    /// (satellite + street labels), "mutedStandard".
    public var mapType: String
    /// JSON-encoded `[{lat, lon, title}]` annotations to drop on
    /// the map. Empty string means no annotations.
    public var mapAnnotationsJSON: String

    // ColorWell-specific
    /// Currently-bound color as a hex string (e.g. "#FF5500").
    public var colorWellHex: String
    /// Whether the well exposes the "Show Colors" picker on click
    /// (default true) — false makes it a static color swatch.
    public var colorWellInteractive: Bool

    // Form-control-shared (stepper, slider, toggle, segmented)
    /// Numeric value: stepper / slider position, 0|1 for toggle, or
    /// the 0-based selected segment index for segmented control.
    public var controlValue: Double
    /// Minimum bound for stepper / slider. Ignored by toggle and
    /// segmented.
    public var controlMin: Double
    /// Maximum bound for stepper / slider.
    public var controlMax: Double
    /// Stepper increment (and slider tick spacing when applicable).
    public var controlStep: Double
    /// Pipe-separated labels for segmented control (e.g.
    /// "Day|Week|Month"). Only meaningful when partType == .segmented.
    public var segmentItems: String

    // AudioRecorder-specific
    /// True while the recorder is actively capturing. Setting this
    /// to true via the AI / HypeTalk surface starts a recording;
    /// setting to false stops it. The host runtime reflects engine
    /// state back into the document so HypeTalk reads stay accurate.
    public var audioRecording: Bool
    /// Absolute path the recorder writes to. Empty = use a temp
    /// file under `FileManager.temporaryDirectory` named after the
    /// part. The path is captured at start-of-recording time.
    public var audioOutputPath: String
    /// Output format. "m4a" (AAC, default) or "caf" (LinearPCM in
    /// CoreAudio Format). m4a is what most users want — small files
    /// + native macOS playback.
    public var audioFormat: String
    /// Last-known recording duration in seconds. Updated ~10x/sec
    /// while recording so HypeTalk reads of `the duration of
    /// recorder "X"` reflect live progress without polling AVKit
    /// directly.
    public var audioDuration: Double

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
        self.pdfURL = ""
        self.pdfCurrentPage = 1
        self.pdfDisplayMode = "continuous"
        self.pdfAutoScales = true
        self.mapCenterLat = 37.7749
        self.mapCenterLon = -122.4194
        self.mapSpan = 0.05
        self.mapType = "standard"
        self.mapAnnotationsJSON = ""
        self.colorWellHex = "#FF5500"
        self.colorWellInteractive = true
        self.controlValue = 0
        self.controlMin = 0
        self.controlMax = 100
        self.controlStep = 1
        self.segmentItems = "First|Second|Third"
        self.audioRecording = false
        self.audioOutputPath = ""
        self.audioFormat = "m4a"
        self.audioDuration = 0
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
        // PDF fields — backward-compat optional.
        pdfURL = try container.decodeIfPresent(String.self, forKey: .pdfURL) ?? ""
        pdfCurrentPage = try container.decodeIfPresent(Int.self, forKey: .pdfCurrentPage) ?? 1
        pdfDisplayMode = try container.decodeIfPresent(String.self, forKey: .pdfDisplayMode) ?? "continuous"
        pdfAutoScales = try container.decodeIfPresent(Bool.self, forKey: .pdfAutoScales) ?? true
        // Map fields — backward-compat optional.
        mapCenterLat = try container.decodeIfPresent(Double.self, forKey: .mapCenterLat) ?? 37.7749
        mapCenterLon = try container.decodeIfPresent(Double.self, forKey: .mapCenterLon) ?? -122.4194
        mapSpan = try container.decodeIfPresent(Double.self, forKey: .mapSpan) ?? 0.05
        mapType = try container.decodeIfPresent(String.self, forKey: .mapType) ?? "standard"
        mapAnnotationsJSON = try container.decodeIfPresent(String.self, forKey: .mapAnnotationsJSON) ?? ""
        // ColorWell fields — backward-compat optional.
        colorWellHex = try container.decodeIfPresent(String.self, forKey: .colorWellHex) ?? "#FF5500"
        colorWellInteractive = try container.decodeIfPresent(Bool.self, forKey: .colorWellInteractive) ?? true
        // Form-control fields — backward-compat optional.
        controlValue = try container.decodeIfPresent(Double.self, forKey: .controlValue) ?? 0
        controlMin = try container.decodeIfPresent(Double.self, forKey: .controlMin) ?? 0
        controlMax = try container.decodeIfPresent(Double.self, forKey: .controlMax) ?? 100
        controlStep = try container.decodeIfPresent(Double.self, forKey: .controlStep) ?? 1
        segmentItems = try container.decodeIfPresent(String.self, forKey: .segmentItems) ?? "First|Second|Third"
        // AudioRecorder fields — backward-compat optional.
        audioRecording = try container.decodeIfPresent(Bool.self, forKey: .audioRecording) ?? false
        audioOutputPath = try container.decodeIfPresent(String.self, forKey: .audioOutputPath) ?? ""
        audioFormat = try container.decodeIfPresent(String.self, forKey: .audioFormat) ?? "m4a"
        audioDuration = try container.decodeIfPresent(Double.self, forKey: .audioDuration) ?? 0
        script = try container.decode(String.self, forKey: .script)
    }
}
