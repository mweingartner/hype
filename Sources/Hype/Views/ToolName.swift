import Foundation

public enum ToolName: String, CaseIterable, Sendable {
    case browse, button, field, shape, webpage, image, video, chart, spriteArea
    case calendar, pdf, map, colorWell
    case stepper, slider, toggle, segmented, audioRecorder, scene3D
    case progressView, gauge, link, menu, searchField, divider
    case select
    case pencil, line, rect, oval, spray, bucket, eraser, text

    /// Human-readable title for the fly-out info window.
    var displayTitle: String {
        switch self {
        case .browse: return "Browse"
        case .button: return "Button"
        case .field: return "Field"
        case .shape: return "Shape"
        case .webpage: return "Web Page"
        case .image: return "Image"
        case .video: return "Video"
        case .chart: return "Chart"
        case .spriteArea: return "Sprite Area"
        case .calendar: return "Calendar"
        case .pdf: return "PDF Viewer"
        case .map: return "Map"
        case .colorWell: return "Color Well"
        case .stepper: return "Stepper"
        case .slider: return "Slider"
        case .toggle: return "Toggle"
        case .segmented: return "Segmented Control"
        case .audioRecorder: return "Audio Recorder"
        case .scene3D: return "3D Scene"
        case .progressView: return "Progress View"
        case .gauge: return "Gauge"
        case .link: return "Link"
        case .menu: return "Menu"
        case .searchField: return "Search Field"
        case .divider: return "Divider"
        case .select: return "Select"
        case .pencil: return "Pencil"
        case .line: return "Line"
        case .rect: return "Rectangle"
        case .oval: return "Oval"
        case .spray: return "Spray"
        case .bucket: return "Bucket Fill"
        case .eraser: return "Eraser"
        case .text: return "Text Annotation"
        }
    }

