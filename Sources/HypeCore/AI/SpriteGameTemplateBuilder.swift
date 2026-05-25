import Foundation

#if canImport(AppKit)
import AppKit
#endif

public struct SpriteGameTemplateResult: Sendable, Equatable {
    public var gameType: String
    public var spriteAreaName: String
    public var assetNames: [String]
    public var nodeNames: [String]
    public var wallColliderCount: Int
    public var pelletCount: Int
    public var powerPelletCount: Int

    public init(
        gameType: String,
        spriteAreaName: String,
        assetNames: [String],
        nodeNames: [String],
        wallColliderCount: Int,
        pelletCount: Int,
        powerPelletCount: Int
    ) {
        self.gameType = gameType
        self.spriteAreaName = spriteAreaName
        self.assetNames = assetNames
        self.nodeNames = nodeNames
        self.wallColliderCount = wallColliderCount
        self.pelletCount = pelletCount
        self.powerPelletCount = powerPelletCount
    }

    public var gameTypeDisplayName: String {
        (SpriteGameTemplateCatalog.descriptor(for: gameType) ?? SpriteGameTemplateCatalog.descriptor(matching: gameType))?.displayName ?? gameType
    }
}

public enum SpriteGameTemplateError: Error, LocalizedError, Sendable {
    case imageEncodingFailed(String)
    case invalidSpriteAreaIndex
    case unsupportedGameType(String)

    public var errorDescription: String? {
        switch self {
        case .imageEncodingFailed(let name):
            return "Could not encode generated PNG asset '\(name)'"
        case .invalidSpriteAreaIndex:
            return "Sprite area not found"
        case .unsupportedGameType(let gameType):
            return "Unsupported sprite game template '\(gameType)'. Supported values: \(SpriteGameTemplateCatalog.supportedIDList). Legacy aliases such as pacman, platformer, barrel_climber, and donkey_kong_style are also accepted."
        }
    }
}

public enum SpriteGameTemplateBuilder {
    public static let defaultPacmanSceneSize = SizeSpec(width: 768, height: 544)
    public static let defaultPlatformerSceneSize = SizeSpec(width: 800, height: 600)
    public static let defaultPacmanTileSize = 32

    private static let wallCategory: UInt32 = 1 << 0
    private static let playerCategory: UInt32 = 1 << 1
    private static let ghostCategory: UInt32 = 1 << 2
    private static let pelletCategory: UInt32 = 1 << 3
    private static let powerPelletCategory: UInt32 = 1 << 4
    private static let goalCategory: UInt32 = 1 << 5
    private static let ladderCategory: UInt32 = 1 << 6
    private static let hammerCategory: UInt32 = 1 << 7

    public static func normalizedGameType(_ raw: String) throws -> String {
        if let descriptor = SpriteGameTemplateCatalog.descriptor(matching: raw) {
            return descriptor.id
        }
        throw SpriteGameTemplateError.unsupportedGameType(raw)
    }

    public static func inferredGameType(forPrompt prompt: String) -> String? {
        SpriteGameTemplateCatalog.inferDescriptor(forPrompt: prompt)?.id
    }

    public static func defaultSceneSize(for normalizedGameType: String) -> SizeSpec {
        (SpriteGameTemplateCatalog.descriptor(for: normalizedGameType) ?? SpriteGameTemplateCatalog.descriptor(matching: normalizedGameType))?.defaultSceneSize ?? defaultPacmanSceneSize
    }

    public static func defaultSpriteAreaName(for normalizedGameType: String) -> String {
        (SpriteGameTemplateCatalog.descriptor(for: normalizedGameType) ?? SpriteGameTemplateCatalog.descriptor(matching: normalizedGameType))?.defaultSpriteAreaName ?? "pacmanArea"
    }

    public static var templateCatalog: [GameTemplateDescriptor] {
        SpriteGameTemplateCatalog.descriptors
    }

    public static var supportedGameTypes: [String] {
        SpriteGameTemplateCatalog.supportedIDs
    }

    public static func templateCatalogSummary(query: String = "", compact: Bool = true) -> String {
        SpriteGameTemplateCatalog.catalogSummary(query: query, compact: compact)
    }

    public static func inferTemplate(forPrompt prompt: String) -> GameTemplateInferenceResult {
        SpriteGameTemplateCatalog.inferTemplate(forPrompt: prompt)
    }

    public static func templateGuide(gameType: String, detailLevel: String = "creation", intent: String = "") -> String {
        SpriteGameTemplateCatalog.templateGuide(gameType: gameType, detailLevel: detailLevel, intent: intent)
    }

    public static func applyTemplate(
        to document: inout HypeDocument,
        partIndex: Int,
        spriteAreaName: String,
        gameType: String
    ) throws -> SpriteGameTemplateResult {
        guard let descriptor = SpriteGameTemplateCatalog.descriptor(for: gameType)
            ?? SpriteGameTemplateCatalog.descriptor(matching: gameType) else {
            throw SpriteGameTemplateError.unsupportedGameType(gameType)
        }
        switch descriptor.id {
        case "barrel_climber":
            return try applyPlatformerTemplate(to: &document, partIndex: partIndex, spriteAreaName: spriteAreaName)
        case "maze_chase":
            return try applyPacmanTemplate(to: &document, partIndex: partIndex, spriteAreaName: spriteAreaName)
        default:
            return try applyCatalogTemplate(
                descriptor,
                to: &document,
                partIndex: partIndex,
                spriteAreaName: spriteAreaName
            )
        }
    }

    public static func createBasicMazeTilesetAsset(
        name: String = "hype_arcade_maze_tiles",
        style: String = "neon",
        tileSize: Int = defaultPacmanTileSize
    ) throws -> Asset {
        let safeTileSize = max(8, min(tileSize, 128))
        let columns = 4
        let width = safeTileSize * columns
        let height = safeTileSize
        let data = try makePNGAsset(name: name, width: width, height: height) { rect in
            drawMazeTileSheet(in: rect, tileSize: safeTileSize, style: style)
        }
        return Asset(
            name: name,
            kind: .tileSet,
            mimeType: "image/png",
            data: data,
            width: width,
            height: height,
            tags: ["hype-template", "deterministic", "maze", style],
            tileWidth: safeTileSize,
            tileHeight: safeTileSize,
            tileColumns: columns,
            tileRows: 1,
            provenance: AssetProvenance(
                origin: .aiGenerated,
                searchQuery: "Deterministic Hype arcade maze tileset",
                license: AssetLicense(
                    name: "Hype generated",
                    identifier: "hype-generated",
                    isShareable: true
                ),
                attribution: AssetAttribution(
                    creator: "Hype",
                    title: name,
                    providerName: "Hype deterministic generator",
                    providerIdentifier: "hype-local"
                )
            )
        )
    }

    @discardableResult
    public static func upsertAsset(_ asset: Asset, in repository: inout AssetRepository) -> Asset {
        let needle = asset.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let index = repository.assets.firstIndex(where: { $0.name.lowercased() == needle }) {
            var replacement = asset
            replacement.id = repository.assets[index].id
            repository.assets[index] = replacement
            return replacement
        }
        repository.assets.append(asset)
        return asset
    }

