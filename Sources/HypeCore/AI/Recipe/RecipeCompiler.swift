import Foundation

// MARK: - RecipeCompilationResult

/// The complete output of compiling a `GameRecipe`.
public struct RecipeCompilationResult: Sendable {
    /// Compiled `HypeNodeSpec` entries for all recipe entities.
    public var nodes: [HypeNodeSpec]
    /// All node names owned by this recipe compilation; used by `merge` to
    /// identify which nodes to replace on recompilation.
    public var recipeOwnedNodeNames: Set<String>
    /// A complete HypeTalk script for the scene, wrapped between
    /// `-- HYPE-RECIPE-BEGIN v1` and `-- HYPE-RECIPE-END` markers.
    /// Always guaranteed to parse (self-validated; safe fallback on failure).
    public var sceneScript: String
    /// Human-readable diagnostics (name conflicts, missing assets, etc.).
    public var diagnostics: [String]

    public init(
        nodes: [HypeNodeSpec] = [],
        recipeOwnedNodeNames: Set<String> = [],
        sceneScript: String = "",
        diagnostics: [String] = []
    ) {
        self.nodes = nodes
        self.recipeOwnedNodeNames = recipeOwnedNodeNames
        self.sceneScript = sceneScript
        self.diagnostics = diagnostics
    }
}

// MARK: - RecipeCompiler

/// Deterministic compiler that lowers a `GameRecipe` into `HypeNodeSpec` entries
/// and a self-validated HypeTalk scene script.
///
/// Rules:
/// - Pure value-in / value-out: no AppKit, no live objects, no Date/random.
/// - All multi-instance position jitter is a deterministic function of index.
/// - Every emitted script is self-validated via `Lexer` + `Parser`; an invalid
///   script is replaced with a safe minimal fallback and a diagnostic is appended.
/// - At most one handler per event (sceneDidLoad, keyDown, keyUp, beginContact,
///   endContact, frameUpdate).
public enum RecipeCompiler {

    // MARK: - Markers

    private static let beginMarker = "-- HYPE-RECIPE-BEGIN v1 (generated — edits between these markers are overwritten by Build)"
    private static let endMarker   = "-- HYPE-RECIPE-END"

    // MARK: - compile

