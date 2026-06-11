import Foundation

// MARK: - Physics Patch

/// Optional overrides that a behavior can apply on top of the role-default
/// `PhysicsBodySpec`. Only non-nil fields are applied.
public struct PhysicsBodyPatch: Sendable, Equatable {
    public var isDynamic: Bool?
    public var affectedByGravity: Bool?
    public var restitution: Double?
    public var friction: Double?
    public var allowsRotation: Bool?
    public var linearDamping: Double?
    public var bodyType: PhysicsBodyType?

    public init(
        isDynamic: Bool? = nil,
        affectedByGravity: Bool? = nil,
        restitution: Double? = nil,
        friction: Double? = nil,
        allowsRotation: Bool? = nil,
        linearDamping: Double? = nil,
        bodyType: PhysicsBodyType? = nil
    ) {
        self.isDynamic = isDynamic
        self.affectedByGravity = affectedByGravity
        self.restitution = restitution
        self.friction = friction
        self.allowsRotation = allowsRotation
        self.linearDamping = linearDamping
        self.bodyType = bodyType
    }

    /// Apply this patch onto a base `PhysicsBodySpec`, returning the merged result.
    public func apply(to base: PhysicsBodySpec) -> PhysicsBodySpec {
        var result = base
        if let v = isDynamic        { result.isDynamic = v }
        if let v = affectedByGravity { result.affectedByGravity = v }
        if let v = restitution      { result.restitution = v }
        if let v = friction         { result.friction = v }
        if let v = allowsRotation   { result.allowsRotation = v }
        if let v = linearDamping    { result.linearDamping = v }
        if let v = bodyType         { result.bodyType = v }
        return result
    }
}

// MARK: - KeyBranch

/// Lines to emit inside an `if the key is "<key>" then ... end if` block in
/// either a `keyDown` or `keyUp` handler.
public struct KeyBranch: Sendable, Equatable {
    /// The exact key string (e.g. `"left"`, `"right"`, `"space"`).
    public var key: String
    /// HypeTalk lines for the body of the key branch (no surrounding `if`).
    public var lines: [String]

    public init(key: String, lines: [String]) {
        self.key = key
        self.lines = lines
    }
}

// MARK: - ContactBranch

/// Lines to emit inside a contact handler, guarded by a HypeTalk boolean
/// expression over the `otherName` variable.
public struct ContactBranch: Sendable, Equatable {
    /// A HypeTalk boolean expression that is `true` when the contact is relevant.
    /// Examples: `otherName is "coin"`, `otherName contains "enemy_"`.
    public var otherPredicate: String
    /// Lines to execute when `otherPredicate` holds.
    public var lines: [String]

    public init(otherPredicate: String, lines: [String]) {
        self.otherPredicate = otherPredicate
        self.lines = lines
    }
}

// MARK: - BehaviorContribution

/// Everything a single `Behavior` instance contributes to the compiled output.
/// The `RecipeCompiler` merges contributions from all behaviors on all entities.
public struct BehaviorContribution: Sendable {
    /// Optional physics overrides for the entity carrying this behavior.
    public var physics: PhysicsBodyPatch?
    /// Lines added to the `sceneDidLoad` handler.
    public var sceneDidLoad: [String]
    /// Branches to add to the `keyDown` handler.
    public var keyDown: [KeyBranch]
    /// Branches to add to the `keyUp` handler.
    public var keyUp: [KeyBranch]
    /// Branches to add to the `beginContact otherName` handler.
    public var beginContact: [ContactBranch]
    /// Branches to add to the `endContact otherName` handler.
    public var endContact: [ContactBranch]
    /// Lines added to the `frameUpdate deltaTime` handler.
    public var frameUpdate: [String]
    /// `ActionSpec`s to attach directly to the node spec.
    public var actions: [ActionSpec]
    /// Global variable names declared at the top of every handler.
    public var requiredGlobals: [String]
    /// State variable names (subset of globals) the recipe must initialize.
    public var requiredStateVars: [String]

    public init(
        physics: PhysicsBodyPatch? = nil,
        sceneDidLoad: [String] = [],
        keyDown: [KeyBranch] = [],
        keyUp: [KeyBranch] = [],
        beginContact: [ContactBranch] = [],
        endContact: [ContactBranch] = [],
        frameUpdate: [String] = [],
        actions: [ActionSpec] = [],
        requiredGlobals: [String] = [],
        requiredStateVars: [String] = []
    ) {
        self.physics = physics
        self.sceneDidLoad = sceneDidLoad
        self.keyDown = keyDown
        self.keyUp = keyUp
        self.beginContact = beginContact
        self.endContact = endContact
        self.frameUpdate = frameUpdate
        self.actions = actions
        self.requiredGlobals = requiredGlobals
        self.requiredStateVars = requiredStateVars
    }
}

