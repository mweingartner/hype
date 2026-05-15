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
            return "Unsupported sprite game template '\(gameType)'. Supported values: pacman, maze_chase."
        }
    }
}

public enum SpriteGameTemplateBuilder {
    public static let defaultPacmanSceneSize = SizeSpec(width: 768, height: 544)
    public static let defaultPacmanTileSize = 32

    private static let wallCategory: UInt32 = 1 << 0
    private static let playerCategory: UInt32 = 1 << 1
    private static let ghostCategory: UInt32 = 1 << 2
    private static let pelletCategory: UInt32 = 1 << 3
    private static let powerPelletCategory: UInt32 = 1 << 4

    public static func normalizedGameType(_ raw: String) throws -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        if normalized.isEmpty || normalized == "pacman" || normalized == "pacmanstyle" {
            return "pacman"
        }
        if normalized == "mazechase" || normalized == "mazechasegame" || normalized == "arcademaze" {
            return "pacman"
        }
        throw SpriteGameTemplateError.unsupportedGameType(raw)
    }

    public static func createBasicMazeTilesetAsset(
        name: String = "hype_arcade_maze_tiles",
        style: String = "neon",
        tileSize: Int = defaultPacmanTileSize
    ) throws -> SpriteAsset {
        let safeTileSize = max(8, min(tileSize, 128))
        let columns = 4
        let width = safeTileSize * columns
        let height = safeTileSize
        let data = try makePNGAsset(name: name, width: width, height: height) { rect in
            drawMazeTileSheet(in: rect, tileSize: safeTileSize, style: style)
        }
        return SpriteAsset(
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
    public static func upsertAsset(_ asset: SpriteAsset, in repository: inout SpriteRepository) -> SpriteAsset {
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
            in: &document.spriteRepository
        )
        let pacman = upsertAsset(try makePacmanAsset(), in: &document.spriteRepository)
        let blinky = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_blinky", colorHex: "#FF3030"), in: &document.spriteRepository)
        let pinky = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_pinky", colorHex: "#FF77C8"), in: &document.spriteRepository)
        let inky = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_inky", colorHex: "#35E3FF"), in: &document.spriteRepository)
        let clyde = upsertAsset(try makeGhostAsset(name: "hype_pacman_ghost_clyde", colorHex: "#FF9D28"), in: &document.spriteRepository)
        let pellet = upsertAsset(try makePelletAsset(name: "hype_pacman_pellet", colorHex: "#FFDFA3", diameter: 8), in: &document.spriteRepository)
        let powerPellet = upsertAsset(try makePelletAsset(name: "hype_pacman_power_pellet", colorHex: "#FFFFFF", diameter: 18), in: &document.spriteRepository)

        let maze = makePacmanMaze(columns: 24, rows: 17)
        let tileSize = Double(defaultPacmanTileSize)
        let tileData = mazeTileData(from: maze)
        var nodes: [HypeNodeSpec] = []

        var tileMapSpec = TileMapSpec(
            columns: maze.columns,
            rows: maze.rows,
            tileWidth: tileSize,
            tileHeight: tileSize,
            tileSetAssetRef: document.spriteRepository.assetRef(for: tiles),
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
                    repository: document.spriteRepository,
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
                repository: document.spriteRepository,
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
            repository: document.spriteRepository,
            col: 1,
            row: maze.rows - 2,
            tileSize: tileSize,
            size: SizeSpec(width: 28, height: 28),
            z: 40,
            physics: playerPhysics()
        ))

        let ghostSpecs: [(String, SpriteAsset, Int, Int, Double, Double)] = [
            ("ghost_blinky", blinky, 11, 8, 120, 0),
            ("ghost_pinky", pinky, 12, 8, -120, 0),
            ("ghost_inky", inky, 10, 8, 0, 120),
            ("ghost_clyde", clyde, 13, 8, 0, -120),
        ]
        for (name, asset, col, row, vx, vy) in ghostSpecs {
            nodes.append(spriteNode(
                name: name,
                asset: asset,
                repository: document.spriteRepository,
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
            gameType: "pacman",
            spriteAreaName: spriteAreaName,
            assetNames: [tiles, pacman, blinky, pinky, inky, clyde, pellet, powerPellet].map(\.name),
            nodeNames: nodes.map(\.name),
            wallColliderCount: wallCount,
            pelletCount: pelletCount,
            powerPelletCount: powerPelletCount
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
        asset: SpriteAsset,
        repository: SpriteRepository,
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
          if otherName contains "ghost_" then
            set the loc of sprite "pacmanPlayer" to "48,496"
            set the velocity of sprite "pacmanPlayer" to "0,0"
          end if
        end beginContact
        """
    }

    private static func makePacmanAsset() throws -> SpriteAsset {
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
        return SpriteAsset(
            name: "hype_pacman_player",
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", "pacman"]
        )
    }

    private static func makeGhostAsset(name: String, colorHex: String) throws -> SpriteAsset {
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
        return SpriteAsset(
            name: name,
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: 64,
            height: 64,
            tags: ["hype-template", "deterministic", "pacman", "ghost"]
        )
    }

    private static func makePelletAsset(name: String, colorHex: String, diameter: Int) throws -> SpriteAsset {
        let size = max(8, diameter + 6)
        let data = try makePNGAsset(name: name, width: size, height: size) { rect in
            #if canImport(AppKit)
            NSColor.clear.setFill()
            rect.fill()
            nsColor(hex: colorHex).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            #endif
        }
        return SpriteAsset(
            name: name,
            kind: .imageTexture,
            mimeType: "image/png",
            data: data,
            width: size,
            height: size,
            tags: ["hype-template", "deterministic", "pacman", "pellet"]
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
