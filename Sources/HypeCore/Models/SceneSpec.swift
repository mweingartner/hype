import Foundation

// MARK: - Geometry Primitives

/// A 2D point in scene coordinates.
public struct PointSpec: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
}

/// A 2D size.
public struct SizeSpec: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double = 0, height: Double = 0) { self.width = width; self.height = height }
}

/// A 2D vector (used for gravity, etc.).
public struct VectorSpec: Codable, Sendable, Equatable {
    public var dx: Double
    public var dy: Double
    public init(dx: Double = 0, dy: Double = -9.8) { self.dx = dx; self.dy = dy }
}

// MARK: - Scene Scale Mode

/// The scaling mode for the scene's content.
public enum SceneScaleMode: String, Codable, Sendable, CaseIterable {
    case fill, aspectFill, aspectFit, resizeFill
}

// MARK: - Scene

/// A complete SpriteKit scene specification.
public struct SceneSpec: Codable, Sendable {
    public var name: String
    public var size: SizeSpec
    public var backgroundColor: String
    public var gravity: VectorSpec
    public var nodes: [HypeNodeSpec]
    public var joints: [JointSpec]
    public var sceneConstraints: [SceneConstraintSpec]
    public var fields: [FieldSpec]
    public var script: String
    public var isPaused: Bool
    public var showsPhysics: Bool
    public var showsFPS: Bool
    public var showsNodeCount: Bool
    public var scaleMode: SceneScaleMode

    public init(
        name: String = "Scene",
        size: SizeSpec = SizeSpec(width: 800, height: 600),
        backgroundColor: String = "#FFFFFF",
        gravity: VectorSpec = VectorSpec(),
        nodes: [HypeNodeSpec] = [],
        joints: [JointSpec] = [],
        sceneConstraints: [SceneConstraintSpec] = [],
        fields: [FieldSpec] = [],
        script: String = "",
        isPaused: Bool = false,
        showsPhysics: Bool = false,
        showsFPS: Bool = false,
        showsNodeCount: Bool = false,
        scaleMode: SceneScaleMode = .aspectFit
    ) {
        self.name = name
        self.size = size
        self.backgroundColor = backgroundColor
        self.gravity = gravity
        self.nodes = nodes
        self.joints = joints
        self.sceneConstraints = sceneConstraints
        self.fields = fields
        self.script = script
        self.isPaused = isPaused
        self.showsPhysics = showsPhysics
        self.showsFPS = showsFPS
        self.showsNodeCount = showsNodeCount
        self.scaleMode = scaleMode
    }

    /// Backward-compatible decoding: new fields default when absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(SizeSpec.self, forKey: .size)
        backgroundColor = try container.decode(String.self, forKey: .backgroundColor)
        gravity = try container.decode(VectorSpec.self, forKey: .gravity)
        nodes = try container.decode([HypeNodeSpec].self, forKey: .nodes)
        joints = try container.decodeIfPresent([JointSpec].self, forKey: .joints) ?? []
        sceneConstraints = try container.decodeIfPresent([SceneConstraintSpec].self, forKey: .sceneConstraints) ?? []
        fields = try container.decodeIfPresent([FieldSpec].self, forKey: .fields) ?? []
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
        isPaused = try container.decode(Bool.self, forKey: .isPaused)
        showsPhysics = try container.decode(Bool.self, forKey: .showsPhysics)
        showsFPS = try container.decode(Bool.self, forKey: .showsFPS)
        showsNodeCount = try container.decode(Bool.self, forKey: .showsNodeCount)
        scaleMode = try container.decodeIfPresent(SceneScaleMode.self, forKey: .scaleMode) ?? .aspectFit
    }

    private enum CodingKeys: String, CodingKey {
        case name, size, backgroundColor, gravity, nodes, joints, sceneConstraints, fields, script
        case isPaused, showsPhysics, showsFPS, showsNodeCount, scaleMode
    }

    /// Parse from JSON string.
    public static func fromJSON(_ json: String) -> SceneSpec? {
        if let scene = fromLegacyJSON(json) {
            return scene
        }
        return SpriteAreaSpec.fromJSON(json)?.activeScene
    }

    /// Parse a raw SceneSpec JSON payload without falling back to SpriteAreaSpec.
    public static func fromLegacyJSON(_ json: String) -> SceneSpec? {
        return JSONCodec.decode(SceneSpec.self, from: json)
    }

    /// Serialize to JSON string.
    public func toJSON() -> String {
        return JSONCodec.encode(self)
    }
}

