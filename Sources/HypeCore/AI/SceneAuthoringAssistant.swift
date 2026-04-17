import Foundation

// MARK: - Lenient enum decoding for AI-produced JSON
//
// Local LLMs frequently produce plausible but not-exactly-spec enum
// values when asked for structured output. For example the user asks
// for a "triangle", the model emits `"shapeType": "triangle"`, and a
// strict `Codable` enum decode fails with `dataCorrupted`, aborting
// the entire scene plan. These helpers accept the raw string, apply
// a small normalization table (case-insensitive, common synonyms),
// then fall back to a caller-supplied default when the value doesn't
// match. The result: one off-spec field degrades gracefully instead
// of taking down the whole response.
extension SceneScaleMode {
    fileprivate static func decodeLenient<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        default fallback: SceneScaleMode
    ) -> SceneScaleMode {
        guard let raw = try? container.decode(String.self, forKey: key) else { return fallback }
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "fill": return .fill
        case "aspectfill", "aspect-fill": return .aspectFill
        case "aspectfit", "aspect-fit": return .aspectFit
        case "resizefill", "resize-fill", "resize": return .resizeFill
        default: return fallback
        }
    }
}

// The public `decodeTolerant` on `NodeType`, `SpriteShapeType`, and
// `PhysicsBodyType` (defined in `SceneSpec.swift`) always returns a
// non-optional value — that's the behavior the loading path wants
// (any malformed JSON still produces a usable object). The AI
// `SceneBlueprintNode` path, however, needs to distinguish "the
// model didn't mention this field" from "the model sent a known
// value" so it can promote a mis-declared sprite+shape combo to a
// shape node. These `decodeLenient` wrappers return an optional to
// preserve that distinction for AI-only code.
extension SpriteShapeType {
    fileprivate static func decodeLenient<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> SpriteShapeType? {
        guard container.contains(key),
              (try? container.decodeNil(forKey: key)) == false else { return nil }
        return decodeTolerant(from: container, forKey: key, default: .rect)
    }
}

extension PhysicsBodyType {
    fileprivate static func decodeLenient<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> PhysicsBodyType? {
        guard container.contains(key),
              (try? container.decodeNil(forKey: key)) == false else { return nil }
        return decodeTolerant(from: container, forKey: key, default: .rect)
    }
}

public struct SceneBlueprint: Codable, Sendable {
    public var size: SizeSpec
    public var backgroundColor: String
    public var gravity: VectorSpec
    public var scaleMode: SceneScaleMode
    public var showsPhysics: Bool
    public var showsFPS: Bool
    public var showsNodeCount: Bool
    public var sceneScript: String
    public var nodes: [SceneBlueprintNode]

    public init(
        size: SizeSpec,
        backgroundColor: String,
        gravity: VectorSpec,
        scaleMode: SceneScaleMode,
        showsPhysics: Bool,
        showsFPS: Bool,
        showsNodeCount: Bool,
        sceneScript: String,
        nodes: [SceneBlueprintNode]
    ) {
        self.size = size
        self.backgroundColor = backgroundColor
        self.gravity = gravity
        self.scaleMode = scaleMode
        self.showsPhysics = showsPhysics
        self.showsFPS = showsFPS
        self.showsNodeCount = showsNodeCount
        self.sceneScript = sceneScript
        self.nodes = nodes
    }

    // Every field has a reasonable default so local models that omit
    // some of the flags (common with 3B-7B models) still decode.
    // Unknown enum values for `scaleMode` fall back to `.aspectFit`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.size = (try? c.decode(SizeSpec.self, forKey: .size))
            ?? SizeSpec(width: 800, height: 600)
        self.backgroundColor = (try? c.decode(String.self, forKey: .backgroundColor))
            ?? "#FFFFFF"
        self.gravity = (try? c.decode(VectorSpec.self, forKey: .gravity))
            ?? VectorSpec(dx: 0, dy: 0)
        self.scaleMode = SceneScaleMode.decodeLenient(from: c, forKey: .scaleMode, default: .aspectFit)
        self.showsPhysics = (try? c.decode(Bool.self, forKey: .showsPhysics)) ?? false
        self.showsFPS = (try? c.decode(Bool.self, forKey: .showsFPS)) ?? false
        self.showsNodeCount = (try? c.decode(Bool.self, forKey: .showsNodeCount)) ?? false
        self.sceneScript = (try? c.decode(String.self, forKey: .sceneScript)) ?? ""
        self.nodes = (try? c.decode([SceneBlueprintNode].self, forKey: .nodes)) ?? []
    }
}

public struct SceneBlueprintNode: Codable, Sendable {
    public var name: String
    public var nodeType: NodeType
    public var position: PointSpec
    public var size: SizeSpec?
    public var alpha: Double?
    public var isHidden: Bool?
    public var assetName: String?
    public var text: String?
    public var fontName: String?
    public var fontSize: Double?
    public var fontColor: String?
    public var shapeType: SpriteShapeType?
    public var fillColor: String?
    public var strokeColor: String?
    public var lineWidth: Double?
    public var cornerRadius: Double?
    public var parentName: String?
    public var physicsEnabled: Bool
    public var physicsBodyType: PhysicsBodyType?
    public var dynamic: Bool?
    public var affectedByGravity: Bool?
    public var restitution: Double?
    public var friction: Double?
    public var allowsRotation: Bool?
    public var linearDamping: Double?
    public var velocity: VectorSpec?
    public var cameraTarget: String?
    public var tileMapColumns: Int?
    public var tileMapRows: Int?
    public var tileSetAssetName: String?
    public var tileWidth: Double?
    public var tileHeight: Double?
    public var audioAssetName: String?
    public var videoAssetName: String?
    public var particleColor: String?
    public var script: String?

    public init(
        name: String,
        nodeType: NodeType,
        position: PointSpec,
        size: SizeSpec? = nil,
        alpha: Double? = nil,
        isHidden: Bool? = nil,
        assetName: String? = nil,
        text: String? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        fontColor: String? = nil,
        shapeType: SpriteShapeType? = nil,
        fillColor: String? = nil,
        strokeColor: String? = nil,
        lineWidth: Double? = nil,
        cornerRadius: Double? = nil,
        parentName: String? = nil,
        physicsEnabled: Bool = false,
        physicsBodyType: PhysicsBodyType? = nil,
        dynamic: Bool? = nil,
        affectedByGravity: Bool? = nil,
        restitution: Double? = nil,
        friction: Double? = nil,
        allowsRotation: Bool? = nil,
        linearDamping: Double? = nil,
        velocity: VectorSpec? = nil,
        cameraTarget: String? = nil,
        tileMapColumns: Int? = nil,
        tileMapRows: Int? = nil,
        tileSetAssetName: String? = nil,
        tileWidth: Double? = nil,
        tileHeight: Double? = nil,
        audioAssetName: String? = nil,
        videoAssetName: String? = nil,
        particleColor: String? = nil,
        script: String? = nil
    ) {
        self.name = name
        self.nodeType = nodeType
        self.position = position
        self.size = size
        self.alpha = alpha
        self.isHidden = isHidden
        self.assetName = assetName
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontColor = fontColor
        self.shapeType = shapeType
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.parentName = parentName
        self.physicsEnabled = physicsEnabled
        self.physicsBodyType = physicsBodyType
        self.dynamic = dynamic
        self.affectedByGravity = affectedByGravity
        self.restitution = restitution
        self.friction = friction
        self.allowsRotation = allowsRotation
        self.linearDamping = linearDamping
        self.velocity = velocity
        self.cameraTarget = cameraTarget
        self.tileMapColumns = tileMapColumns
        self.tileMapRows = tileMapRows
        self.tileSetAssetName = tileSetAssetName
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.audioAssetName = audioAssetName
        self.videoAssetName = videoAssetName
        self.particleColor = particleColor
        self.script = script
    }