    /// Compile a `GameRecipe` into nodes + validated HypeTalk script.
    public static func compile(
        _ recipe: GameRecipe,
        repository: AssetRepository
    ) -> RecipeCompilationResult {

        var diagnostics: [String] = []

        // Guard: empty recipe
        if recipe.entities.isEmpty {
            diagnostics.append("Recipe has no entities; compiled to an empty scene.")
            let script = wrapScript(handlers: "on sceneDidLoad\n  -- empty recipe\nend sceneDidLoad")
            return RecipeCompilationResult(
                nodes: [],
                recipeOwnedNodeNames: [],
                sceneScript: script,
                diagnostics: diagnostics
            )
        }

        // MARK: 1. Build nodes

        // Cap total entities processed to prevent compile-time DoS.
        // Max 200 distinct entity definitions; excess emit a diagnostic.
        let entitiesToProcess: [GameEntity]
        if recipe.entities.count > 200 {
            diagnostics.append("Recipe has \(recipe.entities.count) entities; only the first 200 are compiled (cap: 200).")
            entitiesToProcess = Array(recipe.entities.prefix(200))
        } else {
            entitiesToProcess = recipe.entities
        }

        var nodes: [HypeNodeSpec] = []
        var usedNames: Set<String> = []
        var ownedNames: Set<String> = []

        for entity in entitiesToProcess {
            let newNodes = buildNodes(
                for: entity,
                recipe: recipe,
                repository: repository,
                usedNames: &usedNames,
                ownedNames: &ownedNames,
                diagnostics: &diagnostics
            )
            nodes.append(contentsOf: newNodes)
        }

        // MARK: 2. Gather all behavior contributions

        // Map entity name -> list of contributions for that entity
        var allContributions: [(entityName: String, contrib: BehaviorContribution)] = []
        for entity in entitiesToProcess {
            let instanceNames = instanceNamesFor(entity)
            // Contributions reference the base entity name; the script operates
            // on those names (for count==1) or on dynamically-created names
            // (for spawners). For count>1 static entities, we generate per-instance
            // contributions below.
            for behavior in entity.behaviors {
                var contrib = BehaviorLibrary.contribution(for: behavior, entity: entity, recipe: recipe)
                // For multi-count non-spawner entities, replicate frame/contact lines per instance.
                if entity.count > 1 && !isSpawnerBehavior(behavior.kind) {
                    contrib = replicateForInstances(contrib, entity: entity, instanceNames: instanceNames)
                }
                allContributions.append((entityName: entity.name, contrib: contrib))
            }
        }

        // MARK: 2b. Gather rule contributions and append them to allContributions

        let ruleContribs = ruleContributions(for: recipe, diagnostics: &diagnostics)
        for contrib in ruleContribs {
            allContributions.append((entityName: "--rule--", contrib: contrib))
        }

        // MARK: 3. Compose handlers

        // Collect all globals
        var allGlobals: [String] = ["gameOver"]
        let state = recipe.gameState
        if state.trackScore  { allGlobals.append("score") }
        if state.trackLives  { allGlobals.append("lives") }
        if state.trackLevel  { allGlobals.append("level") }
        if state.trackTimer  { allGlobals.append("gameTimer") }

        for (_, contrib) in allContributions {
            allGlobals.append(contentsOf: contrib.requiredGlobals)
        }
        let globalList = stableUnique(allGlobals)

        // sceneDidLoad lines
        var didLoadLines: [String] = []
        didLoadLines.append("put \"false\" into gameOver")
        if state.trackScore  { didLoadLines.append("put \(state.initialScore) into score") }
        if state.trackLives  { didLoadLines.append("put \(state.initialLives) into lives") }
        if state.trackLevel  { didLoadLines.append("put \(state.initialLevel) into level") }
        if state.trackTimer  { didLoadLines.append("put \(fmt(state.initialTimerSeconds)) into gameTimer") }

        // HUD initialization
        if let scoreHUD = state.scoreHUDEntityName {
            let safeHUD = sanitizedLiteral(scoreHUD)
            let rawText = recipe.entities.first(where: { $0.name == scoreHUD })?.initialText ?? "Score: 0"
            let initText = sanitizedLiteral(rawText)
            didLoadLines.append("set the text of label \"\(safeHUD)\" to \"\(initText)\"")
        }
        if let livesHUD = state.livesHUDEntityName {
            let safeHUD = sanitizedLiteral(livesHUD)
            let rawText = recipe.entities.first(where: { $0.name == livesHUD })?.initialText ?? "Lives: \(state.initialLives)"
            let initText = sanitizedLiteral(rawText)
            didLoadLines.append("set the text of label \"\(safeHUD)\" to \"\(initText)\"")
        }
        if let statusHUD = state.statusHUDEntityName {
            let safeHUD = sanitizedLiteral(statusHUD)
            let rawText = recipe.entities.first(where: { $0.name == statusHUD })?.initialText ?? ""
            let initText = sanitizedLiteral(rawText)
            didLoadLines.append("set the text of label \"\(safeHUD)\" to \"\(initText)\"")
        }

        for (_, contrib) in allContributions {
            didLoadLines.append(contentsOf: contrib.sceneDidLoad)
        }

        // keyDown / keyUp — group by key
        var keyDownByKey: [String: [String]] = [:]
        var keyUpByKey:   [String: [String]] = [:]
        for (_, contrib) in allContributions {
            for branch in contrib.keyDown {
                keyDownByKey[branch.key, default: []].append(contentsOf: branch.lines)
            }
            for branch in contrib.keyUp {
                keyUpByKey[branch.key, default: []].append(contentsOf: branch.lines)
            }
        }

        // beginContact / endContact — per-branch
        var beginContactBranches: [ContactBranch] = []
        var endContactBranches:   [ContactBranch] = []
        for (_, contrib) in allContributions {
            beginContactBranches.append(contentsOf: contrib.beginContact)
            endContactBranches.append(contentsOf: contrib.endContact)
        }

        // frameUpdate lines
        var frameUpdateLines: [String] = []
        for (_, contrib) in allContributions {
            frameUpdateLines.append(contentsOf: contrib.frameUpdate)
        }

        // GameState win/lose conditions contribute additional frameUpdate checks
        frameUpdateLines.append(contentsOf: winLoseFrameLines(
            state: recipe.gameState,
            recipe: recipe
        ))

        // MARK: 4. Render handlers

        var handlerParts: [String] = []

        // sceneDidLoad
        if !didLoadLines.isEmpty {
            let h = renderHandler(
                name: "sceneDidLoad",
                args: [],
                globals: globalList,
                body: didLoadLines
            )
            handlerParts.append(h)
        }

        // keyDown
        if !keyDownByKey.isEmpty {
            let body = renderKeyBranches(keyDownByKey) + [
                // Allow no movement during game over.
            ]
            // Prepend game-over gate
            let gated = ["if gameOver is \"true\" then", "  exit keyDown", "end if"] + body
            let h = renderHandler(name: "keyDown", args: [], globals: globalList, body: gated)
            handlerParts.append(h)
        }

        // keyUp
        if !keyUpByKey.isEmpty {
            let body = renderKeyBranches(keyUpByKey)
            let h = renderHandler(name: "keyUp", args: [], globals: globalList, body: body)
            handlerParts.append(h)
        }

        // beginContact
        if !beginContactBranches.isEmpty {
            var body: [String] = []
            body.append("if gameOver is \"true\" then")
            body.append("  exit beginContact")
            body.append("end if")
            for branch in beginContactBranches {
                body.append("if \(branch.otherPredicate) then")
                for line in branch.lines {
                    body.append("  \(line)")
                }
                body.append("end if")
            }
            let h = renderHandler(name: "beginContact", args: ["otherName"], globals: globalList, body: body)
            handlerParts.append(h)
        }

        // endContact
        if !endContactBranches.isEmpty {
            var body: [String] = []
            for branch in endContactBranches {
                body.append("if \(branch.otherPredicate) then")
                for line in branch.lines {
                    body.append("  \(line)")
                }
                body.append("end if")
            }
            let h = renderHandler(name: "endContact", args: ["otherName"], globals: globalList, body: body)
            handlerParts.append(h)
        }

        // frameUpdate
        if !frameUpdateLines.isEmpty {
            let gated = ["if gameOver is \"true\" then", "  exit frameUpdate", "end if"] + frameUpdateLines
            let h = renderHandler(name: "frameUpdate", args: ["deltaTime"], globals: globalList, body: gated)
            handlerParts.append(h)
        }

        let allHandlers = handlerParts.joined(separator: "\n\n")
        let wrappedScript = wrapScript(handlers: allHandlers)

        // MARK: 5. Self-validate script
        let validatedScript: String
        if let parseError = scriptParseError(wrappedScript) {
            diagnostics.append("Recipe compiler emitted an invalid script: \(parseError). Using safe fallback.")
            assertionFailure("RecipeCompiler produced an invalid script: \(parseError)\n\nScript:\n\(wrappedScript)")
            validatedScript = wrapScript(handlers: "on sceneDidLoad\n  -- recipe produced an invalid script; see diagnostics\nend sceneDidLoad")
        } else {
            validatedScript = wrappedScript
        }

        return RecipeCompilationResult(
            nodes: nodes,
            recipeOwnedNodeNames: ownedNames,
            sceneScript: validatedScript,
            diagnostics: diagnostics
        )
    }