public extension SceneSpec {
    var allNodes: [HypeNodeSpec] {
        nodes.flatMap { [$0] + $0.allDescendants }
    }

    var allNodeIDs: [UUID] {
        allNodes.map(\.id)
    }

    func node(id: UUID) -> HypeNodeSpec? {
        nodes.lazy.compactMap { $0.node(id: id) }.first
    }

    func node(named name: String) -> HypeNodeSpec? {
        nodes.lazy.compactMap { $0.node(named: name) }.first
    }

    func ancestorPath(for nodeId: UUID) -> [HypeNodeSpec] {
        for node in nodes {
            if let path = node.ancestorPath(for: nodeId) {
                return path
            }
        }
        return []
    }

    @discardableResult
    mutating func updateNode(id: UUID, _ transform: (inout HypeNodeSpec) -> Void) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                transform(&nodes[index])
                return true
            }
            if nodes[index].updateDescendant(id: id, transform) {
                return true
            }
        }
        return false
    }

    @discardableResult
    mutating func removeNode(id: UUID) -> HypeNodeSpec? {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            return nodes.remove(at: index)
        }
        for index in nodes.indices {
            if let removed = nodes[index].removeDescendant(id: id) {
                return removed
            }
        }
        return nil
    }
}

// MARK: - Node

/// The type of a scene node.
public enum NodeType: String, Codable, Sendable {
    case sprite, group, label, shape, emitter, audio, tileMap, camera, video, crop, effect, light
}