    // Lenient decoder: accept missing defaults and off-enum values.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `name` is required upstream, but if the model forgot it we
        // synthesize a placeholder so the rest of the node still
        // decodes and normalization can give it a real name later.
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "node"
        self.nodeType = NodeType.decodeTolerant(from: c, forKey: .nodeType, default: .sprite)
        self.position = (try? c.decode(PointSpec.self, forKey: .position)) ?? PointSpec()
        self.size = try? c.decode(SizeSpec.self, forKey: .size)
        self.alpha = try? c.decode(Double.self, forKey: .alpha)
        self.isHidden = try? c.decode(Bool.self, forKey: .isHidden)
        self.assetName = try? c.decode(String.self, forKey: .assetName)
        self.text = try? c.decode(String.self, forKey: .text)
        self.fontName = try? c.decode(String.self, forKey: .fontName)
        self.fontSize = try? c.decode(Double.self, forKey: .fontSize)
        self.fontColor = try? c.decode(String.self, forKey: .fontColor)

        // If the model wrote "triangle" or "square", promote the
        // node to nodeType=shape so the blueprint-to-HypeNodeSpec
        // mapper produces a shape node with a sensible shapeType.
        // Decode shape lenient first so we can use it to correct
        // nodeType if the model said "sprite" but gave a shape name.
        let lenientShape = SpriteShapeType.decodeLenient(from: c, forKey: .shapeType)
        self.shapeType = lenientShape
        // Heuristic correction: a "sprite" with an explicit shapeType
        // is really a shape node. This is what callers expect.
        if self.nodeType == .sprite && lenientShape != nil {
            self.nodeType = .shape
        }

        self.fillColor = try? c.decode(String.self, forKey: .fillColor)
        self.strokeColor = try? c.decode(String.self, forKey: .strokeColor)
        self.lineWidth = try? c.decode(Double.self, forKey: .lineWidth)
        self.cornerRadius = try? c.decode(Double.self, forKey: .cornerRadius)
        self.parentName = try? c.decode(String.self, forKey: .parentName)
        self.physicsEnabled = (try? c.decode(Bool.self, forKey: .physicsEnabled)) ?? false
        self.physicsBodyType = PhysicsBodyType.decodeLenient(from: c, forKey: .physicsBodyType)
        self.dynamic = try? c.decode(Bool.self, forKey: .dynamic)
        self.affectedByGravity = try? c.decode(Bool.self, forKey: .affectedByGravity)
        self.restitution = try? c.decode(Double.self, forKey: .restitution)
        self.friction = try? c.decode(Double.self, forKey: .friction)
        self.allowsRotation = try? c.decode(Bool.self, forKey: .allowsRotation)
        self.linearDamping = try? c.decode(Double.self, forKey: .linearDamping)
        self.velocity = try? c.decode(VectorSpec.self, forKey: .velocity)
        self.cameraTarget = try? c.decode(String.self, forKey: .cameraTarget)
        self.tileMapColumns = try? c.decode(Int.self, forKey: .tileMapColumns)
        self.tileMapRows = try? c.decode(Int.self, forKey: .tileMapRows)
        self.tileSetAssetName = try? c.decode(String.self, forKey: .tileSetAssetName)
        self.tileWidth = try? c.decode(Double.self, forKey: .tileWidth)
        self.tileHeight = try? c.decode(Double.self, forKey: .tileHeight)
        self.audioAssetName = try? c.decode(String.self, forKey: .audioAssetName)
        self.videoAssetName = try? c.decode(String.self, forKey: .videoAssetName)
        self.particleColor = try? c.decode(String.self, forKey: .particleColor)
        self.script = try? c.decode(String.self, forKey: .script)
    }
}

public struct SceneCreateProposal: Codable, Sendable {
    public var areaName: String
    public var sceneName: String
    public var createSpriteAreaIfMissing: Bool
    public var summary: String
    public var checklist: [SceneChecklistItem]
    public var scene: SceneBlueprint

    public init(
        areaName: String,
        sceneName: String,
        createSpriteAreaIfMissing: Bool,
        summary: String,
        checklist: [SceneChecklistItem],
        scene: SceneBlueprint
    ) {
        self.areaName = areaName
        self.sceneName = sceneName
        self.createSpriteAreaIfMissing = createSpriteAreaIfMissing
        self.summary = summary
        self.checklist = checklist
        self.scene = scene
    }

    // Lenient decoder — accept missing metadata fields so a scene
    // that the model got mostly right still applies. Empty-string
    // fallbacks for areaName / sceneName are deliberate: callers
    // detect empties and substitute real context (the targeted
    // sprite area's name, the active scene name) instead of a
    // literal placeholder that might accidentally collide with a
    // real object's name.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.areaName = (try? c.decode(String.self, forKey: .areaName)) ?? ""
        self.sceneName = (try? c.decode(String.self, forKey: .sceneName)) ?? ""
        self.createSpriteAreaIfMissing =
            (try? c.decode(Bool.self, forKey: .createSpriteAreaIfMissing)) ?? true
        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        self.checklist = (try? c.decode([SceneChecklistItem].self, forKey: .checklist)) ?? []
        // The `scene` field is the only thing that absolutely must be
        // present — everything else can degrade. If the model omits
        // it we still throw so the caller knows the whole plan is
        // unusable.
        self.scene = try c.decode(SceneBlueprint.self, forKey: .scene)
    }
}

public struct SceneRepairProposal: Codable, Sendable {
    public var areaName: String
    public var summary: String
    public var issues: [SceneDiagnosticIssue]
    public var diff: SceneDiff

    public init(
        areaName: String,
        summary: String,
        issues: [SceneDiagnosticIssue],
        diff: SceneDiff
    ) {
        self.areaName = areaName
        self.summary = summary
        self.issues = issues
        self.diff = diff
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Empty-string fallback (not "main") so the caller's
        // authoritative overwrite or the applyRepairProposal
        // resolve-by-card fallback has a clear signal that the model
        // didn't name the area itself.
        self.areaName = (try? c.decode(String.self, forKey: .areaName)) ?? ""
        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        self.issues = (try? c.decode([SceneDiagnosticIssue].self, forKey: .issues)) ?? []
        self.diff = (try? c.decode(SceneDiff.self, forKey: .diff)) ?? SceneDiff()
    }
}

