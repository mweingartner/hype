import Foundation

public struct GameTemplateDescriptor: Identifiable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var aliases: [String]
    public var description: String
    public var supportedControls: [String]
    public var coreMechanics: [String]
    public var defaultSceneSize: SizeSpec
    public var defaultSpriteAreaName: String
    public var requiredAssets: [String]
    public var generatedNodeNames: [String]
    public var testContract: [String]

    public init(
        id: String,
        displayName: String,
        aliases: [String],
        description: String,
        supportedControls: [String],
        coreMechanics: [String],
        defaultSceneSize: SizeSpec,
        defaultSpriteAreaName: String,
        requiredAssets: [String],
        generatedNodeNames: [String],
        testContract: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.description = description
        self.supportedControls = supportedControls
        self.coreMechanics = coreMechanics
        self.defaultSceneSize = defaultSceneSize
        self.defaultSpriteAreaName = defaultSpriteAreaName
        self.requiredAssets = requiredAssets
        self.generatedNodeNames = generatedNodeNames
        self.testContract = testContract
    }
}

public struct GameTemplateInferenceResult: Codable, Sendable, Equatable {
    public var query: String
    public var templateID: String?
    public var displayName: String?
    public var confidence: Double
    public var matchedTerms: [String]
    public var ambiguousTemplateIDs: [String]
    public var recommendedSpriteAreaName: String?
    public var defaultSceneWidth: Double?
    public var defaultSceneHeight: Double?
    public var recommendedCreateArguments: [String: String]
    public var guidance: String

    enum CodingKeys: String, CodingKey {
        case query
        case templateID = "template_id"
        case displayName = "display_name"
        case confidence
        case matchedTerms = "matched_terms"
        case ambiguousTemplateIDs = "ambiguous_template_ids"
        case recommendedSpriteAreaName = "recommended_sprite_area_name"
        case defaultSceneWidth = "default_scene_width"
        case defaultSceneHeight = "default_scene_height"
        case recommendedCreateArguments = "recommended_create_arguments"
        case guidance
    }
}

