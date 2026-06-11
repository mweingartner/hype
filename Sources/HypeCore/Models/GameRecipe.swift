import Foundation

// MARK: - EntityRole

/// The semantic role of a `GameEntity` within a `GameRecipe`.
///
/// Roles drive compiler decisions (physics categories, default behaviors,
/// collision groups). Unknown raw strings decode to `.decoration` so
/// AI-produced JSON with novel role names degrades gracefully.
public enum EntityRole: String, Codable, Sendable, Equatable, CaseIterable {
    case player
    case enemy
    case collectible
    case hazard
    case projectile
    case goal
    case wall
    case hud
    case decoration
    case spawner
    case background

    /// Tolerant decode: unknown raw strings fall back to `.decoration`.
    public static func decodeTolerant(_ raw: String) -> EntityRole {
        return EntityRole(rawValue: raw) ?? .decoration
    }
}

// MARK: - GameEntity

/// A single entity template within a `GameRecipe`.
///
/// Each entity maps to one or more compiled `HypeNodeSpec` entries.
/// The `behaviors` array is decoded tolerantly: unknown behavior kinds
/// are silently dropped so a recipe with a single novel behavior
/// does not fail to decode entirely.
public struct GameEntity: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var role: EntityRole
    public var position: PointSpec
    public var size: SizeSpec
    /// How many instances to spawn at scene load.
    public var count: Int
    /// References an `ArtRoleBinding.role` for asset resolution.
    public var artRoleRef: String?
    /// Hex color used when no art asset is resolved.
    public var placeholderColor: String?
    public var zPosition: Double
    public var behaviors: [Behavior]
    /// Initial text content (for HUD/label entities).
    public var initialText: String?
    public var fontSize: Double?
    public var fontColor: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        role: EntityRole = .decoration,
        position: PointSpec = PointSpec(),
        size: SizeSpec = SizeSpec(width: 64, height: 64),
        count: Int = 1,
        artRoleRef: String? = nil,
        placeholderColor: String? = nil,
        zPosition: Double = 0,
        behaviors: [Behavior] = [],
        initialText: String? = nil,
        fontSize: Double? = nil,
        fontColor: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.position = position
        self.size = size
        self.count = count
        self.artRoleRef = artRoleRef
        self.placeholderColor = placeholderColor
        self.zPosition = zPosition
        self.behaviors = behaviors
        self.initialText = initialText
        self.fontSize = fontSize
        self.fontColor = fontColor
    }

    /// Tolerant decoder. All fields use `decodeIfPresent ?? default`.
    /// The `behaviors` array decodes each element via `try?` / `compactMap`
    /// so an unknown `BehaviorKind` drops that element without failing the
    /// whole entity.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        let rawRole = (try? c.decode(String.self, forKey: .role)) ?? ""
        self.role = EntityRole.decodeTolerant(rawRole)
        self.position = (try? c.decode(PointSpec.self, forKey: .position)) ?? PointSpec()
        self.size = (try? c.decode(SizeSpec.self, forKey: .size)) ?? SizeSpec(width: 64, height: 64)
        self.count = (try? c.decode(Int.self, forKey: .count)) ?? 1
        self.artRoleRef = try? c.decode(String.self, forKey: .artRoleRef)
        self.placeholderColor = try? c.decode(String.self, forKey: .placeholderColor)
        self.zPosition = (try? c.decode(Double.self, forKey: .zPosition)) ?? 0
        self.initialText = try? c.decode(String.self, forKey: .initialText)
        self.fontSize = try? c.decode(Double.self, forKey: .fontSize)
        self.fontColor = try? c.decode(String.self, forKey: .fontColor)

        // Tolerant behaviors: decode as raw Any-decodable JSON elements,
        // attempt to decode each as a Behavior, and compact-map out nils.
        // Unknown BehaviorKind strings cause Behavior.init(from:) to throw,
        // which try? converts to nil, which compactMap discards.
        if var behaviorContainer = try? c.nestedUnkeyedContainer(forKey: .behaviors) {
            var decoded: [Behavior] = []
            while !behaviorContainer.isAtEnd {
                let behavior = try? behaviorContainer.decode(Behavior.self)
                if let behavior {
                    decoded.append(behavior)
                } else {
                    // Advance past the unknown element to avoid an infinite loop.
                    _ = try? behaviorContainer.decode(AnyCodable.self)
                }
            }
            self.behaviors = decoded
        } else {
            self.behaviors = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, role, position, size, count, artRoleRef, placeholderColor
        case zPosition, behaviors, initialText, fontSize, fontColor
    }
}

// MARK: - AnyCodable (private decode-only helper)

