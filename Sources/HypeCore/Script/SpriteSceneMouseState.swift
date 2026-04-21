import Foundation

/// Shared state tracking the sprite currently under the mouse cursor
/// in the active sprite-area scene. Written by the view layer
/// (`CardCanvasView.spriteScene(_:didReceiveEvent:)` on every
/// `.mouseWithin`) and read by the interpreter's `the hoveredSprite`
/// / `the spriteUnderMouse` property evaluator.
///
/// Exists so AI-generated scripts asking "is the cursor over sprite
/// X?" can be answered with a single property read — without making
/// the AI invent unparseable grammar like `the name of node at
/// mouse location`. The property update path is:
///
///   HypeSKScene.mouseMoved
///     → CardCanvasView.spriteScene(... .mouseWithin(nodeId, pos))
///       → resolve nodeId → Hype node name
///       → SpriteSceneMouseState.shared.hoveredSprite = name
///
///   HypeTalk evaluate `the hoveredSprite`
///     → MainActor.run { SpriteSceneMouseState.shared.hoveredSprite }
///     → returns the sprite's name (or "" when no sprite is under the
///       cursor)
///
/// The state is global (one value per process), which is a simplification
/// that matches current usage — only one sprite-area scene is typically
/// under the cursor at a time. If that assumption ever breaks (multiple
/// overlapping sprite areas), this should be keyed by the owning
/// sprite-area part ID.
public final class SpriteSceneMouseState: @unchecked Sendable {

    public static let shared = SpriteSceneMouseState()

    private var _hoveredSprite: String = ""
    private let lock = NSLock()

    /// Name of the sprite currently under the mouse cursor in the
    /// active scene, or empty string when the cursor is over the
    /// scene background / outside any sprite. Reads and writes are
    /// serialised by an `NSLock` so cross-thread access (view-layer
    /// writes on main, interpreter reads from a background Task) is
    /// safe even without `@MainActor` isolation.
    public var hoveredSprite: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _hoveredSprite
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _hoveredSprite = newValue
        }
    }

    private init() {}
}