    public static func applyPacmanTemplate(
        to document: inout HypeDocument,
        partIndex: Int,
        spriteAreaName: String
    ) throws -> SpriteGameTemplateResult {
        guard document.parts.indices.contains(partIndex),
              document.parts[partIndex].partType == .spriteArea else {
            throw SpriteGameTemplateError.invalidSpriteAreaIndex
        }

        let tiles = upsertAsset(
            try createBasicMazeTilesetAsset(name: "hype_pacman_maze_tiles", style: "neon"),
            in: &document.assetRepository
        )
        let pacman = upsertAsset(try makePacmanAsset(), in: &document.assetRepository)
        let blinky = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_blinky", colorHex: "#FF3030"), in: &document.assetRepository)
        let pinky = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_pinky", colorHex: "#FF77C8"), in: &document.assetRepository)
        let inky = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_inky", colorHex: "#35E3FF"), in: &document.assetRepository)
        let clyde = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_clyde", colorHex: "#FF9D28"), in: &document.assetRepository)
        let pellet = upsertAsset(try makePelletAsset(name: "hype_pacman_pellet", colorHex: "#FFDFA3", diameter: 8), in: &document.assetRepository)
        let powerPellet = upsertAsset(try makePelletAsset(name: "hype_pacman_power_pellet", colorHex: "#FFFFFF", diameter: 18), in: &document.assetRepository)

        let maze = makePacmanMaze(columns: 24, rows: 17)
        let tileSize = Double(defaultPacmanTileSize)
        let tileData = mazeTileData(from: maze)
        var nodes: [HypeNodeSpec] = []

        var tileMapSpec = TileMapSpec(
            columns: maze.columns,
            rows: maze.rows,
            tileWidth: tileSize,
            tileHeight: tileSize,
            tileSetAssetRef: document.assetRepository.assetRef(for: tiles),
            tileSetColumns: tiles.tileColumns,
            tileData: tileData
        )
        tileMapSpec.tileData = tileData

        nodes.append(HypeNodeSpec(
            name: "maze",
            nodeType: .tileMap,
            position: PointSpec(x: 0, y: 0),
            zPosition: 0,
            tileMapSpec: tileMapSpec
        ))

        var wallCount = 0
        for row in 0..<maze.rows {
            for col in 0..<maze.columns where maze.walls[row][col] {
                wallCount += 1
                nodes.append(wallColliderNode(name: "wall_\(wallCount)", col: col, row: row, tileSize: tileSize))
            }
        }

        let powerCells = Set([
            MazeCell(col: 1, row: 3),
            MazeCell(col: maze.columns - 2, row: 3),
            MazeCell(col: 1, row: maze.rows - 4),
            MazeCell(col: maze.columns - 2, row: maze.rows - 4),
        ])
        let reservedCells = powerCells.union([
            MazeCell(col: 1, row: maze.rows - 2),
            MazeCell(col: 2, row: maze.rows - 2),
            MazeCell(col: 10, row: 8),
            MazeCell(col: 11, row: 8),
            MazeCell(col: 12, row: 8),
            MazeCell(col: 13, row: 8),
        ])

        var pelletCount = 0
        for row in 1..<(maze.rows - 1) {
            for col in 1..<(maze.columns - 1) {
                let cell = MazeCell(col: col, row: row)
                guard !maze.walls[row][col], !reservedCells.contains(cell) else { continue }
                pelletCount += 1
                nodes.append(spriteNode(
                    name: String(format: "pellet_%03d", pelletCount),
                    asset: pellet,
                    repository: document.assetRepository,
                    col: col,
                    row: row,
                    tileSize: tileSize,
                    size: SizeSpec(width: 8, height: 8),
                    z: 20,
                    physics: PhysicsBodySpec(
                        bodyType: .circle,
                        isDynamic: false,
                        categoryBitmask: pelletCategory,
                        contactTestBitmask: playerCategory,
                        collisionBitmask: 0,
                        restitution: 0,
                        friction: 0,
                        affectedByGravity: false,
                        allowsRotation: false
                    )
                ))
            }
        }

        var powerPelletCount = 0
        for cell in powerCells.sorted() {
            guard !maze.walls[cell.row][cell.col] else { continue }
            powerPelletCount += 1
            nodes.append(spriteNode(
                name: "power_pellet_\(powerPelletCount)",
                asset: powerPellet,
                repository: document.assetRepository,
                col: cell.col,
                row: cell.row,
                tileSize: tileSize,
                size: SizeSpec(width: 18, height: 18),
                z: 21,
                physics: PhysicsBodySpec(
                    bodyType: .circle,
                    isDynamic: false,
                    categoryBitmask: powerPelletCategory,
                    contactTestBitmask: playerCategory,
                    collisionBitmask: 0,
                    restitution: 0,
                    friction: 0,
                    affectedByGravity: false,
                    allowsRotation: false
                )
            ))
        }

        nodes.append(scoreLabelNode())
        nodes.append(spriteNode(
            name: "pacmanPlayer",
            asset: pacman,
            repository: document.assetRepository,
            col: 1,
            row: maze.rows - 2,
            tileSize: tileSize,
            size: SizeSpec(width: 28, height: 28),
            z: 40,
            physics: playerPhysics()
        ))

        let ghostSpecs: [(String, Asset, Int, Int, Double, Double)] = [
            ("ghost_blinky", blinky, 11, 8, 120, 0),
            ("ghost_pinky", pinky, 12, 8, -120, 0),
            ("ghost_inky", inky, 10, 8, 0, 120),
            ("ghost_clyde", clyde, 13, 8, 0, -120),
        ]
        for (name, asset, col, row, vx, vy) in ghostSpecs {
            nodes.append(spriteNode(
                name: name,
                asset: asset,
                repository: document.assetRepository,
                col: col,
                row: row,
                tileSize: tileSize,
                size: SizeSpec(width: 28, height: 28),
                z: 35,
                physics: ghostPhysics(velocityX: vx, velocityY: vy)
            ))
        }

        let scene = SceneSpec(
            name: "main",
            size: SizeSpec(width: Double(maze.columns) * tileSize, height: Double(maze.rows) * tileSize),
            backgroundColor: "#050510",
            gravity: VectorSpec(dx: 0, dy: 0),
            nodes: nodes,
            script: pacmanSceneScript(),
            showsPhysics: false,
            showsFPS: false,
            showsNodeCount: false,
            scaleMode: .aspectFit
        )

        var part = document.parts[partIndex]
        part.setSpriteAreaSpec(SpriteAreaSpec(scene: scene, fallbackSize: scene.size))
        if part.width <= 0 { part.width = scene.size.width }
        if part.height <= 0 { part.height = scene.size.height }
        document.parts[partIndex] = part

        return SpriteGameTemplateResult(
            gameType: "maze_chase",
            spriteAreaName: spriteAreaName,
            assetNames: [tiles, pacman, blinky, pinky, inky, clyde, pellet, powerPellet].map(\.name),
            nodeNames: nodes.map(\.name),
            wallColliderCount: wallCount,
            pelletCount: pelletCount,
            powerPelletCount: powerPelletCount
        )
    }

    public static func applyPlatformerTemplate(
        to document: inout HypeDocument,
        partIndex: Int,
        spriteAreaName: String
    ) throws -> SpriteGameTemplateResult {
        guard document.parts.indices.contains(partIndex),
              document.parts[partIndex].partType == .spriteArea else {
            throw SpriteGameTemplateError.invalidSpriteAreaIndex
        }

        let platform = upsertAsset(try makePlatformerPlatformAsset(), in: &document.assetRepository)
        let hero = upsertAsset(try makePlatformerHeroAsset(), in: &document.assetRepository)
        let barrel = upsertAsset(try makePlatformerBarrelAsset(), in: &document.assetRepository)
        let rival = upsertAsset(try makePlatformerRivalAsset(), in: &document.assetRepository)
        let prize = upsertAsset(try makePlatformerPrizeAsset(), in: &document.assetRepository)
        let ladder = upsertAsset(try makePlatformerLadderAsset(), in: &document.assetRepository)
        let hammer = upsertAsset(try makePlatformerHammerAsset(), in: &document.assetRepository)

        let sceneSize = defaultPlatformerSceneSize
        var nodes: [HypeNodeSpec] = []

        nodes.append(platformerLabel(
            name: "titleLabel",
            text: "Barrel Climber",
            x: 400,
            y: 34,
            fontSize: 26,
            color: "#FFE66D"
        ))
        nodes.append(platformerLabel(
            name: "scoreLabel",
            text: "Score: 0",
            x: 92,
            y: 34,
            fontSize: 18,
            color: "#FFFFFF"
        ))
        nodes.append(platformerLabel(
            name: "livesLabel",
            text: "Lives: 3",
            x: 92,
            y: 60,
            fontSize: 16,
            color: "#FFDC5E"
        ))
        nodes.append(platformerLabel(
            name: "hammerLabel",
            text: "",
            x: 400,
            y: 60,
            fontSize: 16,
            color: "#FF9F1C"
        ))
        nodes.append(platformerLabel(
            name: "statusLabel",
            text: "A/D move, W/S climb, Space jumps. Ladders are safe. Grab hammers to smash barrels.",
            x: 400,
            y: 574,
            fontSize: 14,
            color: "#D4E7FF"
        ))

        let platformSpecs: [(String, Double, Double, Double, Double)] = [
            ("platform_ground", 400, 552, 760, 24),
            ("platform_gorilla", 160, 148, 260, 20),
            ("platform_1", 510, 458, 520, 20),
            ("platform_2", 290, 364, 520, 20),
            ("platform_3", 510, 270, 520, 20),
            ("platform_4", 290, 176, 520, 20),
            ("platform_goal", 620, 102, 300, 20),
        ]
        for (name, x, y, width, height) in platformSpecs {
            nodes.append(spriteNode(
                name: name,
                asset: platform,
                repository: document.assetRepository,
                position: PointSpec(x: x, y: y),
                size: SizeSpec(width: width, height: height),
                z: 10,
                physics: platformPhysics()
            ))
        }

        let boundarySpecs: [(String, Double, Double, Double, Double)] = [
            ("left_boundary", -12, 300, 24, 600),
            ("right_boundary", 812, 300, 24, 600),
            ("bottom_boundary", 400, 612, 800, 24),
        ]
        for (name, x, y, width, height) in boundarySpecs {
            nodes.append(platformColliderNode(
                name: name,
                x: x,
                y: y,
                width: width,
                height: height,
                alpha: 0.001
            ))
        }

        let ladderSpecs: [(String, Double, Double, Double)] = [
            ("ladder_1", 640, 505, 92),
            ("ladder_2", 205, 411, 92),
            ("ladder_3", 600, 317, 92),
            ("ladder_4", 250, 223, 92),
            ("ladder_5", 650, 129, 92),
        ]
        for (name, x, y, height) in ladderSpecs {
            nodes.append(spriteNode(
                name: name,
                asset: ladder,
                repository: document.assetRepository,
                position: PointSpec(x: x, y: y),
                size: SizeSpec(width: 42, height: height),
                z: 16,
                physics: ladderPhysics()
            ))
        }

        let hammerSpecs: [(String, Double, Double)] = [
            ("hammer_1", 412, 336),
            ("hammer_2", 468, 242),
        ]
        for (name, x, y) in hammerSpecs {
            nodes.append(spriteNode(
                name: name,
                asset: hammer,
                repository: document.assetRepository,
                position: PointSpec(x: x, y: y),
                size: SizeSpec(width: 34, height: 34),
                z: 37,
                physics: hammerPickupPhysics()
            ))
        }

        var hammerSwing = spriteNode(
            name: "hammerSwing",
            asset: hammer,
            repository: document.assetRepository,
            position: PointSpec(x: -120, y: -120),
            size: SizeSpec(width: 42, height: 42),
            z: 45,
            physics: hammerSwingPhysics()
        )
        hammerSwing.isHidden = true
        nodes.append(hammerSwing)

        nodes.append(spriteNode(
            name: "hero",
            asset: hero,
            repository: document.assetRepository,
            position: PointSpec(x: 82, y: 516),
            size: SizeSpec(width: 38, height: 46),
            z: 35,
            physics: platformerPlayerPhysics()
        ))
        nodes.append(spriteNode(
            name: "rival",
            asset: rival,
            repository: document.assetRepository,
            position: PointSpec(x: 112, y: 102),
            size: SizeSpec(width: 70, height: 62),
            z: 34,
            physics: nil
        ))
        nodes.append(spriteNode(
            name: "goal_prize",
            asset: prize,
            repository: document.assetRepository,
            position: PointSpec(x: 702, y: 62),
            size: SizeSpec(width: 44, height: 44),
            z: 36,
            physics: goalPhysics()
        ))

        let barrelSpecs: [(String, Double, Double, Double)] = [
            ("barrel_1", 148, 130, 165),
            ("barrel_2", 172, 130, 150),
            ("barrel_3", 196, 130, 175),
            ("barrel_4", 220, 130, 155),
            ("barrel_5", 244, 130, 145),
        ]
        for (name, x, y, velocityX) in barrelSpecs {
            nodes.append(spriteNode(
                name: name,
                asset: barrel,
                repository: document.assetRepository,
                position: PointSpec(x: x, y: y),
                size: SizeSpec(width: 34, height: 34),
                z: 32,
                physics: barrelPhysics(velocityX: velocityX)
            ))
        }

        let scene = SceneSpec(
            name: "main",
            size: sceneSize,
            backgroundColor: "#120A18",
            gravity: VectorSpec(dx: 0, dy: -9.8),
            nodes: nodes,
            script: platformerSceneScript(),
            showsPhysics: false,
            showsFPS: false,
            showsNodeCount: false,
            scaleMode: .aspectFit
        )

        var part = document.parts[partIndex]
        part.setSpriteAreaSpec(SpriteAreaSpec(scene: scene, fallbackSize: scene.size))
        if part.width <= 0 { part.width = scene.size.width }
        if part.height <= 0 { part.height = scene.size.height }
        document.parts[partIndex] = part
        upsertPlatformerNewGameButton(in: &document, spriteAreaPartIndex: partIndex, spriteAreaName: spriteAreaName)

        return SpriteGameTemplateResult(
            gameType: "barrel_climber",
            spriteAreaName: spriteAreaName,
            assetNames: [platform, hero, barrel, rival, prize, ladder, hammer].map(\.name),
            nodeNames: nodes.map(\.name),
            wallColliderCount: platformSpecs.count + boundarySpecs.count,
            pelletCount: barrelSpecs.count,
            powerPelletCount: ladderSpecs.count + hammerSpecs.count
        )
    }