/// A minimal decode-only wrapper used to advance past unknown elements in
/// a `nestedUnkeyedContainer` without consuming their bytes permanently.
private struct AnyCodable: Decodable {
    init(from decoder: Decoder) throws {
        // Consume any JSON value by attempting each container type.
        if var c = try? decoder.unkeyedContainer() {
            while !c.isAtEnd { _ = try? c.decode(AnyCodable.self) }
        } else if let c = try? decoder.container(keyedBy: GenericCodingKey.self) {
            for key in c.allKeys { _ = try? c.decode(AnyCodable.self, forKey: key) }
        } else {
            _ = try? decoder.singleValueContainer()
        }
    }
}

private struct GenericCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

// MARK: - WinLoseCondition

/// A single win or lose condition checked by the game runtime.
public struct WinLoseCondition: Codable, Sendable, Equatable {

    /// The type of condition trigger.
    public enum Kind: String, Codable, Sendable, Equatable, CaseIterable {
        case reachScore
        case zeroLives
        case zeroTimer
        case reachGoal
        case allCollected
        case contactRole
        case zeroHealth
        case custom

        public static func decodeTolerant(_ raw: String) -> Kind {
            return Kind(rawValue: raw) ?? .custom
        }
    }

    public var kind: Kind
    public var scoreThreshold: Int?
    public var goalEntityName: String?
    public var collectibleRole: EntityRole?
    public var contactRole: EntityRole?
    public var statusMessage: String?

    public init(
        kind: Kind = .custom,
        scoreThreshold: Int? = nil,
        goalEntityName: String? = nil,
        collectibleRole: EntityRole? = nil,
        contactRole: EntityRole? = nil,
        statusMessage: String? = nil
    ) {
        self.kind = kind
        self.scoreThreshold = scoreThreshold
        self.goalEntityName = goalEntityName
        self.collectibleRole = collectibleRole
        self.contactRole = contactRole
        self.statusMessage = statusMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        self.kind = Kind.decodeTolerant(rawKind)
        self.scoreThreshold = try? c.decode(Int.self, forKey: .scoreThreshold)
        self.goalEntityName = try? c.decode(String.self, forKey: .goalEntityName)
        if let rawRole = try? c.decode(String.self, forKey: .collectibleRole) {
            self.collectibleRole = EntityRole.decodeTolerant(rawRole)
        } else {
            self.collectibleRole = nil
        }
        if let rawRole = try? c.decode(String.self, forKey: .contactRole) {
            self.contactRole = EntityRole.decodeTolerant(rawRole)
        } else {
            self.contactRole = nil
        }
        self.statusMessage = try? c.decode(String.self, forKey: .statusMessage)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, scoreThreshold, goalEntityName, collectibleRole, contactRole, statusMessage
    }
}

// MARK: - GameState

/// Persistent game state variables and win/lose conditions for a `GameRecipe`.
public struct GameState: Codable, Sendable, Equatable {
    public var trackScore: Bool
    public var initialScore: Int
    public var trackLives: Bool
    public var initialLives: Int
    public var trackLevel: Bool
    public var initialLevel: Int
    public var trackTimer: Bool
    public var initialTimerSeconds: Double
    public var winConditions: [WinLoseCondition]
    public var loseConditions: [WinLoseCondition]
    /// Name of the entity used to display the score in the HUD.
    public var scoreHUDEntityName: String?
    /// Name of the entity used to display lives in the HUD.
    public var livesHUDEntityName: String?
    /// Name of the entity used to display a status message in the HUD.
    public var statusHUDEntityName: String?

