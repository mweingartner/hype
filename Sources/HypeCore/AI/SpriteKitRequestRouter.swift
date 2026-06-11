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
        // v3.1 (Apr 2026): removed "inside" and "bounds" — they
        // misfire on ordinary English. Their useful sense is
        // "stay inside the scene bounds", now matched below as
        // phrases in `behaviorPhrases`.
        let behaviorTerms = [
            "bounce",
            "bouncing",
            "collision",
            "gravity",
            "velocity",
            "accelerate",
            "decelerate",
            "physics",
            "boundary"
        ]
        // Phrase-level matches for idioms that want SpriteKit
        // routing but share stem words with ordinary prompts.
        let behaviorPhrases = [
            "stay inside the scene",
            "inside the scene",
            "scene bounds",
            "scene boundary",
        ]
        let explicitCreateTerms = [
            "create sprite area",
            "create spritearea",
            "create spritekit scene",
            "create spritekit game",
            "create a spritekit game",
            "create a spritekit based game",
            "create sprite scene",
            "build spritekit game",
            "build a spritekit game",
            "build spritekit scene",
            "make spritekit game",
            "make a spritekit game",
            "set up spritekit scene",
            "setup spritekit scene",
            "starter scene",
            "new sprite area"
        ]
        let spriteKitGameTerms = [
            "spritekit based game",
            "spritekit game",
            "sprite scene game",
            "sprite area game",
            "donkey kong",
            "barrel game",
            "barrel climber",
            "barrel jumper",
            "jump barrels",
            "platformer",
            "platform game",
            "arcade game",
            "tower defense",
            "top down shooter",
            "top-down shooter",
            "space shooter",
            "physics puzzle",
            "breakout",
            "pinball",
            "endless runner",
            "match-3",
            "match 3",
            "sokoban",
            "racing game",
            "pong",
            "rhythm game",
            "boss battle",
            "physics sandbox",
            // Freeform custom-game intent phrases for the composable recipe flow.
            "make a game where",
            "build a game where",
            "create a game where",
            "control a ",
            "score points",
            "game with enemies",
            "game with a player",
            "dodge the",
            "shoot the",
            "collect the",
            "avoid the",
        ]
        let formControlTerms = [
            "entry form",
            "data entry",
            "text entry",
            "input form",
            "customer entry",
            "contact form",
            "login form",
            "registration form",
            "basic controls",
            "form with fields",
            "fields and labels",
            "labels and fields",
            "input fields",
            "text fields",
            "field labels",
            "header and fields",
        ]
        let explicitRepairTerms = [
            "repair the scene",
            "fix this scene",
            "fix the scene",
            "debug the scene",
            "diagnose the scene",
            "redesign the scene",
            "redo the scene",
            "rebuild the scene"
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
        // Prompts containing any of these explicitly target a
        // card/background-level part operation. Force the full
        // authoring toolset so the model can reach `set_part_property`
        // / `create_button` / etc. — even if the current card
        // happens to also contain a sprite area whose name token
        // coincidentally appears in the prompt.
        let partAuthoringOverrideTerms = [
            "set the text ",
            "set the script ",
            "set the property ",
            "set the style ",
            "set the fill ",
            "set the stroke ",
            "set the font",
            "set the value",
            "set the width",
            "set the height",
            "set the left",
            "set the top",
            "set the url",
            "change the text ",
            "change the script ",
            "change the style ",
            "rename ",
            "move button ",
            "move field ",
            "move shape ",
            "resize button ",
            "resize field ",
            "resize shape ",
            "delete button ",
            "delete field ",
            "delete shape ",
            "hide button ",
            "hide field ",
            "show button ",
            "show field ",
            "on the card",
            "on the background",
            "create a button",
            "create a field",
            "create a shape",
            "create an image",
            "create a webpage",
            "create a video",
            "create a chart",
            "add a button",
            "add a field",
            "add a shape",
            "add an image",
            "add a webpage",
            "add a video",
            "add a chart",
        ]

        let mentionsSpriteKit = spriteKitTerms.contains(where: { lower.contains($0) })
        let mentionsSpriteBehavior = behaviorTerms.contains(where: { lower.contains($0) })
            || behaviorPhrases.contains(where: { lower.contains($0) })
        let explicitCreate = explicitCreateTerms.contains(where: { lower.contains($0) })
        let inferredTemplateGame = SpriteGameTemplateBuilder.inferredGameType(forPrompt: prompt) != nil
        let mentionsSpriteKitGame = inferredTemplateGame || spriteKitGameTerms.contains(where: { lower.contains($0) })
            || (lower.contains("game") && (mentionsSpriteKit || lower.contains("sprite scene") || lower.contains("sprite area")))
        let explicitRepair = explicitRepairTerms.contains(where: { lower.contains($0) })
        let explicitScriptRequest = explicitScriptTerms.contains(where: { lower.contains($0) }) || lower.contains(" script ")
        let partAuthoringOverride = partAuthoringOverrideTerms.contains(where: { lower.contains($0) })
        let formControlOverride = formControlTerms.contains(where: { lower.contains($0) })
            && !mentionsSpriteKit
            && !explicitCreate
            && !explicitRepair

        // Early escape: the user is explicitly talking about a
        // card/background-level part. Skip all SpriteKit inference and
        // go straight to the full authoring toolset, unless the prompt
        // is explicitly a SpriteKit game request that merely includes
        // card-level supporting pieces like "add a New Game button".
        if formControlOverride || (partAuthoringOverride
            && !mentionsSpriteKit
            && !mentionsSpriteKitGame
            && !mentionsSpriteBehavior
            && !explicitCreate
            && !mentionsKnownArea
            && !mentionsKnownNode) {
            return SpriteKitAIRoute(
                isSpriteKitRequest: false,
                structuredIntent: nil,
                prefersSceneTooling: false,
                explicitScriptRequest: explicitScriptRequest
            )
        }

        let isSpriteKitRequest =
            mentionsSpriteKit || mentionsSpriteKitGame || mentionsSpriteBehavior || mentionsKnownArea || mentionsKnownNode

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

        // v3.1: only route to the structured scene-proposal flow
        // when the user explicitly asks for repair/create. Every
        // other SpriteKit-adjacent request goes through the
        // regular tool-call loop with the sprite-scene toolset
        // (which now also includes part-level tools).
        if explicitRepair && hasExistingSpriteArea {
            return SpriteKitAIRoute(
                isSpriteKitRequest: true,
                structuredIntent: .repair,
                prefersSceneTooling: true,
                explicitScriptRequest: false
            )
        }

        if explicitCreate {
            return SpriteKitAIRoute(
                isSpriteKitRequest: true,
                structuredIntent: .create,
                prefersSceneTooling: true,
                explicitScriptRequest: false
            )
        }

        // SpriteKit-adjacent but not explicitly repair/create: use
        // the regular tool-call loop with scene-preferred tools.
        return SpriteKitAIRoute(
            isSpriteKitRequest: true,
            structuredIntent: nil,
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