    private static func upsertPlatformerNewGameButton(
        in document: inout HypeDocument,
        spriteAreaPartIndex: Int,
        spriteAreaName: String
    ) {
        guard document.parts.indices.contains(spriteAreaPartIndex) else { return }
        let area = document.parts[spriteAreaPartIndex]
        let buttonName = "New Game"
        let left = max(12, min(area.left + area.width - 124, Double(document.stack.width) - 124))
        let top = max(12, area.top + 12)
        let script = """
        on mouseUp
          send "sceneDidLoad" to spriteArea "\(spriteAreaName)"
        end mouseUp
        """

        let matchesLayer: (Part) -> Bool = { part in
            if let cardId = area.cardId {
                return part.cardId == cardId
            }
            if let backgroundId = area.backgroundId {
                return part.backgroundId == backgroundId
            }
            return false
        }

        if let existingIndex = document.parts.firstIndex(where: { part in
            part.partType == .button &&
            matchesLayer(part) &&
            ["new game", "newgame", "newgamebutton"].contains(part.name.lowercased().replacingOccurrences(of: " ", with: ""))
        }) {
            document.parts[existingIndex].name = buttonName
            document.parts[existingIndex].textContent = buttonName
            document.parts[existingIndex].left = left
            document.parts[existingIndex].top = top
            document.parts[existingIndex].width = 112
            document.parts[existingIndex].height = 38
            document.parts[existingIndex].buttonStyle = .default
            document.parts[existingIndex].script = script
            return
        }

        var button = Part(
            partType: .button,
            cardId: area.cardId,
            backgroundId: area.backgroundId,
            name: buttonName,
            left: left,
            top: top,
            width: 112,
            height: 38
        )
        button.textContent = buttonName
        button.buttonStyle = .default
        button.script = script
        document.addPart(button)
    }

    private static func applyCatalogTemplate(
        _ descriptor: GameTemplateDescriptor,
        to document: inout HypeDocument,
        partIndex: Int,
        spriteAreaName: String
    ) throws -> SpriteGameTemplateResult {
        guard document.parts.indices.contains(partIndex),
              document.parts[partIndex].partType == .spriteArea else {
            throw SpriteGameTemplateError.invalidSpriteAreaIndex
        }

        let player = upsertAsset(try makeTemplateAsset(templateID: descriptor.id, role: "player", colorHex: "#2EC4FF"), in: &document.assetRepository)
        let enemy = upsertAsset(try makeTemplateAsset(templateID: descriptor.id, role: "enemy", colorHex: "#FF4D6D"), in: &document.assetRepository)
        let pickup = upsertAsset(try makeTemplateAsset(templateID: descriptor.id, role: "pickup", colorHex: "#FFD166"), in: &document.assetRepository)
        let goal = upsertAsset(try makeTemplateAsset(templateID: descriptor.id, role: "goal", colorHex: "#8AF64E"), in: &document.assetRepository)
        let projectile = upsertAsset(try makeTemplateAsset(templateID: descriptor.id, role: "projectile", colorHex: "#FFFFFF"), in: &document.assetRepository)
        let block = upsertAsset(try makeTemplateAsset(templateID: descriptor.id, role: "block", colorHex: "#5FFBFF"), in: &document.assetRepository)
        var assets = [player, enemy, pickup, goal, projectile, block]

        let size = descriptor.defaultSceneSize
        var nodes: [HypeNodeSpec] = []
        nodes.append(platformerLabel(name: "titleLabel", text: descriptor.displayName, x: size.width / 2, y: 34, fontSize: 24, color: "#FFFFFF"))
        nodes.append(platformerLabel(name: "scoreLabel", text: "Score: 0", x: 90, y: 64, fontSize: 18, color: "#FFE66D"))
        nodes.append(platformerLabel(name: "statusLabel", text: descriptor.description, x: size.width / 2, y: size.height - 28, fontSize: 13, color: "#D4E7FF"))
        nodes.append(contentsOf: templateBounds(size: size))

        if templateUsesTileMap(descriptor.id) {
            let tiles = upsertAsset(try createBasicMazeTilesetAsset(name: "hype_\(descriptor.id)_tiles", style: "template", tileSize: 32), in: &document.assetRepository)
            assets.append(tiles)
            nodes.append(templateTileMapNode(asset: tiles, repository: document.assetRepository, size: size))
        }

        nodes.append(contentsOf: templateDecorNodes(for: descriptor.id, size: size))
        nodes.append(spriteNode(
            name: "player",
            asset: player,
            repository: document.assetRepository,
            position: templatePlayerStart(for: descriptor.id, size: size),
            size: SizeSpec(width: 38, height: 38),
            z: 40,
            physics: templatePlayerPhysics(gravity: templateGravity(for: descriptor.id).dy != 0)
        ))
        nodes.append(spriteNode(
            name: "enemy_1",
            asset: enemy,
            repository: document.assetRepository,
            position: PointSpec(x: size.width * 0.68, y: size.height * 0.52),
            size: SizeSpec(width: 36, height: 36),
            z: 35,
            physics: templateEnemyPhysics(velocityX: templateEnemyVelocity(for: descriptor.id), velocityY: 0)
        ))
        nodes.append(spriteNode(
            name: "enemy_2",
            asset: enemy,
            repository: document.assetRepository,
            position: PointSpec(x: size.width * 0.42, y: size.height * 0.34),
            size: SizeSpec(width: 32, height: 32),
            z: 34,
            physics: templateEnemyPhysics(velocityX: -templateEnemyVelocity(for: descriptor.id), velocityY: 0)
        ))
        nodes.append(spriteNode(
            name: "pickup_1",
            asset: pickup,
            repository: document.assetRepository,
            position: PointSpec(x: size.width * 0.28, y: size.height * 0.42),
            size: SizeSpec(width: 28, height: 28),
            z: 33,
            physics: templateTriggerPhysics(category: pelletCategory)
        ))
        nodes.append(spriteNode(
            name: "pickup_2",
            asset: pickup,
            repository: document.assetRepository,
            position: PointSpec(x: size.width * 0.58, y: size.height * 0.68),
            size: SizeSpec(width: 28, height: 28),
            z: 33,
            physics: templateTriggerPhysics(category: pelletCategory)
        ))
        nodes.append(spriteNode(
            name: "goal",
            asset: goal,
            repository: document.assetRepository,
            position: PointSpec(x: size.width - 72, y: 92),
            size: SizeSpec(width: 42, height: 42),
            z: 33,
            physics: templateTriggerPhysics(category: goalCategory)
        ))
        var projectileNode = spriteNode(
            name: "projectile_1",
            asset: projectile,
            repository: document.assetRepository,
            position: PointSpec(x: -120, y: -120),
            size: SizeSpec(width: 18, height: 18),
            z: 50,
            physics: templateProjectilePhysics()
        )
        projectileNode.isHidden = true
        nodes.append(projectileNode)

        if descriptor.id == "tower_defense" {
            nodes.append(spriteNode(
                name: "tower_1",
                asset: block,
                repository: document.assetRepository,
                position: PointSpec(x: size.width * 0.5, y: size.height * 0.44),
                size: SizeSpec(width: 44, height: 44),
                z: 32,
                physics: nil
            ))
        }

        let scene = SceneSpec(
            name: "main",
            size: size,
            backgroundColor: templateBackgroundColor(for: descriptor.id),
            gravity: templateGravity(for: descriptor.id),
            nodes: nodes,
            fields: templateFields(for: descriptor.id, size: size),
            script: genericTemplateSceneScript(descriptor: descriptor),
            showsPhysics: false,
            showsFPS: false,
            showsNodeCount: false,
            scaleMode: .aspectFit
        )

        var part = document.parts[partIndex]
        part.setSpriteAreaSpec(SpriteAreaSpec(scene: scene, fallbackSize: scene.size))
        if part.width <= 0 { part.width = scene.size.width }
        if part.height <= 0 { part.height = scene.size.height }
        document.parts[partIndex] = part
        upsertTemplateNewGameButton(in: &document, spriteAreaPartIndex: partIndex, spriteAreaName: spriteAreaName)

        return SpriteGameTemplateResult(
            gameType: descriptor.id,
            spriteAreaName: spriteAreaName,
            assetNames: assets.map(\.name),
            nodeNames: nodes.map(\.name),
            wallColliderCount: nodes.filter { $0.name.hasPrefix("wall_") || $0.name.hasPrefix("platform_") }.count,
            pelletCount: nodes.filter { $0.name.hasPrefix("pickup_") || $0.name.hasPrefix("enemy_") }.count,
            powerPelletCount: nodes.filter { ["goal", "projectile_1", "tower_1"].contains($0.name) }.count
        )
    }