    public init(
        trackScore: Bool = false,
        initialScore: Int = 0,
        trackLives: Bool = false,
        initialLives: Int = 0,
        trackLevel: Bool = false,
        initialLevel: Int = 0,
        trackTimer: Bool = false,
        initialTimerSeconds: Double = 0,
        winConditions: [WinLoseCondition] = [],
        loseConditions: [WinLoseCondition] = [],
        scoreHUDEntityName: String? = nil,
        livesHUDEntityName: String? = nil,
        statusHUDEntityName: String? = nil
    ) {
        self.trackScore = trackScore
        self.initialScore = initialScore
        self.trackLives = trackLives
        self.initialLives = initialLives
        self.trackLevel = trackLevel
        self.initialLevel = initialLevel
        self.trackTimer = trackTimer
        self.initialTimerSeconds = initialTimerSeconds
        self.winConditions = winConditions
        self.loseConditions = loseConditions
        self.scoreHUDEntityName = scoreHUDEntityName
        self.livesHUDEntityName = livesHUDEntityName
        self.statusHUDEntityName = statusHUDEntityName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.trackScore = (try? c.decode(Bool.self, forKey: .trackScore)) ?? false
        self.initialScore = (try? c.decode(Int.self, forKey: .initialScore)) ?? 0
        self.trackLives = (try? c.decode(Bool.self, forKey: .trackLives)) ?? false
        self.initialLives = (try? c.decode(Int.self, forKey: .initialLives)) ?? 0
        self.trackLevel = (try? c.decode(Bool.self, forKey: .trackLevel)) ?? false
        self.initialLevel = (try? c.decode(Int.self, forKey: .initialLevel)) ?? 0
        self.trackTimer = (try? c.decode(Bool.self, forKey: .trackTimer)) ?? false
        self.initialTimerSeconds = (try? c.decode(Double.self, forKey: .initialTimerSeconds)) ?? 0
        self.winConditions = (try? c.decode([WinLoseCondition].self, forKey: .winConditions)) ?? []
        self.loseConditions = (try? c.decode([WinLoseCondition].self, forKey: .loseConditions)) ?? []
        self.scoreHUDEntityName = try? c.decode(String.self, forKey: .scoreHUDEntityName)
        self.livesHUDEntityName = try? c.decode(String.self, forKey: .livesHUDEntityName)
        self.statusHUDEntityName = try? c.decode(String.self, forKey: .statusHUDEntityName)
    }

    private enum CodingKeys: String, CodingKey {
        case trackScore, initialScore, trackLives, initialLives, trackLevel, initialLevel
        case trackTimer, initialTimerSeconds, winConditions, loseConditions
        case scoreHUDEntityName, livesHUDEntityName, statusHUDEntityName
    }
}

// MARK: - ControlBinding

/// A mapping from a keyboard key to a game action.
public struct ControlBinding: Codable, Sendable, Equatable {

    /// The action triggered by this binding.
    public enum Action: String, Codable, Sendable, Equatable, CaseIterable {
        case moveLeft
        case moveRight
        case moveUp
        case moveDown
        case jump
        case fire
        case none

        public static func decodeTolerant(_ raw: String) -> Action {
            return Action(rawValue: raw) ?? .none
        }
    }

    /// The key identifier (e.g. `"ArrowLeft"`, `"Space"`, `"KeyA"`).
    public var key: String
    public var action: Action
    /// The name of the entity this binding targets (nil = all player entities).
    public var targetEntityName: String?
    /// Scalar magnitude applied to movement/force actions.
    public var magnitude: Double?

    public init(
        key: String = "",
        action: Action = .none,
        targetEntityName: String? = nil,
        magnitude: Double? = nil
    ) {
        self.key = key
        self.action = action
        self.targetEntityName = targetEntityName
        self.magnitude = magnitude
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key)) ?? ""
        let rawAction = (try? c.decode(String.self, forKey: .action)) ?? ""
        self.action = Action.decodeTolerant(rawAction)
        self.targetEntityName = try? c.decode(String.self, forKey: .targetEntityName)
        self.magnitude = try? c.decode(Double.self, forKey: .magnitude)
    }

    private enum CodingKeys: String, CodingKey {
        case key, action, targetEntityName, magnitude
    }
}

// MARK: - ArtRoleBinding

/// Maps a logical art role name to an asset or a generation prompt.
///
/// The compiler resolves entity `artRoleRef` strings through these bindings
/// to find either a named asset or a prompt for deferred image generation.
public struct ArtRoleBinding: Codable, Sendable, Equatable {
    /// The logical role name referenced by `GameEntity.artRoleRef`.
    public var role: String
    /// The asset name in the project's asset catalogue. Nil if asset is generated.
    public var assetName: String?
    /// When true, the compiler schedules image generation for this role.
    public var generate: Bool
    /// The prompt used when `generate` is true.
    public var generationPrompt: String?

    public init(
        role: String = "",
        assetName: String? = nil,
        generate: Bool = false,
        generationPrompt: String? = nil
    ) {
        self.role = role
        self.assetName = assetName
        self.generate = generate
        self.generationPrompt = generationPrompt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.role = (try? c.decode(String.self, forKey: .role)) ?? ""
        self.assetName = try? c.decode(String.self, forKey: .assetName)
        self.generate = (try? c.decode(Bool.self, forKey: .generate)) ?? false
        self.generationPrompt = try? c.decode(String.self, forKey: .generationPrompt)
    }

    private enum CodingKeys: String, CodingKey {
        case role, assetName, generate, generationPrompt
    }
}

// MARK: - RuleTrigger

/// What event fires a `GameRule`.
public struct RuleTrigger: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable, Equatable, CaseIterable {
        case onContact
        case onKey
        case everyNSeconds
        case onScoreReached
        case onSceneLoad
        case onFrame

