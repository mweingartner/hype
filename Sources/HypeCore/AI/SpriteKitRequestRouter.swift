import Foundation

public enum SpriteKitStructuredIntent: String, Sendable {
    case create
    case repair
}

public struct SpriteKitAIRoute: Equatable, Sendable {
    public var isSpriteKitRequest: Bool
    public var structuredIntent: SpriteKitStructuredIntent?
    public var prefersSceneTooling: Bool
    public var explicitScriptRequest: Bool

    public init(
        isSpriteKitRequest: Bool = false,
        structuredIntent: SpriteKitStructuredIntent? = nil,
        prefersSceneTooling: Bool = false,
        explicitScriptRequest: Bool = false
    ) {
        self.isSpriteKitRequest = isSpriteKitRequest
        self.structuredIntent = structuredIntent
        self.prefersSceneTooling = prefersSceneTooling
        self.explicitScriptRequest = explicitScriptRequest
    }
}

public enum SpriteKitRequestRouter {
    public static func route(
        prompt: String,
        document: HypeDocument,
        currentCardId: UUID?
    ) -> SpriteKitAIRoute {
        let lower = prompt.lowercased()
        let spriteAreas = candidateSpriteAreas(in: document, currentCardId: currentCardId)
        let hasExistingSpriteArea = !spriteAreas.isEmpty

        let areaNames = spriteAreas.map { $0.name.lowercased() }.filter { !$0.isEmpty }
        let nodeNames = spriteAreas.flatMap { part in
            part.activeSceneSpec?.allNodes.map { $0.name.lowercased() }.filter { !$0.isEmpty } ?? []
        }

        let mentionsKnownArea = areaNames.contains { lower.contains($0) }
        let mentionsKnownNode = nodeNames.contains { lower.contains($0) }

        let spriteKitTerms = [
            "spritekit",
            "sprite area",
            "spritearea",
            "sprite scene",
            "scene node",
            "tilemap",
            "tile map",
            "physics body",
            "begincontact",
            "endcontact",
            "emitter",
            "camera",
            "sprite "
        ]
        let behaviorTerms = [
            "bounce",
            "bouncing",
            "collision",
            "gravity",
            "velocity",
            "accelerate",
            "decelerate",
            "physics",
            "boundary",
            "bounds",
            "inside"
        ]
        let explicitCreateTerms = [
            "create sprite area",
            "create spritearea",
            "create spritekit scene",
            "create sprite scene",
            "build spritekit scene",
            "set up spritekit scene",
            "setup spritekit scene",
            "starter scene",
            "new sprite area"
        ]
        let explicitScriptTerms = [
            "write a script",
            "generate a script",
            "hype talk script",
            "hypetalk script",
            "handler",
            "on idle",
            "on keydown",
            "on keyup",
            "on begincontact",
            "on endcontact"
        ]

        let mentionsSpriteKit = spriteKitTerms.contains(where: { lower.contains($0) })
        let mentionsSpriteBehavior = behaviorTerms.contains(where: { lower.contains($0) })
        let explicitCreate = explicitCreateTerms.contains(where: { lower.contains($0) })
        let explicitScriptRequest = explicitScriptTerms.contains(where: { lower.contains($0) }) || lower.contains(" script ")

        let isSpriteKitRequest =
            mentionsSpriteKit || mentionsSpriteBehavior || mentionsKnownArea || mentionsKnownNode

        guard isSpriteKitRequest else {
            return SpriteKitAIRoute()
        }

        if explicitScriptRequest {
            return SpriteKitAIRoute(
                isSpriteKitRequest: true,
                structuredIntent: nil,
                prefersSceneTooling: false,
                explicitScriptRequest: true
            )
        }

        if hasExistingSpriteArea && (mentionsKnownArea || mentionsKnownNode || mentionsSpriteBehavior || mentionsSpriteKit) {
            return SpriteKitAIRoute(
                isSpriteKitRequest: true,
                structuredIntent: .repair,
                prefersSceneTooling: true,
                explicitScriptRequest: false
            )
        }

        if explicitCreate || !hasExistingSpriteArea {
            return SpriteKitAIRoute(
                isSpriteKitRequest: true,
                structuredIntent: .create,
                prefersSceneTooling: true,
                explicitScriptRequest: false
            )
        }

        return SpriteKitAIRoute(
            isSpriteKitRequest: true,
            structuredIntent: .repair,
            prefersSceneTooling: true,
            explicitScriptRequest: false
        )
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
}