public actor SceneAuthoringAssistant {
    private let client: OllamaToolClient

    public init(client: OllamaToolClient) {
        self.client = client
    }

    public func createProposal(
        userRequest: String,
        document: HypeDocument,
        currentCardId: UUID
    ) async throws -> SceneCreateProposal {
        let context = sceneContext(document: document, currentCardId: currentCardId)
        let prompt = """
        Build a starter SpriteKit scene plan for Hype. Prefer native SpriteKit primitives over per-frame scripting. \
        Make the scene easy for a user to continue editing by naming nodes clearly, using cameras/tilemaps/physics when appropriate, \
        and keeping scripts short with TODO comments instead of large logic dumps. \
        For requests involving bouncing, gravity, collisions, or objects staying inside a sprite area, use SpriteKit physics bodies, \
        restitution, velocity, and boundary nodes instead of `on idle` or `on frameUpdate` scripts.

        USER REQUEST:
        \(userRequest)

        CURRENT HYPE CONTEXT:
        \(context)
        """
        let messages = [
            OllamaMessage(
                role: "system",
                content: """
                You are planning a Hype SpriteKit scene. Output only JSON matching the provided schema.
                Use asset names exactly as they appear in the repository.
                If no sprite area exists yet, set createSpriteAreaIfMissing to true and choose a sensible areaName.
                Include a clear checklist so the editor can walk the user through the remaining setup work.
                Do not use sceneScript or node scripts to fake movement, bouncing, gravity, or collisions when SpriteKit physics can express the behavior.
                For a bouncing object inside a sprite area, create a dynamic body with high restitution, a starting velocity, and static bounds or wall nodes.

                \(Self.hypeTalkScriptLanguageRules)
                """
            ),
            OllamaMessage(role: "user", content: prompt)
        ]

        let result: (response: OllamaChatResponse, decoded: SceneCreateProposal) =
            try await client.structuredChat(
                messages: messages,
                format: Self.sceneCreateFormat
            )
        // Best-effort correction: if the user prompt explicitly names an
        // existing sprite area on the current card, honor THAT name even
        // if the model returned something else (or blank). Same rationale
        // as the repair path — the model routinely confuses scene names
        // with area names, especially when the user prompt mentions both.
        var proposal = result.decoded
        Self.applyUserRequestOverrides(
            to: &proposal,
            userRequest: userRequest,
            document: document,
            currentCardId: currentCardId
        )
        return Self.normalizeCreateProposal(proposal, for: userRequest)
    }

    /// Shared language block injected into every scene-authoring
    /// system prompt. Models trained on SpriteKit with JavaScript
    /// bindings, Swift SpriteKit, or Cocos2D routinely emit
    /// JavaScript / Swift code into `script` fields because their
    /// training data associates "SpriteKit scene" with those
    /// languages. This block asserts unambiguously that scripts are
    /// HypeTalk, shows what valid HypeTalk looks like, and calls
    /// out the specific non-HypeTalk tokens we refuse to accept.
    /// It's deliberately short — a full guide would eat context
    /// budget — but long enough to steer the model.
    static let hypeTalkScriptLanguageRules: String = """
    SCRIPT LANGUAGE — READ THIS BEFORE WRITING ANY script / sceneScript FIELD:

    Every `script` or `sceneScript` field in this schema MUST be valid HypeTalk. \
    HypeTalk is an English-like, HyperCard-descended scripting language. \
    It is NOT JavaScript, NOT Swift, NOT Objective-C, NOT TypeScript, NOT Lua, \
    NOT Python. If you aren't sure, leave the field empty ("") — a blank \
    script is always better than a wrong-language script.

    Every HypeTalk script is a sequence of handler blocks:
        on <handlerName> [paramNames]
            <statements>
        end <handlerName>
    Common handlers: mouseUp, mouseDown, openCard, closeCard, idle, \
    keyDown, keyUp, beginContact, endContact.

    Statement forms are English-like:
        put "Hello" into field "greeting"
        set the loc of sprite "ball" to "300,200"
        go next
        add 1 to counter
        if the name of me is "player" then answer "Hi"
        repeat with i from 1 to 10 ... end repeat

    Variables do NOT require declaration — just use them. Use `global name` \
    inside a handler to share across handlers.

    FORBIDDEN TOKENS (if any of these appear in a script field, Hype will reject the whole script):
        var x = 1            — no `var` / `let` / `const` keyword
        function() { ... }   — no JavaScript `function(` syntax, no `{` `}` blocks
        self.childNode(...)  — no `self.`
        SKAction / SKNode / SKPhysicsBody / SKSpriteNode — (Swift SpriteKit API, not HypeTalk)
        (x) => { ... }       — no arrow functions
        ;                    — no semicolons at end of statements
        addEventListener / onKeyDown = function(...)  — not HypeTalk event wiring

    If the user asked for keyboard input, use an `on keyDown` handler and read \
    `the key` (HypeTalk's keyDown event variable). For collisions, use an \
    `on beginContact` handler. Keep every handler short — 3–10 statements max.
    """

    /// Override `areaName` / `sceneName` when the user prompt explicitly
    /// names an existing sprite area or scene. Prevents the model-level
    /// confusion of scene vs. area names from targeting the wrong part.
    static func applyUserRequestOverrides(
        to proposal: inout SceneCreateProposal,
        userRequest: String,
        document: HypeDocument,
        currentCardId: UUID
    ) {
        let lower = userRequest.lowercased()
        let areas = document.effectivePartsForCard(currentCardId).filter {
            $0.partType == .spriteArea
        }

        // 1) If the prompt names a real sprite area, lock areaName to it.
        if let named = areas.first(where: {
            !$0.name.isEmpty && lower.contains($0.name.lowercased())
        }) {
            proposal.areaName = named.name
            // 2) And if that area has a scene whose name appears in the
            // prompt too, use that — otherwise use the active scene.
            if let spec = named.spriteAreaSpecModel {
                let sceneNames = spec.scenes.map { $0.scene.name.lowercased() }
                if let match = sceneNames.first(where: {
                    !$0.isEmpty && lower.contains($0)
                }) {
                    proposal.sceneName = match
                } else if proposal.sceneName.isEmpty, let active = spec.activeScene {
                    proposal.sceneName = active.name
                }
            }
        } else if proposal.areaName.isEmpty,
                  let only = areas.first, areas.count == 1 {
            // 3) No mention in prompt and nothing from the model, but
            // there's exactly one sprite area on this card — use it.
            proposal.areaName = only.name
            if proposal.sceneName.isEmpty,
               let active = only.spriteAreaSpecModel?.activeScene {
                proposal.sceneName = active.name
            }
        }
    }

    public func repairProposal(
        userRequest: String,
        spriteAreaName: String,
        scene: SceneSpec,
        repository: SpriteRepository
    ) async throws -> SceneRepairProposal {
        let diagnostics = scene.diagnostics(using: repository)
        let prompt = """
        Diagnose and repair a Hype SpriteKit scene. Prefer minimal, validated changes.

        USER REQUEST:
        \(userRequest)

        TARGET SPRITE AREA:
        \(spriteAreaName)

        SCENE JSON:
        \(scene.toJSON())

        LOCAL DIAGNOSTICS:
        \(Self.jsonString(for: diagnostics))
        """
        let messages = [
            OllamaMessage(
                role: "system",
                content: """
                You are repairing a Hype SpriteKit scene. Output only JSON matching the provided schema.
                Use the diff to propose focused fixes. Prefer updateNodes/removeNodeIds/sceneUpdates over addNodes unless a new node is required.
                Treat sprite-area requests as scene and node authoring, not generic part scripting.
                Do not use sceneUpdates.script or node script changes to fake movement, bouncing, gravity, collisions, or staying inside bounds when SpriteKit physics can express it.
                If keyboard input is requested, use event handlers only to adjust velocity, forces, or actions on SpriteKit nodes.

                \(Self.hypeTalkScriptLanguageRules)
                """
            ),
            OllamaMessage(role: "user", content: prompt)
        ]

        let result: (response: OllamaChatResponse, decoded: SceneRepairProposal) =
            try await client.structuredChat(
                messages: messages,
                format: Self.sceneRepairFormat
            )
        // The caller told us which sprite area to target. Authoritatively
        // overwrite whatever the model returned (or whatever the lenient
        // decoder filled in for a missing field) so downstream code can
        // always find the right part. Without this, a model that omits
        // `areaName` triggers the fallback "main" and applyRepairProposal
        // surfaces "Could not find sprite area 'main' to repair."
        var proposal = result.decoded
        proposal.areaName = spriteAreaName
        return Self.normalizeRepairProposal(proposal, for: userRequest, currentScene: scene)
    }

    private func sceneContext(document: HypeDocument, currentCardId: UUID) -> String {
        let currentCard = document.cards.first(where: { $0.id == currentCardId })
        let cardName = currentCard?.name.isEmpty == false ? currentCard!.name : "Current Card"
        let spriteAreas = document.effectivePartsForCard(currentCardId).filter { $0.partType == .spriteArea }
        let areaLines = spriteAreas.map { part -> String in
            guard let areaSpec = part.spriteAreaSpecModel,
                  let scene = areaSpec.activeScene else {
                return "Sprite area '\(part.name)' has no active scene."
            }
            return "Sprite area '\(part.name)' active scene '\(scene.name)' size \(Int(scene.size.width))x\(Int(scene.size.height)) with \(scene.allNodes.count) nodes."
        }
        let assetLines = document.spriteRepository.assets.map { asset in
            var line = "\(asset.kind.rawValue) '\(asset.name)'"
            if asset.isTileSet {
                line += " tileset \(asset.tileColumns)x\(asset.tileRows) of \(asset.tileWidth)x\(asset.tileHeight)"
            }
            return line
        }
        return """
        Card: \(cardName)
        Sprite areas: \(areaLines.isEmpty ? "none" : areaLines.joined(separator: " "))
        Repository assets: \(assetLines.isEmpty ? "none" : assetLines.joined(separator: ", "))
        """
    }

    private static func jsonString<T: Encodable>(for value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static func normalizeCreateProposal(_ proposal: SceneCreateProposal, for userRequest: String) -> SceneCreateProposal {
        var normalized = proposal

        // First pass: sanitize every script field so no non-HypeTalk
        // code ever lands in the document. Runs regardless of the
        // physics-bounce path because the bug (JS emitted into
        // node.script / sceneScript) can happen on any request, not
        // just bouncing ones.
        var wrongLanguageCount = 0
        if let clean = sanitizedHypeTalkScript(normalized.scene.sceneScript) {
            if clean != normalized.scene.sceneScript { wrongLanguageCount += 1 }
            normalized.scene.sceneScript = clean
        }
        for index in normalized.scene.nodes.indices {
            if let original = normalized.scene.nodes[index].script,
               let clean = sanitizedHypeTalkScript(original),
               clean != original {
                normalized.scene.nodes[index].script = clean
                wrongLanguageCount += 1
            }
        }
        if wrongLanguageCount > 0 {
            addWrongLanguageWarning(to: &normalized, count: wrongLanguageCount)
        }

        let wantsPhysicsBounce = wantsPhysicsBounce(for: userRequest)

        guard wantsPhysicsBounce else { return normalized }

        normalized.scene.gravity = VectorSpec(dx: 0, dy: 0)
        if isManualMovementScript(normalized.scene.sceneScript) {
            normalized.scene.sceneScript = ""
        }

        if let primaryIndex = normalized.scene.nodes.firstIndex(where: { $0.physicsEnabled && ($0.dynamic ?? true) }) ??
            normalized.scene.nodes.firstIndex(where: { $0.nodeType == .sprite || $0.nodeType == .shape }) {
            normalized.scene.nodes[primaryIndex] = normalizedPhysicsBounceNode(normalized.scene.nodes[primaryIndex])
        } else {
            normalized.scene.nodes.append(defaultBounceNode(in: normalized.scene.size))
        }

        if !normalized.scene.nodes.contains(where: isBoundaryNode) {
            normalized.scene.nodes.append(contentsOf: boundaryNodes(for: normalized.scene.size))
        }

        if !normalized.checklist.contains(where: { $0.key == "physics" }) {
            normalized.checklist.append(
                SceneChecklistItem(
                    key: "physics",
                    title: "Physics Setup",
                    status: .complete,
                    detail: "The moving object uses a physics body and static wall nodes keep it inside the sprite area."
                )
            )
        }
        if !normalized.summary.lowercased().contains("physics") {
            normalized.summary += " Uses SpriteKit physics bodies and boundary walls instead of an idle script."
        }
        return normalized
    }

    static func normalizeRepairProposal(
        _ proposal: SceneRepairProposal,
        for userRequest: String,
        currentScene: SceneSpec
    ) -> SceneRepairProposal {
        var normalized = proposal

        // First pass: sanitize every script field in the diff so no
        // non-HypeTalk code sneaks into the document via repair.
        var wrongLanguageCount = 0
        if var sceneUpdates = normalized.diff.sceneUpdates,
           let existingScript = sceneUpdates.script,
           let clean = sanitizedHypeTalkScript(existingScript),
           clean != existingScript {
            sceneUpdates.script = clean
            normalized.diff.sceneUpdates = sceneUpdates
            wrongLanguageCount += 1
        }
        if var addNodes = normalized.diff.addNodes {
            for index in addNodes.indices {
                if let clean = sanitizedHypeTalkScript(addNodes[index].script),
                   clean != addNodes[index].script {
                    addNodes[index].script = clean
                    wrongLanguageCount += 1
                }
            }
            normalized.diff.addNodes = addNodes
        }
        if var updateNodes = normalized.diff.updateNodes {
            for index in updateNodes.indices {
                if let scriptValue = updateNodes[index].properties["script"],
                   let clean = sanitizedHypeTalkScript(scriptValue),
                   clean != scriptValue {
                    updateNodes[index].properties["script"] = clean
                    wrongLanguageCount += 1
                }
            }
            normalized.diff.updateNodes = updateNodes
        }
        if wrongLanguageCount > 0 {
            let note = "Hype stripped \(wrongLanguageCount) non-HypeTalk script field\(wrongLanguageCount == 1 ? "" : "s") from the plan (JavaScript/Swift code isn't valid in HypeTalk)."
            if !normalized.summary.contains("non-HypeTalk") {
                normalized.summary = normalized.summary.isEmpty ? note : (normalized.summary + " " + note)
            }
        }

        guard wantsPhysicsBounce(for: userRequest) else { return normalized }

        var sceneUpdates = normalized.diff.sceneUpdates ?? SceneUpdate()
        sceneUpdates.gravity = VectorSpec(dx: 0, dy: 0)
        if containsFrameDrivenSceneScript(sceneUpdates.script) {
            sceneUpdates.script = ""
        }
        normalized.diff.sceneUpdates = sceneUpdates

        if let targetId = primaryBounceNodeID(in: currentScene, diff: normalized.diff) {
            upsertBounceNodeUpdate(targetId: targetId, scene: currentScene, diff: &normalized.diff)
        } else {
            normalized.diff.addNodes = (normalized.diff.addNodes ?? []) + [defaultBounceHypeNode(in: currentScene.size)]
        }

        if !sceneHasBoundaryNodes(currentScene) &&
            !(normalized.diff.addNodes ?? []).contains(where: isBoundaryNode) {
            normalized.diff.addNodes = (normalized.diff.addNodes ?? []) + boundaryHypeNodes(for: currentScene.size)
        }

        if !normalized.summary.lowercased().contains("physics") {
            normalized.summary += " Uses SpriteKit physics and boundary nodes instead of an idle script."
        }
        return normalized
    }

    private static func wantsPhysicsBounce(for userRequest: String) -> Bool {
        let lower = userRequest.lowercased()
        return (lower.contains("bounce") || lower.contains("bouncing") || lower.contains("ricochet") || lower.contains("rebound")) &&
            (lower.contains("sprite") || lower.contains("spritearea") || lower.contains("sprite area") || lower.contains("scene"))
    }

    private static func isManualMovementScript(_ script: String) -> Bool {
        let lower = script.lowercased()
        return (lower.contains("on idle") || lower.contains("on frameupdate")) &&
            (lower.contains("set the loc of sprite") || lower.contains("add dx to") || lower.contains("add dy to"))
    }

    /// Best-effort detector for "this script looks like JavaScript /
    /// Swift / Objective-C, not HypeTalk." Local models sometimes
    /// emit wrong-language content even with a corrective system
    /// prompt — this gives us a server-side safety net.
    ///
    /// Returns `true` when any token strongly suggests a different
    /// language AND the script doesn't also look like HypeTalk
    /// (e.g. it doesn't have an `on … end …` handler block). The
    /// combination avoids false positives on HypeTalk that happens
    /// to contain the word "var" in a string literal.
    static func looksLikeNonHypeTalkScript(_ script: String) -> Bool {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()

        // Hard signals — these tokens don't exist in HypeTalk at all
        // and are extremely common in JS / Swift / Obj-C scene code.
        let hardSignals: [String] = [
            "function(", "function (",
            "=>",
            "self.",
            "this.",
            "skphysicsbody", "sknode", "skaction", "skspritenode", "sklabelnode",
            "skshapenode", "skscene", "skfield",
            "addeventlistener",
            "document.", "window.",
            "node.physicsbody", "node.childnode",
            "edgeloopfrom:", "edgeloopfrom(",
            "childnodewithname(",
            "enumeratechildrenwithnodepattern(",
            "categorybitmask",
            "@objc", "nonisolated",
            "console.log(", "print(",
            ".tolowercase()", ".touppercase()",
            "];",  // array close + statement-end, very non-HypeTalk
        ]
        // Soft signals — one of these alone isn't enough because it
        // can occur in HypeTalk identifier names or string literals,
        // but combined with another signal they confirm non-HypeTalk.
        let softSignals: [String] = [
            "var ", "let ", "const ",
            ".foreach(", ".map(", ".filter(",
            "return ",
            ";",   // statement terminator
            "{ ",  // open block with space
            " }",  // close block with space
        ]

        let hardHits = hardSignals.filter { lower.contains($0) }.count
        let softHits = softSignals.filter { lower.contains($0) }.count

        // Any hard signal is enough. A mere soft-signal accumulation
        // needs at least 3 distinct hits to fire, so HypeTalk with a
        // stray `return` or a comment containing `{` doesn't false-
        // positive.
        let probablyNonHypeTalk = hardHits >= 1 || softHits >= 3

        guard probablyNonHypeTalk else { return false }

        // Rescue clause: if the script contains a real HypeTalk
        // handler block (e.g. `on mouseUp ... end mouseUp`), trust
        // it. Otherwise the detector fires.
        if containsHypeTalkHandler(lower) { return false }
        return true
    }

    /// True when the string contains at least one HypeTalk handler
    /// block opening (`on <name>` or `function <name>` — the second
    /// form is HypeTalk's user-defined-function keyword, distinct
    /// from JavaScript's `function(` which has a parenthesis right
    /// after).
    private static func containsHypeTalkHandler(_ lower: String) -> Bool {
        // "on <ident>" at the start of a line, followed somewhere
        // by "end <ident>". A bit fuzzy — intentionally so, because
        // partial decoding leaves half-valid blocks sometimes.
        if let onRange = lower.range(of: #"(^|\n)\s*on\s+[a-z]"#, options: .regularExpression),
           lower.range(of: #"(^|\n)\s*end\s+[a-z]"#, options: .regularExpression, range: onRange.upperBound..<lower.endIndex) != nil {
            return true
        }
        // "function <ident>" with at least one space before the
        // parenthesis, or no parenthesis at all — HypeTalk's user
        // function keyword. JavaScript's `function foo()` also
        // matches but is rare in AI-generated scene code; when it
        // does appear, other hard signals (self. / => / ;) almost
        // always accompany it and trigger the hard path.
        if lower.range(of: #"(^|\n)\s*function\s+[a-z]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// If `script` looks like non-HypeTalk code, return a
    /// placeholder comment explaining why. Otherwise return the
    /// original string untouched. The callback lets the normalizer
    /// count sanitizations so the proposal summary can flag them.
    static func sanitizedHypeTalkScript(_ script: String) -> String? {
        guard !script.isEmpty else { return script }
        if looksLikeNonHypeTalkScript(script) {
            return "-- TODO: rewrite this handler in HypeTalk\n-- (the AI emitted non-HypeTalk code here, which Hype removed for safety)\n"
        }
        return script
    }

    /// Append a checklist entry that tells the user their plan had
    /// non-HypeTalk script fields that were stripped, so they know
    /// to refill those fields themselves.
    private static func addWrongLanguageWarning(
        to proposal: inout SceneCreateProposal,
        count: Int
    ) {
        let detail = "Hype stripped \(count) non-HypeTalk script field\(count == 1 ? "" : "s") from the plan (the model emitted JavaScript / Swift / etc. by mistake). Open each affected node's script and rewrite in HypeTalk — use `on mouseUp / end mouseUp` style handlers."
        if !proposal.checklist.contains(where: { $0.key == "hypetalk-scripts" }) {
            proposal.checklist.append(
                SceneChecklistItem(
                    key: "hypetalk-scripts",
                    title: "Rewrite scripts in HypeTalk",
                    status: .missing,
                    detail: detail
                )
            )
        }
        if !proposal.summary.contains("non-HypeTalk") {
            proposal.summary = proposal.summary.isEmpty
                ? detail
                : proposal.summary + " " + detail
        }
    }

    private static func containsFrameDrivenSceneScript(_ script: String?) -> Bool {
        let lower = script?.lowercased() ?? ""
        return lower.contains("on idle") || lower.contains("on frameupdate")
    }

    private static func normalizedPhysicsBounceNode(_ node: SceneBlueprintNode) -> SceneBlueprintNode {
        var node = node
        node.physicsEnabled = true
        node.dynamic = true
        node.affectedByGravity = false
        node.physicsBodyType = node.physicsBodyType ?? defaultBounceBodyType(for: node)
        node.restitution = max(node.restitution ?? 0.95, 0.95)
        node.friction = min(node.friction ?? 0.05, 0.05)
        node.allowsRotation = node.allowsRotation ?? false
        node.linearDamping = node.linearDamping ?? 0
        if node.velocity == nil {
            node.velocity = VectorSpec(dx: 220, dy: 170)
        }
        if isManualMovementScript(node.script ?? "") {
            node.script = ""
        }
        if node.size == nil {
            node.size = SizeSpec(width: 40, height: 40)
        }
        if node.nodeType == .shape && node.shapeType == nil {
            node.shapeType = .circle
        }
        return node
    }

    private static func defaultBounceNode(in size: SizeSpec) -> SceneBlueprintNode {
        SceneBlueprintNode(
            name: "blue_ball",
            nodeType: .shape,
            position: PointSpec(x: size.width / 2, y: size.height / 2),
            size: SizeSpec(width: 40, height: 40),
            shapeType: .circle,
            fillColor: "#4AA8FF",
            strokeColor: "#1D5FBD",
            lineWidth: 2,
            physicsEnabled: true,
            physicsBodyType: .circle,
            dynamic: true,
            affectedByGravity: false,
            restitution: 0.98,
            friction: 0.02,
            allowsRotation: false,
            linearDamping: 0,
            velocity: VectorSpec(dx: 220, dy: 170)
        )
    }

    private static func isBoundaryNode(_ node: SceneBlueprintNode) -> Bool {
        let lower = node.name.lowercased()
        return (lower.contains("wall") || lower.contains("boundary") || lower.contains("bounds")) &&
            node.physicsEnabled &&
            (node.dynamic == false || node.physicsBodyType == .rect || node.physicsBodyType == .edge)
    }

    private static func boundaryNodes(for size: SizeSpec) -> [SceneBlueprintNode] {
        let thickness = 20.0
        let halfThickness = thickness / 2
        return [
            SceneBlueprintNode(
                name: "_leftWall",
                nodeType: .shape,
                position: PointSpec(x: halfThickness, y: size.height / 2),
                size: SizeSpec(width: thickness, height: size.height),
                alpha: 0,
                isHidden: true,
                shapeType: .rect,
                fillColor: "#000000",
                strokeColor: "#000000",
                lineWidth: 0,
                physicsEnabled: true,
                physicsBodyType: .rect,
                dynamic: false,
                affectedByGravity: false,
                restitution: 1,
                friction: 0,
                allowsRotation: false
            ),
            SceneBlueprintNode(
                name: "_rightWall",
                nodeType: .shape,
                position: PointSpec(x: max(size.width - halfThickness, halfThickness), y: size.height / 2),
                size: SizeSpec(width: thickness, height: size.height),
                alpha: 0,
                isHidden: true,
                shapeType: .rect,
                fillColor: "#000000",
                strokeColor: "#000000",
                lineWidth: 0,
                physicsEnabled: true,
                physicsBodyType: .rect,
                dynamic: false,
                affectedByGravity: false,
                restitution: 1,
                friction: 0,
                allowsRotation: false
            ),
            SceneBlueprintNode(
                name: "_topWall",
                nodeType: .shape,
                position: PointSpec(x: size.width / 2, y: max(size.height - halfThickness, halfThickness)),
                size: SizeSpec(width: size.width, height: thickness),
                alpha: 0,
                isHidden: true,
                shapeType: .rect,
                fillColor: "#000000",
                strokeColor: "#000000",
                lineWidth: 0,
                physicsEnabled: true,
                physicsBodyType: .rect,
                dynamic: false,
                affectedByGravity: false,
                restitution: 1,
                friction: 0,
                allowsRotation: false
            ),
            SceneBlueprintNode(
                name: "_bottomWall",
                nodeType: .shape,
                position: PointSpec(x: size.width / 2, y: halfThickness),
                size: SizeSpec(width: size.width, height: thickness),
                alpha: 0,
                isHidden: true,
                shapeType: .rect,
                fillColor: "#000000",
                strokeColor: "#000000",
                lineWidth: 0,
                physicsEnabled: true,
                physicsBodyType: .rect,
                dynamic: false,
                affectedByGravity: false,
                restitution: 1,
                friction: 0,
                allowsRotation: false
            )
        ]
    }

    private static func defaultBounceBodyType(for node: SceneBlueprintNode) -> PhysicsBodyType {
        if node.nodeType == .shape, node.shapeType == .circle {
            return .circle
        }
        if let size = node.size, abs(size.width - size.height) < 0.5 {
            return .circle
        }
        return .rect
    }

    private static func primaryBounceNodeID(in scene: SceneSpec, diff: SceneDiff) -> UUID? {
        if let updated = diff.updateNodes?.first(where: { scene.node(id: $0.id) != nil }) {
            return updated.id
        }
        if let named = scene.node(named: "blue_ball") {
            return named.id
        }
        if let firstDynamic = scene.allNodes.first(where: {
            ($0.nodeType == .sprite || $0.nodeType == .shape) &&
            ($0.physicsBody?.isDynamic ?? true)
        }) {
            return firstDynamic.id
        }
        return scene.allNodes.first(where: { $0.nodeType == .sprite || $0.nodeType == .shape })?.id
    }

    private static func upsertBounceNodeUpdate(targetId: UUID, scene: SceneSpec, diff: inout SceneDiff) {
        let targetNode = scene.node(id: targetId)
        let bodyType: PhysicsBodyType
        if let node = targetNode {
            bodyType = defaultBounceBodyType(for: node)
        } else {
            bodyType = .circle
        }

        let size = targetNode?.size ?? SizeSpec(width: 40, height: 40)
        var properties = [
            "script": "",
            "physics.enabled": "true",
            "physics.bodyType": bodyType.rawValue,
            "physics.isDynamic": "true",
            "physics.affectedByGravity": "false",
            "physics.restitution": "0.98",
            "physics.friction": "0.02",
            "physics.allowsRotation": "false",
            "physics.linearDamping": "0",
            "physics.velocityX": "220",
            "physics.velocityY": "170",
            "size.width": "\(Int(size.width))",
            "size.height": "\(Int(size.height))"
        ]

        if targetNode?.nodeType == .shape {
            properties["shape.shapeType"] = bodyType == .circle ? "circle" : "rect"
        }

        var updates = diff.updateNodes ?? []
        if let index = updates.firstIndex(where: { $0.id == targetId }) {
            for (key, value) in properties {
                updates[index].properties[key] = value
            }
        } else {
            updates.append(NodeUpdate(id: targetId, properties: properties))
        }
        diff.updateNodes = updates
    }

    private static func sceneHasBoundaryNodes(_ scene: SceneSpec) -> Bool {
        scene.allNodes.contains(where: isBoundaryNode)
    }

    private static func isBoundaryNode(_ node: HypeNodeSpec) -> Bool {
        let lower = node.name.lowercased()
        return (lower.contains("wall") || lower.contains("boundary") || lower.contains("bounds")) &&
            node.physicsBody != nil &&
            (node.physicsBody?.isDynamic == false || node.physicsBody?.bodyType == .rect || node.physicsBody?.bodyType == .edge)
    }

    private static func boundaryHypeNodes(for size: SizeSpec) -> [HypeNodeSpec] {
        let thickness = 20.0
        let halfThickness = thickness / 2
        return [
            HypeNodeSpec(
                name: "_leftWall",
                nodeType: .shape,
                position: PointSpec(x: halfThickness, y: size.height / 2),
                alpha: 0,
                isHidden: true,
                size: SizeSpec(width: thickness, height: size.height),
                shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#000000", strokeColor: "#000000", lineWidth: 0),
                physicsBody: PhysicsBodySpec(
                    bodyType: .rect,
                    isDynamic: false,
                    restitution: 1,
                    friction: 0,
                    affectedByGravity: false,
                    allowsRotation: false
                )
            ),
            HypeNodeSpec(
                name: "_rightWall",
                nodeType: .shape,
                position: PointSpec(x: max(size.width - halfThickness, halfThickness), y: size.height / 2),
                alpha: 0,
                isHidden: true,
                size: SizeSpec(width: thickness, height: size.height),
                shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#000000", strokeColor: "#000000", lineWidth: 0),
                physicsBody: PhysicsBodySpec(
                    bodyType: .rect,
                    isDynamic: false,
                    restitution: 1,
                    friction: 0,
                    affectedByGravity: false,
                    allowsRotation: false
                )
            ),
            HypeNodeSpec(
                name: "_topWall",
                nodeType: .shape,
                position: PointSpec(x: size.width / 2, y: max(size.height - halfThickness, halfThickness)),
                alpha: 0,
                isHidden: true,
                size: SizeSpec(width: size.width, height: thickness),
                shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#000000", strokeColor: "#000000", lineWidth: 0),
                physicsBody: PhysicsBodySpec(
                    bodyType: .rect,
                    isDynamic: false,
                    restitution: 1,
                    friction: 0,
                    affectedByGravity: false,
                    allowsRotation: false
                )
            ),
            HypeNodeSpec(
                name: "_bottomWall",
                nodeType: .shape,
                position: PointSpec(x: size.width / 2, y: halfThickness),
                alpha: 0,
                isHidden: true,
                size: SizeSpec(width: size.width, height: thickness),
                shapeSpec: ShapeNodeSpec(shapeType: .rect, fillColor: "#000000", strokeColor: "#000000", lineWidth: 0),
                physicsBody: PhysicsBodySpec(
                    bodyType: .rect,
                    isDynamic: false,
                    restitution: 1,
                    friction: 0,
                    affectedByGravity: false,
                    allowsRotation: false
                )
            )
        ]
    }

    private static func defaultBounceHypeNode(in size: SizeSpec) -> HypeNodeSpec {
        HypeNodeSpec(
            name: "blue_ball",
            nodeType: .shape,
            position: PointSpec(x: size.width / 2, y: size.height / 2),
            alpha: 1,
            isHidden: false,
            size: SizeSpec(width: 40, height: 40),
            shapeSpec: ShapeNodeSpec(shapeType: .circle, fillColor: "#4AA8FF", strokeColor: "#1D5FBD", lineWidth: 2),
            physicsBody: PhysicsBodySpec(
                bodyType: .circle,
                isDynamic: true,
                restitution: 0.98,
                friction: 0.02,
                affectedByGravity: false,
                allowsRotation: false,
                linearDamping: 0,
                velocityX: 220,
                velocityY: 170
            )
        )
    }

    private static func defaultBounceBodyType(for node: HypeNodeSpec) -> PhysicsBodyType {
        if node.nodeType == .shape, node.shapeSpec?.shapeType == .circle {
            return .circle
        }
        if let size = node.size, abs(size.width - size.height) < 0.5 {
            return .circle
        }
        return .rect
    }

    private static var sceneCreateFormat: OllamaResponseFormat {
        .schema(OllamaJSONSchema(object: [
            "type": "object",
            "required": ["areaName", "sceneName", "createSpriteAreaIfMissing", "summary", "checklist", "scene"],
            "properties": [
                "areaName": ["type": "string"],
                "sceneName": ["type": "string"],
                "createSpriteAreaIfMissing": ["type": "boolean"],
                "summary": ["type": "string"],
                "checklist": [
                    "type": "array",
                    "items": checklistItemSchema()
                ],
                "scene": sceneBlueprintSchema()
            ]
        ]))
    }

    private static var sceneRepairFormat: OllamaResponseFormat {
        .schema(OllamaJSONSchema(object: [
            "type": "object",
            "required": ["areaName", "summary", "issues", "diff"],
            "properties": [
                "areaName": ["type": "string"],
                "summary": ["type": "string"],
                "issues": [
                    "type": "array",
                    "items": diagnosticIssueSchema()
                ],
                "diff": sceneDiffSchema()
            ]
        ]))
    }

    private static func checklistItemSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["key", "title", "status", "detail"],
            "properties": [
                "key": ["type": "string"],
                "title": ["type": "string"],
                "status": [
                    "type": "string",
                    "enum": ["complete", "recommended", "missing"]
                ],
                "detail": ["type": "string"]
            ]
        ]
    }

    private static func diagnosticIssueSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["severity", "message"],
            "properties": [
                "severity": [
                    "type": "string",
                    "enum": ["info", "warning", "error"]
                ],
                "message": ["type": "string"]
            ]
        ]
    }

    private static func pointSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["x", "y"],
            "properties": [
                "x": ["type": "number"],
                "y": ["type": "number"]
            ]
        ]
    }

    private static func sizeSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["width", "height"],
            "properties": [
                "width": ["type": "number"],
                "height": ["type": "number"]
            ]
        ]
    }

    private static func vectorSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["dx", "dy"],
            "properties": [
                "dx": ["type": "number"],
                "dy": ["type": "number"]
            ]
        ]
    }

    private static func sceneBlueprintSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["size", "backgroundColor", "gravity", "scaleMode", "showsPhysics", "showsFPS", "showsNodeCount", "sceneScript", "nodes"],
            "properties": [
                "size": sizeSchema(),
                "backgroundColor": ["type": "string"],
                "gravity": vectorSchema(),
                "scaleMode": [
                    "type": "string",
                    "enum": ["fill", "aspectFill", "aspectFit", "resizeFill"]
                ],
                "showsPhysics": ["type": "boolean"],
                "showsFPS": ["type": "boolean"],
                "showsNodeCount": ["type": "boolean"],
                "sceneScript": ["type": "string"],
                "nodes": [
                    "type": "array",
                    "items": sceneBlueprintNodeSchema()
                ]
            ]
        ]
    }

    private static func sceneBlueprintNodeSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["name", "nodeType", "position", "physicsEnabled"],
            "properties": [
                "name": ["type": "string"],
                "nodeType": [
                    "type": "string",
                    "enum": ["sprite", "group", "label", "shape", "emitter", "audio", "tileMap", "camera", "video", "crop", "effect", "light"]
                ],
                "position": pointSchema(),
                "size": sizeSchema(),
                "alpha": ["type": "number"],
                "isHidden": ["type": "boolean"],
                "assetName": ["type": "string"],
                "text": ["type": "string"],
                "fontName": ["type": "string"],
                "fontSize": ["type": "number"],
                "fontColor": ["type": "string"],
                "shapeType": [
                    "type": "string",
                    "enum": ["rect", "circle", "ellipse", "path"]
                ],
                "fillColor": ["type": "string"],
                "strokeColor": ["type": "string"],
                "lineWidth": ["type": "number"],
                "cornerRadius": ["type": "number"],
                "parentName": ["type": "string"],
                "physicsEnabled": ["type": "boolean"],
                "physicsBodyType": [
                    "type": "string",
                    "enum": ["circle", "rect", "texture", "none", "edge"]
                ],
                "dynamic": ["type": "boolean"],
                "affectedByGravity": ["type": "boolean"],
                "restitution": ["type": "number"],
                "friction": ["type": "number"],
                "allowsRotation": ["type": "boolean"],
                "linearDamping": ["type": "number"],
                "velocity": vectorSchema(),
                "cameraTarget": ["type": "string"],
                "tileMapColumns": ["type": "integer"],
                "tileMapRows": ["type": "integer"],
                "tileSetAssetName": ["type": "string"],
                "tileWidth": ["type": "number"],
                "tileHeight": ["type": "number"],
                "audioAssetName": ["type": "string"],
                "videoAssetName": ["type": "string"],
                "particleColor": ["type": "string"],
                "script": ["type": "string"]
            ]
        ]
    }

    private static func sceneDiffSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "addNodes": [
                    "type": "array",
                    "items": hypeNodeSpecSchema()
                ],
                "removeNodeIds": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "updateNodes": [
                    "type": "array",
                    "items": nodeUpdateSchema()
                ],
                "sceneUpdates": sceneUpdateSchema()
            ]
        ]
    }

    private static func sceneUpdateSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "size": sizeSchema(),
                "gravity": vectorSchema(),
                "backgroundColor": ["type": "string"],
                "script": ["type": "string"],
                "isPaused": ["type": "boolean"],
                "showsPhysics": ["type": "boolean"],
                "showsFPS": ["type": "boolean"],
                "showsNodeCount": ["type": "boolean"],
                "scaleMode": [
                    "type": "string",
                    "enum": ["fill", "aspectFill", "aspectFit", "resizeFill"]
                ]
            ]
        ]
    }

    private static func nodeUpdateSchema() -> [String: Any] {
        [
            "type": "object",
            "required": ["id", "properties"],
            "properties": [
                "id": ["type": "string"],
                "properties": [
                    "type": "object",
                    "additionalProperties": ["type": "string"]
                ],
                "removeAllActions": ["type": "boolean"],
                "removeChildIds": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "addChildren": [
                    "type": "array",
                    "items": hypeNodeSpecSchema()
                ]
            ]
        ]
    }

    private static func hypeNodeSpecSchema() -> [String: Any] {
        [
            "type": "object",
            "required": [
                "id", "name", "nodeType", "position", "zPosition", "rotation",
                "xScale", "yScale", "alpha", "isHidden", "actions", "children", "script"
            ],
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "nodeType": [
                    "type": "string",
                    "enum": ["sprite", "group", "label", "shape", "emitter", "audio", "tileMap", "camera", "video", "crop", "effect", "light"]
                ],
                "position": pointSchema(),
                "zPosition": ["type": "number"],
                "rotation": ["type": "number"],
                "xScale": ["type": "number"],
                "yScale": ["type": "number"],
                "alpha": ["type": "number"],
                "isHidden": ["type": "boolean"],
                "assetRef": [
                    "type": "object",
                    "required": ["id", "name", "mimeType"],
                    "properties": [
                        "id": ["type": "string"],
                        "name": ["type": "string"],
                        "mimeType": ["type": "string"]
                    ]
                ],
                "size": sizeSchema(),
                "text": ["type": "string"],
                "fontName": ["type": "string"],
                "fontSize": ["type": "number"],
                "fontColor": ["type": "string"],
                "shapeSpec": [
                    "type": "object",
                    "properties": [
                        "shapeType": [
                            "type": "string",
                            "enum": ["rect", "circle", "ellipse", "path"]
                        ],
                        "fillColor": ["type": "string"],
                        "strokeColor": ["type": "string"],
                        "lineWidth": ["type": "number"],
                        "cornerRadius": ["type": "number"]
                    ]
                ],
                "tileMapSpec": [
                    "type": "object",
                    "properties": [
                        "columns": ["type": "integer"],
                        "rows": ["type": "integer"],
                        "tileWidth": ["type": "number"],
                        "tileHeight": ["type": "number"],
                        "tileSetColumns": ["type": "integer"]
                    ]
                ],
                "cameraTarget": ["type": "string"],
                "physicsBody": [
                    "type": "object",
                    "properties": [
                        "bodyType": [
                            "type": "string",
                            "enum": ["circle", "rect", "texture", "none", "edge"]
                        ],
                        "isDynamic": ["type": "boolean"],
                        "affectedByGravity": ["type": "boolean"],
                        "allowsRotation": ["type": "boolean"],
                        "restitution": ["type": "number"],
                        "friction": ["type": "number"],
                        "linearDamping": ["type": "number"],
                        "velocityX": ["type": "number"],
                        "velocityY": ["type": "number"]
                    ]
                ],
                "actions": [
                    "type": "array",
                    "items": ["type": "object"]
                ],
                "children": [
                    "type": "array",
                    "items": ["type": "object"]
                ],
                "script": ["type": "string"]
            ]
        ]
    }
}