/// A single node within a SpriteKit scene.
public struct HypeNodeSpec: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var nodeType: NodeType
    public var position: PointSpec
    public var zPosition: Double
    public var rotation: Double
    public var xScale: Double
    public var yScale: Double
    public var alpha: Double
    public var isHidden: Bool

    // Sprite-specific
    public var assetRef: AssetRef?
    public var size: SizeSpec?

    // Label-specific
    public var text: String?
    public var fontName: String?
    public var fontSize: Double?
    public var fontColor: String?
    /// HypeTalk-style textStyle string for label nodes:
    /// `"plain"` / `"bold,italic"` / etc. Parsed via
    /// `TextStyleFlags`. Optional + nil-default so older `.hype`
    /// documents (and non-label nodes) round-trip cleanly without
    /// migration. Underline / strikethrough land via attributedText
    /// on the rendered `SKLabelNode`; bold / italic apply as font
    /// traits.
    public var textStyle: String?

    // Shape-specific
    public var shapeSpec: ShapeNodeSpec?

    // Audio-specific
    public var audioLoop: Bool?
    public var audioVolume: Double?
    public var audioAutoplay: Bool?
    public var audioPositional: Bool?

    // Emitter-specific
    public var emitterSpec: EmitterSpec?

    // TileMap-specific
    public var tileMapSpec: TileMapSpec?

    // Video-specific
    public var videoLoop: Bool?
    public var videoAutoplay: Bool?

    // Camera-specific
    public var cameraTarget: String?  // name of node to follow

    // Physics
    public var physicsBody: PhysicsBodySpec?

    // Actions and children
    public var actions: [ActionSpec]
    public var children: [HypeNodeSpec]

    // Script
    public var script: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        nodeType: NodeType = .sprite,
        position: PointSpec = PointSpec(),
        zPosition: Double = 0,
        rotation: Double = 0,
        xScale: Double = 1,
        yScale: Double = 1,
        alpha: Double = 1,
        isHidden: Bool = false,
        assetRef: AssetRef? = nil,
        size: SizeSpec? = nil,
        text: String? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        fontColor: String? = nil,
        textStyle: String? = nil,
        shapeSpec: ShapeNodeSpec? = nil,
        emitterSpec: EmitterSpec? = nil,
        audioLoop: Bool? = nil,
        audioVolume: Double? = nil,
        audioAutoplay: Bool? = nil,
        audioPositional: Bool? = nil,
        tileMapSpec: TileMapSpec? = nil,
        videoLoop: Bool? = nil,
        videoAutoplay: Bool? = nil,
        cameraTarget: String? = nil,
        physicsBody: PhysicsBodySpec? = nil,
        actions: [ActionSpec] = [],
        children: [HypeNodeSpec] = [],
        script: String = ""
    ) {
        self.id = id
        self.name = name
        self.nodeType = nodeType
        self.position = position
        self.zPosition = zPosition
        self.rotation = rotation
        self.xScale = xScale
        self.yScale = yScale
        self.alpha = alpha
        self.isHidden = isHidden
        self.assetRef = assetRef
        self.size = size
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontColor = fontColor
        self.textStyle = textStyle
        self.shapeSpec = shapeSpec
        self.emitterSpec = emitterSpec
        self.audioLoop = audioLoop
        self.audioVolume = audioVolume
        self.audioAutoplay = audioAutoplay
        self.audioPositional = audioPositional
        self.tileMapSpec = tileMapSpec
        self.videoLoop = videoLoop
        self.videoAutoplay = videoAutoplay
        self.cameraTarget = cameraTarget
        self.physicsBody = physicsBody
        self.actions = actions
        self.children = children
        self.script = script
    }

    /// Tolerant decoder for AI-produced JSON.
    ///
    /// Local LLMs routinely emit nodes with missing required fields,
    /// unknown enum values (e.g. `"nodeType": "triangle"`), or bare
    /// string IDs that aren't UUIDs. Before this lenient decoder, any
    /// such deviation caused the enclosing `addNodes: [HypeNodeSpec]?`
    /// in `SceneDiff` to decode as nil, silently erasing the entire
    /// scene-repair diff and making the AI appear broken ("I asked for
    /// three shapes and nothing showed up"). The canonical/manual
    /// `init(...)` path is unaffected — all tolerance lives here.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = HypeNodeSpec.decodeUUIDTolerant(from: c, forKey: .id) ?? UUID()
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""

        // Lenient nodeType: accept synonyms; default to .sprite.
        self.nodeType = NodeType.decodeTolerant(
            from: c, forKey: .nodeType, default: .sprite
        )

        self.position = (try? c.decode(PointSpec.self, forKey: .position)) ?? PointSpec()
        self.zPosition = (try? c.decode(Double.self, forKey: .zPosition)) ?? 0
        self.rotation = (try? c.decode(Double.self, forKey: .rotation)) ?? 0
        self.xScale = (try? c.decode(Double.self, forKey: .xScale)) ?? 1
        self.yScale = (try? c.decode(Double.self, forKey: .yScale)) ?? 1
        self.alpha = (try? c.decode(Double.self, forKey: .alpha)) ?? 1
        self.isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false

        self.assetRef = try? c.decode(AssetRef.self, forKey: .assetRef)
        self.size = try? c.decode(SizeSpec.self, forKey: .size)
        self.text = try? c.decode(String.self, forKey: .text)
        self.fontName = try? c.decode(String.self, forKey: .fontName)
        self.fontSize = try? c.decode(Double.self, forKey: .fontSize)
        self.fontColor = try? c.decode(String.self, forKey: .fontColor)
        self.textStyle = try? c.decode(String.self, forKey: .textStyle)
        self.shapeSpec = try? c.decode(ShapeNodeSpec.self, forKey: .shapeSpec)
        self.audioLoop = try? c.decode(Bool.self, forKey: .audioLoop)
        self.audioVolume = try? c.decode(Double.self, forKey: .audioVolume)
        self.audioAutoplay = try? c.decode(Bool.self, forKey: .audioAutoplay)
        self.audioPositional = try? c.decode(Bool.self, forKey: .audioPositional)
        self.emitterSpec = try? c.decode(EmitterSpec.self, forKey: .emitterSpec)
        self.tileMapSpec = try? c.decode(TileMapSpec.self, forKey: .tileMapSpec)
        self.videoLoop = try? c.decode(Bool.self, forKey: .videoLoop)
        self.videoAutoplay = try? c.decode(Bool.self, forKey: .videoAutoplay)
        self.cameraTarget = try? c.decode(String.self, forKey: .cameraTarget)
        self.physicsBody = try? c.decode(PhysicsBodySpec.self, forKey: .physicsBody)
        self.actions = (try? c.decode([ActionSpec].self, forKey: .actions)) ?? []
        self.children = (try? c.decode([HypeNodeSpec].self, forKey: .children)) ?? []
        self.script = (try? c.decode(String.self, forKey: .script)) ?? ""

        // Heuristic: a node declared as `sprite` but with an explicit
        // shapeSpec is really a shape node. Same correction as
        // SceneBlueprintNode. This catches models that default
        // nodeType to "sprite" regardless of the payload.
        if self.nodeType == .sprite && self.shapeSpec != nil {
            self.nodeType = .shape
        }
    }

    /// Accept either a UUID-string or anything else (including a model-
    /// invented handle like "red_square"). If the value isn't a valid
    /// UUID, callers get nil so they can mint a fresh one.
    private static func decodeUUIDTolerant<K: CodingKey>(
        from c: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> UUID? {
        if let uuid = try? c.decode(UUID.self, forKey: key) { return uuid }
        if let s = try? c.decode(String.self, forKey: key), let uuid = UUID(uuidString: s) {
            return uuid
        }
        return nil
    }
}

