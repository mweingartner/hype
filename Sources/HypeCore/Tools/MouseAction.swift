import Foundation
#if canImport(CoreGraphics)
import CoreGraphics

/// Result of processing a mouse event.
public enum MouseActionResult: Sendable {
    case none
    case selectPart(UUID)
    case deselectAll
    case sendMessage(partId: UUID, message: String)
    case createPart(PartType, CGRect, [String: String])
    case movePart(UUID, dx: Double, dy: Double)
    case beginDrag(startX: Double, startY: Double)
}

/// Process mouse events based on tool state.
public struct MouseHandler: Sendable {

    public init() {}

    /// Handle mouseDown given the current tool state and hit test result.
    public func handleMouseDown(
        tool: ToolState,
        hitPart: Part?,
        point: CGPoint
    ) -> MouseActionResult {
        switch tool.category {
        case .browse:
            if let part = hitPart {
                return .sendMessage(partId: part.id, message: "mouseDown")
            }
            return .none

        case .edit:
            if tool.currentTool == "select" {
                if let part = hitPart {
                    return .selectPart(part.id)
                }
                return .deselectAll
            }
            // For button/field/shape/webpage tools, start drag-to-create
            return .beginDrag(startX: Double(point.x), startY: Double(point.y))

        case .paint:
            return .beginDrag(startX: Double(point.x), startY: Double(point.y))
        }
    }

    /// Handle mouseUp for creation tools.
    public func handleMouseUp(
        tool: ToolState,
        hitPart: Part?,
        dragStart: CGPoint?,
        point: CGPoint
    ) -> MouseActionResult {
        switch tool.category {
        case .browse:
            if let part = hitPart {
                return .sendMessage(partId: part.id, message: "mouseUp")
            }
            return .none

        case .edit:
            guard tool.currentTool != "select" else { return .none }
            guard let start = dragStart else { return .none }
            let rect = CGRect(
                x: min(Double(start.x), Double(point.x)),
                y: min(Double(start.y), Double(point.y)),
                width: abs(Double(point.x - start.x)),
                height: abs(Double(point.y - start.y))
            )
            guard rect.width > 5 && rect.height > 5 else { return .none }

            let partType: PartType
            var extras: [String: String] = [:]
            switch tool.currentTool {
            case "button": partType = .button
            case "field": partType = .field
            case "shape": partType = .shape; extras["shapeType"] = "rectangle"
            case "webpage": partType = .webpage
            default: return .none
            }
            return .createPart(partType, rect, extras)

        case .paint:
            return .none
        }
    }
}
#endif