    // MARK: - merge

    /// Merge a compiled result into an existing `SceneSpec`.
    ///
    /// - Replaces nodes whose names are in `result.recipeOwnedNodeNames`.
    /// - Inserts new recipe nodes that don't exist yet.
    /// - Preserves nodes not owned by the recipe.
    /// - For the script: replaces only the `-- HYPE-RECIPE-BEGIN`…`-- HYPE-RECIPE-END`
    ///   region, preserving any text before or after. If no markers exist, inserts
    ///   the recipe region at the top and keeps existing content below a separator.
    public static func merge(_ result: RecipeCompilationResult, into scene: inout SceneSpec) {
        // Merge nodes: remove recipe-owned nodes, then insert new recipe nodes.
        scene.nodes.removeAll { result.recipeOwnedNodeNames.contains($0.name) }
        scene.nodes.append(contentsOf: result.nodes)

        // Merge script.
        scene.script = mergeScript(result.sceneScript, into: scene.script)
    }

    // MARK: - Private: Node building

    private static func buildNodes(
        for entity: GameEntity,
        recipe: GameRecipe,
        repository: AssetRepository,
        usedNames: inout Set<String>,
        ownedNames: inout Set<String>,
        diagnostics: inout [String]
    ) -> [HypeNodeSpec] {

        // Cap per-entity count to prevent compile-time DoS via huge count values.
        // Max 500 nodes per entity; values above the cap emit a diagnostic.
        let rawCount = max(1, entity.count)
        let count: Int
        if rawCount > 500 {
            diagnostics.append("Entity '\(entity.name)' count \(rawCount) exceeds cap of 500; clamped to 500.")
            count = 500
        } else {
            count = rawCount
        }
        var nodes: [HypeNodeSpec] = []

        for i in 0..<count {
            let name = instanceName(entity: entity, index: i, count: count)
            // Deduplicate names across entities.
            var finalName = name
            if usedNames.contains(finalName) {
                var suffix = 2
                while usedNames.contains("\(finalName)_\(suffix)") { suffix += 1 }
                diagnostics.append("Entity name '\(finalName)' conflicts; renamed to '\(finalName)_\(suffix)'.")
                finalName = "\(finalName)_\(suffix)"
            }
            usedNames.insert(finalName)
            ownedNames.insert(finalName)

            let position = instancePosition(entity: entity, index: i, count: count, sceneSize: recipe.sceneSize)

            // Resolve art asset
            let assetRef: AssetRef? = resolveAsset(entity: entity, recipe: recipe, repository: repository, diagnostics: &diagnostics)

            // Build physics body
            var physicsBody = RolePhysics.base(for: entity.role, size: entity.size)
            for behavior in entity.behaviors {
                let contrib = BehaviorLibrary.contribution(for: behavior, entity: entity, recipe: recipe)
                if let patch = contrib.physics, var body = physicsBody {
                    physicsBody = patch.apply(to: body)
                } else if let patch = contrib.physics {
                    // If RolePhysics returned nil but behavior wants a body, create a default.
                    let defaultBody = PhysicsBodySpec(
                        bodyType: patch.bodyType ?? .rect,
                        isDynamic: patch.isDynamic ?? true,
                        categoryBitmask: RolePhysics.category(for: entity.role),
                        contactTestBitmask: RolePhysics.contactMask(for: entity.role),
                        collisionBitmask: 0,
                        restitution: patch.restitution ?? 0.2,
                        friction: patch.friction ?? 0.2,
                        affectedByGravity: patch.affectedByGravity ?? false,
                        allowsRotation: patch.allowsRotation ?? false
                    )
                    physicsBody = defaultBody
                }
                _ = physicsBody // ensure assigned
            }

            // HUD entities become label nodes
            if entity.role == .hud {
                let node = HypeNodeSpec(
                    name: finalName,
                    nodeType: .label,
                    position: position,
                    zPosition: entity.zPosition,
                    text: entity.initialText ?? "",
                    fontName: "Helvetica-Bold",
                    fontSize: entity.fontSize ?? 20,
                    fontColor: entity.fontColor ?? "#FFFFFF",
                    physicsBody: nil,
                    actions: [],
                    script: ""
                )
                nodes.append(node)
            } else if let assetRef {
                // Sprite node with resolved asset
                var actionsList: [ActionSpec] = []
                for behavior in entity.behaviors {
                    let contrib = BehaviorLibrary.contribution(for: behavior, entity: entity, recipe: recipe)
                    actionsList.append(contentsOf: contrib.actions)
                }
                let node = HypeNodeSpec(
                    name: finalName,
                    nodeType: .sprite,
                    position: position,
                    zPosition: entity.zPosition,
                    assetRef: assetRef,
                    size: entity.size,
                    physicsBody: physicsBody,
                    actions: actionsList,
                    script: ""
                )
                nodes.append(node)
            } else {
                // Shape node (placeholder)
                var actionsList: [ActionSpec] = []
                for behavior in entity.behaviors {
                    let contrib = BehaviorLibrary.contribution(for: behavior, entity: entity, recipe: recipe)
                    actionsList.append(contentsOf: contrib.actions)
                }
                let fillColor = entity.placeholderColor ?? rolePlaceholderColor(entity.role)
                let shapeSpec = ShapeNodeSpec(
                    shapeType: .rect,
                    fillColor: fillColor,
                    strokeColor: "#000000",
                    lineWidth: 1
                )
                let node = HypeNodeSpec(
                    name: finalName,
                    nodeType: .shape,
                    position: position,
                    zPosition: entity.zPosition,
                    size: entity.size,
                    shapeSpec: shapeSpec,
                    physicsBody: physicsBody,
                    actions: actionsList,
                    script: ""
                )
                nodes.append(node)
            }
        }

        return nodes
    }