    private static func upsertTemplateNewGameButton(
        in document: inout HypeDocument,
        spriteAreaPartIndex: Int,
        spriteAreaName: String
    ) {
        guard document.parts.indices.contains(spriteAreaPartIndex) else { return }
        let area = document.parts[spriteAreaPartIndex]
        let buttonName = "New Game"
        let left = max(12, min(area.left + area.width - 124, Double(document.stack.width) - 124))
        let top = max(12, area.top + 12)
        let script = """
        on mouseUp
          send "sceneDidLoad" to spriteArea "\(spriteAreaName)"
        end mouseUp
        """
        let matchesLayer: (Part) -> Bool = { part in
            if let cardId = area.cardId { return part.cardId == cardId }
            if let backgroundId = area.backgroundId { return part.backgroundId == backgroundId }
            return false
        }
        if let existingIndex = document.parts.firstIndex(where: { part in
            part.partType == .button &&
            matchesLayer(part) &&
            ["new game", "newgame", "newgamebutton"].contains(part.name.lowercased().replacingOccurrences(of: " ", with: ""))
        }) {
            document.parts[existingIndex].name = buttonName
            document.parts[existingIndex].textContent = buttonName
            document.parts[existingIndex].left = left
            document.parts[existingIndex].top = top
            document.parts[existingIndex].width = 112
            document.parts[existingIndex].height = 38
            document.parts[existingIndex].buttonStyle = .default
            document.parts[existingIndex].script = script
            return
        }
        var button = Part(
            partType: .button,
            cardId: area.cardId,
            backgroundId: area.backgroundId,
            name: buttonName,
            left: left,
            top: top,
            width: 112,
            height: 38
        )
        button.textContent = buttonName
        button.buttonStyle = .default
        button.script = script
        document.addPart(button)
    }

    private static func templateUsesTileMap(_ id: String) -> Bool {
        [
            "top_down_adventure",
            "tower_defense",
            "match3_grid_puzzle",
            "sokoban_block_puzzle",
            "board_card_game",
            "racing_lane",
        ].contains(id)
    }

    private static func templateTileMapNode(asset: Asset, repository: AssetRepository, size: SizeSpec) -> HypeNodeSpec {
        let columns = 16
        let rows = 12
        var tileData = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        for row in 0..<rows {
            for col in 0..<columns where row == 0 || col == 0 || row == rows - 1 || col == columns - 1 {
                tileData[row][col] = 2
            }
        }
        return HypeNodeSpec(
            name: "templateTileMap",
            nodeType: .tileMap,
            position: PointSpec(x: 0, y: 0),
            zPosition: 0,
            tileMapSpec: TileMapSpec(
                columns: columns,
                rows: rows,
                tileWidth: size.width / Double(columns),
                tileHeight: size.height / Double(rows),
                tileSetAssetRef: repository.assetRef(for: asset),
                tileSetColumns: asset.tileColumns,
                tileData: tileData
            )
        )
    }

    private static func templateBounds(size: SizeSpec) -> [HypeNodeSpec] {
        [
            templateWall(name: "wall_left", x: -8, y: size.height / 2, width: 16, height: size.height),
            templateWall(name: "wall_right", x: size.width + 8, y: size.height / 2, width: 16, height: size.height),
            templateWall(name: "wall_top", x: size.width / 2, y: -8, width: size.width, height: 16),
            templateWall(name: "wall_bottom", x: size.width / 2, y: size.height + 8, width: size.width, height: 16),
        ]
    }

    private static func templateDecorNodes(for id: String, size: SizeSpec) -> [HypeNodeSpec] {
        switch id {
        case "side_scroller_platformer", "endless_runner":
            return [
                templatePlatform(name: "platform_ground", x: size.width / 2, y: size.height - 50, width: size.width - 80, height: 24),
                templatePlatform(name: "platform_1", x: size.width * 0.42, y: size.height * 0.64, width: 230, height: 20),
                templatePlatform(name: "platform_2", x: size.width * 0.72, y: size.height * 0.46, width: 220, height: 20),
            ]
        case "breakout":
            return (0..<8).map { index in
                templateShape(
                    name: "brick_\(index + 1)",
                    x: 110 + Double(index) * 82,
                    y: 132,
                    width: 64,
                    height: 24,
                    fill: index.isMultiple(of: 2) ? "#FF6B6B" : "#FFD166",
                    physics: templateTriggerPhysics(category: pelletCategory)
                )
            }
        case "rhythm_timing":
            return (0..<4).map { index in
                templateShape(
                    name: "lane_\(index + 1)",
                    x: 220 + Double(index) * 120,
                    y: size.height / 2,
                    width: 70,
                    height: size.height - 160,
                    fill: "#14213D",
                    stroke: "#5FFBFF",
                    physics: nil
                )
            }
        default:
            return [
                templateShape(name: "guide_1", x: size.width * 0.5, y: size.height * 0.5, width: 180, height: 18, fill: "#223047", physics: nil)
            ]
        }
    }

