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
        case "button", "field", "shape", "webpage", "image", "video", "chart", "select": return .edit
        default: return .paint
        }
    }

    public var isEditMode: Bool { category != .browse }

    public mutating func selectTool(_ tool: String) {
        currentTool = tool
        selectedPartId = nil
    }
}
