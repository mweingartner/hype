import Foundation

/// All tools available to the AI for interacting with Hype.
public struct HypeToolDefinitions {

    /// The complete set of tools the AI can invoke.
    public static let allTools: [OllamaTool] = [
        // Stack management
        makeTool(name: "create_card", description: "Create a new card in the stack. Optionally specify a background name.", params: [
            "background_name": ("string", "Name of background to use (optional)", false),
        ]),
        makeTool(name: "create_background", description: "Create a new named background that can be shared by multiple cards.", params: [
            "name": ("string", "Unique name for the background", true),
        ]),
        makeTool(name: "go_to_card", description: "Navigate to a card by name, number, or direction (next, previous, first, last).", params: [
            "destination": ("string", "Card name, card number (e.g. 4), or direction: next, previous, first, last", true),
        ]),
        makeTool(name: "delete_card", description: "Delete the current card.", params: [:]),

        // Part creation
        makeTool(name: "create_button", description: "Create a button on the current card or its background. Set on_background to true to place on the background (shared across all cards with that background). The script should be a HypeTalk command like 'go next' — it will be auto-wrapped in 'on mouseUp / end mouseUp'.", params: [
            "name": ("string", "Button name/label", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "style": ("string", "Button style: roundRect, rectangle, default, oval, shadow, checkBox, toggle, popup", false),
            "script": ("string", "HypeTalk command(s) for the button, e.g. 'go next' — auto-wrapped in on mouseUp", false),
            "on_background": ("string", "Set to 'true' to place on the card's background (shared across cards)", false),
        ]),
        makeTool(name: "create_field", description: "Create a text field on the current card or its background. Set on_background to true to place on the background.", params: [
            "name": ("string", "Field name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "text": ("string", "Default text content", false),
            "style": ("string", "Field style: rectangle, scrolling, shadow, transparent, opaque", false),
            "fill_color": ("string", "Fill color hex, e.g. #FFFFFF", false),
            "stroke_color": ("string", "Border/stroke color hex, e.g. #000000", false),
            "stroke_width": ("string", "Border/stroke width in points. Use 0 for no border.", false),
            "text_font": ("string", "Font name", false),
            "text_size": ("string", "Text size in points", false),
            "text_align": ("string", "Text alignment: left, center, right", false),
            "lock_text": ("string", "Set to 'true' for read-only label/display fields", false),
            "show_name": ("string", "Set to 'false' to hide the field name in renderers that show names", false),
            "script": ("string", "HypeTalk script to attach", false),
            "on_background": ("string", "Set to 'true' to place on the card's background (shared across cards)", false),
        ]),
        makeTool(name: "create_label", description: "Create a basic card/background label using a locked transparent field. Use this for form labels and headers; do not create a SpriteKit label unless the user explicitly asked for a sprite scene.", params: [
            "name": ("string", "Label part name", true),
            "text": ("string", "Label text to display", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "text_size": ("string", "Text size in points", false),
            "text_align": ("string", "Text alignment: left, center, right", false),
            "text_font": ("string", "Font name", false),
            "on_background": ("string", "Set to 'true' to place on the card's background", false),
        ]),
        makeTool(name: "create_shape", description: "Create a shape on the current card or its background. Set on_background to true for background placement.", params: [
            "name": ("string", "Shape name", true),
            "shape_type": ("string", "Shape type: rectangle, roundRect, oval, line", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "fill_color": ("string", "Fill color hex, e.g. #FF0000", false),
            "stroke_color": ("string", "Stroke color hex", false),
            "stroke_width": ("string", "Stroke width in points", false),
            "on_background": ("string", "Set to 'true' to place on the card's background", false),
        ]),
        makeTool(name: "create_webpage", description: "Create a web page viewer on the current card or background.", params: [
            "name": ("string", "Webpage part name", true),
            "url": ("string", "URL to display", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "on_background": ("string", "Set to 'true' to place on the card's background", false),
        ]),

        makeTool(name: "create_video", description: "Create a video player on the current card or background.", params: [
            "name": ("string", "Video part name", true),
            "video_url": ("string", "URL or file path to the video", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "on_background": ("string", "Set to 'true' to place on the card's background", false),
        ]),

        makeTool(name: "create_chart", description: """
            Create a chart control with data. Use the 'data' parameter for simple data \
            (e.g. 'Jan=120,Feb=150,Mar=180') or 'data_json' for JSON format. \
            ALWAYS provide meaningful x_axis_label and y_axis_label (e.g. 'Month', 'Sales') \
            for bar/line/area/point/rule charts so the rendered chart has visible axis \
            titles. show_legend defaults to 'true' and identifies the series in the rendered \
            legend; set it to 'false' only if the user explicitly wants the legend hidden.
            """, params: [
            "name": ("string", "Chart name", true),
            "chart_type": ("string", "Chart type: bar, line, area, point, pie, rule", true),
            "title": ("string", "Chart title", false),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "data": ("string", "Simple data format: name=value pairs separated by commas, e.g. 'Jan=120,Feb=150,Mar=180'", false),
            "data_json": ("string", "JSON array of data points with name, value, color: [{\"name\":\"Jan\",\"value\":120,\"color\":\"#4A90D9\"}]", false),
            "series_name": ("string", "Series name shown in the legend (e.g. 'Sales')", false),
            "series_color": ("string", "Series color hex, e.g. #FF6B6B", false),
            "x_axis_label": ("string", "X-axis title, e.g. 'Month'. Shown under the X axis.", false),
            "y_axis_label": ("string", "Y-axis title, e.g. 'Sales'. Shown beside the Y axis.", false),
            "show_legend": ("string", "'true' (default) to show the legend, 'false' to hide it", false),
            "show_grid": ("string", "'true' (default) to show grid lines, 'false' to hide them", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "create_pdf", description: """
            Create a PDF viewer control. Loads a PDF from a local file path or http(s) \
            URL and presents it as a scrollable, zoomable PDFView. The user can change the \
            page; HypeTalk reads of `the currentPage of pdf "manual"` reflect the visible \
            page. Set `pdfurl` (file path or URL), `current_page` (1-based), `display_mode` \
            ('single' | 'continuous' | 'twoUp' | 'twoUpContinuous'), `auto_scales` ('true'/'false').
            """, params: [
            "name": ("string", "PDF part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "pdfurl": ("string", "Path or http(s) URL of the PDF document", false),
            "current_page": ("string", "1-based initial page number", false),
            "display_mode": ("string", "single | continuous (default) | twoUp | twoUpContinuous", false),
            "auto_scales": ("string", "true (default) to fit pages to width", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "create_map", description: """
            Create a map control. Wraps MKMapView. Provide `center_lat`/`center_lon` (decimal \
            degrees), `span` (degrees of latitude shown — smaller is more zoomed in; 0.05 ≈ \
            city blocks), `map_type` ('standard' | 'satellite' | 'hybrid' | 'mutedStandard'). \
            Annotations attach via the separate `add_map_annotation` tool or by setting the \
            `annotations` property to a JSON array of {lat, lon, title} objects. \
            A `location` argument is also accepted for human-friendly placement \
            ("Eiffel Tower", "Rogue River, OR", "97537") — the host geocodes it \
            asynchronously via CLGeocoder and writes the resolved lat/lon back \
            into the part. Geocoding may fail (network, invalid query, rate \
            limit) — when it does, the supplied or default lat/lon stays in place.
            """, params: [
            "name": ("string", "Map part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "center_lat": ("string", "Center latitude (decimal degrees)", false),
            "center_lon": ("string", "Center longitude (decimal degrees)", false),
            "span": ("string", "Span in degrees (default 0.05)", false),
            "map_type": ("string", "standard (default) | satellite | hybrid | mutedStandard", false),
            "location": ("string", "Human-friendly location: place name, address, or US ZIP. Resolved asynchronously by the host (CLGeocoder) on display; lat/lon are written back into the part once geocoded. If both location and center_lat/center_lon are provided, the geocoded location overrides lat/lon. Empty = use lat/lon directly.", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "add_map_annotation", description: """
            Append an annotation pin to an existing map part. Annotations stack — call this \
            multiple times to add multiple pins. To replace the entire set, use \
            `set_part_property` with property=annotations and a JSON array string.
            """, params: [
            "map_name": ("string", "Map part name", true),
            "lat": ("string", "Latitude (decimal degrees)", true),
            "lon": ("string", "Longitude (decimal degrees)", true),
            "title": ("string", "Annotation title shown on tap", false),
        ]),

        makeTool(name: "clear_map_annotations", description: "Remove every annotation from a map part.", params: [
            "map_name": ("string", "Map part name", true),
        ]),

        makeTool(name: "create_stepper", description: """
            Create a numeric stepper (NSStepper) with optional min/max/step bounds. \
            User-driven changes fire the `valueChanged` HypeTalk message; reads use \
            `the value of stepper "X"`.
            """, params: [
            "name": ("string", "Stepper part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "value": ("string", "Initial value (default 0)", false),
            "min": ("string", "Minimum value (default 0)", false),
            "max": ("string", "Maximum value (default 100)", false),
            "step": ("string", "Increment per click (default 1)", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "create_slider", description: """
            Create a slider (NSSlider). Continuous-tracking — `valueChanged` fires \
            during drag, not just on release. Reads use `the value of slider "X"`.
            """, params: [
            "name": ("string", "Slider part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "value": ("string", "Initial value (default 0)", false),
            "min": ("string", "Minimum value (default 0)", false),
            "max": ("string", "Maximum value (default 100)", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        // create_toggle removed in dedup — use create_button with
        // style="toggle" instead. The button's `hilite` field
        // backs the on/off state. (style="switch" is a deprecated
        // alias that still resolves to .toggle for backward compat.)

        makeTool(name: "create_segmented", description: """
            Create a segmented control (NSSegmentedControl) with a comma- or pipe-separated \
            list of segment labels. Reads use `the selectedSegment of segmented "X"` (returns \
            the 0-based index). User picks fire the `selectionChanged` message.
            """, params: [
            "name": ("string", "Segmented part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "segments": ("string", "Pipe-separated labels (e.g. 'Day|Week|Month')", true),
            "selected_segment": ("string", "0-based selected index (default 0)", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "set_image_filter", description: """
            Apply a CoreImage filter to an existing image part. Friendly names: \
            'none' (clears the filter), 'sepia', 'blackwhite', 'mono', 'noir', 'blur', \
            'vignette', 'invert', 'posterize', 'comic', 'process', 'transfer', \
            'instant', 'fade', 'tonal', 'chrome'. `intensity` is 0..1 and affects \
            sepia / blur / vignette / posterize; ignored by the rest.
            """, params: [
            "image_name": ("string", "The image part to filter", true),
            "filter": ("string", "Filter name (see description). 'none' clears.", true),
            "intensity": ("string", "0..1 strength (default 0.7)", false),
        ]),

        makeTool(name: "create_scene3d", description: """
            Create a 3D scene viewer (SceneKit). Loads `.usdz`, `.scn`, `.dae`, `.obj`, `.stl` \
            from a local file path or http(s) URL. `.stl` files are auto-converted to `.obj` \
            on import (cached by SHA-256 of file contents). Camera control \
            (mouse-orbit / scroll-zoom) on by default. HypeTalk reads: \
            `the object of scene3d "X"` (source path) or `the modelURL of scene3d "X"` \
            (resolved path after STL conversion).
            """, params: [
            "name": ("string", "Scene3D part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "object": ("string", "Path or URL of the 3D model file. Accepts .usdz, .usd, .scn, .dae, .obj, .stl. STL is auto-converted to OBJ on import.", false),
            "model_url": ("string", "(deprecated alias for object — still works)", false),
            "allows_camera_control": ("string", "'true' (default) to let user orbit/zoom", false),
            "auto_lighting": ("string", "'true' (default) to add default lights", false),
            "background": ("string", "Hex color for the scene background (empty = transparent)", false),
            "antialiasing": ("string", "'none' | 'multisampling2X' | 'multisampling4X' (default)", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "create_audio_recorder", description: """
            Create an audio-recorder control. Setting `recording` to true (via the AI \
            tool, HypeTalk `set the recording of recorder "memo" to true`, or the \
            inspector toggle) starts capturing from the microphone; setting it false \
            stops. The recorder writes m4a (AAC) by default to a temp file under \
            FileManager.temporaryDirectory; pass `output_path` to choose where. \
            HypeTalk reads: `the duration of recorder "X"` (seconds), `the recording \
            of recorder "X"`, `the outputPath of recorder "X"`. Messages: \
            `recordingStarted` / `recordingStopped`.
            """, params: [
            "name": ("string", "Recorder part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "format": ("string", "'m4a' (AAC, default) or 'caf' (LinearPCM)", false),
            "output_path": ("string", "Absolute file path. Empty = auto-generate.", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "create_color_well", description: """
            Create a color-picker (NSColorWell) control. Click opens the macOS color panel; \
            picks fire the `colorChanged` HypeTalk message on the part. Read the bound color \
            via `the color of colorWell "name"` (returns a hex string like '#FF5500').
            """, params: [
            "name": ("string", "Color-well part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "color": ("string", "Initial color as hex (e.g. '#FF5500')", false),
            "interactive": ("string", "'true' (default) to allow opening the color panel; 'false' for a static swatch", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "create_calendar", description: """
            Create a calendar/date-picker control. The user picks dates via a live \
            macOS NSDatePicker; the selected date is stored on the part as ISO 8601 \
            (yyyy-MM-dd) and is readable from HypeTalk as `the selectedDate of \
            calendar "name"`. The `dateChanged` message fires on the part each time \
            the user changes the selection. Set `selected_date`, `min_date`, `max_date` \
            using yyyy-MM-dd format. `style` is one of 'graphical' (default month grid), \
            'textual' (compact text + stepper), or 'clockAndCalendar' (graphical month \
            plus an analog clock face).
            """, params: [
            "name": ("string", "Calendar part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "selected_date": ("string", "Initially-selected date as yyyy-MM-dd. Empty = today.", false),
            "display_month": ("string", "Visible month as yyyy-MM-01. Empty = follows selected_date.", false),
            "min_date": ("string", "Earliest allowed date as yyyy-MM-dd. Empty = no minimum.", false),
            "max_date": ("string", "Latest allowed date as yyyy-MM-dd. Empty = no maximum.", false),
            "style": ("string", "'graphical' (default), 'textual', or 'clockAndCalendar'", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        // MARK: - Phase 3 framework controls

        makeTool(name: "create_progressview", description: """
            Create a progress indicator showing determinate or indeterminate progress as a \
            linear bar (default) or circular spinner. Set `value` between 0 and `total` to show \
            progress. Set `is_indeterminate` to 'true' for a spinner/barber-pole bar. The \
            `progressFinished` HypeTalk message fires once when value reaches total.
            """, params: [
            "name": ("string", "Progress part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "value": ("string", "Initial progress value (default 0)", false),
            "total": ("string", "Total / maximum value (default 1.0)", false),
            "is_circular": ("string", "'true' for circular spinner; 'false' (default) for linear bar", false),
            "is_indeterminate": ("string", "'true' for indeterminate animation; 'false' (default) for determinate", false),
            "label": ("string", "Optional caption shown above the bar", false),
            "tint": ("string", "Optional tint color hex (e.g. '#FF8800')", false),
            "decimals": ("string", "Number of fractional digits the value is rounded to on every write. Default 0 — integer-only steps. Capped at 10. Same contract as the gauge control.", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "create_gauge", description: """
            Create a Gauge indicator showing a value within a range. Available styles: \
            'linearCapacity' (default), 'accessoryCircular', 'accessoryCircularCapacity', \
            'accessoryLinear', 'accessoryLinearCapacity'. Requires macOS 13+; falls back to a \
            progress bar on older systems. HypeTalk: `the value of gauge "X"`.
            """, params: [
            "name": ("string", "Gauge part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "value": ("string", "Initial value (default 0)", false),
            "min": ("string", "Range minimum (default 0)", false),
            "max": ("string", "Range maximum (default 1.0)", false),
            "style": ("string", "Gauge style: linearCapacity (default), accessoryCircular, accessoryCircularCapacity, accessoryLinear, accessoryLinearCapacity", false),
            "tint": ("string", "Tint color hex (e.g. '#FF8800')", false),
            "label": ("string", "Label text", false),
            "min_label": ("string", "Label at the minimum end", false),
            "max_label": ("string", "Label at the maximum end", false),
            "decimals": ("string", "Number of fractional digits the gauge rounds its value to (and shows in the value label). Default 0 — integral steps only when the user scrubs interactively. Capped at 10.", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        // create_link, create_menu, create_searchfield removed in dedup —
        // use create_button with style="link" / style="popup" or
        // create_field with style="search" instead. URL handling for
        // .link buttons enforces the http/https/mailto allowlist on
        // mouseUp dispatch in CardCanvasView.

        makeTool(name: "create_divider", description: """
            Create a thin horizontal or vertical separator line. Use to visually group content \
            on a card. Set `orientation` to 'horizontal' (default) or 'vertical'. No lifecycle \
            messages — purely visual.
            """, params: [
            "name": ("string", "Divider part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "orientation": ("string", "'horizontal' (default) or 'vertical'", false),
            "thickness": ("string", "Line thickness in pts (default 1)", false),
            "color": ("string", "Line color hex (default uses system separator color)", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        makeTool(name: "repair_form_controls", description: """
            Convert a form-like Sprite Area on the current card into ordinary Hype controls. \
            Label nodes become locked transparent field labels. If the Sprite Area contains \
            only labels/groups, it is removed after conversion. Use only when repairing a form \
            that was accidentally built as a SpriteKit scene.
            """, params: [
            "sprite_area_name": ("string", "Optional Sprite Area name to repair. Defaults to the best form-like Sprite Area on the current card.", false),
        ]),

        // Sprite area creation and management
        makeTool(name: "create_sprite_area", description: "Create a Sprite Area (SpriteKit scene container) on the current card.", params: [
            "name": ("string", "Sprite area name", true),
            "scene_name": ("string", "Initial scene name", false),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "on_background": ("string", "true to place on background", false),
        ]),
        makeTool(name: "get_scene_spec", description: "Get the full SceneSpec JSON for a sprite area.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
        ]),
        makeTool(name: "set_scene_script", description: """
            Set the HypeTalk script on a sprite-area scene. This is \
            the script shown in the Script Editor with title \
            "<sprite_area_name> / <scene_name>", and the one that \
            handles scene events like sceneDidLoad, frameUpdate, \
            keyDown, beginContact, etc. \
            Prefer this explicit scene tool for requests like "set \
            the script on the bounder object/sprite area". The \
            compatibility path `set_part_property` with \
            `part_name: <sprite area>` + `property: script` routes \
            to this same active-scene script, but this tool is clearer \
            and exposes the optional scene name. If `scene_name` is \
            omitted, the active scene is used.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part (e.g. 'bounder')", true),
            "script": ("string", "Full HypeTalk script for the scene, wrapped in on <event> ... end <event> handler blocks", true),
            "scene_name": ("string", "Optional scene name within the sprite area; defaults to the active scene", false),
        ]),
        makeTool(name: "apply_scene_diff", description: """
            Apply a JSON diff to modify a sprite scene incrementally. Pass diff_json as a \
            JSON STRING whose top-level keys are optional: addNodes (array of HypeNodeSpec), \
            removeNodeIds (array of UUIDs), updateNodes (array of NodeUpdate), and sceneUpdates \
            (object with gravity, backgroundColor, isPaused, SCRIPT (the scene-level HypeTalk \
            script), size, name, scaleMode). A HypeNodeSpec needs at least \
            {id, name, nodeType, position:{x,y}}; nodeType is one of sprite, label, shape, \
            emitter, audio, tileMap, camera, video, crop, effect, light, group. For labels \
            include {text, fontSize, fontColor}. For shapes include shapeSpec:{shapeType, \
            fillColor, strokeColor, lineWidth}. Every id must be a valid lowercase UUID. \
            To update only the scene's script, use `set_scene_script` — simpler and avoids \
            JSON-encoding a multi-line script. \
            Example: {"sceneUpdates":{"backgroundColor":"#000000"},"addNodes":[{"id":"...","name":"player","nodeType":"shape","position":{"x":200,"y":150},"shapeSpec":{"shapeType":"circle","fillColor":"#00FF00"},"actions":[],"children":[],"script":""}]}
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "diff_json": ("string", "SceneDiff as a JSON-encoded string (see description)", true),
        ]),
        makeTool(name: "add_sprite_to_scene", description: "Add a sprite node to a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "sprite_name": ("string", "Name for the new sprite", true),
            "asset_name": ("string", "Repository asset name for texture", false),
            "x": ("string", "X position", false),
            "y": ("string", "Y position", false),
            "width": ("string", "Width", false),
            "height": ("string", "Height", false),
        ]),
        makeTool(name: "create_tilemap", description: """
            Create a tile map node in a sprite area scene. If you pass \
            `tileset_asset`, the referenced repository asset should be \
            classified as a tileset first via `classify_asset_as_tileset` \
            so the tile size, column count, and row count are picked up \
            automatically — otherwise multi-column tilesets render as a \
            single vertical strip. Columns/rows control the tile MAP \
            dimensions (how many cells the map contains), not the tile \
            SET dimensions (how many tiles the sprite sheet contains).
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area", true),
            "tilemap_name": ("string", "Name for the tile map", true),
            "columns": ("string", "Number of tile map columns (cells wide)", true),
            "rows": ("string", "Number of tile map rows (cells tall)", true),
            "tile_size": ("string", "Tile size in pixels. Optional — defaults to the tileset asset's tileWidth when the asset is classified.", false),
            "tileset_asset": ("string", "Repository asset name for the tile set sprite sheet. Classify it first with classify_asset_as_tileset for correct rendering.", false),
        ]),
        makeTool(name: "classify_asset_as_tileset", description: """
            Mark a repository image asset as a tileset and record its \
            grid metadata (tile width/height, how many tiles across and \
            down). Must be called on a tileset sprite sheet BEFORE using \
            it with create_tilemap, or the tilemap will render the entire \
            sheet as a single vertical strip. Columns and rows are \
            auto-derived from image dimensions when omitted. Safe to call \
            multiple times to re-classify with different tile sizes.
            """, params: [
            "asset_name": ("string", "Name of the asset in the sprite repository to classify", true),
            "tile_width": ("string", "Width of a single tile in pixels (required, > 0)", true),
            "tile_height": ("string", "Height of a single tile in pixels (required, > 0)", true),
            "tile_columns": ("string", "Number of tile columns in the sprite sheet (optional, auto-derived from image width / tile_width when omitted)", false),
            "tile_rows": ("string", "Number of tile rows in the sprite sheet (optional, auto-derived from image height / tile_height when omitted)", false),
        ]),
        makeTool(name: "set_tile", description: """
            Set a single cell of an existing tile map to a tile index. \
            The tile_index is 0-based (left-to-right, top-to-bottom in \
            the source tileset). Pass -1 to clear a cell. The tile map \
            must already exist via create_tilemap, and column/row must \
            fall within its bounds.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area containing the tile map", true),
            "tilemap_name": ("string", "Name of the tile map node", true),
            "column": ("string", "Column index (0-based)", true),
            "row": ("string", "Row index (0-based)", true),
            "tile_index": ("string", "Tile index from the tileset, or -1 to clear", true),
        ]),
        makeTool(name: "fill_tilemap", description: """
            Fill every cell of a tile map with the same tile index. \
            Useful for painting a ground layer (e.g. all grass) before \
            stamping obstacles on top with set_tile. Pass tile_index=-1 \
            to clear the entire map.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area containing the tile map", true),
            "tilemap_name": ("string", "Name of the tile map node", true),
            "tile_index": ("string", "Tile index to fill with, or -1 to clear all cells", true),
        ]),
        makeTool(name: "get_tilemap_info", description: """
            Report the dimensions, tile size, tileset binding, and \
            tile-data preview of an existing tile map. Use this to \
            verify your create_tilemap / set_tile sequence produced the \
            expected state, and to confirm the tileset asset was \
            classified correctly (tileSetColumns > 1).
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area containing the tile map", true),
            "tilemap_name": ("string", "Name of the tile map node", true),
        ]),
        makeTool(name: "create_camera", description: "Create a camera node in a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area", true),
            "camera_name": ("string", "Name for the camera", true),
        ]),
        makeTool(name: "capture_scene_snapshot", description: "Capture a text description of the current scene state for debugging.", params: [
            "sprite_area_name": ("string", "Name of the sprite area", true),
        ]),
        makeTool(name: "get_scene_diagnostics", description: "Get diagnostic information about a sprite scene including errors and warnings.", params: [
            "sprite_area_name": ("string", "Name of the sprite area", true),
        ]),
        makeTool(name: "list_repository_assets", description: "List all sprite assets in the stack's Sprite Repository.", params: [:]),
        makeTool(name: "import_repository_asset", description: "Import an image file into the Sprite Repository as a named asset.", params: [
            "name": ("string", "Asset name", true),
            "file_path": ("string", "Absolute path to PNG/JPG image file", true),
        ]),
        makeTool(name: "generate_sprite_asset", description: """
            Generate a new sprite image asset through the configured OpenAI image model and add it to the Sprite Repository. \
            Use this when the user asks to create, add, draw, or generate a sprite/library/repository asset that looks like something. \
            Do not call this tool unless the user has provided the desired sprite asset name; if the name is missing, ask a follow-up question first.
            """, params: [
            "asset_name": ("string", "Required sprite asset name chosen by the user. Ask for it before calling this tool if the user did not provide one.", true),
            "prompt": ("string", "Detailed visual description of the sprite image to generate", true),
            "generation_size": ("string", "OpenAI generation size: 1024x1024, 1536x1024, or 1024x1536. Defaults to 1024x1024.", false),
            "quality": ("string", "Image quality: low, medium, or high. Defaults to the model default.", false),
            "background": ("string", "transparent, opaque, or auto. Defaults to transparent for sprite assets.", false),
            "kind": ("string", "Repository kind: imageTexture, spriteSheet, or tileSet. Defaults to imageTexture unless the name implies tileset.", false),
            "model": ("string", "Optional OpenAI image model override. Normally omit.", false),
        ]),

        // Part modification
        makeTool(name: "set_part_property", description: """
            Set a property on a part by name. Available properties: name, left, top, width, height, \
            text, url, videoURL, fillColor, strokeColor, strokeWidth, cornerRadius, visible, enabled, hilite, \
            autoHilite, showName, lockText, textFont, textSize, textAlign, textStyle, fontColor, helpText, script, style. \
            textStyle is a comma-separated subset of: plain, bold, italic, underline, strikethrough \
            (e.g. "bold" or "bold,italic"). fontColor is a hex string ("#FF0000") for the text \
            foreground; passing an empty string reverts to the auto contrast-aware default. \
            Image / GIF parts also accept: transparentBackground (boolean — when true, the renderer \
            chroma-keys the dominant corner-pixel color out so whatever is behind the image shows \
            through; useful for JPGs and indexed GIFs whose 'background' is a solid color rather \
            than a real alpha channel). \
            Sprite Area parts also accept transparentBackground: when true, the SpriteKit scene \
            composites against the card so an image part placed BENEATH the sprite area shows \
            through (the scene's nodes still render normally on top). \
            Chart-specific properties: chartdata, charttype, charttitle, x_axis_label, y_axis_label, \
            show_legend, show_grid. \
            If the named part is a Sprite Area and property is script, this routes to the active \
            scene script shown in "<sprite area> / <scene>" Script Editor. Prefer set_scene_script \
            when the user asks for SpriteKit scene behavior. \
            For 'style': button styles are transparent/opaque/rectangle/roundRect/shadow/checkBox/standard/default/popup/oval/toggle. \
            Field styles are transparent/opaque/rectangle/shadow/scrolling. \
            Shape types are rectangle/roundRect/oval/line/freeform.
            """, params: [
            "part_name": ("string", "Name of the part to modify", true),
            "property": ("string", "Property to set", true),
            "value": ("string", "New value", true),
        ]),
        makeTool(name: "delete_part", description: "Delete a part by name.", params: [
            "part_name": ("string", "Name of the part to delete", true),
        ]),

        makeTool(name: "check_script", description: """
            REQUIRED before storing any HypeTalk script. Run this tool \
            on every script you're about to attach to a part, card, \
            background, or stack (via create_button, create_field, \
            set_part_property with property='script', etc.) BEFORE \
            making the storage call. If check_script reports errors, \
            fix the script and call check_script again. Keep iterating \
            until it returns 'OK' — only then should you store the \
            script. This prevents silently-broken scripts where the \
            part is created successfully but no handler ever fires. \
            Pass the FULL script you intend to store, already wrapped \
            in 'on <event> ... end <event>' handler blocks (bare one- \
            liners like 'go next' are auto-wrapped by create_button, \
            so check the wrapped form 'on mouseUp\\n  go next\\nend \
            mouseUp' if you want to validate that case). The tool \
            returns 'OK: <N> handler(s) parsed' on success, or a \
            human-readable error with the offending line number on \
            failure.
            """, params: [
            "script": ("string", "The HypeTalk script source to validate. Include the full handler block(s).", true),
        ]),

        makeTool(name: "set_chart_data_point_color", description: """
            Set the color of a single data point inside a chart's series at \
            runtime. Use this for structured updates to per-point colors \
            without having to re-emit the whole chart. The series defaults \
            to 1 if omitted (convenient for single-series charts). The \
            point can be referenced by 1-based index ('1', '2', …) or by \
            its name (e.g. 'Jan').
            """, params: [
            "chart_name": ("string", "Name of the chart part to modify", true),
            "series": ("string", "Series identifier — 1-based index or series name. Defaults to '1'.", false),
            "point": ("string", "Data point identifier — 1-based index or point name", true),
            "color": ("string", "Hex color like '#FF6B6B'", true),
        ]),

        makeTool(name: "get_chart_data_points", description: """
            List every series and data point in a chart, including each \
            point's name, value, and effective color (per-point override \
            with fallback to the series default). Use this before calling \
            set_chart_data_point_color to check which points exist and \
            what names they have.
            """, params: [
            "chart_name": ("string", "Name of the chart part to inspect", true),
        ]),

        // Information / read-side. The granular property tools
        // (`get_stack_property`, `get_card_property`, etc.) live in
        // their own scope-tools section below — see the v3.x block
        // around `set_card_property` / theme support — so we don't
        // duplicate the makeTool declarations here. Both batches
        // hit the same dispatcher in HypeToolExecutor.
        makeTool(name: "get_stack_info", description: "Get information about the current stack: card count, background names, current card.", params: [:]),
        makeTool(name: "get_card_parts", description: "List all parts on the current card with their properties.", params: [:]),

        // ------------------------------------------------------------------
        // Read-side tools (granular queries — prefer these over the dumps)
        // ------------------------------------------------------------------

        makeTool(name: "get_part_property", description: """
            Read the current value of a single property on a named card part. Complements \
            set_part_property — always call this first when you need to read-then-write (e.g. \
            bumping a score by 10, toggling visibility). Returns "Part 'X' not found" when the \
            part doesn't exist. Property names match set_part_property: name, left, top, width, \
            height, text, url, videoURL, fillColor, strokeColor, strokeWidth, cornerRadius, \
            visible, enabled, hilite, autoHilite, showName, lockText, textFont, textSize, \
            textAlign, textStyle, fontColor, helpText, script, style. For Sprite Area parts, property=script returns \
            the active scene script, matching set_part_property's compatibility routing.
            """, params: [
            "part_name": ("string", "Name of the part to query", true),
            "property": ("string", "Property name to read", true),
        ]),

        makeTool(name: "list_all_properties", description: """
            Return EVERY property of a named part (with current value AND default), so you \
            can discover what's settable without guessing the name. Use this before set_part_property \
            when you don't already know the property name — saves a round-trip on misspellings.

            The output is a structured text block, one property per line, formatted as \
            `propertyName = currentValue   (default: defaultValue)`. Common properties \
            (geometry, state, text, script) come first; type-specific properties (e.g. \
            mapCenterLat / audioOutputPath / scene3DAntialiasing) follow. The same property \
            names work as the `property` argument to set_part_property and get_part_property, \
            and as the property name in HypeTalk's `the X of <kind> "name"` syntax.

            Returns "Part 'X' not found" if the named part doesn't exist on the current card or \
            its background.
            """, params: [
            "part_name": ("string", "Name of the part to enumerate. Match is case-insensitive.", true),
        ]),

        makeTool(name: "get_node_property", description: """
            Read the current value of a single property on a scene node. Use this instead of \
            dumping the whole scene via get_scene_spec when you only need one field. Supports \
            dotted paths for nested properties: position.x, position.y, rotation, xScale, \
            yScale, alpha, isHidden, zPosition, text, fontSize, fontColor, script, \
            shape.fillColor, shape.strokeColor, shape.lineWidth, shape.cornerRadius, \
            physics.restitution, physics.friction, physics.mass, physics.velocityX, \
            physics.velocityY, physics.isDynamic, physics.affectedByGravity, \
            physics.allowsRotation, physics.linearDamping, physics.angularDamping.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node within the scene", true),
            "property": ("string", "Property path to read", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "list_all_cards", description: "List every card in the stack with name, number, and background. Compact line-oriented output. Use this instead of get_stack_info when you need card names for navigation.", params: [:]),

        makeTool(name: "list_backgrounds", description: "List every background with its name and the count of cards using it.", params: [:]),

        makeTool(name: "get_background_parts", description: """
            List only the parts that live on the current card's background, or on a named \
            background when background_name is supplied. Use this when the user asks for \
            background objects/parts/buttons/fields; use get_card_parts for the combined \
            effective card view.
            """, params: [
            "background_name": ("string", "Background name (defaults to current card's background)", false),
        ]),

        makeTool(name: "list_scene_nodes", description: """
            List every node in a sprite area scene. Compact output — one line per node with \
            id, name, type, and position. Prefer this over get_scene_spec for scene overviews; \
            get_scene_spec returns the full (often very large) JSON. Use list_scene_nodes first \
            to see what exists, then get_node_property for specific fields.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "list_scene_joints", description: "List every physics joint in a sprite area scene, grouped by type.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "list_scene_constraints", description: "List every scene constraint (distance / orient / position) in a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "get_scene_script", description: "Return ONLY the HypeTalk script attached to a sprite area scene — much cheaper than get_scene_spec when you just need the script.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "get_node_script", description: "Return ONLY the HypeTalk script attached to a scene node.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node within the scene", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "get_stack_script", description: "Return the HypeTalk script attached to the stack — i.e. the script shown in the Stack Script Editor, executing on openStack / closeStack / idle.", params: [:]),

        makeTool(name: "get_card_script", description: "Return the HypeTalk script attached to a card (openCard / closeCard / mouseDown etc.). Use the current card when card_name is omitted.", params: [
            "card_name": ("string", "Card name (defaults to current card)", false),
        ]),

        makeTool(name: "get_background_script", description: "Return the HypeTalk script attached to a background (openBackground / closeBackground handlers). Uses the current background when background_name is omitted.", params: [
            "background_name": ("string", "Background name (defaults to current background)", false),
        ]),

        // ------------------------------------------------------------------
        // Script-setter tools for card / background / stack (set_scene_script
        // already exists). set_part_property does NOT reach these.
        // ------------------------------------------------------------------

        makeTool(name: "set_stack_script", description: """
            Set the HypeTalk script attached to the stack (shown in the Stack Script Editor). \
            Triggered by openStack, closeStack, idle, and stack-level messages. Use this for \
            globals, shared handlers, and stack-wide setup. Prefer set_card_script / \
            set_background_script for narrower scope.
            """, params: [
            "script": ("string", "Full HypeTalk script for the stack", true),
        ]),

        makeTool(name: "set_card_script", description: """
            Set the HypeTalk script attached to a card (openCard, closeCard, mouseDown on the \
            card background, etc.). Use the current card when card_name is omitted. \
            set_part_property with property='script' does NOT reach card scripts — use this \
            tool instead.
            """, params: [
            "card_name": ("string", "Card name (defaults to current card)", false),
            "script": ("string", "Full HypeTalk script for the card", true),
        ]),

        makeTool(name: "set_background_script", description: """
            Set the HypeTalk script attached to a background (openBackground, closeBackground, \
            etc.). Shared by every card that uses the background. set_part_property does NOT \
            reach background scripts — use this tool instead. Uses the current background when \
            background_name is omitted.
            """, params: [
            "background_name": ("string", "Background name (defaults to current background)", false),
            "script": ("string", "Full HypeTalk script for the background", true),
        ]),

        // ------------------------------------------------------------------
        // Scene-node creators for non-sprite node types. Existing
        // add_sprite_to_scene covers sprites; add_*_to_scene below cover
        // the rest without forcing the AI to hand-roll an apply_scene_diff.
        // ------------------------------------------------------------------

        makeTool(name: "add_label_to_scene", description: "Add a text label node to a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "label_name": ("string", "Name for the label node", true),
            "text": ("string", "Label text to display", true),
            "x": ("string", "X position", false),
            "y": ("string", "Y position", false),
            "font_name": ("string", "Font name (e.g. 'HelveticaNeue-Bold')", false),
            "font_size": ("string", "Font size in points", false),
            "font_color": ("string", "Font color hex (e.g. #FFFFFF)", false),
            "z_position": ("string", "Z-order (higher draws on top)", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_shape_to_scene", description: """
            Add a shape node (rect / circle / ellipse / path) to a sprite area scene. Prefer \
            this over apply_scene_diff when you need a single shape — it avoids hand-rolling \
            a HypeNodeSpec with shapeSpec set.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "shape_name": ("string", "Name for the shape node", true),
            "shape_type": ("string", "Shape type: rect, circle, ellipse, path", true),
            "x": ("string", "X position", false),
            "y": ("string", "Y position", false),
            "width": ("string", "Width in points", false),
            "height": ("string", "Height in points", false),
            "fill_color": ("string", "Fill color hex", false),
            "stroke_color": ("string", "Stroke color hex", false),
            "line_width": ("string", "Stroke width in points", false),
            "corner_radius": ("string", "Corner radius (rect only)", false),
            "z_position": ("string", "Z-order", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_emitter_to_scene", description: "Add a particle emitter node to a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "emitter_name": ("string", "Name for the emitter node", true),
            "x": ("string", "X position", false),
            "y": ("string", "Y position", false),
            "birth_rate": ("string", "Particles per second (default 50)", false),
            "lifetime": ("string", "Particle lifetime in seconds (default 2)", false),
            "speed": ("string", "Particle speed (default 100)", false),
            "emission_angle": ("string", "Emission angle in degrees (default 90 = up)", false),
            "particle_color": ("string", "Particle color hex", false),
            "particle_scale": ("string", "Particle scale (default 0.3)", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_audio_to_scene", description: "Add an audio node to a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "audio_name": ("string", "Name for the audio node", true),
            "asset_name": ("string", "Repository asset for the sound", false),
            "loop": ("string", "'true' to loop playback", false),
            "volume": ("string", "Volume 0.0–1.0", false),
            "autoplay": ("string", "'true' to start on scene load", false),
            "positional": ("string", "'true' for 3D positional audio", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_video_to_scene", description: "Add a video node to a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "video_name": ("string", "Name for the video node", true),
            "asset_name": ("string", "Repository asset with the video file", true),
            "x": ("string", "X position", false),
            "y": ("string", "Y position", false),
            "width": ("string", "Width in points", false),
            "height": ("string", "Height in points", false),
            "loop": ("string", "'true' to loop playback", false),
            "autoplay": ("string", "'true' to start on scene load", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_group_to_scene", description: "Add an empty group node (organisational container) to a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "group_name": ("string", "Name for the group node", true),
            "x": ("string", "X position", false),
            "y": ("string", "Y position", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_joint_to_scene", description: "Add a physics joint connecting two scene nodes.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "joint_type": ("string", "Joint type: pin, spring, sliding, fixed, limit", true),
            "node_a": ("string", "First node name", true),
            "node_b": ("string", "Second node name", true),
            "anchor_a_x": ("string", "Anchor point on node A, x (relative)", false),
            "anchor_a_y": ("string", "Anchor point on node A, y (relative)", false),
            "anchor_b_x": ("string", "Anchor point on node B, x (relative)", false),
            "anchor_b_y": ("string", "Anchor point on node B, y (relative)", false),
            "spring_frequency": ("string", "Spring frequency (spring joints only)", false),
            "spring_damping": ("string", "Spring damping (spring joints only)", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_constraint_to_scene", description: "Add a scene constraint (distance / orient / position) between two nodes.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "constraint_type": ("string", "Constraint type: distance, orient, position", true),
            "source_node": ("string", "Source node name", true),
            "target_node": ("string", "Target node name", true),
            "min_distance": ("string", "Minimum distance", false),
            "max_distance": ("string", "Maximum distance", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_physics_field_to_scene", description: "Add a physics field to a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "field_type": ("string", "Field type: linearGravity, radialGravity, vortex, noise, turbulence, spring, drag, electric, magnetic", true),
            "strength": ("string", "Field strength", true),
            "region_width": ("string", "Field region width (omit for infinite)", false),
            "region_height": ("string", "Field region height (omit for infinite)", false),
            "direction_x": ("string", "Direction x (linear fields)", false),
            "direction_y": ("string", "Direction y (linear fields)", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "create_image", description: "Create an image part on the current card or its background. Either file_path (load from disk) or asset_name (reference sprite repository) should be provided.", params: [
            "name": ("string", "Image part name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "file_path": ("string", "Absolute path to an image file on disk", false),
            "asset_name": ("string", "Name of an asset already in the Sprite Repository", false),
            "on_background": ("string", "'true' to place on the background (shared across cards)", false),
        ]),
        // ------------------------------------------------------------------
        // Meshy 3D generation tools (Phase 2)
        // ------------------------------------------------------------------

        makeTool(name: "list_3d_models", description: """
            List every 3D model asset (kind == .model3D) currently in the Sprite Repository. \
            Returns one line per asset: name=<n> id=<uuid> size=<bytes>B. \
            Returns "(no 3D models in repository)" when there are none. \
            Use this before calling a generate_3d_model_* tool to avoid regenerating a model the user already has.
            """, params: [:]),

        makeTool(name: "generate_3d_model_from_text", description: """
            Generate a 3D model from a text prompt using Meshy.ai and add it to the \
            Sprite Repository as a model3D asset. Optionally also place a scene3D part \
            on the current card or background referencing the new asset (when place_on_card='true').

            Generation takes ~60–120 seconds; the tool blocks while the Meshy task runs. \
            Progress is reported live via the AI log. The wait is capped at 5 minutes — \
            if generation hasn't finished by then, the tool returns an error and the user \
            can retry from the Generate 3D sheet.

            Requires: (a) the stack has meshyEnabled; (b) the Meshy API key is in the Keychain.
            """, params: [
            "prompt":         ("string", "Plain-English description of the model (max 600 chars)", true),
            "ai_model":       ("string", "meshy-6 (default) | meshy-5 | meshy-4 | latest", false),
            "art_style":      ("string", "realistic (default) | sculpture", false),
            "should_remesh":  ("string", "'true' / 'false'. Defaults to model default.", false),
            "with_usdz":      ("string", "'true' to also download USDZ for AR/Quick Look", false),
            "place_on_card":  ("string", "'true' to also create a scene3D part referencing the new asset", false),
            "part_name":      ("string", "Name for the scene3D part (required when place_on_card='true')", false),
            "left":           ("string", "X position for the scene3D part (default 100)", false),
            "top":            ("string", "Y position (default 100)", false),
            "width":          ("string", "Width in points (default 400)", false),
            "height":         ("string", "Height in points (default 300)", false),
            "on_background":  ("string", "'true' to place the scene3D part on the background", false),
        ]),

        makeTool(name: "generate_3d_model_from_image", description: """
            Generate a 3D model from a single 2D image using Meshy.ai. Exactly one of \
            image_path, image_asset_name, or image_base64 must be set.

            image_asset_name is preferred — keeps bytes local. \
            image_path must be an absolute path under the user's home or temp directory. \
            image_base64 accepts raw base64 (with or without data: prefix), capped at 10 MB.

            Allowed formats: PNG, JPEG, WebP. Cap: 10 MB. Generation: ~90–150 s; 5-min cap.
            """, params: [
            "image_path":        ("string", "Absolute path to a PNG/JPEG/WebP image on disk", false),
            "image_asset_name":  ("string", "Name of an existing image asset in the Sprite Repository", false),
            "image_base64":      ("string", "Raw base64 image bytes (or data: URI), max 10 MB", false),
            "ai_model":          ("string", "meshy-6 (default) | meshy-5 | meshy-4 | latest", false),
            "should_remesh":     ("string", "'true' / 'false'", false),
            "with_usdz":         ("string", "'true' to also download USDZ", false),
            "place_on_card":     ("string", "'true' to also create a scene3D part", false),
            "part_name":         ("string", "Name for the scene3D part (required when place_on_card='true')", false),
            "left":              ("string", "X position (default 100)", false),
            "top":               ("string", "Y position (default 100)", false),
            "width":             ("string", "Width (default 400)", false),
            "height":            ("string", "Height (default 300)", false),
            "on_background":     ("string", "'true' to place on background", false),
        ]),

        makeTool(name: "generate_3d_model_from_images", description: """
            Generate a 3D model from 2–4 images of the same object from different angles \
            (e.g. front / side / back). Multi-view input typically produces higher-fidelity \
            reconstructions than single-image.

            images is a comma-separated list of refs. Each ref must be prefixed with: \
            asset:<name> (preferred), path:<absolute-path>, or base64:<base64-bytes>. Example: \
            images='asset:robot-front,asset:robot-side,asset:robot-back'

            Same image-format and security constraints as generate_3d_model_from_image apply \
            to EACH image. Combined cap: 40 MB. Generation: ~150–300 s; 5-min cap.
            """, params: [
            "images":         ("string", "Comma-separated 2–4 image refs, each prefixed 'asset:', 'path:', or 'base64:'", true),
            "ai_model":       ("string", "meshy-6 (default) | meshy-5 | meshy-4 | latest", false),
            "should_remesh":  ("string", "'true' / 'false'", false),
            "with_usdz":      ("string", "'true' to also download USDZ", false),
            "place_on_card":  ("string", "'true' to also create a scene3D part", false),
            "part_name":      ("string", "Name for the scene3D part (required when place_on_card='true')", false),
            "left":           ("string", "X position (default 100)", false),
            "top":            ("string", "Y position (default 100)", false),
            "width":          ("string", "Width (default 400)", false),
            "height":         ("string", "Height (default 300)", false),
            "on_background":  ("string", "'true' to place on background", false),
        ]),

        makeTool(name: "remesh_3d_model", description: """
            Remesh an existing model3D asset in the Sprite Repository — reduces or \
            increases polygon count while preserving the model's shape and textures. \
            Useful when a generated model is too high-poly for use in a real-time scene \
            OR when the user wants a quad-topology rebuild.

            The source asset MUST have been generated by Meshy (its provenance carries a \
            Meshy task id). If the source was imported from disk or generated before \
            Phase 1, the tool returns an error.

            Generation takes ~30–60 seconds; the wait is capped at 5 minutes. The \
            result is a NEW model3D asset (the source is preserved).

            Requires: (a) the stack has meshyEnabled; (b) the Meshy API key is set.
            """, params: [
            "source_asset_name": ("string", "Name of an existing model3D asset to remesh", true),
            "target_polycount":  ("string", "Target polygon count, 100–300,000", true),
            "topology":          ("string", "triangle (default) | quad", false),
            "place_on_card":     ("string", "'true' to also create a scene3D part referencing the new asset", false),
            "part_name":         ("string", "Name for the scene3D part (required when place_on_card='true')", false),
            "left":              ("string", "X position (default 100)", false),
            "top":               ("string", "Y position (default 100)", false),
            "width":             ("string", "Width (default 400)", false),
            "height":            ("string", "Height (default 300)", false),
            "on_background":     ("string", "'true' to place the scene3D part on the background", false),
        ]),

        makeTool(name: "retexture_3d_model", description: """
            Apply a new texture to an existing model3D asset using a text prompt. \
            The geometry is preserved; only the surface material/texture changes. \
            Useful for color/material variations of the same shape.

            The source asset MUST have been generated by Meshy. \
            Generation takes ~60–120 seconds; capped at 5 minutes.

            Result is a NEW model3D asset (source preserved).
            """, params: [
            "source_asset_name": ("string", "Name of an existing model3D asset to retexture", true),
            "style_prompt":      ("string", "Description of the new texture (max 600 chars)", true),
            "ai_model":          ("string", "meshy-6 (default) | meshy-5 | latest", false),
            "enable_pbr":        ("string", "'true' to generate PBR maps", false),
            "hd_texture":        ("string", "'true' for 4K base color (meshy-6/latest only)", false),
            "place_on_card":     ("string", "'true' to also create a scene3D part", false),
            "part_name":         ("string", "Name for the scene3D part", false),
            "left":              ("string", "X position (default 100)", false),
            "top":               ("string", "Y position (default 100)", false),
            "width":             ("string", "Width (default 400)", false),
            "height":            ("string", "Height (default 300)", false),
            "on_background":     ("string", "'true' to place on background", false),
        ]),

        makeTool(name: "generate_image", description: """
            Generate an image through the configured OpenAI image model and place it as an image part on the current card or current background. \
            Use this when the user asks to add an image/picture/illustration to the card/background that looks like something.
            """, params: [
            "name": ("string", "Image part name", true),
            "prompt": ("string", "Detailed visual description of the image to generate", true),
            "left": ("string", "X position in points. Defaults to 100.", false),
            "top": ("string", "Y position in points. Defaults to 100.", false),
            "width": ("string", "Displayed width in points. Defaults from image aspect ratio.", false),
            "height": ("string", "Displayed height in points. Defaults from image aspect ratio.", false),
            "generation_size": ("string", "OpenAI generation size: 1024x1024, 1536x1024, or 1024x1536. Defaults from requested display aspect.", false),
            "quality": ("string", "Image quality: low, medium, or high. Defaults to the model default.", false),
            "background": ("string", "transparent, opaque, or auto. Optional OpenAI image background mode.", false),
            "transparent_background": ("string", "Set to true only when you want Hype's chroma-key transparentBackground renderer enabled.", false),
            "on_background": ("string", "'true' to place on the background (shared across cards)", false),
            "model": ("string", "Optional OpenAI image model override. Normally omit.", false),
        ]),

        // ------------------------------------------------------------------
        // Scene-node setters. set_node_property handles any writable
        // HypeNodeSpec field via dotted key. set_physics_body is a
        // convenience for bulk physics body configuration.
        // ------------------------------------------------------------------

        makeTool(name: "set_node_property", description: """
            Set a single property on a scene node by dotted key. Covers every writable \
            HypeNodeSpec field: position.x, position.y, zPosition, rotation, xScale, yScale, \
            alpha, isHidden, name, text, fontSize, fontColor, fontName, textStyle, shape.fillColor, \
            shape.strokeColor, shape.lineWidth, shape.cornerRadius, shape.shapeType, \
            physics.enabled, physics.bodyType, physics.isDynamic, physics.restitution, \
            physics.friction, physics.mass, physics.affectedByGravity, physics.allowsRotation, \
            physics.linearDamping, physics.angularDamping, physics.velocityX, \
            physics.velocityY, physics.angularVelocity, emitter.birthRate, \
            emitter.lifetime, emitter.speed, emitter.emissionAngle, emitter.particleColor, \
            emitter.particleScale, emitter.particleAlpha, emitter.particleLifetime, audio.loop, \
            audio.volume, audio.autoplay, audio.positional, video.loop, video.autoplay, \
            camera.target. Prefer this over apply_scene_diff for single-field edits.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node to modify", true),
            "property": ("string", "Property path to set", true),
            "value": ("string", "New value (as a string)", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "set_node_script", description: "Set the HypeTalk script attached to a scene node. Parallels set_scene_script but for individual nodes (the script shown in the node-level Script Editor).", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node", true),
            "script": ("string", "Full HypeTalk script for the node", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "set_physics_body", description: """
            Configure a physics body on a scene node in one call. Use this when the user \
            says something like 'make the ball bounce with restitution 1 and no friction' — \
            it's shorter than multiple set_node_property calls. Any parameter omitted keeps \
            its current value (or the body's default on first configuration).
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node", true),
            "body_type": ("string", "Body geometry: circle, rect, texture, edge, none", false),
            "is_dynamic": ("string", "'true' for dynamic, 'false' for static", false),
            "restitution": ("string", "Bounciness (0.0–1.0+)", false),
            "friction": ("string", "Friction (0.0–1.0)", false),
            "mass": ("string", "Mass", false),
            "affected_by_gravity": ("string", "'true' / 'false'", false),
            "allows_rotation": ("string", "'true' / 'false'", false),
            "velocity_x": ("string", "Initial linear velocity x", false),
            "velocity_y": ("string", "Initial linear velocity y", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "delete_scene_node", description: "Remove a node from a sprite area scene by name.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node to remove", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        // ------------------------------------------------------------------
        // Action authoring on scene nodes.
        // ------------------------------------------------------------------

        makeTool(name: "add_action", description: """
            Queue a SpriteKit action on a scene node. action_type is one of: \
            moveTo, moveBy, rotateTo, rotateBy, scaleTo, scaleBy, fadeTo, fadeIn, fadeOut, \
            sequence, group, repeatForever, repeatCount, wait, removeFromParent, followPath, \
            setTexture, animate, playAudio, stopAudio, changeVolume, resize, hide, unhide, \
            colorize, speedTo, speedBy. Pass per-action inputs in parameters_json as a \
            JSON-encoded map — e.g. {\"x\":\"400\",\"y\":\"300\"} for moveTo/moveBy, \
            {\"angle\":\"90\"} for rotateBy, {\"child_action\":\"rotateBy\",\"child_duration\":\"2\",\"angle\":\"360\"} \
            for repeatForever wrapping a rotation.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node to run the action on", true),
            "action_type": ("string", "Action type (see description)", true),
            "duration": ("string", "Action duration in seconds", false),
            "name": ("string", "Optional action name for later removal", false),
            "parameters_json": ("string", "JSON-encoded {key: value} map for action parameters", false),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "remove_all_actions", description: "Remove every running action from a scene node.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "node_name": ("string", "Name of the node", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        // ------------------------------------------------------------------
        // v3.1: Stack/card/background/scene administration that was
        // reachable only via the UI before. These close the gaps the
        // audit flagged under "Missing Tool Coverage".
        // ------------------------------------------------------------------

        makeTool(name: "set_stack_property", description: """
            Set a stack-level property: width, height, name, defaultFont, theme. `width` and `height` \
            control the canvas size in points. `defaultFont` applies to new parts. \
            `webAssetsAllowed` toggles the stack's AI web-asset search permission. \
            `aiContextCloudSharingAllowed` controls whether attached AI Context Library snippets \
            may be sent to cloud model providers for this stack. \
            `theme` accepts any theme name from `list_themes`; empty value resets to the fallback theme. \
            Use this instead of set_part_property — the stack is not a part.
            """, params: [
            "property": ("string", "Property name: width, height, name, defaultFont, webAssetsAllowed, aiContextCloudSharingAllowed, theme", true),
            "value": ("string", "New value (numeric for width/height, string for name/defaultFont)", true),
        ]),

        makeTool(name: "set_card_property", description: """
            Set one property on a card. Use the current card when card_name is omitted. \
            Supported properties: name, marked, sortKey, backgroundName, theme. \
            `theme` accepts any theme name from `list_themes`; empty value clears the card override. \
            Prefer set_card_script when changing the card's script.
            """, params: [
            "card_name": ("string", "Card name (defaults to current card; accepts 'this card' / 'current card')", false),
            "property": ("string", "Property name: name, marked, sortKey, backgroundName, theme", true),
            "value": ("string", "New value", true),
        ]),

        makeTool(name: "set_background_property", description: """
            Set one property on a background. Uses the current card's background when \
            background_name is omitted. Supported properties: name, sortKey, theme. \
            `theme` accepts any theme name from `list_themes`; empty value clears the background override. \
            Prefer set_background_script when changing the background's script.
            """, params: [
            "background_name": ("string", "Background name (defaults to current background; accepts 'this background' / 'current background')", false),
            "property": ("string", "Property name: name, sortKey, theme", true),
            "value": ("string", "New value", true),
        ]),

        makeTool(name: "set_card_name", description: "Rename a card. Use the current card when card_name is omitted.", params: [
            "card_name": ("string", "Current name of the card (defaults to current card)", false),
            "new_name": ("string", "New name for the card", true),
        ]),

        makeTool(name: "set_background_name", description: "Rename a background.", params: [
            "background_name": ("string", "Current name of the background", true),
            "new_name": ("string", "New name for the background", true),
        ]),

        makeTool(name: "set_card_background", description: "Change which background a card uses by name.", params: [
            "card_name": ("string", "Name of the card (defaults to current card)", false),
            "background_name": ("string", "Name of the background to assign", true),
        ]),

        makeTool(name: "reorder_card", description: "Move a card to a new position in the stack. Positions are 1-based.", params: [
            "card_name": ("string", "Name of the card to move", true),
            "new_position": ("string", "1-based target position", true),
        ]),

        makeTool(name: "duplicate_part", description: "Clone a named part on the current card and offset the copy. The new part's name is the original name with a number suffix unless new_name is given.", params: [
            "part_name": ("string", "Name of the part to duplicate", true),
            "new_name": ("string", "Name for the copy (defaults to '<name> 2')", false),
            "dx": ("string", "Horizontal offset in points (default 20)", false),
            "dy": ("string", "Vertical offset in points (default 20)", false),
        ]),

        makeTool(name: "set_scene_property", description: """
            Set a scene-level property on a sprite area's active scene (or the named scene): \
            gravity (as 'dx,dy'), backgroundColor (hex), isPaused, showsPhysics, showsFPS, \
            showsNodeCount, scaleMode (fill | aspectFill | aspectFit | resizeFill), size (as 'w,h'). \
            Prefer this over apply_scene_diff.sceneUpdates for single-field changes.
            """, params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "property": ("string", "Scene property name", true),
            "value": ("string", "New value (format depends on property)", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        makeTool(name: "add_scene", description: "Add a new named scene to a sprite area. The new scene starts empty and does not become active unless activate is 'true'.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Name for the new scene", true),
            "activate": ("string", "'true' to make this the active scene", false),
        ]),

        makeTool(name: "delete_scene", description: "Remove a scene from a sprite area. Cannot remove the last remaining scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Name of the scene to delete", true),
        ]),

        makeTool(name: "rename_scene", description: "Rename a scene within a sprite area.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Current scene name", true),
            "new_name": ("string", "New scene name", true),
        ]),

        makeTool(name: "set_active_scene", description: "Make a named scene the active scene of a sprite area.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Scene to activate", true),
        ]),

        makeTool(name: "list_scenes", description: "List every scene in a sprite area with its name, size, and whether it's active.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
        ]),

        makeTool(name: "list_scene_physics_fields", description: "List every physics field in a sprite area scene.", params: [
            "sprite_area_name": ("string", "Name of the sprite area part", true),
            "scene_name": ("string", "Optional scene name; defaults to active scene", false),
        ]),

        // ------------------------------------------------------------------
        // v3.2: Symmetric uniform property getter/setters for stack,
        // card, background. Closes the gap noted in the eval set —
        // get_stack_property / set_card_property / etc. were missing.
        // Properties accepted include `theme` so the AI can apply
        // themes without needing a dedicated tool per scope.
        // ------------------------------------------------------------------

        makeTool(name: "get_stack_property", description: """
            Read a stack-level property: name, width, height, defaultFont, script, theme, \
            webAssetsAllowed, aiContextCount, aiContextSummary, aiContextCloudSharingAllowed. \
            Use this instead of get_stack_info when you only need one field.
            """, params: [
            "property": ("string", "Property name to read", true),
        ]),

        makeTool(name: "get_card_property", description: """
            Read a card-level property: name, marked, script, theme, background, effectiveTheme. \
            `effectiveTheme` walks the cascade card→background→stack and returns the resolved name. \
            Use the current card when card_name is omitted.
            """, params: [
            "card_name": ("string", "Card name (defaults to current card; accepts 'this card' / 'current card')", false),
            "property": ("string", "Property name to read", true),
        ]),

        makeTool(name: "set_card_property", description: """
            Set a card-level property: name, marked, script, theme, background. \
            `theme` accepts any theme name from `list_themes` (built-in or stack-local). \
            Setting `theme` to empty string clears the override and lets the cascade fall through. \
            Use the current card when card_name is omitted.
            """, params: [
            "card_name": ("string", "Card name (defaults to current card; accepts 'this card' / 'current card')", false),
            "property": ("string", "Property name to set", true),
            "value": ("string", "New value", true),
        ]),

        makeTool(name: "get_background_property", description: """
            Read a background-level property: name, script, theme, cardCount.
            """, params: [
            "background_name": ("string", "Background name (accepts 'this background' / 'current background')", true),
            "property": ("string", "Property name to read", true),
        ]),

        makeTool(name: "set_background_property", description: """
            Set a background-level property: name, script, theme. \
            `theme` accepts any theme name from `list_themes`; empty value clears the override.
            """, params: [
            "background_name": ("string", "Background name (accepts 'this background' / 'current background')", true),
            "property": ("string", "Property name to set", true),
            "value": ("string", "New value", true),
        ]),

        // ------------------------------------------------------------------
        // v3.2: Theme catalog tools. Themes are document-scoped (live
        // on the .hype file) but built-ins ship with the app and are
        // never deletable. See Sources/HypeCore/Theme/.
        // ------------------------------------------------------------------

        makeTool(name: "list_themes", description: """
            List every theme available to this stack. Output: one line per theme in the form \
            `<name> [built-in|user] [based on <X>]`. Built-ins always appear first.
            """, params: [:]),

        makeTool(name: "create_theme", description: """
            Clone an existing theme into a new user theme on this stack. `base_theme_name` \
            must match a built-in or user theme. `new_name` must be unique within the stack \
            (case-insensitive) and cannot collide with a built-in. `overrides_json` is an \
            optional JSON object whose keys are HypeTheme field names — any key supplied \
            replaces the corresponding field. Examples of overridable keys: `accent`, \
            `cardBackground`, `defaultFontFamily`, `cornerRadiusMedium`, `shadowOpacity`. \
            Color values may be hex (`#FF8800`) or system keys (`system:accentColor`).
            """, params: [
            "base_theme_name": ("string", "Existing theme to clone", true),
            "new_name": ("string", "Name for the new user theme", true),
            "overrides_json": ("string", "JSON object of field overrides", false),
        ]),

        makeTool(name: "duplicate_theme", description: """
            Convenience: duplicate a theme by name. Equivalent to create_theme with no \
            overrides. The new theme's name auto-increments (\"<src> Copy\", \"<src> Copy 2\", …) \
            unless `new_name` is given.
            """, params: [
            "source_theme_name": ("string", "Theme to copy", true),
            "new_name": ("string", "Name for the copy (defaults to '<source> Copy')", false),
        ]),

        makeTool(name: "delete_theme", description: """
            Delete a user theme by name. Refuses to delete a built-in. References from \
            cards/backgrounds clear (cascade falls through). If the stack was using this \
            theme, it resets to the built-in `System` theme.
            """, params: [
            "theme_name": ("string", "User theme to delete", true),
        ]),

        makeTool(name: "set_theme_property", description: """
            Edit a single field on an existing user theme. Refuses to edit a built-in. \
            `property` is any HypeTheme field name (e.g. `accent`, `cardBackground`, \
            `defaultFontFamily`, `cornerRadiusMedium`, `shadowOpacity`). Color values may \
            be hex (`#FF8800`) or system keys (`system:accentColor`).
            """, params: [
            "theme_name": ("string", "User theme to modify", true),
            "property": ("string", "Field name to update", true),
            "value": ("string", "New value", true),
        ]),

        // AI Context Library. These tools expose only user-curated context
        // already attached to the stack; they do not grant arbitrary file-system
        // access.
        makeTool(name: "list_ai_context", description: """
            List the files, images, notes, and directories the user attached to this \
            stack's AI Context Library. Use this before building a complex stack from \
            supplied rules or assets. Returns opaque item IDs, roles, paths, MIME types, \
            and short summaries.
            """, params: [
            "role": ("string", "Optional role filter: rules, asset, styleGuide, example, projectMemory, reference, unknown", false),
        ]),
        makeTool(name: "search_ai_context", description: """
            Search the stack's AI Context Library. Use this instead of broad file tools \
            whenever the user says to use attached files, images, folders, rules, examples, \
            or assets. Returns matching item IDs and snippets.
            """, params: [
            "query": ("string", "Search query, e.g. 'player controls', 'game rules', 'enemy sprite'", true),
            "role": ("string", "Optional role filter: rules, asset, styleGuide, example, projectMemory, reference, unknown", false),
            "limit": ("string", "Maximum results, 1-20. Default 8.", false),
        ]),
        makeTool(name: "read_ai_context_item", description: """
            Read a single AI Context Library item by item_id. Text items return bounded \
            content chunks. Image items return metadata and summary only; use \
            import_context_asset to copy image bytes into the Sprite Repository.
            """, params: [
            "item_id": ("string", "Opaque item ID returned by list_ai_context or search_ai_context", true),
            "max_chars": ("string", "Maximum text characters to return, 1000-20000. Default 12000.", false),
        ]),
        makeTool(name: "import_context_asset", description: """
            Import an image asset from the AI Context Library into the Sprite Repository. \
            Use this before placing an attached image on a card/background or using it as \
            a SpriteKit sprite. The asset_name is the repository display name.
            """, params: [
            "item_id": ("string", "Opaque item ID for an image context item", true),
            "asset_name": ("string", "Sprite Repository asset name. Use short ASCII names like 'player' or 'enemy_ship'.", true),
            "kind": ("string", "Optional asset kind: imageTexture, spriteSheet, tileSet", false),
        ]),
        makeTool(name: "write_ai_context_note", description: """
            Write a durable text note into the current stack's AI Context Library. Use this \
            to remember project decisions, implementation state, TODOs, object naming \
            conventions, known bugs, or user preferences across multiple AI build sessions. \
            Keep notes concise and factual; do not store secrets or API keys.
            """, params: [
            "title": ("string", "Short note title, e.g. 'RPG build state' or 'Current TODOs'", true),
            "text": ("string", "Project-memory note body. Maximum 20,000 characters; keep it concise.", true),
            "role": ("string", "Optional role: projectMemory (default), rules, styleGuide, example, reference, unknown", false),
        ]),

        // Web access
        makeTool(name: "fetch_url", description: "Fetch content from a URL. Returns the response text.", params: [
            "url": ("string", "URL to fetch", true),
        ]),

        // File access
        makeTool(name: "read_file", description: "Read the contents of a local file.", params: [
            "path": ("string", "File path to read", true),
        ]),
        makeTool(name: "write_file", description: "Write content to a local file.", params: [
            "path": ("string", "File path to write", true),
            "content": ("string", "Content to write", true),
        ]),
        makeTool(name: "list_directory", description: "List files in a directory.", params: [
            "path": ("string", "Directory path", true),
        ]),

        // Visual capture
        makeTool(name: "capture_card_image", description: """
            Render the current card (or a named card) to a PNG image and attach it to your next \
            reasoning step. Use this to (a) verify a layout you just modified, (b) assess visual \
            polish before suggesting changes, or (c) form a mental picture of an unfamiliar card. \
            The image arrives as a synthetic user message on your next turn; you do not receive \
            bytes here. The image shows pure card content (buttons, fields, shapes, text, images) \
            but does NOT include macOS chrome, selection handles, alignment guides, or live \
            SpriteKit/video frames — those render as their static placeholder. You have a budget \
            of \(CardCaptureBudget.maxPerSession) captures per chat session and at most one capture \
            per turn. The host will tell you how many captures remain in the result message.
            """, params: [
            "card_name": ("string", "Optional. The name of the card to capture. Defaults to the current card when omitted or empty.", false),
            "purpose": ("string", "Optional. A short free-text reason for the capture (e.g. 'verify button alignment'). Recorded in the chat log so the user understands why you are looking. Never executed.", false),
        ]),
    ]

    /// Default AI authoring surface for the in-app assistant.
    ///
    /// Broad filesystem and web-mutation tools remain available for
    /// explicit use elsewhere, but the scene authoring loop should stay
    /// constrained to stack-aware operations.
    public static let authoringTools: [OllamaTool] = allTools.filter {
        let blocked = Set([
            "fetch_url",
            "read_file",
            "write_file",
            "list_directory",
        ])
        return !blocked.contains($0.function.name)
    }

    /// Default card/background authoring surface for ordinary Hype layouts.
    ///
    /// The in-app assistant uses this unless a request is explicitly routed to
    /// SpriteKit. Keeping scene/node tools out of the default catalog prevents
    /// form prompts such as "make a customer entry form" from satisfying labels
    /// via `add_label_to_scene` and accidentally creating a sprite scene.
    public static let cardControlAuthoringTools: [OllamaTool] = allTools.filter {
        let allowed = Set([
            // Stack/card/background management
            "create_card",
            "create_background",
            "go_to_card",
            "delete_card",
            "set_card_name",
            "set_background_name",
            "set_card_background",
            "reorder_card",
            "list_all_cards",
            "list_backgrounds",
            "get_stack_info",
            // Basic part creation and mutation
            "create_button",
            "create_field",
            "create_label",
            "create_shape",
            "create_image",
            "generate_image",
            "generate_3d_model_from_text",
            "generate_3d_model_from_image",
            "generate_3d_model_from_images",
            "remesh_3d_model",
            "retexture_3d_model",
            "list_3d_models",
            "create_webpage",
            "create_video",
            "create_chart",
            "create_calendar",
            "create_pdf",
            "create_map",
            "add_map_annotation",
            "clear_map_annotations",
            "create_color_well",
            "create_stepper",
            "create_slider",
            "create_segmented",
            "create_audio_recorder",
            "create_scene3d",
            "create_progressview",
            "create_gauge",
            "create_divider",
            "set_image_filter",
            "duplicate_part",
            "delete_part",
            "get_card_parts",
            "get_background_parts",
            "list_repository_assets",
            "generate_sprite_asset",
            "get_part_property",
            "list_all_properties",
            "set_part_property",
            // Stack/card/background properties and scripts
            "get_stack_property",
            "set_stack_property",
            "get_card_property",
            "set_card_property",
            "get_background_property",
            "set_background_property",
            "get_card_script",
            "set_card_script",
            "get_background_script",
            "set_background_script",
            "get_stack_script",
            "set_stack_script",
            // Chart helpers and script validation
            "get_chart_data_points",
            "set_chart_data_point_color",
            "write_ai_context_note",
            "check_script",
            // Narrow current-card remediation for prior bad form output
            "repair_form_controls",
            // Visual capture — available on all authoring surfaces
            "capture_card_image",
        ])
        return allowed.contains($0.function.name)
    }

    /// Narrowed AI surface for SpriteKit scene editing.
    ///
    /// This intentionally excludes generic part-script/property tools so
    /// SpriteKit-area requests stay scene-first unless the user explicitly
    /// asks for HypeTalk scripting.
    public static let spriteSceneAuthoringTools: [OllamaTool] = allTools.filter {
        // v3.1 (Apr 2026): this allowlist used to exclude part-level
        // authoring tools to "steer the model toward scene tools".
        // That steering is now handled by the system prompt's
        // `TOOL-USE PRIORITIES` block (in AIChatPanel.swift) and
        // the corpus. Removing part tools from the catalog forced
        // the model into a corner when the user asked for a part
        // operation on a card that happened to contain a sprite
        // area — the model physically could not call
        // `set_part_property` even when the user explicitly asked
        // for it. v3.1 widens the allowlist to cover both surfaces.
        let allowed = Set([
            // Scene-level creation / diagnostics
            "create_sprite_area",
            "get_scene_spec",
            "get_scene_script",
            "set_scene_script",
            "apply_scene_diff",
            "capture_scene_snapshot",
            "get_scene_diagnostics",
            // Node creators (one per node type)
            "add_sprite_to_scene",
            "add_label_to_scene",
            "add_shape_to_scene",
            "add_emitter_to_scene",
            "add_audio_to_scene",
            "add_video_to_scene",
            "add_group_to_scene",
            "create_camera",
            "create_tilemap",
            // Tile-map authoring
            "classify_asset_as_tileset",
            "set_tile",
            "fill_tilemap",
            "get_tilemap_info",
            // Node read/write
            "list_scene_nodes",
            "list_scene_joints",
            "list_scene_constraints",
            "get_node_property",
            "get_node_script",
            "set_node_property",
            "set_node_script",
            "set_physics_body",
            "delete_scene_node",
            // Physics relationships + fields
            "add_joint_to_scene",
            "add_constraint_to_scene",
            "add_physics_field_to_scene",
            // Actions
            "add_action",
            "remove_all_actions",
            // Script/scene helpers the AI still needs alongside scene tools
            "set_card_script",
            "set_background_script",
            "set_stack_script",
            "get_card_script",
            "get_background_script",
            "get_stack_script",
            "get_stack_property",
            "get_card_property",
            "get_background_property",
            "set_stack_property",
            "set_card_property",
            "set_background_property",
            // Part-level authoring — kept in so the user can still
            // say "set the text of button play" on a card that
            // happens to contain a sprite area.
            "set_part_property",
            "get_part_property",
            "list_all_properties",
            "create_button",
            "create_field",
            "create_label",
            "create_shape",
            "create_image",
            "generate_image",
            "generate_3d_model_from_text",
            "generate_3d_model_from_image",
            "generate_3d_model_from_images",
            "remesh_3d_model",
            "retexture_3d_model",
            "list_3d_models",
            "create_webpage",
            "create_video",
            "create_chart",
            "create_calendar",
            "create_pdf",
            "create_map",
            "add_map_annotation",
            "clear_map_annotations",
            "create_color_well",
            "create_stepper",
            "create_slider",
            "create_segmented",
            "create_audio_recorder",
            "create_scene3d",
            "create_progressview",
            "create_gauge",
            "create_divider",
            "set_image_filter",
            "repair_form_controls",
            "delete_part",
            "set_card_name",
            "set_background_name",
            "set_card_background",
            "reorder_card",
            "duplicate_part",
            "set_scene_property",
            "add_scene",
            "delete_scene",
            "rename_scene",
            "set_active_scene",
            "list_scenes",
            "list_scene_physics_fields",
            // Stack introspection
            "get_card_parts",
            "get_background_parts",
            "get_stack_info",
            "list_all_cards",
            "list_backgrounds",
            // Property accessors (uniform getters/setters for stack/card/bg)
            "get_stack_property",
            "get_card_property",
            "set_card_property",
            "get_background_property",
            "set_background_property",
            // Theme catalog
            "list_themes",
            "create_theme",
            "duplicate_theme",
            "delete_theme",
            "set_theme_property",
            // Chart helpers
            "get_chart_data_points",
            "set_chart_data_point_color",
            // Repository + validation (already in the prior allowlist)
            "list_repository_assets",
            "import_repository_asset",
            "generate_sprite_asset",
            "write_ai_context_note",
            "check_script",
            // Visual capture — available on all authoring surfaces
            "capture_card_image",
        ])
        return allowed.contains($0.function.name)
    }

    /// Tool surface used by the Sprite Repository chat panel.
    ///
    /// This is intentionally repository-only so a sprite-library prompt
    /// cannot mutate card layout or scripts through the wrong surface.
    public static let spriteRepositoryAuthoringTools: [OllamaTool] = allTools.filter {
        let allowed = Set([
            "list_repository_assets",
            "import_repository_asset",
            "generate_sprite_asset",
            "classify_asset_as_tileset",
            "write_ai_context_note",
        ])
        return allowed.contains($0.function.name)
    }

    // MARK: - Web Asset Search Tools

    /// The three web-asset search / import tools. Kept separate so they can
    /// be conditionally added to any tool list via `withWebAssetTools(_:enabled:)`.
    public static let webAssetTools: [OllamaTool] = [
        makeTool(
            name: "search_web_for_sprite",
            description: """
                Search a licensed image provider (Openverse, Wikimedia Commons, or Pexels) \
                for a sprite asset matching a keyword query. Returns a list of candidate_id \
                strings with metadata (title, dimensions, license). Candidates are only valid \
                for the current chat session. Call import_web_asset to download and install one.
                """,
            params: [
                "query":       ("string", "Keyword query describing the desired image", true),
                "max_results": ("string", "Maximum results to return (1-20, default 8)", false),
            ]
        ),
        makeTool(
            name: "import_web_asset",
            description: """
                Download and install a web-asset candidate (from a prior search_web_for_sprite \
                call) into the stack's Sprite Repository. The asset_name is used as the asset's \
                display name — use short ASCII names like "dragon" or "background_sky". \
                Attribution is automatically added to the stack script.
                """,
            params: [
                "candidate_id": ("string", "candidate_id from a prior search_web_for_sprite result", true),
                "asset_name":   ("string", "Display name for the imported asset (ASCII, 1-128 chars)", true),
            ]
        ),
        makeTool(
            name: "find_and_import_sprite",
            description: """
                Convenience: search for an image, pick the first result, and import it — \
                all in one step. Use this when you know what you want and don't need to \
                inspect candidates first. The asset_name is used as the display name in the \
                repository. Attribution is added automatically.
                """,
            params: [
                "query":      ("string", "Keyword query describing the desired image", true),
                "asset_name": ("string", "Display name for the imported asset (ASCII, 1-128 chars)", true),
            ]
        ),
    ]

    /// Return a copy of `base` with the web-asset tools appended when `enabled` is true.
    ///
    /// This is the canonical gate between the stack's `webAssetsAllowed` flag and
    /// the model's available tool schema. When the stack has web assets disabled,
    /// the tools are simply absent from the list — the model cannot even see them.
    ///
    /// - Parameters:
    ///   - base: The existing tool list (e.g. `authoringTools` or `spriteSceneAuthoringTools`).
    ///   - enabled: Whether `Stack.webAssetsAllowed` is true for the current document.
    /// - Returns: `base` unchanged when `enabled` is false; `base + webAssetTools` otherwise.
    public static func withWebAssetTools(_ base: [OllamaTool], enabled: Bool) -> [OllamaTool] {
        guard enabled else { return base }
        return base + webAssetTools
    }

    /// Narrow AI Context Library read/import tools. Kept separate so the chat
    /// layer can withhold existing stack context from cloud models until the
    /// user explicitly opts this stack into cloud context sharing. The
    /// write-only project-memory note tool is also listed here for enabled
    /// context surfaces, but may be present in base authoring surfaces because
    /// it does not expose existing context contents.
    public static let aiContextTools: [OllamaTool] = allTools.filter {
        Set([
            "list_ai_context",
            "search_ai_context",
            "read_ai_context_item",
            "import_context_asset",
            "write_ai_context_note",
        ]).contains($0.function.name)
    }

    public static func withAIContextTools(_ base: [OllamaTool], enabled: Bool) -> [OllamaTool] {
        guard enabled else { return base }
        let existing = Set(base.map { $0.function.name })
        return base + aiContextTools.filter { !existing.contains($0.function.name) }
    }

    // MARK: - Tool builder

    /// Build an OllamaTool from a name, description, and parameter map.
    /// Each parameter entry is: name -> (type, description, required).
    private static func makeTool(
        name: String,
        description: String,
        params: [String: (String, String, Bool)]
    ) -> OllamaTool {
        var properties: [String: OllamaProperty] = [:]
        var required: [String] = []
        for (key, val) in params {
            properties[key] = OllamaProperty(type: val.0, description: val.1)
            if val.2 { required.append(key) }
        }
        return OllamaTool(
            type: "function",
            function: OllamaFunction(
                name: name,
                description: description,
                parameters: OllamaParameters(type: "object", properties: properties, required: required)
            )
        )
    }
}