    private static func instanceName(entity: GameEntity, index: Int, count: Int) -> String {
        // Sanitize at the boundary so all script references and node names agree.
        let safe = sanitizedLiteral(entity.name)
        return count > 1 ? "\(safe)_\(index + 1)" : safe
    }

    private static func instanceNamesFor(_ entity: GameEntity) -> [String] {
        // Use the same cap as buildNodes (500) so the replication loop is bounded.
        let cappedCount = min(max(1, entity.count), 500)
        return (0..<cappedCount).map { instanceName(entity: entity, index: $0, count: cappedCount) }
    }

    /// Deterministic jitter: spread instances across the scene in a row.
    private static func instancePosition(entity: GameEntity, index: Int, count: Int, sceneSize: SizeSpec) -> PointSpec {
        guard count > 1 else { return entity.position }
        // Space instances evenly across the X axis, maintaining the Y from the recipe.
        let step = sceneSize.width / Double(count + 1)
        let x = step * Double(index + 1)
        return PointSpec(x: x, y: entity.position.y)
    }

    private static func resolveAsset(
        entity: GameEntity,
        recipe: GameRecipe,
        repository: AssetRepository,
        diagnostics: inout [String]
    ) -> AssetRef? {
        guard let artRoleRef = entity.artRoleRef else { return nil }
        // Find the ArtRoleBinding for this artRoleRef.
        guard let binding = recipe.artRoles.first(where: { $0.role == artRoleRef }) else { return nil }
        guard let assetName = binding.assetName else { return nil }
        guard let asset = repository.asset(byName: assetName) else {
            diagnostics.append("Entity '\(entity.name)' references art role '\(artRoleRef)' bound to asset '\(assetName)', which is not in the repository. Using placeholder shape.")
            return nil
        }
        return repository.assetRef(for: asset)
    }

    private static func rolePlaceholderColor(_ role: EntityRole) -> String {
        switch role {
        case .player:      return "#4488FF"
        case .enemy:       return "#FF4422"
        case .collectible: return "#FFD700"
        case .hazard:      return "#FF6600"
        case .goal:        return "#00FF88"
        case .wall:        return "#888888"
        case .projectile:  return "#FF88FF"
        case .spawner:     return "#444444"
        case .hud:         return "#FFFFFF"
        case .decoration:  return "#AAAAAA"
        case .background:  return "#222233"
        }
    }

    // MARK: - Private: Handler rendering

    private static func renderHandler(
        name: String,
        args: [String],
        globals: [String],
        body: [String]
    ) -> String {
        var lines: [String] = []
        let signature = args.isEmpty ? "on \(name)" : "on \(name) \(args.joined(separator: ", "))"
        lines.append(signature)
        if !globals.isEmpty {
            lines.append("  global \(globals.joined(separator: ", "))")
        }
        for line in body {
            lines.append("  \(line)")
        }
        lines.append("end \(name)")
        return lines.joined(separator: "\n")
    }

    private static func renderKeyBranches(_ byKey: [String: [String]]) -> [String] {
        var result: [String] = []
        // Sort keys for deterministic output.
        for key in byKey.keys.sorted() {
            guard let lines = byKey[key], !lines.isEmpty else { continue }
            result.append("if the key is \"\(key)\" then")
            for line in lines {
                result.append("  \(line)")
            }
            result.append("end if")
        }
        return result
    }

    private static func wrapScript(handlers: String) -> String {
        [beginMarker, handlers, endMarker].joined(separator: "\n")
    }

    // MARK: - Private: Win/lose conditions from GameState

    private static func winLoseFrameLines(state: GameState, recipe: GameRecipe) -> [String] {
        var lines: [String] = []

        for cond in state.winConditions {
            switch cond.kind {
            case .reachScore:
                if let t = cond.scoreThreshold {
                    let msg = sanitizedLiteral(cond.statusMessage ?? "You Win!")
                    lines.append("if score >= \(t) then")
                    lines.append("  if gameOver is not \"true\" then")
                    lines.append("    put \"true\" into gameOver")
                    lines.append("    set the text of label \"status\" to \"\(msg)\"")
                    lines.append("  end if")
                    lines.append("end if")
                }
            case .allCollected:
                // Check score as proxy (simplified: if all collectibles have been removed,
                // the score matches their total point value). Emit a node-count check.
                let msg = sanitizedLiteral(cond.statusMessage ?? "You Win!")
                let collectibleNames = recipe.entities
                    .filter { $0.role == .collectible }
                    .flatMap { instanceNamesFor($0) }
                if !collectibleNames.isEmpty {
                    // Use score threshold if available as a proxy for "all collected".
                    if let t = cond.scoreThreshold {
                        lines.append("if score >= \(t) then")
                        lines.append("  if gameOver is not \"true\" then")
                        lines.append("    put \"true\" into gameOver")
                        lines.append("    set the text of label \"status\" to \"\(msg)\"")
                        lines.append("  end if")
                        lines.append("end if")
                    }
                }
            default:
                break
            }
        }

        for cond in state.loseConditions {
            switch cond.kind {
            case .zeroLives:
                let msg = sanitizedLiteral(cond.statusMessage ?? "Game Over")
                lines.append("if lives <= 0 then")
                lines.append("  if gameOver is not \"true\" then")
                lines.append("    put \"true\" into gameOver")
                lines.append("    set the text of label \"status\" to \"\(msg)\"")
                lines.append("  end if")
                lines.append("end if")
            case .zeroHealth:
                let msg = sanitizedLiteral(cond.statusMessage ?? "Game Over")
                lines.append("if health <= 0 then")
                lines.append("  if gameOver is not \"true\" then")
                lines.append("    put \"true\" into gameOver")
                lines.append("    set the text of label \"status\" to \"\(msg)\"")
                lines.append("  end if")
                lines.append("end if")
            default:
                break
            }
        }

        return lines
    }