extension NodeType {
    /// Public tolerant decode used by both `HypeNodeSpec` and the AI
    /// `SceneBlueprintNode`. Accepts common synonyms, collapses any
    /// polygon-ish word to `.shape`, and falls back to a caller-
    /// supplied default for truly unknown values.
    public static func decodeTolerant<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        default fallback: NodeType
    ) -> NodeType {
        guard let raw = try? container.decode(String.self, forKey: key) else { return fallback }
        let n = raw.lowercased().replacingOccurrences(of: "_", with: "")
        switch n {
        case "sprite", "image": return .sprite
        case "group", "container": return .group
        case "label", "text": return .label
        case "shape", "rect", "rectangle", "square", "circle", "ellipse",
             "triangle", "polygon", "path", "diamond", "pentagon",
             "hexagon", "octagon", "star", "arrow":
            return .shape
        case "emitter", "particles", "particle": return .emitter
        case "audio", "sound": return .audio
        case "tilemap", "tiles": return .tileMap
        case "camera": return .camera
        case "video", "movie": return .video
        case "crop": return .crop
        case "effect": return .effect
        case "light": return .light
        default: return fallback
        }
    }
}

public extension HypeNodeSpec {
    var allDescendants: [HypeNodeSpec] {
        children.flatMap { [$0] + $0.allDescendants }
    }

    func node(id: UUID) -> HypeNodeSpec? {
        if self.id == id { return self }
        return children.lazy.compactMap { $0.node(id: id) }.first
    }

    func node(named name: String) -> HypeNodeSpec? {
        if self.name.lowercased() == name.lowercased() { return self }
        return children.lazy.compactMap { $0.node(named: name) }.first
    }

    func ancestorPath(for nodeId: UUID) -> [HypeNodeSpec]? {
        if id == nodeId { return [self] }
        for child in children {
            if let path = child.ancestorPath(for: nodeId) {
                return path + [self]
            }
        }
        return nil
    }

