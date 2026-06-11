import Foundation

// MARK: - GenrePresetLibrary

/// A catalogue of starting `GameRecipe` values for common game genres.
///
/// Each preset maps to a canonical id matching the `SpriteGameTemplateCatalog`
/// vocabulary. The returned recipe is pure data — fully editable after creation.
/// The unit of customisation is the recipe itself, not patched scripts.
///
/// Design invariants:
/// - Preset IDs mirror `SpriteGameTemplateCatalog` ids exactly.
/// - `canonicalID(for:)` resolves aliases through the same catalog so callers
///   can pass "platformer" or "shmup" and still get a preset.
/// - Every preset compiles to a parsing, playable scene via `RecipeCompiler`.
/// - Gravity for platformers uses `VectorSpec(dx: 0, dy: -9.8)` which maps
///   directly to SpriteKit's `physicsWorld.gravity` (negative dy = downward
///   pull on affected-by-gravity bodies). The platformerMovement behavior sets
///   `affectedByGravity: true` on the player body automatically.
/// - Scene size and name are honoured verbatim when provided; the catalog's
///   `defaultSceneSize` is used as the fallback.
public enum GenrePresetLibrary {

    // MARK: - Public API

    /// All preset ids this library provides.
    ///
    /// Each id corresponds to a `SpriteGameTemplateCatalog` template id.
    public static var presetIDs: [String] {
        [
            "top_down_adventure",
            "side_scroller_platformer",
            "space_shooter",
            "twin_stick_shooter",
            "breakout",
            "pong_sports_arena",
            "endless_runner",
            "physics_puzzle",
            "racing_lane",
        ]
    }

    /// Return a starting `GameRecipe` for the given genre id.
    ///
    /// - Parameters:
    ///   - id: A canonical preset id (see `presetIDs`) or an alias resolvable
    ///     via `SpriteGameTemplateCatalog`.
    ///   - sceneName: The `GameRecipe.sceneName`; passed through verbatim.
    ///   - sceneSize: When non-nil, overrides the catalog's default scene size.
    /// - Returns: A `GameRecipe` with entities, behaviors, controls, and game
    ///   state configured for the genre, or `nil` for unknown ids.
    public static func preset(
        for id: String,
        sceneName: String,
        sceneSize: SizeSpec?
    ) -> GameRecipe? {
        guard let canonical = canonicalID(for: id) else { return nil }
        let size = sceneSize ?? defaultSize(for: canonical)
        switch canonical {
        case "top_down_adventure":   return topDownAdventure(sceneName: sceneName, size: size)
        case "side_scroller_platformer": return sideScrollerPlatformer(sceneName: sceneName, size: size)
        case "space_shooter":        return spaceShooter(sceneName: sceneName, size: size)
        case "twin_stick_shooter":   return twinStickShooter(sceneName: sceneName, size: size)
        case "breakout":             return breakout(sceneName: sceneName, size: size)
        case "pong_sports_arena":    return pongSportsArena(sceneName: sceneName, size: size)
        case "endless_runner":       return endlessRunner(sceneName: sceneName, size: size)
        case "physics_puzzle":       return physicsPuzzle(sceneName: sceneName, size: size)
        case "racing_lane":          return racingLane(sceneName: sceneName, size: size)
        default:                     return nil
        }
    }

    /// Resolve an id or alias (via `SpriteGameTemplateCatalog`) to a canonical
    /// preset id, or `nil` if the library has no preset for it.
    public static func canonicalID(for raw: String) -> String? {
        // First check if it's already a known preset id.
        let normalised = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if presetIDs.contains(normalised) { return normalised }

        // Resolve through the catalog (handles aliases, spacing, etc.).
        guard let descriptor = SpriteGameTemplateCatalog.descriptor(matching: raw) else {
            return nil
        }
        let catalogID = descriptor.id
        // Return nil if the catalog matched something we don't have a preset for.
        return presetIDs.contains(catalogID) ? catalogID : nil
    }

    // MARK: - Private: default scene sizes

    private static func defaultSize(for id: String) -> SizeSpec {
        SpriteGameTemplateCatalog.descriptor(for: id)?.defaultSceneSize
            ?? SizeSpec(width: 800, height: 600)
    }

