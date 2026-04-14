import SpriteKit
import HypeCore

/// Protocol for SKNodes that represent Hype parts directly in the SpriteKit scene graph.
/// Conforming nodes live in the CardSKScene's nativeLayer and render parts
/// using native SpriteKit primitives instead of CGContext drawing.
@MainActor
protocol CardPartNode: AnyObject {
    /// The unique identifier of the Hype part this node represents.
    var partId: UUID { get }
    /// Update the node's visual properties to match the current part state.
    func updateFromPart(_ part: Part)
}