    @discardableResult
    mutating func updateDescendant(id: UUID, _ transform: (inout HypeNodeSpec) -> Void) -> Bool {
        for index in children.indices {
            if children[index].id == id {
                transform(&children[index])
                return true
            }
            if children[index].updateDescendant(id: id, transform) {
                return true
            }
        }
        return false
    }

    @discardableResult
    mutating func removeDescendant(id: UUID) -> HypeNodeSpec? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            return children.remove(at: index)
        }
        for index in children.indices {
            if let removed = children[index].removeDescendant(id: id) {
                return removed
            }
        }
        return nil
    }
}

// MARK: - Emitter

/// Configuration for a particle emitter node.
public struct EmitterSpec: Codable, Sendable {
    public var particleBirthRate: Double
    public var particleLifetime: Double
    public var particleSpeed: Double
    public var particleSpeedRange: Double
    public var emissionAngle: Double       // degrees
    public var emissionAngleRange: Double   // degrees
    public var particleAlpha: Double
    public var particleAlphaSpeed: Double
    public var particleScale: Double
    public var particleScaleSpeed: Double
    public var particleColor: String       // hex color
    public var particleColorBlendFactor: Double
    public var particlePositionRangeX: Double
    public var particlePositionRangeY: Double

    public init(
        particleBirthRate: Double = 50,
        particleLifetime: Double = 2,
        particleSpeed: Double = 100,
        particleSpeedRange: Double = 50,
        emissionAngle: Double = 90,
        emissionAngleRange: Double = 360,
        particleAlpha: Double = 1,
        particleAlphaSpeed: Double = -0.5,
        particleScale: Double = 0.3,
        particleScaleSpeed: Double = -0.1,
        particleColor: String = "#FFFFFF",
        particleColorBlendFactor: Double = 1,
        particlePositionRangeX: Double = 0,
        particlePositionRangeY: Double = 0
    ) {
        self.particleBirthRate = particleBirthRate
        self.particleLifetime = particleLifetime
        self.particleSpeed = particleSpeed
        self.particleSpeedRange = particleSpeedRange
        self.emissionAngle = emissionAngle
        self.emissionAngleRange = emissionAngleRange
        self.particleAlpha = particleAlpha
        self.particleAlphaSpeed = particleAlphaSpeed
        self.particleScale = particleScale
        self.particleScaleSpeed = particleScaleSpeed
        self.particleColor = particleColor
        self.particleColorBlendFactor = particleColorBlendFactor
        self.particlePositionRangeX = particlePositionRangeX
        self.particlePositionRangeY = particlePositionRangeY
    }
}

// MARK: - Physics Joint

/// The type of physics joint connecting two nodes.
public enum JointType: String, Codable, Sendable {
    case pin, spring, sliding, fixed, limit
}

/// A physics joint connecting two scene nodes.
public struct JointSpec: Identifiable, Codable, Sendable {
    public var id: UUID
    public var jointType: JointType
    public var nodeA: String  // node name
    public var nodeB: String  // node name
    public var anchorA: PointSpec?  // anchor point on nodeA (relative)
    public var anchorB: PointSpec?
    // Spring-specific
    public var springFrequency: Double?
    public var springDamping: Double?

    public init(
        id: UUID = UUID(),
        jointType: JointType = .pin,
        nodeA: String = "",
        nodeB: String = "",
        anchorA: PointSpec? = nil,
        anchorB: PointSpec? = nil,
        springFrequency: Double? = nil,
        springDamping: Double? = nil
    ) {
        self.id = id
        self.jointType = jointType
        self.nodeA = nodeA
        self.nodeB = nodeB
        self.anchorA = anchorA
        self.anchorB = anchorB
        self.springFrequency = springFrequency
        self.springDamping = springDamping
    }
}

// MARK: - Scene Constraint

