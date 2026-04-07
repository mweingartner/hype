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
        makeTool(name: "go_to_card", description: "Navigate to a card by name or direction (next, previous, first, last).", params: [
            "destination": ("string", "Card name or direction: next, previous, first, last", true),
        ]),
        makeTool(name: "delete_card", description: "Delete the current card.", params: [:]),

        // Part creation
        makeTool(name: "create_button", description: "Create a button on the current card.", params: [
            "name": ("string", "Button name/label", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "style": ("string", "Button style: roundRect, rectangle, default, oval, shadow, checkBox, radioButton", false),
            "script": ("string", "HypeTalk script to attach", false),
        ]),
        makeTool(name: "create_field", description: "Create a text field on the current card.", params: [
            "name": ("string", "Field name", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "text": ("string", "Default text content", false),
            "style": ("string", "Field style: rectangle, scrolling, shadow, transparent", false),
            "script": ("string", "HypeTalk script to attach", false),
        ]),
        makeTool(name: "create_shape", description: "Create a shape (rectangle, oval, line, roundRect, freeform) on the current card.", params: [
            "name": ("string", "Shape name", true),
            "shape_type": ("string", "Shape type: rectangle, roundRect, oval, line", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
            "fill_color": ("string", "Fill color hex, e.g. #FF0000", false),
            "stroke_color": ("string", "Stroke color hex", false),
            "stroke_width": ("string", "Stroke width in points", false),
        ]),
        makeTool(name: "create_webpage", description: "Create a web page viewer on the current card that displays a URL.", params: [
            "name": ("string", "Webpage part name", true),
            "url": ("string", "URL to display", true),
            "left": ("string", "X position", true),
            "top": ("string", "Y position", true),
            "width": ("string", "Width in points", true),
            "height": ("string", "Height in points", true),
        ]),

        // Part modification
        makeTool(name: "set_part_property", description: "Set a property on a part by name. Properties: name, left, top, width, height, text, url, fillColor, strokeColor, visible, enabled, script.", params: [
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