    /// Detailed description shown in the fly-out info window when
    /// the user hovers a tool button. Should describe what the tool
    /// creates (or what action it performs in browse / paint mode)
    /// in 2-3 sentences. Quoted forms reference HypeTalk reads.
    var description: String {
        switch self {
        case .browse:
            return "Default mode for navigating cards and clicking buttons. Switch to Browse when you want to interact with the stack as an end user would, without selecting parts for editing."
        case .button:
            return "Click-and-drag to draw a button. Buttons fire mouseUp / mouseDown handlers, can navigate cards (\"go next\"), trigger handlers, or run any HypeTalk script. The most common interactive control."
        case .field:
            return "Click-and-drag to draw a text field. Fields hold editable or locked text, support multi-line content, and emit closeField when their content changes. Read with `the textContent of field \"name\"`."
        case .shape:
            return "Draws a vector shape (rectangle, oval, etc.). Configure fillColor, strokeColor, strokeWidth, and cornerRadius from the inspector. Useful for backdrops, dividers, and custom layout decoration."
        case .webpage:
            return "Embeds a live WebKit view inside the card. Set its URL via the inspector or HypeTalk: `set the url of webpage \"X\" to \"https://...\"`. Renders any web content the system browser supports."
        case .image:
            return "Draws an image part. Supports PNG/JPEG/GIF (animated). Optional chroma-key transparency lifts a solid background out of JPEGs. CoreImage filters (sepia, blur, vignette, etc.) can be applied at render time."
        case .video:
            return "Embeds an AVKit video player. Set videoURL via the inspector or HypeTalk. Plays MP4/MOV/QuickTime formats with native controls (play/pause/scrub)."
        case .chart:
            return "Embeds a Swift Charts chart (bar / line / area / point / pie). Configure data via the AI tool `create_chart` or by editing the chart's JSON spec. Live-updating from script writes."
        case .spriteArea:
            return "A SpriteKit-powered area for 2D physics, animation, and game-style content. Hosts named sprite scenes with nodes, joints, constraints, and physics fields. Author scenes from the AI panel or HypeTalk."
        case .calendar:
            return "An NSDatePicker-backed calendar. The user picks dates; HypeTalk reads `the selectedDate of calendar \"name\"` (ISO 8601). Supports min/max bounds and three styles (graphical / textual / clockAndCalendar)."
        case .pdf:
            return "A PDFKit-powered viewer for PDF documents. Loads from file paths or http(s) URLs. Programmatic page navigation via `set the currentPage of pdf \"name\" to N`."
        case .map:
            return "An MKMapView for displaying maps with annotations. Set center coordinates, zoom span, and map type (standard / satellite / hybrid). Drop pins via the AI `add_map_annotation` tool."
        case .colorWell:
            return "An NSColorWell for picking colors. Click opens the macOS color panel; the picked color is read via `the color of colorWell \"name\"` (hex string). Fires colorChanged on user picks."
        case .stepper:
            return "An NSStepper with optional min/max/step bounds. User clicks ▲/▼ to adjust the value; HypeTalk reads `the value of stepper \"name\"`. Fires valueChanged on each change."
        case .slider:
            return "An NSSlider with continuous tracking. valueChanged fires during drag (not just on release). Set min/max bounds via the inspector or AI tool. Read with `the value of slider \"name\"`."
        case .toggle:
            return "An NSSwitch (on/off toggle). Read state with `the on of toggle \"name\"` (returns true/false). Fires valueChanged when the user flips it."
        case .segmented:
            return "An NSSegmentedControl for selecting one of N labeled options. Configure labels with `set the segments of segmented \"X\" to \"Day|Week|Month\"`. Read selection with `the selectedSegment of segmented \"name\"`."
        case .audioRecorder:
            return "An AVFoundation recorder. Setting `the recording of recorder \"X\"` to true starts capturing from the mic; false stops. Live duration updates 10×/sec; output written to m4a or CAF. Fires recordingStarted / recordingStopped."
        case .scene3D:
            return "A SceneKit view that loads .usdz / .scn / .dae / .obj 3D models. Camera control (orbit / zoom) on by default. Set `the modelURL of scene3d \"name\"` to load a model from disk or URL."
        case .progressView:
            return "A linear or circular progress indicator. Supports determinate (value/total) and indeterminate spinning modes. Fires progressFinished when value reaches total."
        case .gauge:
            return "A SwiftUI Gauge showing a value within a min/max range. Supports circular and linear styles with optional tint color, center label, and min/max axis labels."
        case .link:
            return "A clickable text link that opens a URL in the default browser. Supports http, https, and mailto schemes. Fires linkOpened after the browser launches."
        case .menu:
            return "A popup button menu. Items are defined as newline-separated \"Label||script\" pairs. Fires menuItemSelected with the chosen label, and runs the per-item script if one is provided."
        case .searchField:
            return "An NSSearchField with placeholder text. When searchSendsImmediately is true, fires searchChanged (debounced) as the user types. Always fires searchSubmitted on Return."
        case .divider:
            return "A visual separator line. Can be horizontal or vertical with configurable thickness and color. No interaction — purely decorative layout element."
        case .select:
            return "Selection / move tool. Click a part to select it; drag to move; shift-click to extend the selection. Use the inspector on the right to edit the selected part's properties."
        case .pencil:
            return "Free-form pencil drawing onto the card's paint layer. Adjust the brush size with [ and ] keys. Choose color from the status-bar color picker."
        case .line:
            return "Click-drag to draw a straight-line shape part. Held Shift constrains to 0/45/90°."
        case .rect:
            return "Click-drag to create a rectangle Shape part (vector, movable, scriptable). Pulls fill/stroke colors from the active theme. For raster paint, use Pencil + Bucket instead."
        case .oval:
            return "Click-drag to create an oval Shape part (vector, movable, scriptable). Pulls fill/stroke colors from the active theme. For raster paint, use Pencil + Bucket instead."
        case .spray:
            return "Spray-paint scattering of pixels onto the paint layer. Hold mouse longer for denser fill."
        case .bucket:
            return "Flood-fill the paint layer at the click point. Replaces the contiguous color region under the cursor with the active paint color."
        case .eraser:
            return "Click-drag to erase paint-layer pixels. Adjust eraser size with [ and ] keys."
        case .text:
            return "Click to drop a transparent text annotation field at that point. The result is a regular Field part — for editable text, use the Field tool to draw a sized field instead."
        }
    }

    var systemImageName: String {
        switch self {
        case .browse: return "hand.point.up"
        case .button: return "rectangle"
        case .field: return "text.alignleft"
        case .shape: return "diamond"
        case .webpage: return "globe"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .chart: return "chart.bar"
        case .spriteArea: return "gamecontroller"
        case .calendar: return "calendar"
        case .pdf: return "doc.richtext"
        case .map: return "map"
        case .colorWell: return "paintpalette"
        case .stepper: return "plus.slash.minus"
        case .slider: return "slider.horizontal.3"
        case .toggle: return "switch.2"
        case .segmented: return "rectangle.split.3x1"
        case .audioRecorder: return "mic.circle"
        case .scene3D: return "cube.transparent"
        case .progressView: return "chart.bar.xaxis"
        case .gauge: return "gauge"
        case .link: return "link"
        case .menu: return "list.bullet.rectangle"
        case .searchField: return "magnifyingglass"
        case .divider: return "minus"
        case .select: return "cursor.rays"
        case .pencil: return "pencil"
        case .line: return "line.diagonal"
        case .rect: return "rectangle.portrait"
        case .oval: return "circle"
        case .spray: return "aqi.medium"
        case .bucket: return "drop"
        case .eraser: return "eraser"
        case .text: return "textformat"
        }
    }
}
