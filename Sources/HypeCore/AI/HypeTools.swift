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
            "style": ("string", "Field style: rectangle, scrolling, shadow, transparent", false),
            "script": ("string", "HypeTalk script to attach", false),
            "on_background": ("string", "Set to 'true' to place on the card's background (shared across cards)", false),
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
        makeTool(name: "apply_scene_diff", description: """
            Apply a JSON diff to modify a sprite scene incrementally. Pass diff_json as a \
            JSON STRING whose top-level keys are optional: addNodes (array of HypeNodeSpec), \
            removeNodeIds (array of UUIDs), updateNodes (array of NodeUpdate), and sceneUpdates \
            (object with gravity, backgroundColor, isPaused). A HypeNodeSpec needs at least \
            {id, name, nodeType, position:{x,y}}; nodeType is one of sprite, label, shape, \
            emitter, audio, tileMap, camera, video, crop, effect, light, group. For labels \
            include {text, fontSize, fontColor}. For shapes include shapeSpec:{shapeType, \
            fillColor, strokeColor, lineWidth}. Every id must be a valid lowercase UUID. \
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

        // Part modification
        makeTool(name: "set_part_property", description: """
            Set a property on a part by name. Available properties: name, left, top, width, height, \
            text, url, videoURL, fillColor, strokeColor, strokeWidth, cornerRadius, visible, enabled, hilite, \
            autoHilite, showName, lockText, textFont, textSize, textAlign, textStyle, script, style. \
            Chart-specific properties: chartdata, charttype, charttitle, x_axis_label, y_axis_label, \
            show_legend, show_grid. \
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

        // Information
        makeTool(name: "get_stack_info", description: "Get information about the current stack: card count, background names, current card.", params: [:]),
        makeTool(name: "get_card_parts", description: "List all parts on the current card with their properties.", params: [:]),

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

    /// Narrowed AI surface for SpriteKit scene editing.
    ///
    /// This intentionally excludes generic part-script/property tools so
    /// SpriteKit-area requests stay scene-first unless the user explicitly
    /// asks for HypeTalk scripting.
    public static let spriteSceneAuthoringTools: [OllamaTool] = allTools.filter {
        let allowed = Set([
            "create_sprite_area",
            "get_scene_spec",
            "apply_scene_diff",
            "add_sprite_to_scene",
            "create_tilemap",
            "classify_asset_as_tileset",
            "set_tile",
            "fill_tilemap",
            "get_tilemap_info",
            "create_camera",
            "capture_scene_snapshot",
            "get_scene_diagnostics",
            "list_repository_assets",
            "import_repository_asset",
        ])
        return allowed.contains($0.function.name)
    }

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