public enum SpriteGameTemplateCatalog {
    public static let descriptors: [GameTemplateDescriptor] = [
        descriptor(
            "maze_chase",
            "Pac-Man-style game",
            aliases: ["pacman", "pac-man", "maze chase", "maze-chase", "arcade maze", "ghost chase"],
            description: "Tile-map maze, player movement, ghosts, pellets, power pellets, score, and collision handlers.",
            size: SpriteGameTemplateCatalog.mazeSize,
            areaName: "pacmanArea",
            assets: ["maze tiles", "player", "ghosts", "pellets", "power pellets"],
            nodes: ["maze", "pacmanPlayer", "ghost_blinky", "ghost_pinky", "scoreLabel"],
            mechanics: ["grid maze", "collectibles", "enemy contact", "score reset"]
        ),
        descriptor(
            "barrel_climber",
            "barrel-climber platformer game",
            aliases: ["platformer", "platform game", "barrel climber", "barrel-climber", "barrel jumper", "barrel jump", "donkey kong", "donkey kong style", "donkey-kong-style"],
            description: "Single-screen ladder platformer with A/D/W/S movement, jump, top-origin barrels, lives, hammers, ladder safety, and win/loss state.",
            size: SpriteGameTemplateCatalog.platformerSize,
            areaName: "barrelClimberArea",
            assets: ["platform", "hero", "barrel", "rival", "trophy", "ladder", "hammer"],
            nodes: ["hero", "rival", "goal_prize", "barrel_1", "ladder_1", "hammer_1", "scoreLabel"],
            mechanics: ["platform physics", "ladders", "hazards", "lives", "hammer power-up"]
        ),
        descriptor(
            "side_scroller_platformer",
            "side-scrolling platformer game",
            aliases: ["side scroller", "side-scroller", "side scrolling platformer", "mario style", "run and jump"],
            description: "Horizontal platformer scaffold with floor platforms, player, enemies, pickups, goal, and camera-ready layout.",
            size: SpriteGameTemplateCatalog.platformerSize,
            areaName: "sideScrollerArea",
            assets: commonAssets,
            nodes: commonNodes,
            mechanics: ["run", "jump", "platforms", "enemy hazards", "level goal"]
        ),
        descriptor(
            "top_down_adventure",
            "top-down adventure game",
            aliases: ["top down adventure", "top-down adventure", "zelda", "zelda-like", "room adventure", "dungeon"],
            description: "Top-down room with tile map, player, pickups, hazard, goal, and four-direction movement.",
            areaName: "adventureArea",
            assets: commonAssets + ["tiles"],
            nodes: commonNodes + ["tilemap"],
            mechanics: ["tile map", "room navigation", "pickup", "hazard", "goal"]
        ),
        descriptor(
            "twin_stick_shooter",
            "twin-stick shooter game",
            aliases: ["twin stick shooter", "twin-stick shooter", "arena shooter", "top down shooter", "top-down shooter"],
            description: "Arena shooter scaffold with player, enemies, projectile placeholder, score, and reset rules.",
            areaName: "shooterArea",
            mechanics: ["arena bounds", "projectile", "enemy hazards", "score"]
        ),
        descriptor(
            "space_shooter",
            "space shooter game",
            aliases: ["space shooter", "shmup", "shoot em up", "shoot 'em up", "galaga", "asteroids"],
            description: "Vertical shooter scaffold with ship, enemies, projectile placeholder, pickups, and score.",
            areaName: "spaceShooterArea",
            mechanics: ["ship movement", "projectile", "enemy waves", "score"]
        ),
        descriptor(
            "physics_puzzle",
            "physics puzzle game",
            aliases: ["physics puzzle", "angry birds", "slingshot puzzle", "physics toy puzzle"],
            description: "Gravity puzzle scaffold with player object, blocks, target, pickups, and contact scoring.",
            gravity: VectorSpec(dx: 0, dy: -9.8),
            areaName: "physicsPuzzleArea",
            mechanics: ["gravity", "blocks", "target contact", "reset"]
        ),
        descriptor(
            "breakout",
            "brick-breaker game",
            aliases: ["breakout", "brick breaker", "brick-breaker", "arkanoid"],
            description: "Paddle, ball, brick targets, walls, score, and keyboard paddle control.",
            areaName: "breakoutArea",
            mechanics: ["paddle", "ball", "bricks", "bouncing physics", "score"]
        ),
        descriptor(
            "pinball_pachinko",
            "pinball / pachinko game",
            aliases: ["pinball", "pachinko", "pegboard", "plinko"],
            description: "Gravity board with bumpers, pegs, ball, scoring target, and reset path.",
            gravity: VectorSpec(dx: 0, dy: -9.8),
            areaName: "pinballArea",
            mechanics: ["gravity", "bumpers", "ball", "target", "score"]
        ),
        descriptor(
            "endless_runner",
            "endless runner game",
            aliases: ["endless runner", "runner", "auto runner", "infinite runner"],
            description: "Runner scaffold with player, obstacles, pickups, jump, score, and reset.",
            areaName: "runnerArea",
            mechanics: ["jump", "hazards", "pickups", "score"]
        ),
        descriptor(
            "tower_defense",
            "tower defense game",
            aliases: ["tower defense", "tower-defence", "path defense", "defense game", "base defense", "city defense", "missile command", "missile-command", "missile command style"],
            description: "Path/city-defense map, base/goal, enemies, tower/turret nodes, projectile placeholder, and score.",
            areaName: "towerDefenseArea",
            assets: commonAssets + ["tiles"],
            nodes: commonNodes + ["tower_1", "pathTileMap"],
            mechanics: ["path", "tower/turret", "enemy waves", "projectile", "base defense"]
        ),
        descriptor(
            "match3_grid_puzzle",
            "match-3 grid puzzle game",
            aliases: ["match 3", "match-3", "match three", "bejeweled", "candy match"],
            description: "Grid puzzle scaffold with pieces, selection cursor, score, and reset handler.",
            areaName: "match3Area",
            assets: commonAssets + ["tiles"],
            nodes: commonNodes + ["piece_1", "piece_2", "piece_3"],
            mechanics: ["grid", "pieces", "selection", "matches", "score"]
        ),
        descriptor(
            "sokoban_block_puzzle",
            "Sokoban block-push puzzle game",
            aliases: ["sokoban", "block push", "block-push", "crate puzzle", "warehouse puzzle"],
            description: "Grid puzzle with player, pushable blocks, target cells, walls, and reset.",
            areaName: "sokobanArea",
            assets: commonAssets + ["tiles"],
            nodes: commonNodes + ["crate_1", "target_1"],
            mechanics: ["grid", "push blocks", "targets", "walls", "reset"]
        ),
        descriptor(
            "racing_lane",
            "lane racing game",
            aliases: ["racing", "race game", "lane runner", "driving game", "top down racing", "top-down racing"],
            description: "Lane-based driving scaffold with vehicle, lane markers, hazards, pickups, and finish goal.",
            areaName: "racingArea",
            mechanics: ["lanes", "vehicle movement", "obstacles", "finish goal"]
        ),
        descriptor(
            "pong_sports_arena",
            "Pong / sports arena game",
            aliases: ["pong", "air hockey", "sports arena", "soccer arena", "paddle game"],
            description: "Arena scaffold with paddle/player, ball, goals, walls, score, and keyboard control.",
            areaName: "sportsArenaArea",
            mechanics: ["paddle", "ball", "goals", "score", "arena bounds"]
        ),
        descriptor(
            "rhythm_timing",
            "rhythm timing game",
            aliases: ["rhythm", "timing game", "music timing", "beat game"],
            description: "Beat-lane scaffold with falling notes, hit zone, score, and keyboard timing hook.",
            areaName: "rhythmArea",
            mechanics: ["lanes", "notes", "hit zone", "timing score"]
        ),
        descriptor(
            "board_card_game",
            "board / card game",
            aliases: ["board game", "card game", "dice game", "token game", "tabletop"],
            description: "Board scaffold with tokens, deck/discard placeholders, dice label, turn state, and reset.",
            areaName: "boardGameArea",
            mechanics: ["board", "tokens", "cards", "turn state", "reset"]
        ),
        descriptor(
            "boss_wave_arena",
            "boss wave arena game",
            aliases: ["boss battle", "boss fight", "wave arena", "arena waves", "survival arena"],
            description: "Arena scaffold with player, boss, minion hazards, projectile placeholder, score, and win/loss state.",
            areaName: "bossArenaArea",
            mechanics: ["boss", "waves", "projectile", "hazards", "score"]
        ),
        descriptor(
            "sandbox_physics_toy",
            "sandbox physics toy",
            aliases: ["sandbox", "physics sandbox", "physics toy", "particle toy"],
            description: "Interactive physics sandbox scaffold with movable objects, bumpers, fields-ready nodes, and reset.",
            gravity: VectorSpec(dx: 0, dy: -9.8),
            areaName: "physicsSandboxArea",
            mechanics: ["gravity", "dynamic bodies", "bumpers", "reset"]
        ),
        descriptor(
            "educational_sim",
            "educational simulation",
            aliases: ["educational sim", "simulation", "interactive simulation", "learning game", "science sim"],
            description: "Interactive simulation scaffold with labeled actors, controls note, measurable target, and reset.",
            areaName: "simulationArea",
            mechanics: ["labeled actors", "experimentation", "goal", "reset"]
        ),
    ]