// MARK: - BehaviorLibrary

/// Compiles a single `Behavior` into its `BehaviorContribution`, emitting only
/// verified HypeTalk grammar. Every method is pure and deterministic — no Date,
/// no random, no side effects.
public enum BehaviorLibrary {

    // MARK: - Public API

    /// Returns the contribution for the given behavior as attached to `entity`
    /// within `recipe`. The caller (RecipeCompiler) merges all contributions.
    public static func contribution(
        for behavior: Behavior,
        entity: GameEntity,
        recipe: GameRecipe
    ) -> BehaviorContribution {
        switch behavior.kind {
        case .topDownMovement:      return topDownMovement(behavior, entity)
        case .platformerMovement:   return platformerMovement(behavior, entity)
        case .eightDirection:       return eightDirection(behavior, entity)
        case .followPointer:        return followPointer(behavior, entity)
        case .chaseTarget:          return chaseTarget(behavior, entity, recipe)
        case .patrol:               return patrol(behavior, entity)
        case .physicsBody:          return physicsBodyBehavior(behavior)
        case .bounce:               return bounce()
        case .wrapAround:           return wrapAround(entity, recipe)
        case .constrainToBounds:    return constrainToBounds(entity, recipe)
        case .destroyOutsideBounds: return destroyOutsideBounds(behavior, entity, recipe)
        case .spawner:              return spawner(behavior, entity, recipe)
        case .collectible:          return collectible(entity)
        case .damageOnContact:      return damageOnContact(behavior, entity, recipe)
        case .health:               return health(behavior, entity)
        case .scoreOnCollect:       return scoreOnCollect(behavior, entity, recipe)
        case .winOnReach:           return winOnReach(entity)
        case .winOnScore:           return winOnScore(behavior)
        case .loseOnContact:        return loseOnContact(behavior, entity, recipe)
        case .loseOnZeroHealth:     return loseOnZeroHealth(entity)
        case .draggable:            return draggable(entity)
        case .rotator:              return rotator(behavior, entity)
        case .oscillate:            return oscillate(behavior, entity)
        }
    }

    // MARK: - Helpers

    /// Read a double param with a documented default.
    private static func param(_ b: Behavior, _ key: String, default d: Double) -> Double {
        b.params[key].flatMap(Double.init) ?? d
    }

    /// Read a string param with a documented default.
    private static func paramStr(_ b: Behavior, _ key: String, default d: String) -> String {
        b.params[key] ?? d
    }

    /// Format a Double for emission into HypeTalk strings with no unnecessary
    /// trailing zeros (e.g. 200.0 → "200", 150.5 → "150.5").
    private static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    /// Find the first entity in the recipe with the given role.
    private static func firstEntity(role: EntityRole, in recipe: GameRecipe) -> GameEntity? {
        recipe.entities.first { $0.role == role }
    }

    /// Build a contact predicate for an entity or role.
    /// Single-count: `otherName is "name"`
    /// Multi-count:  `otherName contains "<name>_"`
    private static func contactPredicate(for entity: GameEntity) -> String {
        // Sanitize the entity name before embedding into a HypeTalk string literal.
        let safe = RecipeCompiler.sanitizedLiteral(entity.name)
        if entity.count > 1 {
            return "otherName contains \"\(safe)_\""
        } else {
            return "otherName is \"\(safe)\""
        }
    }

    // MARK: - Individual behavior implementations

    // MARK: topDownMovement
    private static func topDownMovement(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        let speed = param(b, "speed", default: 200)
        // Emit the signed number directly so a negative speed (−50) renders as "-50",
        // not "--50" (double-negative). `fmt(-speed)` produces "-50" correctly.
        let sPos = fmt(speed)
        let sNeg = fmt(-speed)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        let keyDown: [KeyBranch] = [
            KeyBranch(key: "left",  lines: ["set the velocityX of sprite \"\(n)\" to \(sNeg)"]),
            KeyBranch(key: "right", lines: ["set the velocityX of sprite \"\(n)\" to \(sPos)"]),
            KeyBranch(key: "up",    lines: ["set the velocityY of sprite \"\(n)\" to \(sNeg)"]),
            KeyBranch(key: "down",  lines: ["set the velocityY of sprite \"\(n)\" to \(sPos)"]),
        ]
        let keyUp: [KeyBranch] = [
            KeyBranch(key: "left",  lines: ["set the velocityX of sprite \"\(n)\" to 0"]),
            KeyBranch(key: "right", lines: ["set the velocityX of sprite \"\(n)\" to 0"]),
            KeyBranch(key: "up",    lines: ["set the velocityY of sprite \"\(n)\" to 0"]),
            KeyBranch(key: "down",  lines: ["set the velocityY of sprite \"\(n)\" to 0"]),
        ]
        return BehaviorContribution(
            physics: PhysicsBodyPatch(affectedByGravity: false, allowsRotation: false),
            keyDown: keyDown,
            keyUp: keyUp
        )
    }