    private static func templateWall(name: String, x: Double, y: Double, width: Double, height: Double) -> HypeNodeSpec {
        templateShape(
            name: name,
            x: x,
            y: y,
            width: width,
            height: height,
            fill: "#111827",
            stroke: "#111827",
            alpha: 0.01,
            physics: PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: false,
                categoryBitmask: wallCategory,
                contactTestBitmask: 0,
                collisionBitmask: playerCategory | ghostCategory,
                restitution: 0.5,
                friction: 0.2,
                affectedByGravity: false,
                allowsRotation: false
            )
        )
    }

    private static func templatePlatform(name: String, x: Double, y: Double, width: Double, height: Double) -> HypeNodeSpec {
        templateShape(name: name, x: x, y: y, width: width, height: height, fill: "#00D5FF", stroke: "#5FFBFF", physics: platformPhysics())
    }

    private static func templateShape(
        name: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        fill: String,
        stroke: String = "#FFFFFF",
        alpha: Double = 1,
        physics: PhysicsBodySpec?
    ) -> HypeNodeSpec {
        HypeNodeSpec(
            name: name,
            nodeType: .shape,
            position: PointSpec(x: x, y: y),
            zPosition: 12,
            alpha: alpha,
            size: SizeSpec(width: width, height: height),
            shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: fill, strokeColor: stroke, lineWidth: 2, cornerRadius: 6),
            physicsBody: physics
        )
    }

    private static func templatePlayerStart(for id: String, size: SizeSpec) -> PointSpec {
        switch id {
        case "space_shooter": return PointSpec(x: size.width / 2, y: size.height - 84)
        case "side_scroller_platformer", "endless_runner": return PointSpec(x: 92, y: size.height - 96)
        default: return PointSpec(x: 80, y: size.height / 2)
        }
    }

    private static func templateEnemyVelocity(for id: String) -> Double {
        switch id {
        case "rhythm_timing", "space_shooter": return 0
        case "pinball_pachinko", "physics_puzzle", "sandbox_physics_toy": return 90
        default: return 130
        }
    }

    private static func templateGravity(for id: String) -> VectorSpec {
        switch id {
        case "physics_puzzle", "pinball_pachinko", "sandbox_physics_toy", "side_scroller_platformer", "endless_runner":
            return VectorSpec(dx: 0, dy: -9.8)
        default:
            return VectorSpec(dx: 0, dy: 0)
        }
    }

    private static func templateBackgroundColor(for id: String) -> String {
        switch id {
        case "space_shooter": return "#020617"
        case "top_down_adventure": return "#102A18"
        case "breakout": return "#090B1A"
        case "physics_puzzle", "sandbox_physics_toy": return "#1F2937"
        case "rhythm_timing": return "#130B2A"
        default: return "#111827"
        }
    }

    private static func templateFields(for id: String, size: SizeSpec) -> [FieldSpec] {
        guard id == "sandbox_physics_toy" else { return [] }
        return [
            FieldSpec(
                fieldType: .drag,
                strength: 0.25,
                region: SizeSpec(width: size.width, height: size.height),
                direction: nil
            )
        ]
    }

    private static func templatePlayerPhysics(gravity: Bool) -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: true,
            categoryBitmask: playerCategory,
            contactTestBitmask: ghostCategory | pelletCategory | goalCategory,
            collisionBitmask: wallCategory,
            restitution: 0.05,
            friction: 0.25,
            mass: 1,
            affectedByGravity: gravity,
            allowsRotation: false,
            linearDamping: 0.2
        )
    }

    private static func templateEnemyPhysics(velocityX: Double, velocityY: Double) -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: ghostCategory,
            contactTestBitmask: playerCategory,
            collisionBitmask: wallCategory | playerCategory,
            restitution: 1,
            friction: 0,
            mass: 1,
            affectedByGravity: false,
            allowsRotation: true,
            linearDamping: 0,
            angularDamping: 0,
            velocityX: velocityX,
            velocityY: velocityY
        )
    }

    private static func templateTriggerPhysics(category: UInt32) -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: false,
            categoryBitmask: category,
            contactTestBitmask: playerCategory,
            collisionBitmask: 0,
            restitution: 0,
            friction: 0,
            affectedByGravity: false,
            allowsRotation: false
        )
    }

    private static func templateProjectilePhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: playerCategory,
            contactTestBitmask: ghostCategory,
            collisionBitmask: 0,
            restitution: 0,
            friction: 0,
            affectedByGravity: false,
            allowsRotation: false,
            linearDamping: 0,
            velocityX: 0,
            velocityY: 0
        )
    }

    private static func genericTemplateSceneScript(descriptor: GameTemplateDescriptor) -> String {
        """
        on sceneDidLoad
          global score
          global shotActive
          put 0 into score
          put "false" into shotActive
          set the text of label "scoreLabel" to "Score: 0"
          set the text of label "statusLabel" to "\(descriptor.displayName): \(descriptor.coreMechanics.joined(separator: ", ")). Move with WASD or arrows. Space activates the action."
          set the loc of sprite "player" to "\(Int(templatePlayerStart(for: descriptor.id, size: descriptor.defaultSceneSize).x)),\(Int(templatePlayerStart(for: descriptor.id, size: descriptor.defaultSceneSize).y))"
          set the velocity of sprite "player" to "0,0"
          set the loc of sprite "enemy_1" to "\(Int(descriptor.defaultSceneSize.width * 0.68)),\(Int(descriptor.defaultSceneSize.height * 0.52))"
          set the velocity of sprite "enemy_1" to "\(Int(templateEnemyVelocity(for: descriptor.id))),0"
          set the loc of sprite "enemy_2" to "\(Int(descriptor.defaultSceneSize.width * 0.42)),\(Int(descriptor.defaultSceneSize.height * 0.34))"
          set the velocity of sprite "enemy_2" to "-\(Int(templateEnemyVelocity(for: descriptor.id))),0"
          set the loc of sprite "projectile_1" to "-120,-120"
          set the velocity of sprite "projectile_1" to "0,0"
          set the hidden of sprite "projectile_1" to true
        end sceneDidLoad

        on keyDown
          global shotActive
          if the key is "a" then set the velocityX of sprite "player" to -220
          if the key is "left" then set the velocityX of sprite "player" to -220
          if the key is "d" then set the velocityX of sprite "player" to 220
          if the key is "right" then set the velocityX of sprite "player" to 220
          if the key is "w" then set the velocityY of sprite "player" to 220
          if the key is "up" then set the velocityY of sprite "player" to 220
          if the key is "s" then set the velocityY of sprite "player" to -220
          if the key is "down" then set the velocityY of sprite "player" to -220
          if the key is "space" then
            put the loc of sprite "player" into playerLoc
            set the loc of sprite "projectile_1" to playerLoc
            set the hidden of sprite "projectile_1" to false
            set the velocity of sprite "projectile_1" to "320,0"
            put "true" into shotActive
            set the text of label "statusLabel" to "Action fired."
          end if
        end keyDown

        on keyUp
          if the key is "a" then set the velocityX of sprite "player" to 0
          if the key is "left" then set the velocityX of sprite "player" to 0
          if the key is "d" then set the velocityX of sprite "player" to 0
          if the key is "right" then set the velocityX of sprite "player" to 0
          if the key is "w" then set the velocityY of sprite "player" to 0
          if the key is "up" then set the velocityY of sprite "player" to 0
          if the key is "s" then set the velocityY of sprite "player" to 0
          if the key is "down" then set the velocityY of sprite "player" to 0
        end keyUp

        on beginContact otherName
          global score
          if otherName contains "pickup_" then
            remove sprite otherName
            add 10 to score
            set the text of label "scoreLabel" to "Score: " & score
            set the text of label "statusLabel" to "Pickup collected."
          end if
          if otherName contains "enemy_" then
            set the loc of sprite "player" to "\(Int(templatePlayerStart(for: descriptor.id, size: descriptor.defaultSceneSize).x)),\(Int(templatePlayerStart(for: descriptor.id, size: descriptor.defaultSceneSize).y))"
            set the velocity of sprite "player" to "0,0"
            set the text of label "statusLabel" to "Hazard hit. Player reset."
          end if
          if otherName contains "goal" then
            add 100 to score
            set the text of label "scoreLabel" to "Score: " & score
            set the text of label "statusLabel" to "Goal reached. Press New Game to reset."
          end if
        end beginContact

        on frameUpdate
          global shotActive
          if shotActive is "true" then
            put the loc of sprite "projectile_1" into shotLoc
            put item 1 of shotLoc into shotX
            if shotX > \(Int(descriptor.defaultSceneSize.width + 80)) then
              put "false" into shotActive
              set the hidden of sprite "projectile_1" to true
              set the velocity of sprite "projectile_1" to "0,0"
            end if
          end if
        end frameUpdate
        """
    }

    private static func makeTemplateAsset(templateID: String, role: String, colorHex: String) throws -> Asset {
        let name = "hype_\(templateID)_\(role)"
        let data = try makePNGAsset(name: name, width: 64, height: 64) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            let color = nsColor(hex: colorHex)
            color.setFill()
            switch role {
            case "player":
                NSBezierPath(ovalIn: rect.insetBy(dx: 10, dy: 10)).fill()
                nsColor(hex: "#FFFFFF").setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.midX + 8, y: rect.midY + 6, width: 8, height: 8)).fill()
            case "enemy":
                NSBezierPath(roundedRect: rect.insetBy(dx: 9, dy: 12), xRadius: 12, yRadius: 12).fill()
                nsColor(hex: "#111827").setStroke()
                let slash = NSBezierPath()
                slash.lineWidth = 5
                slash.move(to: CGPoint(x: rect.minX + 18, y: rect.minY + 18))
                slash.line(to: CGPoint(x: rect.maxX - 18, y: rect.maxY - 18))
                slash.stroke()
            case "pickup":
                let star = NSBezierPath()
                star.move(to: CGPoint(x: rect.midX, y: rect.maxY - 8))
                star.line(to: CGPoint(x: rect.midX + 8, y: rect.midY + 8))
                star.line(to: CGPoint(x: rect.maxX - 8, y: rect.midY + 6))
                star.line(to: CGPoint(x: rect.midX + 10, y: rect.midY - 4))
                star.line(to: CGPoint(x: rect.maxX - 14, y: rect.minY + 8))
                star.line(to: CGPoint(x: rect.midX, y: rect.midY - 12))
                star.line(to: CGPoint(x: rect.minX + 14, y: rect.minY + 8))
                star.line(to: CGPoint(x: rect.midX - 10, y: rect.midY - 4))
                star.line(to: CGPoint(x: rect.minX + 8, y: rect.midY + 6))
                star.line(to: CGPoint(x: rect.midX - 8, y: rect.midY + 8))
                star.close()
                star.fill()
            case "goal":
                NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 8), xRadius: 8, yRadius: 8).fill()
                nsColor(hex: "#111827").setStroke()
                let flag = NSBezierPath()
                flag.lineWidth = 4
                flag.move(to: CGPoint(x: rect.midX - 8, y: rect.minY + 12))
                flag.line(to: CGPoint(x: rect.midX - 8, y: rect.maxY - 10))
                flag.line(to: CGPoint(x: rect.maxX - 12, y: rect.maxY - 20))
                flag.stroke()
            case "projectile":
                NSBezierPath(ovalIn: rect.insetBy(dx: 18, dy: 22)).fill()
            default:
                NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 5, yRadius: 5).fill()
            }
            #endif
        }
        return Asset(
            name: name,
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", templateID, role]
        )
    }

    private struct MazeCell: Hashable, Comparable {
        var col: Int
        var row: Int

        static func < (lhs: MazeCell, rhs: MazeCell) -> Bool {
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.col < rhs.col
        }
    }

    private struct PacmanMaze {
        var columns: Int
        var rows: Int
        var walls: [[Bool]]
    }

    private static func makePacmanMaze(columns: Int, rows: Int) -> PacmanMaze {
        var walls = Array(repeating: Array(repeating: false, count: columns), count: rows)

        func set(_ col: Int, _ row: Int) {
            guard row >= 0, row < rows, col >= 0, col < columns else { return }
            walls[row][col] = true
        }
        func h(_ row: Int, _ start: Int, _ end: Int) {
            for col in min(start, end)...max(start, end) { set(col, row) }
        }
        func v(_ col: Int, _ start: Int, _ end: Int) {
            for row in min(start, end)...max(start, end) { set(col, row) }
        }
        func clear(_ col: Int, _ row: Int) {
            guard row >= 0, row < rows, col >= 0, col < columns else { return }
            walls[row][col] = false
        }

        h(0, 0, columns - 1)
        h(rows - 1, 0, columns - 1)
        v(0, 0, rows - 1)
        v(columns - 1, 0, rows - 1)

        h(2, 2, 5); h(2, 7, 9); h(2, 14, 16); h(2, 18, 21)
        h(4, 2, 4); h(4, 7, 16); h(4, 19, 21)
        v(6, 2, 6); v(17, 2, 6)
        h(7, 2, 8); h(7, 15, 21)
        v(11, 5, 8); v(12, 5, 8)
        h(10, 2, 5); h(10, 8, 15); h(10, 18, 21)
        v(6, 10, 14); v(17, 10, 14)
        h(13, 2, 9); h(13, 14, 21)
        h(15, 4, 7); h(15, 10, 13); h(15, 16, 19)

        let requiredOpenCells = [
            MazeCell(col: 1, row: 1),
            MazeCell(col: columns - 2, row: 1),
            MazeCell(col: 1, row: 3),
            MazeCell(col: columns - 2, row: 3),
            MazeCell(col: 1, row: rows - 4),
            MazeCell(col: columns - 2, row: rows - 4),
            MazeCell(col: 1, row: rows - 2),
            MazeCell(col: 2, row: rows - 2),
            MazeCell(col: 10, row: 8),
            MazeCell(col: 11, row: 8),
            MazeCell(col: 12, row: 8),
            MazeCell(col: 13, row: 8),
        ]
        for cell in requiredOpenCells {
            clear(cell.col, cell.row)
        }

        return PacmanMaze(columns: columns, rows: rows, walls: walls)
    }

    private static func mazeTileData(from maze: PacmanMaze) -> [[Int]] {
        var data = Array(repeating: Array(repeating: -1, count: maze.columns), count: maze.rows)
        for row in 0..<maze.rows {
            for col in 0..<maze.columns where maze.walls[row][col] {
                let left = col > 0 && maze.walls[row][col - 1]
                let right = col + 1 < maze.columns && maze.walls[row][col + 1]
                let up = row > 0 && maze.walls[row - 1][col]
                let down = row + 1 < maze.rows && maze.walls[row + 1][col]
                if (up || down) && !(left || right) {
                    data[row][col] = 1
                } else if (left || right) && !(up || down) {
                    data[row][col] = 0
                } else {
                    data[row][col] = 2
                }
            }
        }
        return data
    }

    private static func cellCenter(col: Int, row: Int, tileSize: Double) -> PointSpec {
        PointSpec(
            x: Double(col) * tileSize + tileSize / 2,
            y: Double(row) * tileSize + tileSize / 2
        )
    }

    private static func wallColliderNode(name: String, col: Int, row: Int, tileSize: Double) -> HypeNodeSpec {
        HypeNodeSpec(
            name: name,
            nodeType: .shape,
            position: cellCenter(col: col, row: row, tileSize: tileSize),
            zPosition: 5,
            alpha: 0.001,
            size: SizeSpec(width: tileSize, height: tileSize),
            shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#000000", strokeColor: "#000000", lineWidth: 0),
            physicsBody: PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: false,
                categoryBitmask: wallCategory,
                contactTestBitmask: 0,
                collisionBitmask: playerCategory | ghostCategory,
                restitution: 0,
                friction: 0,
                affectedByGravity: false,
                allowsRotation: false
            )
        )
    }

    private static func spriteNode(
        name: String,
        asset: Asset,
        repository: AssetRepository,
        col: Int,
        row: Int,
        tileSize: Double,
        size: SizeSpec,
        z: Double,
        physics: PhysicsBodySpec?
    ) -> HypeNodeSpec {
        HypeNodeSpec(
            name: name,
            nodeType: .sprite,
            position: cellCenter(col: col, row: row, tileSize: tileSize),
            zPosition: z,
            assetRef: repository.assetRef(for: asset),
            size: size,
            physicsBody: physics
        )
    }

    private static func scoreLabelNode() -> HypeNodeSpec {
        HypeNodeSpec(
            name: "scoreLabel",
            nodeType: .label,
            position: PointSpec(x: 96, y: 18),
            zPosition: 60,
            text: "Score: 0",
            fontName: "Avenir Next Heavy",
            fontSize: 18,
            fontColor: "#FFFFFF"
        )
    }

    private static func platformerLabel(
        name: String,
        text: String,
        x: Double,
        y: Double,
        fontSize: Double,
        color: String
    ) -> HypeNodeSpec {
        HypeNodeSpec(
            name: name,
            nodeType: .label,
            position: PointSpec(x: x, y: y),
            zPosition: 60,
            text: text,
            fontName: "Avenir Next Heavy",
            fontSize: fontSize,
            fontColor: color
        )
    }

    private static func platformColliderNode(
        name: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        alpha: Double = 1.0
    ) -> HypeNodeSpec {
        HypeNodeSpec(
            name: name,
            nodeType: .shape,
            position: PointSpec(x: x, y: y),
            zPosition: 8,
            alpha: alpha,
            size: SizeSpec(width: width, height: height),
            shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#00D5FF", strokeColor: "#5FFBFF", lineWidth: 2),
            physicsBody: platformPhysics()
        )
    }

    private static func spriteNode(
        name: String,
        asset: Asset,
        repository: AssetRepository,
        position: PointSpec,
        size: SizeSpec,
        z: Double,
        physics: PhysicsBodySpec?
    ) -> HypeNodeSpec {
        HypeNodeSpec(
            name: name,
            nodeType: .sprite,
            position: position,
            zPosition: z,
            assetRef: repository.assetRef(for: asset),
            size: size,
            physicsBody: physics
        )
    }

    private static func playerPhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: playerCategory,
            contactTestBitmask: ghostCategory | pelletCategory | powerPelletCategory,
            collisionBitmask: wallCategory,
            restitution: 0,
            friction: 0,
            mass: 1,
            affectedByGravity: false,
            allowsRotation: false,
            linearDamping: 0
        )
    }

    private static func platformPhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: false,
            categoryBitmask: wallCategory,
            contactTestBitmask: 0,
            collisionBitmask: playerCategory | ghostCategory,
            restitution: 0.05,
            friction: 0.35,
            affectedByGravity: false,
            allowsRotation: false
        )
    }

    private static func platformerPlayerPhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: true,
            categoryBitmask: playerCategory,
            contactTestBitmask: ghostCategory | goalCategory | ladderCategory | hammerCategory,
            collisionBitmask: wallCategory | ghostCategory,
            restitution: 0.02,
            friction: 0.25,
            mass: 1,
            affectedByGravity: true,
            allowsRotation: false,
            linearDamping: 0.35,
            angularDamping: 0
        )
    }

    private static func ladderPhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: false,
            categoryBitmask: ladderCategory,
            contactTestBitmask: playerCategory,
            collisionBitmask: 0,
            restitution: 0,
            friction: 0,
            affectedByGravity: false,
            allowsRotation: false
        )
    }

    private static func hammerPickupPhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: false,
            categoryBitmask: hammerCategory,
            contactTestBitmask: playerCategory,
            collisionBitmask: 0,
            restitution: 0,
            friction: 0,
            affectedByGravity: false,
            allowsRotation: false
        )
    }

    private static func hammerSwingPhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: false,
            categoryBitmask: playerCategory,
            contactTestBitmask: ghostCategory,
            collisionBitmask: 0,
            restitution: 0,
            friction: 0,
            affectedByGravity: false,
            allowsRotation: false
        )
    }

    private static func barrelPhysics(velocityX: Double) -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: ghostCategory,
            contactTestBitmask: playerCategory,
            collisionBitmask: wallCategory | playerCategory,
            restitution: 0.45,
            friction: 0.08,
            mass: 1,
            affectedByGravity: true,
            allowsRotation: true,
            linearDamping: 0,
            angularDamping: 0.05,
            velocityX: velocityX,
            velocityY: 0
        )
    }

    private static func goalPhysics() -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .rect,
            isDynamic: false,
            categoryBitmask: goalCategory,
            contactTestBitmask: playerCategory,
            collisionBitmask: 0,
            restitution: 0,
            friction: 0,
            affectedByGravity: false,
            allowsRotation: false
        )
    }

    private static func ghostPhysics(velocityX: Double, velocityY: Double) -> PhysicsBodySpec {
        PhysicsBodySpec(
            bodyType: .circle,
            isDynamic: true,
            categoryBitmask: ghostCategory,
            contactTestBitmask: playerCategory,
            collisionBitmask: wallCategory,
            restitution: 1,
            friction: 0,
            mass: 1,
            affectedByGravity: false,
            allowsRotation: false,
            linearDamping: 0,
            angularDamping: 0,
            velocityX: velocityX,
            velocityY: velocityY
        )
    }

    private static func pacmanSceneScript() -> String {
        """
        on sceneDidLoad
          global score
          put 0 into score
          set the text of label "scoreLabel" to "Score: 0"
          set the velocity of sprite "ghost_blinky" to "120,0"
          set the velocity of sprite "ghost_pinky" to "-120,0"
          set the velocity of sprite "ghost_inky" to "0,120"
          set the velocity of sprite "ghost_clyde" to "0,-120"
        end sceneDidLoad

        on keyDown
          if the key is "up" then set the velocity of sprite "pacmanPlayer" to "0,180"
          if the key is "down" then set the velocity of sprite "pacmanPlayer" to "0,-180"
          if the key is "left" then set the velocity of sprite "pacmanPlayer" to "-180,0"
          if the key is "right" then set the velocity of sprite "pacmanPlayer" to "180,0"
          if the key is "w" then set the velocity of sprite "pacmanPlayer" to "0,180"
          if the key is "s" then set the velocity of sprite "pacmanPlayer" to "0,-180"
          if the key is "a" then set the velocity of sprite "pacmanPlayer" to "-180,0"
          if the key is "d" then set the velocity of sprite "pacmanPlayer" to "180,0"
        end keyDown

        on keyUp
          set the velocity of sprite "pacmanPlayer" to "0,0"
        end keyUp

        on beginContact otherName
          global score
          if otherName contains "pellet_" then
            remove sprite otherName
            add 10 to score
            set the text of label "scoreLabel" to "Score: " & score
          end if
          if otherName contains "power_pellet_" then
            remove sprite otherName
            add 50 to score
            set the text of label "scoreLabel" to "Score: " & score
          end if
        end beginContact
        """
    }

    private static func platformerSceneScript() -> String {
        """
        on sceneDidLoad
          global score
          global lives
          global onLadder
          global hammerActive
          global hammerTicks
          global facing
          global gameOver
          put 0 into score
          put 3 into lives
          put "false" into onLadder
          put "false" into hammerActive
          put 0 into hammerTicks
          put "right" into facing
          put "false" into gameOver
          set the text of label "scoreLabel" to "Score: 0"
          set the text of label "livesLabel" to "Lives: 3"
          set the text of label "hammerLabel" to ""
          set the text of label "statusLabel" to "A/D move, W/S climb, Space jumps. Ladders are safe. Grab hammers to smash barrels."
          set the loc of sprite "hero" to "82,516"
          set the velocity of sprite "hero" to "0,0"
          set the affectedByGravity of sprite "hero" to true
          set the collisionBitmask of sprite "hero" to 5
          set the hidden of sprite "hammerSwing" to true
          set the loc of sprite "hammerSwing" to "-120,-120"
          set the loc of sprite "hammer_1" to "412,336"
          set the contactTestBitmask of sprite "hammer_1" to 2
          set the hidden of sprite "hammer_1" to false
          set the loc of sprite "hammer_2" to "468,242"
          set the contactTestBitmask of sprite "hammer_2" to 2
          set the hidden of sprite "hammer_2" to false
          set the loc of sprite "barrel_1" to "148,130"
          set the velocity of sprite "barrel_1" to "165,0"
          set the loc of sprite "barrel_2" to "172,130"
          set the velocity of sprite "barrel_2" to "150,0"
          set the loc of sprite "barrel_3" to "196,130"
          set the velocity of sprite "barrel_3" to "175,0"
          set the loc of sprite "barrel_4" to "220,130"
          set the velocity of sprite "barrel_4" to "155,0"
          set the loc of sprite "barrel_5" to "244,130"
          set the velocity of sprite "barrel_5" to "145,0"
        end sceneDidLoad

        on keyDown
          global facing
          if the key is "a" then
            put "left" into facing
            set the velocityX of sprite "hero" to -190
          end if
          if the key is "left" then
            put "left" into facing
            set the velocityX of sprite "hero" to -190
          end if
          if the key is "d" then
            put "right" into facing
            set the velocityX of sprite "hero" to 190
          end if
          if the key is "right" then
            put "right" into facing
            set the velocityX of sprite "hero" to 190
          end if
          if the key is "w" then set the velocityY of sprite "hero" to 190
          if the key is "up" then set the velocityY of sprite "hero" to 190
          if the key is "s" then set the velocityY of sprite "hero" to -190
          if the key is "down" then set the velocityY of sprite "hero" to -190
          if the key is "space" then set the velocityY of sprite "hero" to 620
        end keyDown

        on keyUp
          if the key is "a" then set the velocityX of sprite "hero" to 0
          if the key is "left" then set the velocityX of sprite "hero" to 0
          if the key is "d" then set the velocityX of sprite "hero" to 0
          if the key is "right" then set the velocityX of sprite "hero" to 0
          if the key is "w" then set the velocityY of sprite "hero" to 0
          if the key is "up" then set the velocityY of sprite "hero" to 0
          if the key is "s" then set the velocityY of sprite "hero" to 0
          if the key is "down" then set the velocityY of sprite "hero" to 0
        end keyUp

        on frameUpdate
          global hammerActive
          global hammerTicks
          global facing
          if hammerActive is "true" then
            subtract 1 from hammerTicks
            put the loc of sprite "hero" into heroLoc
            put item 1 of heroLoc into heroX
            put item 2 of heroLoc into heroY
            if facing is "left" then
              subtract 36 from heroX
            else
              add 36 to heroX
            end if
            set the loc of sprite "hammerSwing" to heroX & "," & heroY
            set the hidden of sprite "hammerSwing" to false
            if hammerTicks < 1 then
              put "false" into hammerActive
              set the hidden of sprite "hammerSwing" to true
              set the text of label "hammerLabel" to ""
              set the text of label "statusLabel" to "Hammer expired. Keep climbing."
            else
              set the text of label "hammerLabel" to "HAMMER: " & hammerTicks
            end if
          end if
        end frameUpdate

        on beginContact otherName
          global score
          global lives
          global onLadder
          global hammerActive
          global hammerTicks
          global gameOver
          if otherName contains "ladder_" then
            put "true" into onLadder
            set the affectedByGravity of sprite "hero" to false
            set the collisionBitmask of sprite "hero" to 1
            set the velocity of sprite "hero" to "0,0"
            set the text of label "statusLabel" to "Safe on ladder. W/S climb, A/D move off."
          end if
          if otherName contains "hammer_" then
            put "true" into hammerActive
            put 240 into hammerTicks
            set the loc of sprite otherName to "-200,-200"
            set the contactTestBitmask of sprite otherName to 0
            set the hidden of sprite otherName to true
            set the text of label "hammerLabel" to "HAMMER: 240"
            set the text of label "statusLabel" to "Hammer time. Touch barrels to smash them."
          end if
          if otherName contains "barrel_" then
            if gameOver is "false" then
              if onLadder is "true" then
                set the text of label "statusLabel" to "Safe on ladder. Barrels cannot hurt you here."
              else
                if hammerActive is "true" then
                  add 25 to score
                  set the text of label "scoreLabel" to "Score: " & score
                  set the loc of sprite otherName to "148,130"
                  set the velocity of sprite otherName to "165,0"
                  set the text of label "statusLabel" to "Barrel smashed."
                else
                  subtract 1 from lives
                  set the text of label "livesLabel" to "Lives: " & lives
                  set the loc of sprite "hero" to "82,516"
                  set the velocity of sprite "hero" to "0,0"
                  set the loc of sprite otherName to "148,130"
                  set the velocity of sprite otherName to "165,0"
                  if lives < 1 then
                    put "true" into gameOver
                    set the velocity of sprite "barrel_1" to "0,0"
                    set the velocity of sprite "barrel_2" to "0,0"
                    set the velocity of sprite "barrel_3" to "0,0"
                    set the velocity of sprite "barrel_4" to "0,0"
                    set the velocity of sprite "barrel_5" to "0,0"
                    set the text of label "statusLabel" to "Game over. Press New Game to try again."
                  else
                    set the text of label "statusLabel" to "Ouch. Lost one life. Keep climbing."
                  end if
                end if
              end if
            end if
          end if
          if otherName contains "goal_prize" then
            if gameOver is "false" then
              add 100 to score
              put "true" into gameOver
              set the velocity of sprite "hero" to "0,0"
              set the velocity of sprite "barrel_1" to "0,0"
              set the velocity of sprite "barrel_2" to "0,0"
              set the velocity of sprite "barrel_3" to "0,0"
              set the velocity of sprite "barrel_4" to "0,0"
              set the velocity of sprite "barrel_5" to "0,0"
              set the text of label "scoreLabel" to "Score: " & score
              set the text of label "statusLabel" to "You win. Press New Game to play again."
            end if
          end if
        end beginContact

        on endContact otherName
          global onLadder
          if otherName contains "ladder_" then
            put "false" into onLadder
            set the affectedByGravity of sprite "hero" to true
            set the collisionBitmask of sprite "hero" to 5
          end if
        end endContact
        """
    }

    private static func makePacmanAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_pacman_player", width: 64, height: 64) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.05, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5)).fill()
            NSColor.black.setFill()
            let mouth = NSBezierPath()
            mouth.move(to: CGPoint(x: rect.midX, y: rect.midY))
            mouth.line(to: CGPoint(x: rect.maxX - 3, y: rect.midY + 17))
            mouth.line(to: CGPoint(x: rect.maxX - 3, y: rect.midY - 17))
            mouth.close()
            mouth.fill()
            #endif
        }
        return Asset(
            name: "hype_pacman_player",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", "pacman"]
        )
    }

    private static func makeGhostAsset(name: String, colorHex: String) throws -> Asset {
        let data = try makePNGAsset(name: name, width: 64, height: 64) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            let bodyColor = nsColor(hex: colorHex)
            bodyColor.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: rect.minX + 8, y: rect.minY + 8, width: rect.width - 16, height: rect.height - 12), xRadius: 22, yRadius: 22)
            body.fill()
            NSBezierPath(rect: NSRect(x: rect.minX + 8, y: rect.minY + 8, width: rect.width - 16, height: 24)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 18, y: rect.minY + 34, width: 12, height: 14)).fill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 36, y: rect.minY + 34, width: 12, height: 14)).fill()
            nsColor(hex: "#1A46FF").setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 22, y: rect.minY + 38, width: 5, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 40, y: rect.minY + 38, width: 5, height: 6)).fill()
            #endif
        }
        return Asset(
            name: name,
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", "pacman", "ghost"]
        )
    }

    private static func makePelletAsset(name: String, colorHex: String, diameter: Int) throws -> Asset {
        let size = max(8, diameter + 6)
        let data = try makePNGAsset(name: name, width: size, height: size) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            nsColor(hex: colorHex).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            #endif
        }
        return Asset(
            name: name,
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: size,
            height: size,
            tags: ["hype-template", "deterministic", "pacman", "pellet"]
        )
    }

    private static func makePlatformerPlatformAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_barrel_platform", width: 96, height: 24) { rect in
            #if canImport(AppKit)
            nsColor(hex: "#3B1D4F").setFill()
            NSBezierPath(rect: rect).fill()
            nsColor(hex: "#FF6B35").setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 5), xRadius: 6, yRadius: 6).fill()
            nsColor(hex: "#FFD166").setStroke()
            let line = NSBezierPath()
            line.move(to: CGPoint(x: rect.minX + 8, y: rect.midY))
            line.line(to: CGPoint(x: rect.maxX - 8, y: rect.midY))
            line.lineWidth = 3
            line.lineCapStyle = .round
            line.stroke()
            #endif
        }
        return Asset(
            name: "hype_barrel_platform",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 96,
            height: 24,
            tags: ["hype-template", "deterministic", "platformer", "platform"]
        )
    }

    private static func makePlatformerHeroAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_barrel_hero", width: 64, height: 80) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            nsColor(hex: "#2EC4FF").setFill()
            NSBezierPath(ovalIn: NSRect(x: 19, y: 49, width: 26, height: 24)).fill()
            nsColor(hex: "#FFE0BD").setFill()
            NSBezierPath(ovalIn: NSRect(x: 23, y: 54, width: 18, height: 16)).fill()
            nsColor(hex: "#FF3366").setFill()
            NSBezierPath(roundedRect: NSRect(x: 18, y: 24, width: 28, height: 30), xRadius: 7, yRadius: 7).fill()
            nsColor(hex: "#273469").setStroke()
            let legs = NSBezierPath()
            legs.lineWidth = 6
            legs.move(to: CGPoint(x: 25, y: 24))
            legs.line(to: CGPoint(x: 20, y: 8))
            legs.move(to: CGPoint(x: 39, y: 24))
            legs.line(to: CGPoint(x: 44, y: 8))
            legs.stroke()
            #endif
        }
        return Asset(
            name: "hype_barrel_hero",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 80,
            tags: ["hype-template", "deterministic", "platformer", "hero"]
        )
    }

    private static func makePlatformerBarrelAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_barrel_hazard", width: 64, height: 64) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            nsColor(hex: "#8B4513").setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 8, dy: 8)).fill()
            nsColor(hex: "#D9822B").setStroke()
            for offset in [18.0, 32.0, 46.0] {
                let band = NSBezierPath()
                band.lineWidth = 4
                band.move(to: CGPoint(x: rect.minX + 12, y: rect.minY + offset))
                band.line(to: CGPoint(x: rect.maxX - 12, y: rect.minY + offset))
                band.stroke()
            }
            nsColor(hex: "#3A1F0B").setStroke()
            let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 8, dy: 8))
            rim.lineWidth = 3
            rim.stroke()
            #endif
        }
        return Asset(
            name: "hype_barrel_hazard",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", "platformer", "barrel"]
        )
    }

    private static func makePlatformerRivalAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_barrel_rival", width: 96, height: 80) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            nsColor(hex: "#6B3E26").setFill()
            NSBezierPath(roundedRect: NSRect(x: 16, y: 12, width: 64, height: 54), xRadius: 18, yRadius: 18).fill()
            nsColor(hex: "#9B5A34").setFill()
            NSBezierPath(ovalIn: NSRect(x: 26, y: 34, width: 44, height: 34)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 36, y: 50, width: 9, height: 9)).fill()
            NSBezierPath(ovalIn: NSRect(x: 52, y: 50, width: 9, height: 9)).fill()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 39, y: 53, width: 4, height: 4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 55, y: 53, width: 4, height: 4)).fill()
            #endif
        }
        return Asset(
            name: "hype_barrel_rival",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 96,
            height: 80,
            tags: ["hype-template", "deterministic", "platformer", "rival"]
        )
    }

    private static func makePlatformerPrizeAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_barrel_trophy", width: 64, height: 64) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            nsColor(hex: "#FFE66D").setFill()
            NSBezierPath(roundedRect: NSRect(x: 20, y: 18, width: 24, height: 28), xRadius: 6, yRadius: 6).fill()
            NSBezierPath(rect: NSRect(x: 28, y: 9, width: 8, height: 12)).fill()
            NSBezierPath(rect: NSRect(x: 20, y: 6, width: 24, height: 5)).fill()
            nsColor(hex: "#FFB703").setStroke()
            let leftHandle = NSBezierPath()
            leftHandle.lineWidth = 4
            leftHandle.move(to: CGPoint(x: 21, y: 38))
            leftHandle.curve(to: CGPoint(x: 12, y: 28), controlPoint1: CGPoint(x: 10, y: 38), controlPoint2: CGPoint(x: 10, y: 28))
            leftHandle.stroke()
            let rightHandle = NSBezierPath()
            rightHandle.lineWidth = 4
            rightHandle.move(to: CGPoint(x: 43, y: 38))
            rightHandle.curve(to: CGPoint(x: 52, y: 28), controlPoint1: CGPoint(x: 54, y: 38), controlPoint2: CGPoint(x: 54, y: 28))
            rightHandle.stroke()
            #endif
        }
        return Asset(
            name: "hype_barrel_trophy",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", "platformer", "goal"]
        )
    }

    private static func makePlatformerLadderAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_barrel_ladder", width: 48, height: 96) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            nsColor(hex: "#00D5FF").setStroke()
            func strokeLine(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, width: CGFloat) {
                let line = NSBezierPath()
                line.lineWidth = width
                line.lineCapStyle = .round
                line.move(to: CGPoint(x: x1, y: y1))
                line.line(to: CGPoint(x: x2, y: y2))
                line.stroke()
            }
            strokeLine(12, 6, 12, rect.height - 6, width: 5)
            strokeLine(rect.width - 12, 6, rect.width - 12, rect.height - 6, width: 5)
            for y in stride(from: 16, through: Int(rect.height - 16), by: 16) {
                strokeLine(12, CGFloat(y), rect.width - 12, CGFloat(y), width: 4)
            }
            #endif
        }
        return Asset(
            name: "hype_barrel_ladder",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 48,
            height: 96,
            tags: ["hype-template", "deterministic", "platformer", "ladder"]
        )
    }

    private static func makePlatformerHammerAsset() throws -> Asset {
        let data = try makePNGAsset(name: "hype_barrel_hammer", width: 64, height: 64) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()

            let handle = NSBezierPath()
            handle.lineWidth = 8
            handle.lineCapStyle = .round
            nsColor(hex: "#8D5524").setStroke()
            handle.move(to: CGPoint(x: rect.minX + 18, y: rect.minY + 12))
            handle.line(to: CGPoint(x: rect.maxX - 16, y: rect.maxY - 18))
            handle.stroke()

            nsColor(hex: "#F2F4F8").setFill()
            let head = NSBezierPath(roundedRect: NSRect(x: rect.maxX - 42, y: rect.maxY - 30, width: 34, height: 16), xRadius: 5, yRadius: 5)
            head.fill()
            nsColor(hex: "#8592A3").setStroke()
            head.lineWidth = 3
            head.stroke()

            nsColor(hex: "#FFD166").setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 12, y: rect.minY + 8, width: 12, height: 12)).fill()
            #endif
        }
        return Asset(
            name: "hype_barrel_hammer",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", "platformer", "hammer"]
        )
    }

    private static func drawMazeTileSheet(in rect: CGRect, tileSize: Int, style: String) {
        #if canImport(AppKit)
        let tile = CGFloat(tileSize)
        let wall = nsColor(hex: "#00E5FF")
        let glow = nsColor(hex: "#154E73")
        let fill = nsColor(hex: "#050A1A")

        func tileRect(_ index: Int) -> CGRect {
            CGRect(x: rect.minX + CGFloat(index) * tile, y: rect.minY, width: tile, height: tile)
        }
        func fillBase(_ r: CGRect) {
            fill.setFill()
            NSBezierPath(rect: r).fill()
        }
        func strokeLine(points: [CGPoint], width: CGFloat, color: NSColor) {
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            for point in points.dropFirst() {
                path.line(to: point)
            }
            path.lineWidth = width
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()
        }

        let horizontal = tileRect(0)
        fillBase(horizontal)
        strokeLine(points: [CGPoint(x: horizontal.minX + 4, y: horizontal.midY), CGPoint(x: horizontal.maxX - 4, y: horizontal.midY)], width: 9, color: glow)
        strokeLine(points: [CGPoint(x: horizontal.minX + 5, y: horizontal.midY), CGPoint(x: horizontal.maxX - 5, y: horizontal.midY)], width: 4, color: wall)

        let vertical = tileRect(1)
        fillBase(vertical)
        strokeLine(points: [CGPoint(x: vertical.midX, y: vertical.minY + 4), CGPoint(x: vertical.midX, y: vertical.maxY - 4)], width: 9, color: glow)
        strokeLine(points: [CGPoint(x: vertical.midX, y: vertical.minY + 5), CGPoint(x: vertical.midX, y: vertical.maxY - 5)], width: 4, color: wall)

        let block = tileRect(2)
        fillBase(block)
        glow.setFill()
        NSBezierPath(roundedRect: block.insetBy(dx: 4, dy: 4), xRadius: 6, yRadius: 6).fill()
        wall.setStroke()
        let border = NSBezierPath(roundedRect: block.insetBy(dx: 6, dy: 6), xRadius: 4, yRadius: 4)
        border.lineWidth = 3
        border.stroke()

        let gate = tileRect(3)
        fillBase(gate)
        nsColor(hex: "#FF66CC").setStroke()
        let gateLine = NSBezierPath()
        gateLine.move(to: CGPoint(x: gate.minX + 5, y: gate.midY))
        gateLine.line(to: CGPoint(x: gate.maxX - 5, y: gate.midY))
        gateLine.lineWidth = 4
        gateLine.lineCapStyle = .round
        gateLine.stroke()
        #endif
    }

    private static func makePNGAsset(name: String, width: Int, height: Int, draw: (CGRect) -> Void) throws -> Data {
        #if canImport(AppKit)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SpriteGameTemplateError.imageEncodingFailed(name)
        }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        draw(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SpriteGameTemplateError.imageEncodingFailed(name)
        }
        return data
        #else
        throw SpriteGameTemplateError.imageEncodingFailed(name)
        #endif
    }

    #if canImport(AppKit)
    private static func nsColor(hex: String) -> NSColor {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
            return .white
        }
        return NSColor(
            calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
    #endif
}