    public static var supportedIDs: [String] {
        descriptors.map(\.id)
    }

    public static var supportedIDList: String {
        supportedIDs.joined(separator: ", ")
    }

    public static func descriptor(for id: String) -> GameTemplateDescriptor? {
        let key = normalize(id)
        return descriptors.first { normalize($0.id) == key }
    }

    public static func descriptor(matching raw: String) -> GameTemplateDescriptor? {
        let key = normalize(raw)
        guard !key.isEmpty else { return descriptor(for: "maze_chase") }
        return descriptors.first { descriptor in
            normalize(descriptor.id) == key || descriptor.aliases.contains { normalize($0) == key }
        }
    }

    public static func inferDescriptor(forPrompt prompt: String) -> GameTemplateDescriptor? {
        let lower = prompt.lowercased()
        let compactPrompt = normalize(prompt)
        return descriptors.first { descriptor in
            ([descriptor.id, descriptor.displayName] + descriptor.aliases).contains { token in
                let compactToken = normalize(token)
                return lower.contains(token.lowercased()) || (!compactToken.isEmpty && compactPrompt.contains(compactToken))
            }
        }
    }

    public static func inferTemplate(forPrompt prompt: String) -> GameTemplateInferenceResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let compactPrompt = normalize(trimmed)

        let matches: [(descriptor: GameTemplateDescriptor, matchedTerms: [String], score: Int)] = descriptors.compactMap { descriptor in
            var matchedTerms: [String] = []
            var score = 0
            let strongTerms = [descriptor.id, descriptor.displayName] + descriptor.aliases
            for term in strongTerms {
                let compactTerm = normalize(term)
                guard !compactTerm.isEmpty else { continue }
                if lower.contains(term.lowercased()) || compactPrompt.contains(compactTerm) {
                    matchedTerms.append(term)
                    score += max(8, compactTerm.count)
                }
            }
            for mechanic in descriptor.coreMechanics {
                let compactTerm = normalize(mechanic)
                guard !compactTerm.isEmpty else { continue }
                if lower.contains(mechanic.lowercased()) || compactPrompt.contains(compactTerm) {
                    matchedTerms.append(mechanic)
                    score += 3
                }
            }
            guard score > 0 else { return nil }
            return (descriptor, Array(Set(matchedTerms)).sorted(), score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.descriptor.id < rhs.descriptor.id }
            return lhs.score > rhs.score
        }

