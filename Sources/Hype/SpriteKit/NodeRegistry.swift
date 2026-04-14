import SpriteKit
import HypeCore

/// Maps Hype UUIDs to live SKNode instances. MainActor-isolated.
@MainActor
final class NodeRegistry {
    private var nodesByID: [UUID: SKNode] = [:]
    private var idsByNode: [ObjectIdentifier: UUID] = [:]

    func register(id: UUID, node: SKNode) {
        nodesByID[id] = node
        idsByNode[ObjectIdentifier(node)] = id
    }

    func unregister(id: UUID) {
        if let node = nodesByID.removeValue(forKey: id) {
            idsByNode.removeValue(forKey: ObjectIdentifier(node))
        }
    }

    func node(for id: UUID) -> SKNode? { nodesByID[id] }
    func id(for node: SKNode) -> UUID? { idsByNode[ObjectIdentifier(node)] }
    func allIDs() -> [UUID] { Array(nodesByID.keys) }
    func clear() { nodesByID.removeAll(); idsByNode.removeAll() }
}