    // MARK: platformerMovement
    private static func platformerMovement(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        let speed = param(b, "speed", default: 200)
        let jumpForce = param(b, "jumpForce", default: 620)
        // Emit signed numbers directly to avoid double-negative (e.g. -200 not --200).
        let sPos = fmt(speed)
        let sNeg = fmt(-speed)
        // Jump velocity is always negative (upward in SpriteKit coords); emit the signed value.
        let jNeg = fmt(-jumpForce)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        // In SpriteKit's physics (and Hype's coordinate system), negative Y
        // is upward. So jumping means applying a negative velocityY.
        let keyDown: [KeyBranch] = [
            KeyBranch(key: "left",  lines: ["set the velocityX of sprite \"\(n)\" to \(sNeg)"]),
            KeyBranch(key: "right", lines: ["set the velocityX of sprite \"\(n)\" to \(sPos)"]),
            KeyBranch(key: "space", lines: ["set the velocityY of sprite \"\(n)\" to \(jNeg)"]),
            KeyBranch(key: "up",    lines: ["set the velocityY of sprite \"\(n)\" to \(jNeg)"]),
        ]
        let keyUp: [KeyBranch] = [
            KeyBranch(key: "left",  lines: ["set the velocityX of sprite \"\(n)\" to 0"]),
            KeyBranch(key: "right", lines: ["set the velocityX of sprite \"\(n)\" to 0"]),
        ]
        return BehaviorContribution(
            physics: PhysicsBodyPatch(affectedByGravity: true, allowsRotation: false),
            keyDown: keyDown,
            keyUp: keyUp
        )
    }

    // MARK: eightDirection
    private static func eightDirection(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        // Eight-direction is topDown movement plus diagonal combinations.
        // Each axis is independent; opposing keys do not cancel (last pressed wins).
        let speed = param(b, "speed", default: 200)
        // Emit signed numbers directly to avoid double-negative (e.g. -200 not --200).
        let sPos = fmt(speed)
        let sNeg = fmt(-speed)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        let keyDown: [KeyBranch] = [
            KeyBranch(key: "left",  lines: ["set the velocityX of sprite \"\(n)\" to \(sNeg)"]),
            KeyBranch(key: "right", lines: ["set the velocityX of sprite \"\(n)\" to \(sPos)"]),
            KeyBranch(key: "up",    lines: ["set the velocityY of sprite \"\(n)\" to \(sNeg)"]),
            KeyBranch(key: "down",  lines: ["set the velocityY of sprite \"\(n)\" to \(sPos)"]),
        ]
        let keyUp: [KeyBranch] = [
            KeyBranch(key: "left",  lines: ["set the velocityX of sprite \"\(n)\" to 0"]),
            KeyBranch(key: "right", lines: ["set the velocityX of sprite \"\(n)\" to 0"]),
            KeyBranch(key: "up",    lines: ["set the velocityY of sprite \"\(n)\" to 0"]),
            KeyBranch(key: "down",  lines: ["set the velocityY of sprite \"\(n)\" to 0"]),
        ]
        return BehaviorContribution(
            physics: PhysicsBodyPatch(affectedByGravity: false, allowsRotation: false),
            keyDown: keyDown,
            keyUp: keyUp
        )
    }

