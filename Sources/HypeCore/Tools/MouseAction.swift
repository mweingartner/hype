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
            // For creation tools, start drag-to-place/create. The final rect
            // is resolved on mouseUp so a click can still create a HIG-sized
            // default part.
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
        point: CGPoint,
        fineControl: Bool = false
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
            guard let spec = PartCreationDefaults.toolSpec(for: tool.currentTool) else {
                return .none
            }
            let rect = PartCreationDefaults.creationRect(
                for: spec.partType,
                dragStart: start,
                currentPoint: point,
                fineControl: fineControl
            )
            return .createPart(spec.partType, rect, spec.extras)

        case .paint:
            return .none
        }
    }
}
#endif