    // MARK: - Private: Multi-instance contribution replication

    /// For multi-count static entities (count > 1), replicate frameUpdate and contact lines
    /// for each instance name (e.g. "enemy_1", "enemy_2", ...).
    private static func replicateForInstances(
        _ contrib: BehaviorContribution,
        entity: GameEntity,
        instanceNames: [String]
    ) -> BehaviorContribution {
        guard instanceNames.count > 1 else { return contrib }
        var result = contrib
        // The contribution lines were generated using sanitizedLiteral(entity.name), so
        // the replacement target must also be the sanitized name.
        let safeName = sanitizedLiteral(entity.name)
        // Replace frameUpdate lines: generate one block per instance, replacing the
        // sanitized base name with each sanitized instance name.
        var allFrameLines: [String] = []
        for instName in instanceNames {
            let replaced = contrib.frameUpdate.map {
                $0.replacingOccurrences(of: "\"\(safeName)\"", with: "\"\(instName)\"")
            }
            allFrameLines.append(contentsOf: replaced)
        }
        result.frameUpdate = allFrameLines

        // Replicate contact branches similarly.
        var allBeginContact: [ContactBranch] = []
        for instName in instanceNames {
            for branch in contrib.beginContact {
                let pred = branch.otherPredicate.replacingOccurrences(of: "\"\(safeName)\"", with: "\"\(instName)\"")
                let lines = branch.lines.map {
                    $0.replacingOccurrences(of: "\"\(safeName)\"", with: "\"\(instName)\"")
                }
                allBeginContact.append(ContactBranch(otherPredicate: pred, lines: lines))
            }
        }
        result.beginContact = allBeginContact

        return result
    }

    // MARK: - Private: Script merge