    // MARK: followPointer
    private static func followPointer(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        let speed = param(b, "speed", default: 220)
        let axis = paramStr(b, "axis", default: "both")
        let s = fmt(speed)
        let sNeg = fmt(-speed)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        // Use a per-frame step capped to speed*deltaTime.
        // item 1 of (the mouseLoc) = x, item 2 = y
        var lines: [String] = []
        lines.append("put item 1 of (the mouseLoc) into mouseX")
        lines.append("put item 2 of (the mouseLoc) into mouseY")
        lines.append("put item 1 of (the loc of sprite \"\(n)\") into sprX")
        lines.append("put item 2 of (the loc of sprite \"\(n)\") into sprY")

        switch axis {
        case "x":
            lines.append("put mouseX - sprX into diffX")
            lines.append("if diffX > \(s) then")
            lines.append("  put \(s) into diffX")
            lines.append("end if")
            lines.append("if diffX < \(sNeg) then")
            lines.append("  put \(sNeg) into diffX")
            lines.append("end if")
            lines.append("set the velocityX of sprite \"\(n)\" to diffX")
        case "y":
            lines.append("put mouseY - sprY into diffY")
            lines.append("if diffY > \(s) then")
            lines.append("  put \(s) into diffY")
            lines.append("end if")
            lines.append("if diffY < \(sNeg) then")
            lines.append("  put \(sNeg) into diffY")
            lines.append("end if")
            lines.append("set the velocityY of sprite \"\(n)\" to diffY")
        default: // both
            lines.append("put mouseX - sprX into diffX")
            lines.append("put mouseY - sprY into diffY")
            lines.append("if diffX > \(s) then")
            lines.append("  put \(s) into diffX")
            lines.append("end if")
            lines.append("if diffX < \(sNeg) then")
            lines.append("  put \(sNeg) into diffX")
            lines.append("end if")
            lines.append("if diffY > \(s) then")
            lines.append("  put \(s) into diffY")
            lines.append("end if")
            lines.append("if diffY < \(sNeg) then")
            lines.append("  put \(sNeg) into diffY")
            lines.append("end if")
            lines.append("set the velocityX of sprite \"\(n)\" to diffX")
            lines.append("set the velocityY of sprite \"\(n)\" to diffY")
        }

        return BehaviorContribution(
            physics: PhysicsBodyPatch(affectedByGravity: false, allowsRotation: false),
            frameUpdate: lines
        )
    }

    // MARK: chaseTarget
    private static func chaseTarget(_ b: Behavior, _ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let targetRoleStr = paramStr(b, "targetRole", default: "player")
        let speed = param(b, "speed", default: 120)
        let s = fmt(speed)
        let sNeg = fmt(-speed)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        // Resolve the target role to the first matching entity name.
        let targetRole = EntityRole.decodeTolerant(targetRoleStr)
        let rawTargetName = firstEntity(role: targetRole, in: recipe)?.name ?? targetRoleStr
        let targetName = RecipeCompiler.sanitizedLiteral(rawTargetName)

        var lines: [String] = []
        lines.append("put item 1 of (the loc of sprite \"\(targetName)\") into targetX")
        lines.append("put item 2 of (the loc of sprite \"\(targetName)\") into targetY")
        lines.append("put item 1 of (the loc of sprite \"\(n)\") into selfX")
        lines.append("put item 2 of (the loc of sprite \"\(n)\") into selfY")
        lines.append("put targetX - selfX into chaseX")
        lines.append("put targetY - selfY into chaseY")
        lines.append("if chaseX > \(s) then")
        lines.append("  put \(s) into chaseX")
        lines.append("end if")
        lines.append("if chaseX < \(sNeg) then")
        lines.append("  put \(sNeg) into chaseX")
        lines.append("end if")
        lines.append("if chaseY > \(s) then")
        lines.append("  put \(s) into chaseY")
        lines.append("end if")
        lines.append("if chaseY < \(sNeg) then")
        lines.append("  put \(sNeg) into chaseY")
        lines.append("end if")
        lines.append("set the velocityX of sprite \"\(n)\" to chaseX")
        lines.append("set the velocityY of sprite \"\(n)\" to chaseY")

        return BehaviorContribution(
            physics: PhysicsBodyPatch(affectedByGravity: false, allowsRotation: false),
            frameUpdate: lines
        )
    }

    // MARK: patrol
    private static func patrol(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        let axis = paramStr(b, "axis", default: "x")
        let speed = param(b, "speed", default: 120)
        let range = param(b, "range", default: 120)
        let s = fmt(speed)
        let r = fmt(range)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)
        // Use a unique accumulator per sanitized entity name to avoid collisions.
        let originVar = "\(n)_patrolOrigin"
        let dirVar = "\(n)_patrolDir"

        let initLines: [String] = [
            "put item 1 of (the loc of sprite \"\(n)\") into \(originVar)",
            "put 1 into \(dirVar)",
        ]

