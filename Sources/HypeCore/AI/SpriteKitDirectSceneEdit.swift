import Foundation

public struct SpriteKitDirectSceneEditResult: Equatable, Sendable {
    public let areaName: String
    public let sceneName: String
    public let nodeNames: [String]

    public init(areaName: String, sceneName: String, nodeNames: [String]) {
        self.areaName = areaName
        self.sceneName = sceneName
        self.nodeNames = nodeNames
    }
}

public enum SpriteKitDirectSceneEdit {
    public static func addBoundaryWallsIfRequested(
        prompt: String,
        document: inout HypeDocument,
        currentCardId: UUID?
    ) -> SpriteKitDirectSceneEditResult? {
        guard isBoundaryWallRequest(prompt) else { return nil }
        guard let target = targetSpriteArea(for: prompt, in: document, currentCardId: currentCardId) else { return nil }

        var editedSceneName = "main"
        document.updatePart(id: target.id) { part in
            part.updateActiveSceneSpec { scene in
                editedSceneName = scene.name.isEmpty ? "main" : scene.name
                upsertBoundaryWalls(in: &scene)
            }
        }

        return SpriteKitDirectSceneEditResult(
            areaName: target.name.isEmpty ? "sprite area" : target.name,
            sceneName: editedSceneName,
            nodeNames: boundaryWallNames
        )
    }

    private static let boundaryWallNames = [
        "_leftWall",
        "_rightWall",
        "_topWall",
        "_bottomWall"
    ]

    private static func isBoundaryWallRequest(_ prompt: String) -> Bool {
        let lower = normalized(prompt)

        if isCompleteGameScaffoldRequest(prompt, normalizedPrompt: lower) {
            return false
        }

        let scriptTerms = [
            "script",
            "hypetalk",
            "handler",
            "on idle",
            "on frameupdate",
            "on begin contact",
            "on begincontact",
            "on endcontact"
        ]
        if scriptTerms.contains(where: { lower.contains($0) }) {
            return false
        }

        let boundaryTerms = [
            "boundary",
            "boundaries",
            "barrier",
            "barriers",
            "barrioer",
            "barrioers",
            "wall",
            "walls",
            "perimeter",
            "perimiter",
            "border",
            "edge",
            "edges",
            "bounds"
        ]
        let shapeTerms = [
            "boundary",
            "boundaries",
            "shape node",
            "shape nodes",
            "line",
            "lines",
            "rect",
            "rectangle",
            "barrier",
            "perimeter",
            "wall",
            "border",
            "edge",
            "edges",
            "bounds"
        ]
        let actionTerms = [
            "add",
            "create",
            "make",
            "put",
            "draw",
            "place",
            "establish"
        ]
        let spriteContextTerms = [
            "sprite",
            "spritekit",
            "scene",
            "object"
        ]

        return boundaryTerms.contains(where: { lower.contains($0) }) &&
            shapeTerms.contains(where: { lower.contains($0) }) &&
            actionTerms.contains(where: { lower.contains($0) }) &&
            spriteContextTerms.contains(where: { lower.contains($0) })
    }

    private static func isCompleteGameScaffoldRequest(_ prompt: String, normalizedPrompt lower: String) -> Bool {
        if lower.contains("all game logic") ||
            lower.contains("complete game") ||
            lower.contains("playable game") {
            return true
        }

        let creationTerms = [
            "create",
            "build",
            "make",
            "generate",
            "implement",
            "develop",
            "scaffold"
        ]
        let asksToCreate = creationTerms.contains { lower.contains($0) }
        guard asksToCreate else { return false }

        if lower.contains(" game") || lower.contains("game ") {
            return true
        }

        let inference = SpriteGameTemplateBuilder.inferTemplate(forPrompt: prompt)
        return inference.templateID != nil && inference.confidence >= 0.8
    }

    private static func targetSpriteArea(
        for prompt: String,
        in document: HypeDocument,
        currentCardId: UUID?
    ) -> Part? {
        let lower = normalized(prompt)
        let candidates = candidateSpriteAreas(in: document, currentCardId: currentCardId)
        guard !candidates.isEmpty else { return nil }

        if let named = candidates.first(where: { !$0.name.isEmpty && lower.contains(normalized($0.name)) }) {
            return named
        }

        if let byNode = candidates.first(where: { area in
            guard let scene = area.activeSceneSpec else { return false }
            return scene.allNodes.contains { node in
                !node.name.isEmpty && lower.contains(normalized(node.name))
            }
        }) {
            return byNode
        }

        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func candidateSpriteAreas(
        in document: HypeDocument,
        currentCardId: UUID?
    ) -> [Part] {
        if let currentCardId {
            let current = document.effectivePartsForCard(currentCardId).filter { $0.partType == .spriteArea }
            if !current.isEmpty { return current }
        }
        return document.parts.filter { $0.partType == .spriteArea }
    }

    private static func upsertBoundaryWalls(in scene: inout SceneSpec) {
        let size = normalizedSize(scene.size)
        for wall in boundaryWallNodes(for: size) {
            if let existing = scene.node(named: wall.name) {
                _ = scene.updateNode(id: existing.id) { node in
                    let preservedId = node.id
                    node = wall
                    node.id = preservedId
                }
            } else {
                scene.nodes.append(wall)
            }
        }
    }

    private static func normalizedSize(_ size: SizeSpec) -> SizeSpec {
        SizeSpec(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
    }

    private static func boundaryWallNodes(for size: SizeSpec) -> [HypeNodeSpec] {
        let thickness = min(max(min(size.width, size.height) * 0.02, 8), 20)
        let halfThickness = thickness / 2
        let fill = "#1F2937"
        let stroke = "#111827"

        return [
            boundaryWall(
                name: "_leftWall",
                position: PointSpec(x: halfThickness, y: size.height / 2),
                size: SizeSpec(width: thickness, height: size.height),
                fill: fill,
                stroke: stroke
            ),
            boundaryWall(
                name: "_rightWall",
                position: PointSpec(x: max(size.width - halfThickness, halfThickness), y: size.height / 2),
                size: SizeSpec(width: thickness, height: size.height),
                fill: fill,
                stroke: stroke
            ),
            boundaryWall(
                name: "_topWall",
                position: PointSpec(x: size.width / 2, y: halfThickness),
                size: SizeSpec(width: size.width, height: thickness),
                fill: fill,
                stroke: stroke
            ),
            boundaryWall(
                name: "_bottomWall",
                position: PointSpec(x: size.width / 2, y: max(size.height - halfThickness, halfThickness)),
                size: SizeSpec(width: size.width, height: thickness),
                fill: fill,
                stroke: stroke
            )
        ]
    }

    private static func boundaryWall(
        name: String,
        position: PointSpec,
        size: SizeSpec,
        fill: String,
        stroke: String
    ) -> HypeNodeSpec {
        HypeNodeSpec(
            name: name,
            nodeType: .shape,
            position: position,
            zPosition: 1_000,
            alpha: 1,
            isHidden: false,
            size: size,
            shapeSpec: ShapeNodeSpec(
                shapeType: .rect,
                fillColor: fill,
                strokeColor: stroke,
                lineWidth: 1
            ),
            physicsBody: PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: false,
                contactTestBitmask: 0xFFFFFFFF,
                collisionBitmask: 0xFFFFFFFF,
                restitution: 1,
                friction: 0,
                affectedByGravity: false,
                allowsRotation: false,
                linearDamping: 0,
                angularDamping: 0
            )
        )
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "_", with: " ")
    }
}