    // MARK: - Preset: top_down_adventure

    /// Top-down adventure (Zelda-style): 4-direction player, patrolling enemies,
    /// collectibles, a goal tile, score tracking, arrow controls.
    private static func topDownAdventure(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        let player = GameEntity(
            name: "player",
            role: .player,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 32, height: 32),
            placeholderColor: "#4488FF",
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "220"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .scoreOnCollect, params: ["points": "10"]),
                Behavior(kind: .loseOnContact, params: ["withRole": "enemy"]),
            ]
        )

        let enemy = GameEntity(
            name: "enemy",
            role: .enemy,
            position: PointSpec(x: w * 0.25, y: h * 0.25),
            size: SizeSpec(width: 28, height: 28),
            count: 3,
            placeholderColor: "#FF4422",
            behaviors: [
                Behavior(kind: .chaseTarget, params: ["targetRole": "player", "speed": "80"]),
                Behavior(kind: .constrainToBounds),
            ]
        )

        let gem = GameEntity(
            name: "gem",
            role: .collectible,
            position: PointSpec(x: w * 0.6, y: h * 0.35),
            size: SizeSpec(width: 20, height: 20),
            count: 5,
            placeholderColor: "#FFD700",
            behaviors: [
                Behavior(kind: .collectible),
            ]
        )

        let goal = GameEntity(
            name: "goal",
            role: .goal,
            position: PointSpec(x: w - 60, y: h - 60),
            size: SizeSpec(width: 40, height: 40),
            placeholderColor: "#00FF88",
            behaviors: [
                Behavior(kind: .winOnReach),
            ]
        )

        let scoreLabel = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: 50),
            size: SizeSpec(width: 300, height: 30),
            initialText: "",
            fontSize: 16,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "left",  action: .moveLeft,  targetEntityName: "player"),
            ControlBinding(key: "right", action: .moveRight, targetEntityName: "player"),
            ControlBinding(key: "up",    action: .moveUp,    targetEntityName: "player"),
            ControlBinding(key: "down",  action: .moveDown,  targetEntityName: "player"),
        ]

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            trackLives: true,
            initialLives: 3,
            winConditions: [WinLoseCondition(kind: .reachGoal, goalEntityName: "goal")],
            loseConditions: [WinLoseCondition(kind: .zeroLives)],
            scoreHUDEntityName: "scoreLabel",
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "top_down_adventure",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#101820",
            gravity: VectorSpec(dx: 0, dy: 0),
            entities: [player, enemy, gem, goal, scoreLabel, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Top-down adventure preset. Collect gems for score, reach the goal to win, avoid enemies."
        )
    }

    // MARK: - Preset: side_scroller_platformer

    /// Side-scrolling platformer: gravity-affected player, ground, a hazard,
    /// and a goal. Left/right + space to jump. Gravity `dy = -9.8` (SpriteKit
    /// convention: negative dy pulls sprites with affectedByGravity=true downward).
    private static func sideScrollerPlatformer(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        let player = GameEntity(
            name: "player",
            role: .player,
            position: PointSpec(x: 80, y: h - 120),
            size: SizeSpec(width: 32, height: 40),
            placeholderColor: "#4488FF",
            behaviors: [
                // platformerMovement sets affectedByGravity=true on the physics body.
                Behavior(kind: .platformerMovement, params: ["speed": "200", "jumpForce": "620"]),
                Behavior(kind: .loseOnContact, params: ["withRole": "hazard"]),
            ]
        )

        // Thin static ground platform spanning the full width.
        let ground = GameEntity(
            name: "ground",
            role: .wall,
            position: PointSpec(x: w / 2, y: h - 16),
            size: SizeSpec(width: w, height: 32),
            placeholderColor: "#888888",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        // A raised platform in the middle.
        let platform = GameEntity(
            name: "platform",
            role: .wall,
            position: PointSpec(x: w / 2, y: h - 200),
            size: SizeSpec(width: 200, height: 20),
            placeholderColor: "#666666",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        let hazard = GameEntity(
            name: "hazard",
            role: .hazard,
            position: PointSpec(x: w * 0.6, y: h - 52),
            size: SizeSpec(width: 28, height: 28),
            placeholderColor: "#FF6600",
            behaviors: [
                Behavior(kind: .patrol, params: ["axis": "x", "speed": "100", "range": "80"]),
            ]
        )

        let goal = GameEntity(
            name: "goal",
            role: .goal,
            position: PointSpec(x: w - 60, y: h - 160),
            size: SizeSpec(width: 32, height: 48),
            placeholderColor: "#00FF88",
            behaviors: [
                Behavior(kind: .winOnReach),
            ]
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: 30),
            size: SizeSpec(width: 300, height: 30),
            initialText: "",
            fontSize: 16,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "left",  action: .moveLeft,  targetEntityName: "player"),
            ControlBinding(key: "right", action: .moveRight, targetEntityName: "player"),
            ControlBinding(key: "space", action: .jump,      targetEntityName: "player"),
            ControlBinding(key: "up",    action: .jump,      targetEntityName: "player"),
        ]

        let gameState = GameState(
            trackLives: true,
            initialLives: 3,
            winConditions: [WinLoseCondition(kind: .reachGoal, goalEntityName: "goal")],
            loseConditions: [WinLoseCondition(kind: .zeroLives)],
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "side_scroller_platformer",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#102030",
            // Gravity dy = -9.8: SpriteKit pulls affectedByGravity bodies downward.
            gravity: VectorSpec(dx: 0, dy: -9.8),
            entities: [player, ground, platform, hazard, goal, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Side-scroller platformer preset. Gravity dy=-9.8 (SpriteKit convention). PlatformerMovement enables affectedByGravity on the player."
        )
    }

    // MARK: - Preset: space_shooter

    /// Vertical space shooter: player ship at the bottom, enemy spawner at the
    /// top, score for surviving, loseOnContact with spawned enemies.
    private static func spaceShooter(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        let player = GameEntity(
            name: "player",
            role: .player,
            position: PointSpec(x: w / 2, y: h - 60),
            size: SizeSpec(width: 40, height: 40),
            placeholderColor: "#4488FF",
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "260"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .loseOnContact, params: ["withRole": "enemy"]),
            ]
        )

        // Template enemy entity — spawned by the spawner; keeps role for contact detection.
        let enemyTemplate = GameEntity(
            name: "enemy",
            role: .enemy,
            position: PointSpec(x: w / 2, y: -60),
            size: SizeSpec(width: 32, height: 32),
            count: 1,
            placeholderColor: "#FF4422",
            behaviors: [
                Behavior(kind: .destroyOutsideBounds, params: ["margin": "80"]),
            ]
        )

        let spawner = GameEntity(
            name: "spawner",
            role: .spawner,
            position: PointSpec(x: w / 2, y: 0),
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "enemy",
                    "interval": "1.5",
                    "fromEdge": "top",
                    "velocity": "0,120",
                    "max": "20",
                ]),
            ]
        )

        let scoreLabel = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 100, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 300, height: 40),
            initialText: "",
            fontSize: 20,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "left",  action: .moveLeft,  targetEntityName: "player"),
            ControlBinding(key: "right", action: .moveRight, targetEntityName: "player"),
            ControlBinding(key: "up",    action: .moveUp,    targetEntityName: "player"),
            ControlBinding(key: "down",  action: .moveDown,  targetEntityName: "player"),
        ]

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            winConditions: [WinLoseCondition(kind: .reachScore, scoreThreshold: 500)],
            scoreHUDEntityName: "scoreLabel",
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "space_shooter",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#000020",
            gravity: VectorSpec(dx: 0, dy: 0),
            entities: [player, enemyTemplate, spawner, scoreLabel, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Space shooter preset. Spawner fires enemies from the top edge."
        )
    }

    // MARK: - Preset: twin_stick_shooter

    /// Arena twin-stick shooter: player moves in 8 directions, enemy spawner,
    /// score on enemy wave, loseOnContact.
    private static func twinStickShooter(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        let player = GameEntity(
            name: "player",
            role: .player,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 36, height: 36),
            placeholderColor: "#4488FF",
            behaviors: [
                Behavior(kind: .eightDirection, params: ["speed": "220"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .loseOnContact, params: ["withRole": "enemy"]),
            ]
        )

        let enemyTemplate = GameEntity(
            name: "enemy",
            role: .enemy,
            position: PointSpec(x: -40, y: h / 2),
            size: SizeSpec(width: 28, height: 28),
            count: 1,
            placeholderColor: "#FF4422",
            behaviors: [
                Behavior(kind: .chaseTarget, params: ["targetRole": "player", "speed": "100"]),
                Behavior(kind: .destroyOutsideBounds, params: ["margin": "80"]),
            ]
        )

        let spawner = GameEntity(
            name: "spawner",
            role: .spawner,
            position: PointSpec(x: 0, y: h / 2),
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "enemy",
                    "interval": "2.0",
                    "fromEdge": "left",
                    "velocity": "60,0",
                    "max": "15",
                ]),
            ]
        )

        let scoreLabel = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 100, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: h / 2 - 40),
            size: SizeSpec(width: 300, height: 40),
            initialText: "",
            fontSize: 20,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "left",  action: .moveLeft,  targetEntityName: "player"),
            ControlBinding(key: "right", action: .moveRight, targetEntityName: "player"),
            ControlBinding(key: "up",    action: .moveUp,    targetEntityName: "player"),
            ControlBinding(key: "down",  action: .moveDown,  targetEntityName: "player"),
        ]

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            winConditions: [WinLoseCondition(kind: .reachScore, scoreThreshold: 300)],
            scoreHUDEntityName: "scoreLabel",
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "twin_stick_shooter",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#0A0010",
            gravity: VectorSpec(dx: 0, dy: 0),
            entities: [player, enemyTemplate, spawner, scoreLabel, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Twin-stick arena shooter preset. Enemy spawner approaches from the left edge."
        )
    }

    // MARK: - Preset: breakout

    /// Classic breakout / brick-breaker: a paddle constrained to the X axis,
    /// a bouncing ball, a row of brick collectibles, and loss when ball leaves bottom.
    private static func breakout(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        // Paddle — player, moves left/right only, constrained.
        let paddle = GameEntity(
            name: "paddle",
            role: .player,
            position: PointSpec(x: w / 2, y: h - 40),
            size: SizeSpec(width: 100, height: 18),
            placeholderColor: "#4488FF",
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "280"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        // Ball — physics body with high restitution and no gravity.
        let ball = GameEntity(
            name: "ball",
            role: .hazard,
            position: PointSpec(x: w / 2, y: h - 100),
            size: SizeSpec(width: 18, height: 18),
            placeholderColor: "#FFFFFF",
            behaviors: [
                Behavior(kind: .physicsBody, params: [
                    "dynamic": "true",
                    "gravity": "false",
                    "restitution": "1.0",
                    "friction": "0.0",
                    "bodyShape": "circle",
                ]),
                Behavior(kind: .bounce),
                Behavior(kind: .destroyOutsideBounds, params: ["margin": "60"]),
            ]
        )

        // Bricks — a row of collectibles.
        let brick = GameEntity(
            name: "brick",
            role: .collectible,
            position: PointSpec(x: w / 2, y: 100),
            size: SizeSpec(width: 60, height: 22),
            count: 8,
            placeholderColor: "#FF6644",
            behaviors: [
                Behavior(kind: .collectible),
                Behavior(kind: .scoreOnCollect, params: ["points": "10"]),
            ]
        )

        // Left, right, top boundary walls — static physics bodies.
        let wallLeft = GameEntity(
            name: "wallLeft",
            role: .wall,
            position: PointSpec(x: 8, y: h / 2),
            size: SizeSpec(width: 16, height: h),
            placeholderColor: "#444444",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false", "restitution": "1.0", "friction": "0.0"]),
            ]
        )

        let wallRight = GameEntity(
            name: "wallRight",
            role: .wall,
            position: PointSpec(x: w - 8, y: h / 2),
            size: SizeSpec(width: 16, height: h),
            placeholderColor: "#444444",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false", "restitution": "1.0", "friction": "0.0"]),
            ]
        )

        let wallTop = GameEntity(
            name: "wallTop",
            role: .wall,
            position: PointSpec(x: w / 2, y: 8),
            size: SizeSpec(width: w, height: 16),
            placeholderColor: "#444444",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false", "restitution": "1.0", "friction": "0.0"]),
            ]
        )

        let scoreLabel = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 80, y: 20),
            size: SizeSpec(width: 160, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 300, height: 40),
            initialText: "",
            fontSize: 22,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "left",  action: .moveLeft,  targetEntityName: "paddle"),
            ControlBinding(key: "right", action: .moveRight, targetEntityName: "paddle"),
        ]

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            trackLives: true,
            initialLives: 3,
            winConditions: [WinLoseCondition(kind: .reachScore, scoreThreshold: 80)],
            loseConditions: [WinLoseCondition(kind: .zeroLives)],
            scoreHUDEntityName: "scoreLabel",
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "breakout",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#101018",
            gravity: VectorSpec(dx: 0, dy: 0),
            entities: [paddle, ball, brick, wallLeft, wallRight, wallTop, scoreLabel, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Breakout preset. Ball physics: restitution=1, friction=0, affectedByGravity=false. Bricks scored as collectibles."
        )
    }

    // MARK: - Preset: pong_sports_arena

    /// Pong arena: two paddles (one player, one patrol AI), a bouncing ball,
    /// score tracking, win at 5 points.
    private static func pongSportsArena(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        let paddlePlayer = GameEntity(
            name: "paddlePlayer",
            role: .player,
            position: PointSpec(x: 30, y: h / 2),
            size: SizeSpec(width: 14, height: 80),
            placeholderColor: "#4488FF",
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "260"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        // AI paddle patrols vertically — simpler than chaseTarget and avoids
        // kinematic-body velocity conflicts with isDynamic=false.
        let paddleAI = GameEntity(
            name: "paddleAI",
            role: .enemy,
            position: PointSpec(x: w - 30, y: h / 2),
            size: SizeSpec(width: 14, height: 80),
            placeholderColor: "#FF4422",
            behaviors: [
                Behavior(kind: .patrol, params: ["axis": "y", "speed": "180", "range": "200"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        // Ball — the primary hazard that bounces.
        let ball = GameEntity(
            name: "ball",
            role: .hazard,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 16, height: 16),
            placeholderColor: "#FFFFFF",
            behaviors: [
                Behavior(kind: .physicsBody, params: [
                    "dynamic": "true",
                    "gravity": "false",
                    "restitution": "1.0",
                    "friction": "0.0",
                    "bodyShape": "circle",
                ]),
                Behavior(kind: .bounce),
            ]
        )

        // Top and bottom walls.
        let wallTop = GameEntity(
            name: "wallTop",
            role: .wall,
            position: PointSpec(x: w / 2, y: 8),
            size: SizeSpec(width: w, height: 16),
            placeholderColor: "#444444",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false", "restitution": "1.0", "friction": "0.0"]),
            ]
        )

        let wallBottom = GameEntity(
            name: "wallBottom",
            role: .wall,
            position: PointSpec(x: w / 2, y: h - 8),
            size: SizeSpec(width: w, height: 16),
            placeholderColor: "#444444",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false", "restitution": "1.0", "friction": "0.0"]),
            ]
        )

        let scoreLabel = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 300, height: 40),
            initialText: "",
            fontSize: 22,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "up",   action: .moveUp,   targetEntityName: "paddlePlayer"),
            ControlBinding(key: "down", action: .moveDown, targetEntityName: "paddlePlayer"),
        ]

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            winConditions: [WinLoseCondition(kind: .reachScore, scoreThreshold: 5)],
            scoreHUDEntityName: "scoreLabel",
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "pong_sports_arena",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#000000",
            gravity: VectorSpec(dx: 0, dy: 0),
            entities: [paddlePlayer, paddleAI, ball, wallTop, wallBottom, scoreLabel, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Pong preset. AI paddle chases the ball role. Ball needs an initial velocity set via set_controls or a rule after build."
        )
    }

    // MARK: - Preset: endless_runner

    /// Endless runner: player jumps over spawned hazards, score increases over time,
    /// loseOnContact with hazard.
    private static func endlessRunner(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        let player = GameEntity(
            name: "player",
            role: .player,
            position: PointSpec(x: 120, y: h - 100),
            size: SizeSpec(width: 32, height: 40),
            placeholderColor: "#4488FF",
            behaviors: [
                // Platformer movement: gravity enabled, jump via space.
                Behavior(kind: .platformerMovement, params: ["speed": "0", "jumpForce": "580"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .loseOnContact, params: ["withRole": "hazard"]),
            ]
        )

        // Ground platform — static physics.
        let ground = GameEntity(
            name: "ground",
            role: .wall,
            position: PointSpec(x: w / 2, y: h - 16),
            size: SizeSpec(width: w, height: 32),
            placeholderColor: "#888888",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        // Hazard template — spawned from the right edge.
        let hazardTemplate = GameEntity(
            name: "hazard",
            role: .hazard,
            position: PointSpec(x: w + 40, y: h - 60),
            size: SizeSpec(width: 30, height: 36),
            count: 1,
            placeholderColor: "#FF6600",
            behaviors: [
                Behavior(kind: .destroyOutsideBounds, params: ["margin": "80"]),
            ]
        )

        let spawner = GameEntity(
            name: "spawner",
            role: .spawner,
            position: PointSpec(x: w, y: h - 60),
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "hazard",
                    "interval": "2.5",
                    "fromEdge": "right",
                    "velocity": "-200,0",
                    "max": "30",
                ]),
            ]
        )

        let scoreLabel = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 100, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 300, height: 40),
            initialText: "",
            fontSize: 22,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "space", action: .jump, targetEntityName: "player"),
            ControlBinding(key: "up",    action: .jump, targetEntityName: "player"),
        ]

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            winConditions: [WinLoseCondition(kind: .reachScore, scoreThreshold: 200)],
            scoreHUDEntityName: "scoreLabel",
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "endless_runner",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#182028",
            gravity: VectorSpec(dx: 0, dy: -9.8),
            entities: [player, ground, hazardTemplate, spawner, scoreLabel, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Endless runner preset. Player jumps over hazards spawned from the right. Gravity dy=-9.8."
        )
    }

    // MARK: - Preset: physics_puzzle

    /// Physics puzzle: gravity on, a draggable ball, some block obstacles,
    /// and a goal zone. Drag the ball to the goal.
    private static func physicsPuzzle(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        // Ball is a physics-enabled player that falls under gravity. The user
        // can add draggable via attach_behavior after creation if desired; omitted
        // here to avoid draggable's isDynamic=false patch conflicting with
        // the physicsBody dynamic=true setting.
        let ball = GameEntity(
            name: "ball",
            role: .player,
            position: PointSpec(x: w / 4, y: h / 4),
            size: SizeSpec(width: 36, height: 36),
            placeholderColor: "#4488FF",
            behaviors: [
                Behavior(kind: .physicsBody, params: [
                    "dynamic": "true",
                    "gravity": "true",
                    "restitution": "0.4",
                    "friction": "0.3",
                    "bodyShape": "circle",
                ]),
                Behavior(kind: .winOnReach),
            ]
        )

        // Static floor.
        let floor = GameEntity(
            name: "floor",
            role: .wall,
            position: PointSpec(x: w / 2, y: h - 16),
            size: SizeSpec(width: w, height: 32),
            placeholderColor: "#888888",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false", "restitution": "0.4", "friction": "0.6"]),
            ]
        )

        // Left wall.
        let wallLeft = GameEntity(
            name: "wallLeft",
            role: .wall,
            position: PointSpec(x: 8, y: h / 2),
            size: SizeSpec(width: 16, height: h),
            placeholderColor: "#666666",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        // Right wall.
        let wallRight = GameEntity(
            name: "wallRight",
            role: .wall,
            position: PointSpec(x: w - 8, y: h / 2),
            size: SizeSpec(width: 16, height: h),
            placeholderColor: "#666666",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "false"]),
            ]
        )

        // A movable block obstacle.
        let block = GameEntity(
            name: "block",
            role: .decoration,
            position: PointSpec(x: w / 2, y: h - 100),
            size: SizeSpec(width: 60, height: 20),
            count: 2,
            placeholderColor: "#AA6622",
            behaviors: [
                Behavior(kind: .physicsBody, params: ["dynamic": "true", "restitution": "0.2", "friction": "0.5"]),
            ]
        )

        // Goal zone at the bottom-right.
        let goal = GameEntity(
            name: "goal",
            role: .goal,
            position: PointSpec(x: w - 60, y: h - 80),
            size: SizeSpec(width: 50, height: 50),
            placeholderColor: "#00FF88",
            behaviors: [
                Behavior(kind: .winOnReach),
            ]
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: 30),
            size: SizeSpec(width: 300, height: 30),
            initialText: "Drag the ball to the goal!",
            fontSize: 16,
            fontColor: "#FFFFFF"
        )

        let gameState = GameState(
            winConditions: [WinLoseCondition(kind: .reachGoal, goalEntityName: "goal")],
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "physics_puzzle",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#1A1A2E",
            gravity: VectorSpec(dx: 0, dy: -9.8),
            entities: [ball, floor, wallLeft, wallRight, block, goal, statusLabel],
            gameState: gameState,
            notes: "Physics puzzle preset. Gravity dy=-9.8. Drag the ball to the goal. Block obstacles are dynamic."
        )
    }

    // MARK: - Preset: racing_lane

    /// Lane racing: player car moves laterally across the scene, hazard obstacles
    /// spawn from the top and scroll down, score increases over time.
    private static func racingLane(sceneName: String, size: SizeSpec) -> GameRecipe {
        let w = size.width, h = size.height

        let player = GameEntity(
            name: "player",
            role: .player,
            position: PointSpec(x: w / 2, y: h - 80),
            size: SizeSpec(width: 36, height: 56),
            placeholderColor: "#4488FF",
            behaviors: [
                Behavior(kind: .topDownMovement, params: ["speed": "240"]),
                Behavior(kind: .constrainToBounds),
                Behavior(kind: .loseOnContact, params: ["withRole": "hazard"]),
            ]
        )

        // Obstacle template spawned from top.
        let obstacleTemplate = GameEntity(
            name: "obstacle",
            role: .hazard,
            position: PointSpec(x: w / 2, y: -40),
            size: SizeSpec(width: 36, height: 56),
            count: 1,
            placeholderColor: "#FF4422",
            behaviors: [
                Behavior(kind: .destroyOutsideBounds, params: ["margin": "80"]),
            ]
        )

        let spawner = GameEntity(
            name: "spawner",
            role: .spawner,
            position: PointSpec(x: w / 2, y: 0),
            size: SizeSpec(width: 1, height: 1),
            behaviors: [
                Behavior(kind: .spawner, params: [
                    "spawnRole": "hazard",
                    "interval": "1.8",
                    "fromEdge": "top",
                    "velocity": "0,160",
                    "max": "25",
                ]),
            ]
        )

        let scoreLabel = GameEntity(
            name: "scoreLabel",
            role: .hud,
            position: PointSpec(x: 100, y: 20),
            size: SizeSpec(width: 200, height: 30),
            initialText: "Score: 0",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )

        let statusLabel = GameEntity(
            name: "statusLabel",
            role: .hud,
            position: PointSpec(x: w / 2, y: h / 2),
            size: SizeSpec(width: 300, height: 40),
            initialText: "",
            fontSize: 22,
            fontColor: "#FFFFFF"
        )

        let controls: [ControlBinding] = [
            ControlBinding(key: "left",  action: .moveLeft,  targetEntityName: "player"),
            ControlBinding(key: "right", action: .moveRight, targetEntityName: "player"),
        ]

        let gameState = GameState(
            trackScore: true,
            initialScore: 0,
            winConditions: [WinLoseCondition(kind: .reachScore, scoreThreshold: 500)],
            scoreHUDEntityName: "scoreLabel",
            statusHUDEntityName: "statusLabel"
        )

        return GameRecipe(
            presetID: "racing_lane",
            sceneName: sceneName,
            sceneSize: size,
            backgroundColor: "#202020",
            gravity: VectorSpec(dx: 0, dy: 0),
            entities: [player, obstacleTemplate, spawner, scoreLabel, statusLabel],
            gameState: gameState,
            controls: controls,
            notes: "Lane racing preset. Obstacles spawn from the top. Player moves left/right to avoid. Score wins at 500."
        )
    }
}