        var frameLines: [String] = []
        if axis == "y" {
            frameLines.append("put item 2 of (the loc of sprite \"\(n)\") into patrolPos")
            frameLines.append("if patrolPos > \(originVar) + \(r) then")
            frameLines.append("  put -1 into \(dirVar)")
            frameLines.append("end if")
            frameLines.append("if patrolPos < \(originVar) - \(r) then")
            frameLines.append("  put 1 into \(dirVar)")
            frameLines.append("end if")
            frameLines.append("set the velocityX of sprite \"\(n)\" to 0")
            frameLines.append("set the velocityY of sprite \"\(n)\" to \(s) * \(dirVar)")
        } else {
            frameLines.append("put item 1 of (the loc of sprite \"\(n)\") into patrolPos")
            frameLines.append("if patrolPos > \(originVar) + \(r) then")
            frameLines.append("  put -1 into \(dirVar)")
            frameLines.append("end if")
            frameLines.append("if patrolPos < \(originVar) - \(r) then")
            frameLines.append("  put 1 into \(dirVar)")
            frameLines.append("end if")
            frameLines.append("set the velocityX of sprite \"\(n)\" to \(s) * \(dirVar)")
            frameLines.append("set the velocityY of sprite \"\(n)\" to 0")
        }

        return BehaviorContribution(
            physics: PhysicsBodyPatch(affectedByGravity: false),
            sceneDidLoad: initLines,
            frameUpdate: frameLines,
            requiredGlobals: [originVar, dirVar]
        )
    }

    // MARK: physicsBody (behavior override)
    private static func physicsBodyBehavior(_ b: Behavior) -> BehaviorContribution {
        let isDynStr = paramStr(b, "dynamic", default: "true")
        let isDynamic = isDynStr.lowercased() == "true"
        let gravStr = paramStr(b, "gravity", default: "roleDefault")
        let affectedByGravity: Bool? = gravStr == "roleDefault" ? nil : gravStr.lowercased() == "true"
        let restitution = param(b, "restitution", default: 0.2)
        let friction = param(b, "friction", default: 0.2)
        let bodyShapeStr = paramStr(b, "bodyShape", default: "rect")
        let bodyType: PhysicsBodyType? = bodyShapeStr == "circle" ? .circle : bodyShapeStr == "rect" ? .rect : nil

        return BehaviorContribution(
            physics: PhysicsBodyPatch(
                isDynamic: isDynamic,
                affectedByGravity: affectedByGravity,
                restitution: restitution,
                friction: friction,
                bodyType: bodyType
            )
        )
    }

    // MARK: bounce
    private static func bounce() -> BehaviorContribution {
        BehaviorContribution(
            physics: PhysicsBodyPatch(restitution: 1.0, friction: 0.0)
        )
    }

    // MARK: wrapAround
    private static func wrapAround(_ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let w = fmt(recipe.sceneSize.width)
        let h = fmt(recipe.sceneSize.height)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        var lines: [String] = []
        lines.append("put item 1 of (the loc of sprite \"\(n)\") into wrapX")
        lines.append("put item 2 of (the loc of sprite \"\(n)\") into wrapY")
        lines.append("if wrapX > \(w) then")
        lines.append("  put 0 into wrapX")
        lines.append("end if")
        lines.append("if wrapX < 0 then")
        lines.append("  put \(w) into wrapX")
        lines.append("end if")
        lines.append("if wrapY > \(h) then")
        lines.append("  put 0 into wrapY")
        lines.append("end if")
        lines.append("if wrapY < 0 then")
        lines.append("  put \(h) into wrapY")
        lines.append("end if")
        lines.append("set the loc of sprite \"\(n)\" to wrapX & \",\" & wrapY")

        return BehaviorContribution(frameUpdate: lines)
    }

    // MARK: constrainToBounds
    private static func constrainToBounds(_ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let w = fmt(recipe.sceneSize.width)
        let h = fmt(recipe.sceneSize.height)
        let hw = fmt(entity.size.width / 2)
        let hh = fmt(entity.size.height / 2)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        var lines: [String] = []
        lines.append("put item 1 of (the loc of sprite \"\(n)\") into clampX")
        lines.append("put item 2 of (the loc of sprite \"\(n)\") into clampY")
        lines.append("if clampX < \(hw) then")
        lines.append("  put \(hw) into clampX")
        lines.append("end if")
        lines.append("if clampX > \(w) - \(hw) then")
        lines.append("  put \(w) - \(hw) into clampX")
        lines.append("end if")
        lines.append("if clampY < \(hh) then")
        lines.append("  put \(hh) into clampY")
        lines.append("end if")
        lines.append("if clampY > \(h) - \(hh) then")
        lines.append("  put \(h) - \(hh) into clampY")
        lines.append("end if")
        lines.append("set the loc of sprite \"\(n)\" to clampX & \",\" & clampY")

        return BehaviorContribution(frameUpdate: lines)
    }

    // MARK: destroyOutsideBounds
    private static func destroyOutsideBounds(_ b: Behavior, _ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let margin = param(b, "margin", default: 80)
        let m = fmt(margin)
        let w = fmt(recipe.sceneSize.width + margin)
        let h = fmt(recipe.sceneSize.height + margin)
        let nm = fmt(-margin)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        var lines: [String] = []
        lines.append("put item 1 of (the loc of sprite \"\(n)\") into dobX")
        lines.append("put item 2 of (the loc of sprite \"\(n)\") into dobY")
        lines.append("if dobX < \(nm) then")
        lines.append("  remove sprite \"\(n)\"")
        lines.append("end if")
        lines.append("if dobX > \(w) then")
        lines.append("  remove sprite \"\(n)\"")
        lines.append("end if")
        lines.append("if dobY < \(nm) then")
        lines.append("  remove sprite \"\(n)\"")
        lines.append("end if")
        lines.append("if dobY > \(h) then")
        lines.append("  remove sprite \"\(n)\"")
        lines.append("end if")

        return BehaviorContribution(frameUpdate: lines)
    }

    // MARK: spawner
    private static func spawner(_ b: Behavior, _ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let spawnRoleStr = paramStr(b, "spawnRole", default: "enemy")
        let interval = param(b, "interval", default: 1.5)
        let fromEdge = paramStr(b, "fromEdge", default: "top")
        let velocityStr = paramStr(b, "velocity", default: "0,-160")
        // Cap max spawn count to prevent runtime DoS via unlimited node creation.
        let rawMax = Int(param(b, "max", default: 8))
        let maxSpawn = min(rawMax, 500)

        let ivl = fmt(interval)
        let maxStr = String(maxSpawn)

        // Resolve spawnRole to a target entity name prefix/base.
        // Sanitize the base name and art reference before embedding in HypeTalk literals.
        let spawnRole = EntityRole.decodeTolerant(spawnRoleStr)
        let spawnEntity = firstEntity(role: spawnRole, in: recipe)
        let spawnBaseName = RecipeCompiler.sanitizedLiteral(spawnEntity?.name ?? spawnRoleStr)
        let spawnAssetArg: String
        if let art = spawnEntity?.artRoleRef {
            let safeArt = RecipeCompiler.sanitizedLiteral(art)
            spawnAssetArg = " with asset \"\(safeArt)\""
        } else {
            spawnAssetArg = ""
        }

        let w = recipe.sceneSize.width
        let h = recipe.sceneSize.height
        let n = RecipeCompiler.sanitizedLiteral(entity.name)
        let timerVar = "\(n)_spawnTimer"
        let countVar = "\(n)_spawnCount"
        // Unique name index var
        let idxVar = "\(n)_spawnIdx"

        // Parse velocity components and validate as numbers to prevent injection.
        // Bare HypeTalk numeric emission — use RecipeCompiler.numericLiteral to reject
        // non-numeric strings (e.g. injection payloads) and fall back to 0.
        let velParts = velocityStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let vx = RecipeCompiler.numericLiteral(velParts.first ?? "0", default: 0)
        let vy = RecipeCompiler.numericLiteral(velParts.count > 1 ? velParts[1] : "0", default: 0)

        // Spawn position depends on edge
        let (spawnX, spawnY): (String, String)
        switch fromEdge {
        case "bottom":
            spawnX = fmt(w / 2)
            spawnY = fmt(h + 20)
        case "left":
            spawnX = "-20"
            spawnY = fmt(h / 2)
        case "right":
            spawnX = fmt(w + 20)
            spawnY = fmt(h / 2)
        default: // top
            spawnX = fmt(w / 2)
            spawnY = "-20"
        }

        let initLines: [String] = [
            "put 0 into \(timerVar)",
            "put 0 into \(countVar)",
            "put 0 into \(idxVar)",
        ]

        var frameLines: [String] = []
        frameLines.append("add deltaTime to \(timerVar)")
        frameLines.append("if \(timerVar) >= \(ivl) then")
        frameLines.append("  if \(countVar) < \(maxStr) then")
        frameLines.append("    add 1 to \(idxVar)")
        frameLines.append("    add 1 to \(countVar)")
        frameLines.append("    put \"\(spawnBaseName)_\" & \(idxVar) into spawnName")
        frameLines.append("    create sprite spawnName in scene \"main\"\(spawnAssetArg)")
        frameLines.append("    set the loc of sprite spawnName to \"\(spawnX),\(spawnY)\"")
        frameLines.append("    set the velocityX of sprite spawnName to \(vx)")
        frameLines.append("    set the velocityY of sprite spawnName to \(vy)")
        frameLines.append("  end if")
        frameLines.append("  put 0 into \(timerVar)")
        frameLines.append("end if")

        return BehaviorContribution(
            sceneDidLoad: initLines,
            frameUpdate: frameLines,
            requiredGlobals: [timerVar, countVar, idxVar]
        )
    }

    // MARK: collectible
    private static func collectible(_ entity: GameEntity) -> BehaviorContribution {
        // Collectible itself has no script contribution beyond ensuring contact
        // testing is set up via physics (handled by RolePhysics).
        // The actual collect logic lives in scoreOnCollect / damageOnContact on
        // the player or the collectible.
        BehaviorContribution()
    }

    // MARK: damageOnContact
    private static func damageOnContact(_ b: Behavior, _ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let amount = param(b, "amount", default: 1)
        let amtStr = fmt(amount)
        let targetRoleStr = paramStr(b, "targetRole", default: "player")
        let targetRole = EntityRole.decodeTolerant(targetRoleStr)
        let targetEntity = firstEntity(role: targetRole, in: recipe)
        let rawTarget = targetEntity?.name ?? targetRoleStr
        let targetName = RecipeCompiler.sanitizedLiteral(rawTarget)
        let pred = "otherName is \"\(targetName)\""

        let lines: [String] = [
            "subtract \(amtStr) from health",
            "if health <= 0 then",
            "  put \"true\" into gameOver",
            "  set the text of label \"status\" to \"Game Over\"",
            "end if",
        ]

        return BehaviorContribution(
            beginContact: [ContactBranch(otherPredicate: pred, lines: lines)],
            requiredGlobals: ["health", "gameOver"],
            requiredStateVars: ["health"]
        )
    }

    // MARK: health
    private static func health(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        let maxHP = Int(param(b, "max", default: 3))
        let initLines: [String] = [
            "put \(maxHP) into health",
        ]
        return BehaviorContribution(
            sceneDidLoad: initLines,
            requiredGlobals: ["health"],
            requiredStateVars: ["health"]
        )
    }

    // MARK: scoreOnCollect
    private static func scoreOnCollect(_ b: Behavior, _ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let points = Int(param(b, "points", default: 10))
        let ptStr = String(points)
        // This behavior lives on the player; the contact is with a collectible.
        let collectibleEntities = recipe.entities.filter { $0.role == .collectible }
        guard !collectibleEntities.isEmpty else { return BehaviorContribution() }

        var branches: [ContactBranch] = []
        for col in collectibleEntities {
            let pred = contactPredicate(for: col)
            var lines: [String] = [
                "add \(ptStr) to score",
                "remove sprite otherName",
            ]
            // Update score HUD if configured.
            if let hudName = recipe.gameState.scoreHUDEntityName {
                let safeHUD = RecipeCompiler.sanitizedLiteral(hudName)
                lines.append("set the text of label \"\(safeHUD)\" to \"Score: \" & score")
            }
            branches.append(ContactBranch(otherPredicate: pred, lines: lines))
        }

        return BehaviorContribution(
            beginContact: branches,
            requiredGlobals: ["score"],
            requiredStateVars: ["score"]
        )
    }

    // MARK: winOnReach
    private static func winOnReach(_ entity: GameEntity) -> BehaviorContribution {
        // This behavior lives on the player; contact with a goal entity triggers win.
        // The player entity name is `entity.name`.
        // We need the goal entities from the recipe, but winOnReach's contribution
        // is placed at the player entity level. We emit a placeholder contact branch
        // that tests for the goal role — the contact is detected from the other side.
        // In practice the RecipeCompiler will add goal contacts from the game state
        // winConditions. This behavior just ensures the physics is set up.
        BehaviorContribution()
    }

    // MARK: winOnScore
    private static func winOnScore(_ b: Behavior) -> BehaviorContribution {
        let threshold = Int(param(b, "threshold", default: 100))
        let tStr = String(threshold)

        let frameLines: [String] = [
            "if score >= \(tStr) then",
            "  if gameOver is not \"true\" then",
            "    put \"true\" into gameOver",
            "    set the text of label \"status\" to \"You Win!\"",
            "  end if",
            "end if",
        ]

        return BehaviorContribution(
            frameUpdate: frameLines,
            requiredGlobals: ["score", "gameOver"],
            requiredStateVars: ["score"]
        )
    }

    // MARK: loseOnContact
    private static func loseOnContact(_ b: Behavior, _ entity: GameEntity, _ recipe: GameRecipe) -> BehaviorContribution {
        let withRoleStr = paramStr(b, "withRole", default: "hazard")
        let withRole = EntityRole.decodeTolerant(withRoleStr)
        let withEntities = recipe.entities.filter { $0.role == withRole }
        guard !withEntities.isEmpty else {
            // Fallback: match by name contains role string (sanitized before embedding).
            let safeRole = RecipeCompiler.sanitizedLiteral(withRoleStr)
            let pred = "otherName contains \"\(safeRole)\""
            let lines: [String] = [
                "put \"true\" into gameOver",
                "set the text of label \"status\" to \"Game Over\"",
            ]
            return BehaviorContribution(
                beginContact: [ContactBranch(otherPredicate: pred, lines: lines)],
                requiredGlobals: ["gameOver"]
            )
        }

        var branches: [ContactBranch] = []
        for hazardEntity in withEntities {
            let pred = contactPredicate(for: hazardEntity)
            let lines: [String] = [
                "put \"true\" into gameOver",
                "set the text of label \"status\" to \"Game Over\"",
            ]
            branches.append(ContactBranch(otherPredicate: pred, lines: lines))
        }

        return BehaviorContribution(
            beginContact: branches,
            requiredGlobals: ["gameOver"]
        )
    }

    // MARK: loseOnZeroHealth
    private static func loseOnZeroHealth(_ entity: GameEntity) -> BehaviorContribution {
        // Checked in frameUpdate every frame.
        let frameLines: [String] = [
            "if health <= 0 then",
            "  if gameOver is not \"true\" then",
            "    put \"true\" into gameOver",
            "    set the text of label \"status\" to \"Game Over\"",
            "  end if",
            "end if",
        ]
        return BehaviorContribution(
            frameUpdate: frameLines,
            requiredGlobals: ["health", "gameOver"]
        )
    }

    // MARK: draggable
    private static func draggable(_ entity: GameEntity) -> BehaviorContribution {
        // Draggable: on frameUpdate, when the mouse is held over this sprite,
        // move it to the mouse location. This is a simplified version that
        // follows the mouse continuously (no press/release distinction since
        // HypeTalk doesn't have mouseDown in frameUpdate).
        // We use followPointer logic.
        let n = RecipeCompiler.sanitizedLiteral(entity.name)
        let lines: [String] = [
            "put item 1 of (the mouseLoc) into dragX",
            "put item 2 of (the mouseLoc) into dragY",
            "set the loc of sprite \"\(n)\" to dragX & \",\" & dragY",
        ]
        return BehaviorContribution(
            physics: PhysicsBodyPatch(isDynamic: false),
            frameUpdate: lines
        )
    }

    // MARK: rotator
    private static func rotator(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        let dps = param(b, "degreesPerSecond", default: 90)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        // Emit a rotateBy ActionSpec repeated forever.
        // Duration=1 second for `dps` degrees, repeated forever.
        let rotateAction = ActionSpec(
            actionType: .rotateBy,
            name: "\(n)_rotate",
            duration: 1.0,
            parameters: ["angle": fmt(dps)]
        )
        let repeatAction = ActionSpec(
            actionType: .repeatForever,
            name: "\(n)_rotate_loop",
            duration: 0,
            parameters: [:],
            children: [rotateAction]
        )

        return BehaviorContribution(actions: [repeatAction])
    }

    // MARK: oscillate
    private static func oscillate(_ b: Behavior, _ entity: GameEntity) -> BehaviorContribution {
        let axis = paramStr(b, "axis", default: "y")
        let amplitude = param(b, "amplitude", default: 40)
        let period = param(b, "period", default: 2)
        let amp = fmt(amplitude)
        let halfPeriod = fmt(period / 2)
        let n = RecipeCompiler.sanitizedLiteral(entity.name)

        // Move by amplitude in one direction, then back, repeating forever.
        // Use moveBy to keep it relative to current position.
        let (dx, dy) = axis == "x" ? (amp, "0") : ("0", amp)
        let moveOut = ActionSpec(
            actionType: .moveBy,
            name: "\(n)_osc_out",
            duration: Double(period / 2),
            parameters: ["x": dx, "y": dy]
        )
        let moveBack = ActionSpec(
            actionType: .moveBy,
            name: "\(n)_osc_back",
            duration: Double(period / 2),
            parameters: ["x": "-\(dx)", "y": "-\(dy)"]
        )
        _ = halfPeriod // used via moveOut/moveBack duration
        let sequence = ActionSpec(
            actionType: .sequence,
            name: "\(n)_osc_seq",
            duration: 0,
            parameters: [:],
            children: [moveOut, moveBack]
        )
        let loop = ActionSpec(
            actionType: .repeatForever,
            name: "\(n)_osc_loop",
            duration: 0,
            parameters: [:],
            children: [sequence]
        )

        return BehaviorContribution(actions: [loop])
    }
}