/// The type of constraint applied between scene nodes.
public enum SceneConstraintType: String, Codable, Sendable {
    case distance, orient, position
}

/// A constraint applied between two scene nodes.
public struct SceneConstraintSpec: Identifiable, Codable, Sendable {
    public var id: UUID
    public var constraintType: SceneConstraintType
    public var sourceNode: String  // node name
    public var targetNode: String  // node name
    public var minDistance: Double?
    public var maxDistance: Double?

    public init(
        id: UUID = UUID(),
        constraintType: SceneConstraintType = .distance,
        sourceNode: String = "",
        targetNode: String = "",
        minDistance: Double? = nil,
        maxDistance: Double? = nil
    ) {
        self.id = id
        self.constraintType = constraintType
        self.sourceNode = sourceNode
        self.targetNode = targetNode
        self.minDistance = minDistance
        self.maxDistance = maxDistance
    }
}

// MARK: - Shape Node

/// The shape type for a shape node.
public enum SpriteShapeType: String, Codable, Sendable, CaseIterable {
    case rect, circle, ellipse, path
}

/// Configuration for a shape node.
public struct ShapeNodeSpec: Codable, Sendable {
    public var shapeType: SpriteShapeType
    public var fillColor: String
    public var strokeColor: String
    public var lineWidth: Double
    public var cornerRadius: Double
    public var path: [PointSpec]?

    public init(
        shapeType: SpriteShapeType = .rect,
        fillColor: String = "#FFFFFF",
        strokeColor: String = "#000000",
        lineWidth: Double = 1,
        cornerRadius: Double = 0,
        path: [PointSpec]? = nil
    ) {
        self.shapeType = shapeType
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.path = path
    }

    /// Tolerant decoder: unknown `shapeType` values map to nearest
    /// canonical form (e.g. "square" → .rect, "triangle" → .path,
    /// "star" → .path) instead of failing decode. Missing numeric
    /// fields default to the same values as the designated init.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.shapeType = SpriteShapeType.decodeTolerant(
            from: c, forKey: .shapeType, default: .rect
        )
        self.fillColor = (try? c.decode(String.self, forKey: .fillColor)) ?? "#FFFFFF"
        self.strokeColor = (try? c.decode(String.self, forKey: .strokeColor)) ?? "#000000"
        self.lineWidth = (try? c.decode(Double.self, forKey: .lineWidth)) ?? 1
        self.cornerRadius = (try? c.decode(Double.self, forKey: .cornerRadius)) ?? 0
        self.path = try? c.decode([PointSpec].self, forKey: .path)
    }
}

extension SpriteShapeType {
    public static func tolerantValue(_ raw: String, default fallback: SpriteShapeType = .rect) -> SpriteShapeType {
        let n = raw.lowercased().replacingOccurrences(of: "_", with: "")
        switch n {
        case "rect", "rectangle", "square", "box": return .rect
        case "circle", "round", "disc": return .circle
        case "ellipse", "oval": return .ellipse
        case "path", "polygon", "triangle", "tri", "diamond",
             "pentagon", "hexagon", "octagon", "star", "arrow":
            return .path
        default: return fallback
        }
    }

    /// Public tolerant decode. "square"/"box"/"rectangle" → .rect,
    /// "round"/"disc" → .circle, "oval" → .ellipse, and every
    /// polygon-ish name ("triangle", "star", "arrow", etc.) → .path
    /// so the SceneBridge triangle renderer gets a chance at it.
    public static func decodeTolerant<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        default fallback: SpriteShapeType
    ) -> SpriteShapeType {
        guard let raw = try? container.decode(String.self, forKey: key) else { return fallback }
        return tolerantValue(raw, default: fallback)
    }
}

// MARK: - Tile Map