    private static func mergeScript(_ recipeScript: String, into existing: String) -> String {
        // If existing script contains markers, replace only the marked region.
        if let beginRange = existing.range(of: beginMarker),
           let endRange = existing.range(of: endMarker),
           beginRange.upperBound <= endRange.lowerBound {
            var merged = existing
            // Half-open: endRange.upperBound is the index *past* the end marker, which
            // is endIndex when the marker terminates the string. A closed range
            // (...upperBound) would index endIndex and trap; ..< replaces exactly the
            // begin-marker-through-end-marker span.
            let replaceRange = beginRange.lowerBound..<endRange.upperBound
            merged.replaceSubrange(replaceRange, with: recipeScript)
            return merged
        }

        // No markers: insert recipe script at top, preserve existing content below separator.
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recipeScript
        }
        return recipeScript + "\n\n-- User handlers below (preserved by merge)\n" + existing
    }

    // MARK: - Private: Script validation

    private static func scriptParseError(_ script: String) -> String? {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return nil
        } catch let error as ParseError {
            return error.errorDescription ?? String(describing: error)
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Private: Sanitization helpers

    /// Neutralize a recipe-supplied string before it is interpolated into a
    /// generated HypeTalk double-quoted string literal. HypeTalk has no backslash
    /// escape, so the only safe transform is to remove the literal delimiter and
    /// any newline/return that could terminate the line and inject a handler.
    static func sanitizedLiteral(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\"", with: "'")
           .replacingOccurrences(of: "\n", with: " ")
           .replacingOccurrences(of: "\r", with: " ")
           .replacingOccurrences(of: "\\", with: "/")
    }

    /// Normalize a recipe-supplied numeric string for bare (unquoted) HypeTalk
    /// emission. Rejects strings that cannot be parsed as a Double (e.g. injection
    /// payloads) and falls back to `def`. The result uses `fmt` so it never
    /// contains trailing `.0` noise.
    static func numericLiteral(_ raw: String, default def: Double) -> String {
        fmt(Double(raw) ?? def)
    }

    // MARK: - Private: Utilities

    private static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    private static func stableUnique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for name in names {
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(name)
        }
        return result
    }

    private static func isSpawnerBehavior(_ kind: BehaviorKind) -> Bool {
        kind == .spawner
    }

    // MARK: - Rule Contributions

    /// Converts every `GameRule` in the recipe into `BehaviorContribution` values that
    /// feed the existing single-handler-per-event merge path in `compile(_:repository:)`.
    ///
    /// Rules use index-stable global names (e.g. `ruleTimer_0`, `ruleTimer_1`) so the
    /// compiled output is deterministic across recompilations.
    private static func ruleContributions(
        for recipe: GameRecipe,
        diagnostics: inout [String]
    ) -> [BehaviorContribution] {

        var contributions: [BehaviorContribution] = []
        let state = recipe.gameState

        for (ruleIndex, rule) in recipe.rules.enumerated() {
            let contrib = ruleContribution(
                rule: rule,
                ruleIndex: ruleIndex,
                recipe: recipe,
                state: state,
                diagnostics: &diagnostics
            )
            contributions.append(contrib)
        }

        return contributions
    }

    /// Compile a single `GameRule` into a `BehaviorContribution`.
    private static func ruleContribution(
        rule: GameRule,
        ruleIndex: Int,
        recipe: GameRecipe,
        state: GameState,
        diagnostics: inout [String]
    ) -> BehaviorContribution {

        var sceneDidLoadLines: [String] = []
        var keyDownBranches: [KeyBranch] = []
        var beginContactBranches: [ContactBranch] = []
        var frameUpdateLines: [String] = []
        var requiredGlobals: [String] = []

        switch rule.trigger.kind {

        // MARK: onContact
        case .onContact:
            // Validate roles are present — roleA defines whose handler fires; roleB is the "other" entity.
            guard rule.trigger.roleA != nil, let roleB = rule.trigger.roleB else {
                diagnostics.append("Rule \(ruleIndex): onContact trigger requires both roleA and roleB. Skipping.")
                break
            }

            let roleBEntities = recipe.entities.filter { $0.role == roleB }
            if roleBEntities.isEmpty {
                diagnostics.append("Rule \(ruleIndex): onContact trigger references role '\(roleB.rawValue)' but no entities with that role exist.")
            }

            // Build action lines; destroyOther is valid in contact context.
            let (actionLines, actionGlobals, actionInitLines) = compileActions(
                rule.actions,
                rule: rule,
                ruleIndex: ruleIndex,
                recipe: recipe,
                state: state,
                inContactContext: true,
                diagnostics: &diagnostics
            )
            requiredGlobals.append(contentsOf: actionGlobals)
            sceneDidLoadLines.append(contentsOf: actionInitLines)

            // Wrap in condition guard if needed
            let bodyLines = wrapWithConditions(rule.conditions, body: actionLines, recipe: recipe, diagnostics: &diagnostics)

            // Emit one ContactBranch per roleB entity (mirrors loseOnContact / scoreOnCollect).
            // This avoids OR compound predicates that may not be supported by the parser.
            if roleBEntities.isEmpty {
                // Fallback: match by role name string when no entities resolved
                let fallbackPred = "otherName contains \"\(roleB.rawValue)\""
                beginContactBranches.append(ContactBranch(otherPredicate: fallbackPred, lines: bodyLines))
            } else {
                for roleBEntity in roleBEntities {
                    let predicate = contactPredicateForRole(roleBEntity)
                    beginContactBranches.append(ContactBranch(otherPredicate: predicate, lines: bodyLines))
                }
            }

        // MARK: onKey
        case .onKey:
            guard let key = rule.trigger.key, !key.isEmpty else {
                diagnostics.append("Rule \(ruleIndex): onKey trigger requires a non-empty key. Skipping.")
                break
            }

            let (actionLines, actionGlobals, actionInitLines) = compileActions(
                rule.actions,
                rule: rule,
                ruleIndex: ruleIndex,
                recipe: recipe,
                state: state,
                inContactContext: false,
                diagnostics: &diagnostics
            )
            requiredGlobals.append(contentsOf: actionGlobals)
            sceneDidLoadLines.append(contentsOf: actionInitLines)
            let bodyLines = wrapWithConditions(rule.conditions, body: actionLines, recipe: recipe, diagnostics: &diagnostics)
            keyDownBranches.append(KeyBranch(key: key, lines: bodyLines))

        // MARK: everyNSeconds
        case .everyNSeconds:
            let seconds = rule.trigger.seconds ?? 1.0
            let timerVar = "ruleTimer_\(ruleIndex)"
            requiredGlobals.append(timerVar)

            // Initialize timer in sceneDidLoad
            sceneDidLoadLines.append("put 0 into \(timerVar)")

            let (actionLines, actionGlobals, actionInitLines) = compileActions(
                rule.actions,
                rule: rule,
                ruleIndex: ruleIndex,
                recipe: recipe,
                state: state,
                inContactContext: false,
                diagnostics: &diagnostics
            )
            requiredGlobals.append(contentsOf: actionGlobals)
            sceneDidLoadLines.append(contentsOf: actionInitLines)
            let bodyLines = wrapWithConditions(rule.conditions, body: actionLines, recipe: recipe, diagnostics: &diagnostics)

            // Emit timer accumulation + threshold check
            frameUpdateLines.append("add deltaTime to \(timerVar)")
            frameUpdateLines.append("if \(timerVar) >= \(fmt(seconds)) then")
            for line in bodyLines {
                frameUpdateLines.append("  \(line)")
            }
            frameUpdateLines.append("  put 0 into \(timerVar)")
            frameUpdateLines.append("end if")

        // MARK: onScoreReached
        case .onScoreReached:
            let threshold = rule.trigger.scoreThreshold ?? 0

            let (actionLines, actionGlobals, actionInitLines) = compileActions(
                rule.actions,
                rule: rule,
                ruleIndex: ruleIndex,
                recipe: recipe,
                state: state,
                inContactContext: false,
                diagnostics: &diagnostics
            )
            requiredGlobals.append(contentsOf: actionGlobals)
            sceneDidLoadLines.append(contentsOf: actionInitLines)
            let bodyLines = wrapWithConditions(rule.conditions, body: actionLines, recipe: recipe, diagnostics: &diagnostics)

            // Emit score threshold check; gate with gameOver to fire only once if win/lose
            frameUpdateLines.append("if score >= \(threshold) then")
            frameUpdateLines.append("  if gameOver is not \"true\" then")
            for line in bodyLines {
                frameUpdateLines.append("    \(line)")
            }
            frameUpdateLines.append("  end if")
            frameUpdateLines.append("end if")

        // MARK: onSceneLoad
        case .onSceneLoad:
            let (actionLines, actionGlobals, actionInitLines) = compileActions(
                rule.actions,
                rule: rule,
                ruleIndex: ruleIndex,
                recipe: recipe,
                state: state,
                inContactContext: false,
                diagnostics: &diagnostics
            )
            requiredGlobals.append(contentsOf: actionGlobals)
            sceneDidLoadLines.append(contentsOf: actionInitLines)
            let bodyLines = wrapWithConditions(rule.conditions, body: actionLines, recipe: recipe, diagnostics: &diagnostics)
            sceneDidLoadLines.append(contentsOf: bodyLines)

        // MARK: onFrame
        case .onFrame:
            let (actionLines, actionGlobals, actionInitLines) = compileActions(
                rule.actions,
                rule: rule,
                ruleIndex: ruleIndex,
                recipe: recipe,
                state: state,
                inContactContext: false,
                diagnostics: &diagnostics
            )
            requiredGlobals.append(contentsOf: actionGlobals)
            sceneDidLoadLines.append(contentsOf: actionInitLines)
            let bodyLines = wrapWithConditions(rule.conditions, body: actionLines, recipe: recipe, diagnostics: &diagnostics)
            frameUpdateLines.append(contentsOf: bodyLines)
        }

        return BehaviorContribution(
            sceneDidLoad: sceneDidLoadLines,
            keyDown: keyDownBranches,
            beginContact: beginContactBranches,
            frameUpdate: frameUpdateLines,
            requiredGlobals: requiredGlobals
        )
    }

    // MARK: - Rule helpers

    /// Build a contact predicate string for a single entity (mirrors BehaviorLibrary.contactPredicate).
    private static func contactPredicateForRole(_ entity: GameEntity) -> String {
        let safe = sanitizedLiteral(entity.name)
        return entity.count > 1
            ? "otherName contains \"\(safe)_\""
            : "otherName is \"\(safe)\""
    }

    /// Wrap action lines in a HypeTalk `if` guard built from `RuleCondition`s.
    /// A single `always` condition (or an empty list) emits no wrapping.
    /// Multiple conditions are ANDed together via nested `if` blocks.
    private static func wrapWithConditions(
        _ conditions: [RuleCondition],
        body: [String],
        recipe: GameRecipe,
        diagnostics: inout [String]
    ) -> [String] {
        guard !body.isEmpty else { return [] }

        // Collect only conditions that produce a non-nil HypeTalk expression.
        // Use an explicit loop rather than compactMap so the inout diagnostics
        // parameter can be threaded through without a closure capture issue.
        var expressions: [String] = []
        for cond in conditions {
            if let expr = conditionExpression(cond, recipe: recipe, diagnostics: &diagnostics) {
                expressions.append(expr)
            }
        }
        guard !expressions.isEmpty else { return body }

        // Build nested if-blocks for each expression (AND semantics via nesting)
        var result: [String] = []
        let depth = expressions.count

        for (i, expr) in expressions.enumerated() {
            result.append("\(String(repeating: "  ", count: i))if \(expr) then")
        }

        // Body lines indented by full nesting depth
        for line in body {
            result.append("\(String(repeating: "  ", count: depth))\(line)")
        }

        // Close all nested ifs in reverse order
        for i in stride(from: depth - 1, through: 0, by: -1) {
            result.append("\(String(repeating: "  ", count: i))end if")
        }

        return result
    }

    /// Returns a HypeTalk boolean expression for a condition, or nil if the condition
    /// is trivially true (`always`) or lacks required fields.
    private static func conditionExpression(_ cond: RuleCondition, recipe: GameRecipe, diagnostics: inout [String]) -> String? {
        guard cond.kind != .always else { return nil }
        guard let stateVar = cond.stateVar, let v = cond.value else { return nil }
        let global = resolvedStateVar(stateVar, diagnostics: &diagnostics)
        let value = fmt(v)
        switch cond.kind {
        case .stateEquals:  return "\(global) is \"\(value)\""
        case .stateGreater: return "\(global) > \(value)"
        case .stateLess:    return "\(global) < \(value)"
        case .always:       return nil
        }
    }

    /// Map common logical state variable names to the global names the compiler uses.
    /// Non-identifier strings (i.e. anything beyond letters/digits/underscore) are
    /// rejected and fall back to "gameOver" with a diagnostic so a hostile stateVar
    /// cannot inject into a bare HypeTalk expression.
    private static func resolvedStateVar(_ stateVar: String, diagnostics: inout [String]) -> String {
        switch stateVar.lowercased() {
        case "score":     return "score"
        case "lives":     return "lives"
        case "level":     return "level"
        case "gameover":  return "gameOver"
        case "health":    return "health"
        default:
            // Validate: allow only letters, digits, and underscores (safe HypeTalk identifier).
            let isIdentifier = !stateVar.isEmpty && stateVar.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            if isIdentifier {
                return stateVar
            }
            diagnostics.append("stateVar '\(stateVar)' is not a valid identifier; falling back to 'gameOver'.")
            return "gameOver"
        }
    }

    /// Compile a list of `RuleAction`s into HypeTalk lines plus any required globals
    /// and sceneDidLoad initialization lines.
    ///
    /// - Parameter inContactContext: when `false`, `destroyOther` is invalid and
    ///   emits a diagnostic instead of an unparseable line.
    /// - Returns: A tuple of (action lines, globals to declare, sceneDidLoad init lines).
    private static func compileActions(
        _ actions: [RuleAction],
        rule: GameRule,
        ruleIndex: Int,
        recipe: GameRecipe,
        state: GameState,
        inContactContext: Bool,
        diagnostics: inout [String]
    ) -> (lines: [String], globals: [String], initLines: [String]) {

        var lines: [String] = []
        var globals: [String] = []
        var initLines: [String] = []

        for action in actions {
            switch action.kind {

            case .addScore:
                let amount = Int(action.amount ?? 1)
                lines.append("add \(amount) to score")
                globals.append("score")
                if let hudName = state.scoreHUDEntityName {
                    let safeHUD = sanitizedLiteral(hudName)
                    lines.append("set the text of label \"\(safeHUD)\" to \"Score: \" & score")
                }

            case .addLives:
                let amount = Int(action.amount ?? 1)
                lines.append("add \(amount) to lives")
                globals.append("lives")
                if let hudName = state.livesHUDEntityName {
                    let safeHUD = sanitizedLiteral(hudName)
                    lines.append("set the text of label \"\(safeHUD)\" to \"Lives: \" & lives")
                }

            case .setStatus:
                let msg = sanitizedLiteral(action.message ?? "")
                if let hudName = state.statusHUDEntityName {
                    let safeHUD = sanitizedLiteral(hudName)
                    lines.append("set the text of label \"\(safeHUD)\" to \"\(msg)\"")
                } else {
                    // No status HUD configured; emit to the conventional "status" label
                    lines.append("set the text of label \"status\" to \"\(msg)\"")
                }

            case .destroyOther:
                guard inContactContext else {
                    diagnostics.append("Rule \(ruleIndex): destroyOther action is only valid in an onContact trigger. Skipping this action.")
                    break
                }
                lines.append("remove sprite otherName")

            case .destroySelf:
                // Resolve which entity name to destroy; fall back to the roleA entity in the recipe.
                let roleFallback: EntityRole = rule.trigger.roleA ?? .decoration
                let entityName = action.entityName
                    ?? rule.trigger.entityName
                    ?? (recipe.entities.first(where: { $0.role == roleFallback })?.name)
                if let name = entityName {
                    let safeName = sanitizedLiteral(name)
                    lines.append("remove sprite \"\(safeName)\"")
                } else {
                    diagnostics.append("Rule \(ruleIndex): destroySelf action could not resolve entity name. Skipping this action.")
                }

            case .respawnEntity:
                guard let entityName = action.entityName ?? rule.trigger.entityName else {
                    diagnostics.append("Rule \(ruleIndex): respawnEntity action requires entityName. Skipping this action.")
                    break
                }
                let safeName = sanitizedLiteral(entityName)
                // Find the entity's spawn position from the recipe
                if let entity = recipe.entities.first(where: { $0.name == entityName }) {
                    let x = fmt(entity.position.x)
                    let y = fmt(entity.position.y)
                    lines.append("set the loc of sprite \"\(safeName)\" to \"\(x),\(y)\"")
                } else {
                    diagnostics.append("Rule \(ruleIndex): respawnEntity references unknown entity '\(entityName)'.")
                    // Still emit a parseable line using the sanitized name
                    lines.append("set the loc of sprite \"\(safeName)\" to \"400,300\"")
                }

            case .spawnEntity:
                // Deterministic spawn name using rule index so each rule gets its own namespace
                let spawnIdxVar = "ruleSpawnIdx_\(ruleIndex)"
                globals.append(spawnIdxVar)
                // Initialize the spawn counter once in sceneDidLoad
                initLines.append("put 0 into \(spawnIdxVar)")

                // Resolve asset from the spawn target entity or artRoleRef.
                // Sanitize the target name before embedding into a string literal.
                let targetName = sanitizedLiteral(action.entityName ?? "entity")
                let spawnAssetArg: String
                if let spawnEntity = recipe.entities.first(where: { $0.name == (action.entityName ?? "entity") }),
                   let artRef = spawnEntity.artRoleRef {
                    let safeArt = sanitizedLiteral(artRef)
                    spawnAssetArg = " with asset \"\(safeArt)\""
                } else {
                    spawnAssetArg = ""
                }

                lines.append("add 1 to \(spawnIdxVar)")
                lines.append("put \"\(targetName)_\" & \(spawnIdxVar) into ruleSpawnName_\(ruleIndex)")
                lines.append("create sprite ruleSpawnName_\(ruleIndex) in scene \"main\"\(spawnAssetArg)")

            case .setVelocity:
                let entityName = action.entityName ?? rule.trigger.entityName
                guard let name = entityName else {
                    diagnostics.append("Rule \(ruleIndex): setVelocity action requires entityName. Skipping this action.")
                    break
                }
                let safeName = sanitizedLiteral(name)
                // Use fmt directly on the already-numeric values (already Double from the model).
                let vx = fmt(action.velocityX ?? 0)
                let vy = fmt(action.velocityY ?? 0)
                lines.append("set the velocity of sprite \"\(safeName)\" to \"\(vx),\(vy)\"")

            case .winGame:
                let msg = sanitizedLiteral(action.message ?? "You Win!")
                lines.append("put \"true\" into gameOver")
                globals.append("gameOver")
                if let hudName = state.statusHUDEntityName {
                    let safeHUD = sanitizedLiteral(hudName)
                    lines.append("set the text of label \"\(safeHUD)\" to \"\(msg)\"")
                } else {
                    lines.append("set the text of label \"status\" to \"\(msg)\"")
                }

            case .loseGame:
                let msg = sanitizedLiteral(action.message ?? "Game Over")
                lines.append("put \"true\" into gameOver")
                globals.append("gameOver")
                if let hudName = state.statusHUDEntityName {
                    let safeHUD = sanitizedLiteral(hudName)
                    lines.append("set the text of label \"\(safeHUD)\" to \"\(msg)\"")
                } else {
                    lines.append("set the text of label \"status\" to \"\(msg)\"")
                }

            case .playSound:
                // The HypeTalk grammar supported by this project does not include
                // a `play sound` verb that parses cleanly — emitting an unknown verb
                // would cause the self-validation fallback to trigger.
                // We record a diagnostic and skip the emission entirely.
                let assetName = action.soundAsset ?? action.entityName ?? "unknown"
                diagnostics.append("Rule \(ruleIndex): playSound action ('\(assetName)') is not emitted — no parseable HypeTalk sound verb is available in the current grammar. Wire up audio through a dedicated handler instead.")
            }
        }

        return (lines, globals, initLines)
    }
}