        guard let best = matches.first else {
            return GameTemplateInferenceResult(
                query: trimmed,
                templateID: nil,
                displayName: nil,
                confidence: 0,
                matchedTerms: [],
                ambiguousTemplateIDs: [],
                recommendedSpriteAreaName: nil,
                defaultSceneWidth: nil,
                defaultSceneHeight: nil,
                recommendedCreateArguments: [:],
                guidance: "No deterministic template matched this prompt. Call list_sprite_game_templates with a query, ask one concise clarification, or use ordinary SpriteKit scene tools only if the user is not asking for a complete game scaffold."
            )
        }

        let ambiguous = matches
            .dropFirst()
            .filter { Double($0.score) >= Double(best.score) * 0.72 }
            .map(\.descriptor.id)
        let confidence: Double = {
            if !ambiguous.isEmpty { return 0.62 }
            if best.score >= 24 { return 0.94 }
            if best.score >= 12 { return 0.84 }
            return 0.72
        }()
        let size = best.descriptor.defaultSceneSize
        return GameTemplateInferenceResult(
            query: trimmed,
            templateID: best.descriptor.id,
            displayName: best.descriptor.displayName,
            confidence: confidence,
            matchedTerms: best.matchedTerms,
            ambiguousTemplateIDs: ambiguous,
            recommendedSpriteAreaName: best.descriptor.defaultSpriteAreaName,
            defaultSceneWidth: size.width,
            defaultSceneHeight: size.height,
            recommendedCreateArguments: [
                "game_type": best.descriptor.id,
                "sprite_area_name": best.descriptor.defaultSpriteAreaName,
                "scene_width": String(Int(size.width.rounded())),
                "scene_height": String(Int(size.height.rounded())),
            ],
            guidance: ambiguous.isEmpty
                ? "Use create_sprite_game_template with the recommended arguments first. If the user asked for extra mechanics or art direction, call get_sprite_game_template_guide for this template before additional edits."
                : "The request matched multiple templates. Ask one clarification or call get_sprite_game_template_guide for the top candidate before creating the scaffold."
        )
    }

    public static func catalogSummary(query: String = "", compact: Bool = true) -> String {
        let filtered = filteredDescriptors(query: query)
        guard !filtered.isEmpty else {
            return "No deterministic SpriteKit game templates matched '\(query)'. Try a broader genre query such as maze, platformer, shooter, puzzle, racing, defense, or simulation."
        }
        if compact {
            return filtered.map { descriptor in
                "\(descriptor.id): \(descriptor.displayName) | controls: \(descriptor.supportedControls.joined(separator: ", ")) | mechanics: \(descriptor.coreMechanics.joined(separator: ", "))"
            }.joined(separator: "\n")
        }
        return filtered.map { descriptor in
            let controls = descriptor.supportedControls.joined(separator: ", ")
            let mechanics = descriptor.coreMechanics.joined(separator: ", ")
            return "\(descriptor.id): \(descriptor.displayName) | controls: \(controls) | mechanics: \(mechanics) | aliases: \(descriptor.aliases.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    public static func templateGuide(gameType raw: String, detailLevel: String = "creation", intent: String = "") -> String {
        guard let descriptor = descriptor(for: raw) ?? descriptor(matching: raw) else {
            return "Unknown sprite game template '\(raw)'. Call infer_sprite_game_template or list_sprite_game_templates before requesting a guide."
        }

        let level = normalize(detailLevel.isEmpty ? "creation" : detailLevel)
        let size = descriptor.defaultSceneSize
        let base = """
        Template guide: \(descriptor.id) (\(descriptor.displayName))
        Description: \(descriptor.description)
        Default create call: create_sprite_game_template(game_type="\(descriptor.id)", sprite_area_name="\(descriptor.defaultSpriteAreaName)", scene_width="\(Int(size.width.rounded()))", scene_height="\(Int(size.height.rounded()))")
        Controls: \(descriptor.supportedControls.joined(separator: ", "))
        Core mechanics: \(descriptor.coreMechanics.joined(separator: ", "))
        Generated nodes: \(descriptor.generatedNodeNames.joined(separator: ", "))
        Required placeholder assets: \(descriptor.requiredAssets.joined(separator: ", "))
        """

        let creation = """

        Creation workflow:
        1. Call create_sprite_game_template first. It creates deterministic placeholder assets, the Sprite Area, SceneSpec nodes, physics, reset path, and parser-tested scene-level HypeTalk.
        2. Do not manually recreate the baseline terrain, player, hazards, score labels, or reset script with low-level tools.
        3. After the scaffold exists, use list_scene_nodes and targeted set_node_property / set_scene_script / set_physics_body calls only for requested customization.
        """

        let customization = """

        Customization workflow:
        - For visual changes, prefer set_node_property for colors/textures/visibility and generate_sprite_asset only as an optional second pass.
        - For mechanics, inspect the generated node names and update the existing scene script rather than replacing it blindly.
        - Keep user-provided assets stack-local through the Asset Repository.
        - Validate any new or replacement HypeTalk with check_script before storage.
        """

        let scriptContract = """

        Script contract:
        - Generated scripts are scene-level HypeTalk stored on the active SceneSpec, not live SKNode state.
        - Baseline handlers include sceneDidLoad for reset/new-game state, keyDown/keyUp or mouse handlers where useful, beginContact for collisions, and frameUpdate for timed mechanics where needed.
        - Preserve the reset path and named node contract unless the user explicitly asks to redesign the template.
        - Use pass only when intentionally bubbling scene/card/background/stack messages.
        """

        let testing = """

        Test contract:
        \(descriptor.testContract.map { "- \($0)" }.joined(separator: "\n"))
        """

        let intentNote = intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nUser intent to account for after baseline creation: \(intent.trimmingCharacters(in: .whitespacesAndNewlines))"

        switch level {
        case "summary":
            return base + intentNote
        case "customization":
            return base + customization + scriptContract + intentNote
        case "scriptcontract", "script_contract", "script":
            return base + scriptContract + testing + intentNote
        case "full":
            return base + creation + customization + scriptContract + "\n\n" + testing + intentNote
        default:
            return base + creation + intentNote
        }
    }

    private static func filteredDescriptors(query: String) -> [GameTemplateDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return descriptors }
        let lower = trimmed.lowercased()
        let compact = normalize(trimmed)
        return descriptors.filter { descriptor in
            let terms = [descriptor.id, descriptor.displayName, descriptor.description]
                + descriptor.aliases
                + descriptor.coreMechanics
                + descriptor.supportedControls
            return terms.contains { term in
                let compactTerm = normalize(term)
                return term.lowercased().contains(lower)
                    || lower.contains(term.lowercased())
                    || (!compact.isEmpty && !compactTerm.isEmpty && (compactTerm.contains(compact) || compact.contains(compactTerm)))
            }
        }
    }

    private static let mazeSize = SizeSpec(width: 768, height: 544)
    private static let platformerSize = SizeSpec(width: 800, height: 600)
    private static let commonSize = SizeSpec(width: 800, height: 600)
    private static let commonAssets = ["player", "enemy", "pickup", "goal", "projectile", "block"]
    private static let commonNodes = ["player", "enemy_1", "pickup_1", "goal", "projectile_1", "scoreLabel", "statusLabel"]

    private static func descriptor(
        _ id: String,
        _ displayName: String,
        aliases: [String],
        description: String,
        gravity: VectorSpec = VectorSpec(dx: 0, dy: 0),
        size: SizeSpec = commonSize,
        areaName: String,
        assets: [String] = commonAssets,
        nodes: [String] = commonNodes,
        mechanics: [String]
    ) -> GameTemplateDescriptor {
        GameTemplateDescriptor(
            id: id,
            displayName: displayName,
            aliases: aliases,
            description: description,
            supportedControls: ["A/D or Left/Right move", "W/S or Up/Down move", "Space action", "sceneDidLoad resets"],
            coreMechanics: mechanics,
            defaultSceneSize: size,
            defaultSpriteAreaName: areaName,
            requiredAssets: assets,
            generatedNodeNames: nodes,
            testContract: [
                "creates a valid SceneSpec",
                "creates deterministic embedded placeholder assets",
                "generated HypeTalk parses successfully",
                "sceneDidLoad provides a reset path",
                "keyDown/keyUp provide keyboard control",
                "beginContact updates score/status for pickups, hazards, and goals"
            ]
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
