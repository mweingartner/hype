import Foundation

/// Top-level scene property updates.
public struct SceneUpdate: Codable, Sendable {
    public var name: String?
    public var size: SizeSpec?
    public var gravity: VectorSpec?
    public var backgroundColor: String?
    public var script: String?
    public var isPaused: Bool?
    public var showsPhysics: Bool?
    public var showsFPS: Bool?
    public var showsNodeCount: Bool?
    public var scaleMode: SceneScaleMode?

    public init(
        name: String? = nil,
        size: SizeSpec? = nil,
        gravity: VectorSpec? = nil,
        backgroundColor: String? = nil,
        script: String? = nil,
        isPaused: Bool? = nil,
        showsPhysics: Bool? = nil,
        showsFPS: Bool? = nil,
        showsNodeCount: Bool? = nil,
        scaleMode: SceneScaleMode? = nil
    ) {
        self.name = name
        self.size = size
        self.gravity = gravity
        self.backgroundColor = backgroundColor
        self.script = script
        self.isPaused = isPaused
        self.showsPhysics = showsPhysics
        self.showsFPS = showsFPS
        self.showsNodeCount = showsNodeCount
        self.scaleMode = scaleMode
    }
}

/// A set of property changes to apply to a single node.
public struct NodeUpdate: Codable, Sendable {
    public var id: UUID
    public var properties: [String: String]
    public var addActions: [ActionSpec]?
    public var removeAllActions: Bool?
    public var addChildren: [HypeNodeSpec]?
    public var removeChildIds: [UUID]?

    public init(
        id: UUID,
        properties: [String: String] = [:],
        addActions: [ActionSpec]? = nil,
        removeAllActions: Bool? = nil,
        addChildren: [HypeNodeSpec]? = nil,
        removeChildIds: [UUID]? = nil
    ) {
        self.id = id
        self.properties = properties
        self.addActions = addActions
        self.removeAllActions = removeAllActions
        self.addChildren = addChildren
        self.removeChildIds = removeChildIds
    }
}

/// A diff that can be applied to a SceneSpec to produce an updated scene.
public struct SceneDiff: Codable, Sendable {
    public var addNodes: [HypeNodeSpec]?
    public var removeNodeIds: [UUID]?
    public var updateNodes: [NodeUpdate]?
    public var sceneUpdates: SceneUpdate?

    public init(
        addNodes: [HypeNodeSpec]? = nil,
        removeNodeIds: [UUID]? = nil,
        updateNodes: [NodeUpdate]? = nil,
        sceneUpdates: SceneUpdate? = nil
    ) {
        self.addNodes = addNodes
        self.removeNodeIds = removeNodeIds
        self.updateNodes = updateNodes
        self.sceneUpdates = sceneUpdates
    }

    /// Apply this diff to a scene spec, mutating it in place.
    public func apply(to spec: inout SceneSpec) {
        // Add new nodes
        if let nodesToAdd = addNodes {
            spec.nodes.append(contentsOf: nodesToAdd)
        }

        // Remove nodes by ID (recursive through children)
        if let idsToRemove = removeNodeIds {
            for id in idsToRemove {
                SceneDiff.removeNode(id: id, from: &spec.nodes)
            }
        }

        // Update existing nodes
        if let updates = updateNodes {
            for update in updates {
                SceneDiff.applyNodeUpdate(update, to: &spec.nodes)
            }
        }

        // Apply scene-level updates
        if let updates = sceneUpdates {
            if let name = updates.name { spec.name = name }
            if let size = updates.size { spec.size = size }
            if let gravity = updates.gravity { spec.gravity = gravity }
            if let bg = updates.backgroundColor { spec.backgroundColor = bg }
            if let script = updates.script { spec.script = script }
            if let paused = updates.isPaused { spec.isPaused = paused }
            if let physics = updates.showsPhysics { spec.showsPhysics = physics }
            if let fps = updates.showsFPS { spec.showsFPS = fps }
            if let count = updates.showsNodeCount { spec.showsNodeCount = count }
            if let mode = updates.scaleMode { spec.scaleMode = mode }
        }
    }

    // MARK: - Private Helpers