/// Configuration for a tile map node.
public struct TileMapSpec: Codable, Sendable {
    public var columns: Int
    public var rows: Int
    public var tileWidth: Double
    public var tileHeight: Double
    public var tileSetAssetRef: AssetRef?  // sprite sheet image for tiles
    public var tileSetColumns: Int         // how many tile columns in the sprite sheet
    public var tileData: [[Int]]           // 2D array [row][col] of tile indices (-1 = empty)

    public init(
        columns: Int = 10, rows: Int = 10,
        tileWidth: Double = 32, tileHeight: Double = 32,
        tileSetAssetRef: AssetRef? = nil,
        tileSetColumns: Int = 1,
        tileData: [[Int]] = []
    ) {
        self.columns = columns
        self.rows = rows
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.tileSetAssetRef = tileSetAssetRef
        self.tileSetColumns = tileSetColumns
        self.tileData = tileData
    }
}

// MARK: - Physics Field

/// The type of physics field in a scene.
public enum FieldType: String, Codable, Sendable {
    case linearGravity, radialGravity, vortex, noise, turbulence, spring, drag, electric, magnetic
}

/// A physics field specification within a scene.
public struct FieldSpec: Identifiable, Codable, Sendable {
    public var id: UUID
    public var fieldType: FieldType
    public var strength: Double
    public var region: SizeSpec?  // nil = infinite
    public var direction: PointSpec?  // for linear fields

    public init(id: UUID = UUID(), fieldType: FieldType = .linearGravity, strength: Double = 1.0,
                region: SizeSpec? = nil, direction: PointSpec? = nil) {
        self.id = id
        self.fieldType = fieldType
        self.strength = strength
        self.region = region
        self.direction = direction
    }
}

// MARK: - Transition

/// The type of scene transition animation.
public enum TransitionType: String, Codable, Sendable {
    case fade, push, moveIn, reveal, crossfade, doorway, flipHorizontal, flipVertical
}

/// Configuration for a scene transition animation.
public struct TransitionSpec: Codable, Sendable {
    public var type: TransitionType
    public var duration: Double

    public init(type: TransitionType = .fade, duration: Double = 0.5) {
        self.type = type
        self.duration = duration
    }
}

// MARK: - Physics Body

/// The type of physics body geometry.
public enum PhysicsBodyType: String, Codable, Sendable, CaseIterable {
    case circle, rect, texture, none, edge
}

/// Physics body configuration for a scene node.
public struct PhysicsBodySpec: Codable, Sendable {
    public var bodyType: PhysicsBodyType
    public var isDynamic: Bool
    public var categoryBitmask: UInt32
    public var contactTestBitmask: UInt32
    public var collisionBitmask: UInt32
    public var restitution: Double
    public var friction: Double
    public var mass: Double?
    public var affectedByGravity: Bool
    public var allowsRotation: Bool
    public var density: Double?
    public var linearDamping: Double?
    public var angularDamping: Double?
    public var velocityX: Double?
    public var velocityY: Double?
    public var angularVelocity: Double?

    public init(
        bodyType: PhysicsBodyType = .rect,
        isDynamic: Bool = true,
        categoryBitmask: UInt32 = 0xFFFFFFFF,
        contactTestBitmask: UInt32 = 0,
        collisionBitmask: UInt32 = 0xFFFFFFFF,
        restitution: Double = 0.2,
        friction: Double = 0.2,
        mass: Double? = nil,
        affectedByGravity: Bool = true,
        allowsRotation: Bool = true,
        density: Double? = nil,
        linearDamping: Double? = nil,
        angularDamping: Double? = nil,
        velocityX: Double? = nil,
        velocityY: Double? = nil,
        angularVelocity: Double? = nil
    ) {
        self.bodyType = bodyType
        self.isDynamic = isDynamic
        self.categoryBitmask = categoryBitmask
        self.contactTestBitmask = contactTestBitmask
        self.collisionBitmask = collisionBitmask
        self.restitution = restitution
        self.friction = friction
        self.mass = mass
        self.affectedByGravity = affectedByGravity
        self.allowsRotation = allowsRotation
        self.density = density
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.angularVelocity = angularVelocity
    }

