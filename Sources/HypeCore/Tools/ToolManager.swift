import Foundation

/// Categories of tools.
public enum ToolCategory: Sendable {
    case browse, edit, paint
}

/// Manages the current tool and provides tool metadata.
public struct ToolState: Sendable {
    public var currentTool: String  // matches ToolName.rawValue
    public var selectedPartId: UUID?

    public init(currentTool: String = "browse") {
        self.currentTool = currentTool
        self.selectedPartId = nil
    }

    public var category: ToolCategory {
        switch currentTool {
        case "browse": return .browse
        // Object-creation / selection tools — the category that
        // routes mouseUp through the drag-to-create part path
        // (CardCanvasView.mouseUp's .edit branch).
        case "button", "field", "shape", "webpage", "image", "video",
             "chart", "spriteArea", "select",
             // Phase 1 framework controls.
             "calendar", "pdf", "map", "colorWell",
             // Phase 2 form controls.
             "stepper", "slider", "toggle", "segmented",
             // Phase 2 media + 3D.
             "audioRecorder", "scene3D":
            return .edit
        // Everything else (rect, oval, line, pencil, spray, bucket,
        // eraser, text) is a drag-to-paint or drag-to-create-shape
        // shortcut routed through the .paint category. The mouseUp
        // for those tools handles part creation directly via the
        // tool-specific switch in CardCanvasView (lines 1946+).
        default: return .paint
        }
    }

    public var isEditMode: Bool { category != .browse }

    public mutating func selectTool(_ tool: String) {
        currentTool = tool
        selectedPartId = nil
    }
}