        public static func decodeTolerant(_ raw: String) -> Kind {
            return Kind(rawValue: raw) ?? .onSceneLoad
        }
    }

    public var kind: Kind
    /// First role in a contact trigger.
    public var roleA: EntityRole?
    /// Second role in a contact trigger.
    public var roleB: EntityRole?
    /// Named entity for triggers that target a specific entity.
    public var entityName: String?
    /// Key identifier for `onKey` triggers.
    public var key: String?
    /// Interval in seconds for `everyNSeconds` triggers.
    public var seconds: Double?
    /// Score value for `onScoreReached` triggers.
    public var scoreThreshold: Int?

    public init(
        kind: Kind = .onSceneLoad,
        roleA: EntityRole? = nil,
        roleB: EntityRole? = nil,
        entityName: String? = nil,
        key: String? = nil,
        seconds: Double? = nil,
        scoreThreshold: Int? = nil
    ) {
        self.kind = kind
        self.roleA = roleA
        self.roleB = roleB
        self.entityName = entityName
        self.key = key
        self.seconds = seconds
        self.scoreThreshold = scoreThreshold
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        self.kind = Kind.decodeTolerant(rawKind)
        if let rawRole = try? c.decode(String.self, forKey: .roleA) {
            self.roleA = EntityRole.decodeTolerant(rawRole)
        } else {
            self.roleA = nil
        }
        if let rawRole = try? c.decode(String.self, forKey: .roleB) {
            self.roleB = EntityRole.decodeTolerant(rawRole)
        } else {
            self.roleB = nil
        }
        self.entityName = try? c.decode(String.self, forKey: .entityName)
        self.key = try? c.decode(String.self, forKey: .key)
        self.seconds = try? c.decode(Double.self, forKey: .seconds)
        self.scoreThreshold = try? c.decode(Int.self, forKey: .scoreThreshold)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, roleA, roleB, entityName, key, seconds, scoreThreshold
    }
}

// MARK: - RuleCondition

/// A predicate that must hold for a `GameRule` to fire its actions.
public struct RuleCondition: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable, Equatable, CaseIterable {
        case stateEquals
        case stateGreater
        case stateLess
        case always

        public static func decodeTolerant(_ raw: String) -> Kind {
            return Kind(rawValue: raw) ?? .always
        }
    }

    public var kind: Kind
    /// The state variable name (e.g. `"score"`, `"lives"`).
    public var stateVar: String?
    public var value: Double?

    public init(kind: Kind = .always, stateVar: String? = nil, value: Double? = nil) {
        self.kind = kind
        self.stateVar = stateVar
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        self.kind = Kind.decodeTolerant(rawKind)
        self.stateVar = try? c.decode(String.self, forKey: .stateVar)
        self.value = try? c.decode(Double.self, forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, stateVar, value
    }
}

// MARK: - RuleAction

/// A mutation or event emitted when a `GameRule` fires.
public struct RuleAction: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable, Equatable, CaseIterable {
        case addScore
        case addLives
        case setStatus
        case destroyOther
        case destroySelf
        case respawnEntity
        case spawnEntity
        case setVelocity
        case winGame
        case loseGame
        case playSound

        public static func decodeTolerant(_ raw: String) -> Kind {
            return Kind(rawValue: raw) ?? .addScore
        }
    }

    public var kind: Kind
    public var amount: Double?
    public var entityName: String?
    public var message: String?
    public var velocityX: Double?
    public var velocityY: Double?
    public var soundAsset: String?

    public init(
        kind: Kind = .addScore,
        amount: Double? = nil,
        entityName: String? = nil,
        message: String? = nil,
        velocityX: Double? = nil,
        velocityY: Double? = nil,
        soundAsset: String? = nil
    ) {
        self.kind = kind
        self.amount = amount
        self.entityName = entityName
        self.message = message
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.soundAsset = soundAsset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        self.kind = Kind.decodeTolerant(rawKind)
        self.amount = try? c.decode(Double.self, forKey: .amount)
        self.entityName = try? c.decode(String.self, forKey: .entityName)
        self.message = try? c.decode(String.self, forKey: .message)
        self.velocityX = try? c.decode(Double.self, forKey: .velocityX)
        self.velocityY = try? c.decode(Double.self, forKey: .velocityY)
        self.soundAsset = try? c.decode(String.self, forKey: .soundAsset)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, amount, entityName, message, velocityX, velocityY, soundAsset
    }
}

// MARK: - GameRule