    /// Recursively remove a node with the given ID from a node array.
    private static func removeNode(id: UUID, from nodes: inout [HypeNodeSpec]) {
        nodes.removeAll { $0.id == id }
        for i in nodes.indices {
            removeNode(id: id, from: &nodes[i].children)
        }
    }

    /// Recursively find a node by ID and apply property updates.
    private static func applyNodeUpdate(_ update: NodeUpdate, to nodes: inout [HypeNodeSpec]) {
        for i in nodes.indices {
            if nodes[i].id == update.id {
                applyProperties(update, to: &nodes[i])
                return
            }
            applyNodeUpdate(update, to: &nodes[i].children)
        }
    }

    /// Apply a NodeUpdate's properties to a single node.
    private static func applyProperties(_ update: NodeUpdate, to node: inout HypeNodeSpec) {
        for (key, value) in update.properties {
            switch key {
            case "position.x":
                if let v = Double(value) { node.position.x = v }
            case "position.y":
                if let v = Double(value) { node.position.y = v }
            case "size.width":
                if let v = Double(value) {
                    if node.size == nil { node.size = SizeSpec() }
                    node.size?.width = v
                }
            case "size.height":
                if let v = Double(value) {
                    if node.size == nil { node.size = SizeSpec() }
                    node.size?.height = v
                }
            case "rotation":
                if let v = Double(value) { node.rotation = v }
            case "xScale":
                if let v = Double(value) { node.xScale = v }
            case "yScale":
                if let v = Double(value) { node.yScale = v }
            case "alpha":
                if let v = Double(value) { node.alpha = v }
            case "isHidden":
                node.isHidden = (value == "true")
            case "zPosition":
                if let v = Double(value) { node.zPosition = v }
            case "name":
                node.name = value
            case "text":
                node.text = value
            case "fontName":
                node.fontName = value
            case "fontSize":
                if let v = Double(value) { node.fontSize = v }
            case "fontColor":
                node.fontColor = value
            case "script":
                node.script = value
            case "shape.shapeType":
                if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
                if let shapeType = SpriteShapeType(rawValue: value) {
                    node.shapeSpec?.shapeType = shapeType
                }
            case "shape.fillColor":
                if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
                node.shapeSpec?.fillColor = value
            case "shape.strokeColor":
                if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
                node.shapeSpec?.strokeColor = value
            case "shape.lineWidth":
                if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
                if let v = Double(value) { node.shapeSpec?.lineWidth = v }
            case "shape.cornerRadius":
                if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
                if let v = Double(value) { node.shapeSpec?.cornerRadius = v }
            case "physics.enabled":
                if value.lowercased() == "true" {
                    if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                } else {
                    node.physicsBody = nil
                }
            case "physics.bodyType":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                if let bodyType = PhysicsBodyType(rawValue: value) {
                    node.physicsBody?.bodyType = bodyType
                }
            case "physics.isDynamic":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.isDynamic = (value.lowercased() == "true")
            case "physics.restitution":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                if let v = Double(value) { node.physicsBody?.restitution = v }
            case "physics.friction":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                if let v = Double(value) { node.physicsBody?.friction = v }
            case "physics.affectedByGravity":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.affectedByGravity = (value.lowercased() == "true")
            case "physics.allowsRotation":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.allowsRotation = (value.lowercased() == "true")
            case "physics.linearDamping":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.linearDamping = Double(value)
            case "physics.angularDamping":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.angularDamping = Double(value)
            case "physics.velocityX":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.velocityX = Double(value)
            case "physics.velocityY":
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
                node.physicsBody?.velocityY = Double(value)
            default:
                break
            }
        }

        // Remove all actions if requested
        if update.removeAllActions == true {
            node.actions = []
        }

        // Add new actions
        if let actionsToAdd = update.addActions {
            node.actions.append(contentsOf: actionsToAdd)
        }

        // Remove child nodes by ID
        if let childIdsToRemove = update.removeChildIds {
            for id in childIdsToRemove {
                node.children.removeAll { $0.id == id }
            }
        }

        // Add new children
        if let childrenToAdd = update.addChildren {
            node.children.append(contentsOf: childrenToAdd)
        }
    }
}
