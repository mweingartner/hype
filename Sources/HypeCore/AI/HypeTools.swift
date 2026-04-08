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
            "style": ("string", "Button style: roundRect, rectangle, default, oval, shadow, checkBox, radioButton", false),
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

        makeTool(name: "create_chart", description: "Create a chart control with data. Use the 'data' parameter for simple data (e.g., 'Jan=120,Feb=150,Mar=180') or 'data_json' for JSON format.", params: [
            "name": ("string", "Chart name", true),
            "chart_type": ("string", "Chart type: bar, line, area, point, pie, rule", true),
            "title": ("string", "Chart title", false),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width", true),
            "height": ("string", "Height", true),
            "data": ("string", "Simple data format: label=value pairs separated by commas, e.g. 'Jan=120,Feb=150,Mar=180'", false),
            "data_json": ("string", "JSON array of data points: [{\"label\":\"Jan\",\"value\":120}]", false),
            "series_name": ("string", "Series name", false),
            "series_color": ("string", "Series color hex, e.g. #FF6B6B", false),
            "on_background": ("string", "true to place on background", false),
        ]),

        // Part modification
        makeTool(name: "set_part_property", description: """
            Set a property on a part by name. Available properties: name, left, top, width, height, \
            text, url, videoURL, chartdata, charttype, charttitle, fillColor, strokeColor, strokeWidth, cornerRadius, visible, enabled, hilite, \
            autoHilite, showName, lockText, textFont, textSize, textAlign, textStyle, script, style. \
            For 'style': button styles are transparent/opaque/rectangle/roundRect/shadow/checkBox/radioButton/standard/default/popup/oval/toggle. \
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