    /// Tolerant decoder: AI-produced JSON routinely omits required
    /// physics fields or names the body type with a word that isn't
    /// in the enum ("polygon"). All scalar/bool fields get the same
    /// defaults as the canonical initializer, and `bodyType` falls
    /// back to `.rect` through the tolerant enum decoder.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bodyType = PhysicsBodyType.decodeTolerant(
            from: c, forKey: .bodyType, default: .rect
        )
        self.isDynamic = (try? c.decode(Bool.self, forKey: .isDynamic)) ?? true
        self.categoryBitmask = (try? c.decode(UInt32.self, forKey: .categoryBitmask)) ?? 0xFFFFFFFF
        self.contactTestBitmask = (try? c.decode(UInt32.self, forKey: .contactTestBitmask)) ?? 0
        self.collisionBitmask = (try? c.decode(UInt32.self, forKey: .collisionBitmask)) ?? 0xFFFFFFFF
        self.restitution = (try? c.decode(Double.self, forKey: .restitution)) ?? 0.2
        self.friction = (try? c.decode(Double.self, forKey: .friction)) ?? 0.2
        self.mass = try? c.decode(Double.self, forKey: .mass)
        self.affectedByGravity = (try? c.decode(Bool.self, forKey: .affectedByGravity)) ?? true
        self.allowsRotation = (try? c.decode(Bool.self, forKey: .allowsRotation)) ?? true
        self.density = try? c.decode(Double.self, forKey: .density)
        self.linearDamping = try? c.decode(Double.self, forKey: .linearDamping)
        self.angularDamping = try? c.decode(Double.self, forKey: .angularDamping)
        self.velocityX = try? c.decode(Double.self, forKey: .velocityX)
        self.velocityY = try? c.decode(Double.self, forKey: .velocityY)
        self.angularVelocity = try? c.decode(Double.self, forKey: .angularVelocity)
    }
}

extension PhysicsBodyType {
    public static func decodeTolerant<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        default fallback: PhysicsBodyType
    ) -> PhysicsBodyType {
        guard let raw = try? container.decode(String.self, forKey: key) else { return fallback }
        let n = raw.lowercased().replacingOccurrences(of: "_", with: "")
        switch n {
        case "circle", "round": return .circle
        case "rect", "rectangle", "box", "square": return .rect
        case "texture", "pixel": return .texture
        case "none", "off", "disabled": return .none
        case "edge", "border", "boundary": return .edge
        // Polygon-ish physics bodies fall back to .rect because SpriteKit
        // has no "arbitrary polygon" body type; rect is the best
        // approximation for triangles/stars/etc. at their AABB.
        case "polygon", "triangle", "tri", "diamond", "pentagon",
             "hexagon", "octagon", "star", "arrow":
            return .rect
        default: return fallback
        }
    }
}

// MARK: - Actions

/// The type of action a node can perform.
public enum ActionType: String, Codable, Sendable {
    case moveTo, moveBy
    case rotateTo, rotateBy
    case scaleTo, scaleBy
    case fadeTo, fadeIn, fadeOut
    case sequence, group
    case repeatForever, repeatCount
    case wait
    case removeFromParent
    case followPath
    case setTexture, animate
    case playAudio, stopAudio, changeVolume
    case resize, hide, unhide, colorize, speedTo, speedBy
}

/// A single action specification for a scene node.
public struct ActionSpec: Codable, Sendable {
    public var actionType: ActionType
    public var name: String
    public var duration: Double
    public var parameters: [String: String]
    public var children: [ActionSpec]?

    public init(
        actionType: ActionType = .moveTo,
        name: String = "",
        duration: Double = 0.25,
        parameters: [String: String] = [:],
        children: [ActionSpec]? = nil
    ) {
        self.actionType = actionType
        self.name = name
        self.duration = duration
        self.parameters = parameters
        self.children = children
    }
}