/// A reactive rule: when `trigger` fires and all `conditions` hold,
/// execute `actions` in order.
public struct GameRule: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var trigger: RuleTrigger
    public var conditions: [RuleCondition]
    public var actions: [RuleAction]

    public init(
        id: UUID = UUID(),
        trigger: RuleTrigger = RuleTrigger(),
        conditions: [RuleCondition] = [],
        actions: [RuleAction] = []
    ) {
        self.id = id
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.trigger = (try? c.decode(RuleTrigger.self, forKey: .trigger)) ?? RuleTrigger()
        self.conditions = (try? c.decode([RuleCondition].self, forKey: .conditions)) ?? []
        self.actions = (try? c.decode([RuleAction].self, forKey: .actions)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, trigger, conditions, actions
    }
}

// MARK: - GameRecipe

/// The declarative intent for a playable game authored within a `spriteArea` part.
///
/// A `GameRecipe` is pure data describing WHAT a game is (entities, roles,
/// behaviors, rules, state) without specifying HOW the engine implements it.
/// A deterministic compiler (built in a later phase) lowers a `GameRecipe`
/// into a `SceneSpec` plus generated HypeTalk scripts.
///
/// Schema versioning: `recipeSchemaVersion` starts at 1. The compiler
/// rejects recipes with an unsupported version; the decoder is always
/// backward-compatible within a version.
public struct GameRecipe: Codable, Sendable, Equatable {
    /// Monotonically increasing schema version. Increment only on breaking changes.
    public var recipeSchemaVersion: Int
    /// Optional identifier linking this recipe to a canned game preset.
    public var presetID: String?
    /// Human-readable name echoed into the compiled `SceneSpec.name`.
    public var sceneName: String
    /// The logical design size of the game canvas.
    public var sceneSize: SizeSpec
    /// Hex background color (e.g. `"#101018"`).
    public var backgroundColor: String
    /// Scene-level gravity vector compiled into `SceneSpec.gravity`.
    public var gravity: VectorSpec
    public var entities: [GameEntity]
    public var rules: [GameRule]
    public var gameState: GameState
    public var controls: [ControlBinding]
    public var artRoles: [ArtRoleBinding]
    /// Free-form author notes; not compiled into the scene.
    public var notes: String

    public init(
        recipeSchemaVersion: Int = 1,
        presetID: String? = nil,
        sceneName: String = "Game",
        sceneSize: SizeSpec = SizeSpec(width: 800, height: 600),
        backgroundColor: String = "#101018",
        gravity: VectorSpec = VectorSpec(dx: 0, dy: 0),
        entities: [GameEntity] = [],
        rules: [GameRule] = [],
        gameState: GameState = GameState(),
        controls: [ControlBinding] = [],
        artRoles: [ArtRoleBinding] = [],
        notes: String = ""
    ) {
        self.recipeSchemaVersion = recipeSchemaVersion
        self.presetID = presetID
        self.sceneName = sceneName
        self.sceneSize = sceneSize
        self.backgroundColor = backgroundColor
        self.gravity = gravity
        self.entities = entities
        self.rules = rules
        self.gameState = gameState
        self.controls = controls
        self.artRoles = artRoles
        self.notes = notes
    }

    /// Tolerant decoder: every field uses `decodeIfPresent ?? default`
    /// so AI-produced or partially-written recipes always decode to a
    /// usable value.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.recipeSchemaVersion = (try? c.decode(Int.self, forKey: .recipeSchemaVersion)) ?? 1
        self.presetID = try? c.decode(String.self, forKey: .presetID)
        self.sceneName = (try? c.decode(String.self, forKey: .sceneName)) ?? "Game"
        self.sceneSize = (try? c.decode(SizeSpec.self, forKey: .sceneSize)) ?? SizeSpec(width: 800, height: 600)
        self.backgroundColor = (try? c.decode(String.self, forKey: .backgroundColor)) ?? "#101018"
        self.gravity = (try? c.decode(VectorSpec.self, forKey: .gravity)) ?? VectorSpec(dx: 0, dy: 0)
        self.entities = (try? c.decode([GameEntity].self, forKey: .entities)) ?? []
        self.rules = (try? c.decode([GameRule].self, forKey: .rules)) ?? []
        self.gameState = (try? c.decode(GameState.self, forKey: .gameState)) ?? GameState()
        self.controls = (try? c.decode([ControlBinding].self, forKey: .controls)) ?? []
        self.artRoles = (try? c.decode([ArtRoleBinding].self, forKey: .artRoles)) ?? []
        self.notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case recipeSchemaVersion, presetID, sceneName, sceneSize, backgroundColor
        case gravity, entities, rules, gameState, controls, artRoles, notes
    }
}
