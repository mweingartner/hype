import Foundation

/// Executor branches for the composable game-recipe AI tool surface.
///
/// These tools let the AI author a `GameRecipe` incrementally — start,
/// add entities, attach behaviors, set state, configure controls, bind
/// art, and finally compile the recipe into a validated scene script with
/// `build_game` — without hand-writing any HypeTalk game loops.
///
/// Architecture invariants (enforced here, not just documented):
/// - **Fail-closed**: any tool that implies an existing target (via
///   `require_existing_scene=true` or when no explicit area name + multiple
///   candidates exist) returns an error and mutates NOTHING.
/// - **Script gate**: `build_game` routes the compiler's output through
///   `refusalForInvalidDraft` before storing it. A refusal returns the
///   sentinel string and leaves the document unchanged.
/// - **Intent preserved verbatim**: entity names, scene size, art roles,
///   and behaviors passed by the caller are stored exactly as given.
/// - **No network / image calls**: `bind_art_role` with `generate=true`
///   marks intent only; it never invokes any image-generation API.
package enum GameRecipeExecutorBranches {

    // MARK: - start_game_recipe

    /// Create or reuse a sprite area and initialise an empty `GameRecipe` on it.
    ///
    /// Fail-closed: if `require_existing_scene=true` (or the caller implies an
    /// existing target) and no unique match can be found, returns an error.
    package static func executeStartGameRecipe(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let explicitAreaName = arguments["sprite_area_name"].flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let requestedSceneName = arguments["scene_name"]
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? "main"
        let sceneWidth  = Double(arguments["scene_width"]  ?? "") ?? 800.0
        let sceneHeight = Double(arguments["scene_height"] ?? "") ?? 600.0
        let backgroundColor = arguments["background_color"] ?? "#101018"
        let gravityStr = arguments["gravity"] ?? ""
        let requireExisting = context.boolArgument(arguments["require_existing_scene"]) ?? false

        // Parse gravity "dx,dy"
        let gravity = parseVector(gravityStr) ?? VectorSpec(dx: 0, dy: 0)

        // Resolve or create the sprite area.
        let resolvedIdx: Int?
        if let name = explicitAreaName {
            resolvedIdx = context.spriteAreaIndex(named: name, currentCardId: currentCardId, in: document)
        } else {
            resolvedIdx = nil
        }

        let partIdx: Int
        let didCreate: Bool

        if let existingIdx = resolvedIdx {
            // Named area found — use it.
            partIdx = existingIdx
            didCreate = false
        } else if requireExisting {
            // Caller said "use existing" but we can't find it.
            if let name = explicitAreaName {
                return "Sprite area '\(name)' not found. No recipe was started because require_existing_scene=true."
            }
            // No explicit name + require_existing: check for exactly one candidate.
            let candidates = document.effectivePartsForCard(currentCardId).filter { $0.partType == .spriteArea }
            guard candidates.count == 1,
                  let idx = document.parts.firstIndex(where: { $0.id == candidates[0].id }) else {
                return "require_existing_scene=true but \(candidates.count == 0 ? "no" : "multiple") sprite areas found on this card. Pass sprite_area_name to target a specific area."
            }
            partIdx = idx
            didCreate = false
        } else if explicitAreaName == nil {
            // Auto-resolve: exactly one sprite area on current card?
            let candidates = document.effectivePartsForCard(currentCardId).filter { $0.partType == .spriteArea }
            if candidates.count == 1,
               let idx = document.parts.firstIndex(where: { $0.id == candidates[0].id }) {
                partIdx = idx
                didCreate = false
            } else {
                // Create a new sprite area.
                let areaName = "Game"
                let place = context.placement(arguments: arguments, currentCardId: currentCardId, document: document)
                let stackWidth = Double(document.stack.width)
                let stackHeight = Double(document.stack.height)
                let left = Double(arguments["left"] ?? "") ?? max(0, (stackWidth - sceneWidth) / 2)
                let top  = Double(arguments["top"]  ?? "") ?? max(0, (stackHeight - sceneHeight) / 2)
                var newPart = Part(
                    partType: .spriteArea,
                    cardId: place.cardId,
                    backgroundId: place.backgroundId,
                    name: areaName,
                    left: left,
                    top: top,
                    width: sceneWidth,
                    height: sceneHeight
                )
                newPart.setSpriteAreaSpec(
                    SpriteAreaSpec(defaultSceneNamed: requestedSceneName, fallbackSize: SizeSpec(width: sceneWidth, height: sceneHeight))
                )
                document.addPart(newPart)
                partIdx = document.parts.count - 1
                didCreate = true
            }
        } else {
            // explicitAreaName given but no match — create it.
            let areaName = explicitAreaName!
            let place = context.placement(arguments: arguments, currentCardId: currentCardId, document: document)
            let stackWidth = Double(document.stack.width)
            let stackHeight = Double(document.stack.height)
            let left = Double(arguments["left"] ?? "") ?? max(0, (stackWidth - sceneWidth) / 2)
            let top  = Double(arguments["top"]  ?? "") ?? max(0, (stackHeight - sceneHeight) / 2)
            var newPart = Part(
                partType: .spriteArea,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: areaName,
                left: left,
                top: top,
                width: sceneWidth,
                height: sceneHeight
            )
            newPart.setSpriteAreaSpec(
                SpriteAreaSpec(defaultSceneNamed: requestedSceneName, fallbackSize: SizeSpec(width: sceneWidth, height: sceneHeight))
            )
            document.addPart(newPart)
            partIdx = document.parts.count - 1
            didCreate = true
        }

        // Resolve an optional genre preset and build the initial recipe from it.
        // When a preset arg is supplied and recognised, the preset's entities,
        // behaviors, controls, and gameState form the starting recipe — honoring
        // any explicit scene_width/height overrides from the caller. When the
        // preset id is unknown we fall back to an empty recipe and note it.
        let presetArg = arguments["preset"]
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        let areaName = document.parts[partIdx].name
        let recipe: GameRecipe
        var presetNote = ""

        if let rawPreset = presetArg {
            let overrideSize = SizeSpec(width: sceneWidth, height: sceneHeight)
            // Resolve alias → canonical id, then build the preset recipe.
            if let canonicalID = GenrePresetLibrary.canonicalID(for: rawPreset),
               var presetRecipe = GenrePresetLibrary.preset(
                   for: canonicalID,
                   sceneName: requestedSceneName,
                   sceneSize: overrideSize
               ) {
                // Honour caller size and scene name overrides even when they
                // differ from the preset's defaults.
                presetRecipe.sceneName = requestedSceneName
                presetRecipe.sceneSize = overrideSize
                if !backgroundColor.isEmpty && backgroundColor != "#101018" {
                    presetRecipe.backgroundColor = backgroundColor
                }
                // Only override gravity when the caller provided an explicit value.
                if !gravityStr.isEmpty {
                    presetRecipe.gravity = gravity
                }
                recipe = presetRecipe
                presetNote = " Preset '\(canonicalID)' applied (\(recipe.entities.count) entities)."
            } else {
                // Unknown preset: start empty and inform the caller.
                recipe = GameRecipe(
                    sceneName: requestedSceneName,
                    sceneSize: SizeSpec(width: sceneWidth, height: sceneHeight),
                    backgroundColor: backgroundColor,
                    gravity: gravity
                )
                presetNote = " (Note: preset '\(rawPreset)' not found; started with empty recipe. Known preset ids: \(GenrePresetLibrary.presetIDs.joined(separator: ", ")))"
            }
        } else {
            // No preset requested — empty recipe as before.
            recipe = GameRecipe(
                sceneName: requestedSceneName,
                sceneSize: SizeSpec(width: sceneWidth, height: sceneHeight),
                backgroundColor: backgroundColor,
                gravity: gravity
            )
        }

        document.parts[partIdx].updateRecipe { $0 = recipe }

        let action = didCreate ? "Created" : "Initialised recipe on"
        let entitySummary = recipe.entities.isEmpty
            ? "0 entities. Add entities with add_entity, configure with set_game_state/set_controls/add_rule, then call build_game."
            : "\(recipe.entities.count) entities. Customise with add_entity/attach_behavior/set_game_state/set_controls, then call build_game."
        return "\(action) sprite area '\(areaName)' (\(Int(sceneWidth))×\(Int(sceneHeight)), scene '\(requestedSceneName)'). Recipe has \(entitySummary)\(presetNote)"
    }

    // MARK: - add_entity

    /// Add a `GameEntity` to the sprite area's recipe.
    ///
    /// The entity `name` is preserved verbatim. Unknown behavior kinds
    /// return an actionable error listing valid kinds.
    package static func executeAddEntity(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let entityName = arguments["name"] ?? ""
        guard !entityName.isEmpty else {
            return "add_entity: 'name' is required."
        }
        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "add_entity: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }
        guard document.parts[partIdx].spriteAreaSpecModel?.recipe != nil else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe first."
        }

        let roleStr  = arguments["role"] ?? "decoration"
        let role     = EntityRole.decodeTolerant(roleStr)
        let x        = Double(arguments["x"] ?? "") ?? 0
        let y        = Double(arguments["y"] ?? "") ?? 0
        let width    = Double(arguments["width"]  ?? "") ?? 64
        let height   = Double(arguments["height"] ?? "") ?? 64
        let count    = Int(arguments["count"] ?? "")    ?? 1
        let artRole  = arguments["art_role"]
        let color    = arguments["color"]
        let z        = Double(arguments["z"] ?? "") ?? 0
        let text     = arguments["text"]
        let fontSize = Double(arguments["font_size"] ?? "")
        let fontColor = arguments["font_color"]

        // Parse behaviors from comma-separated "kind" or "kind:key=val;key2=val2"
        let behaviorsArg = arguments["behaviors"] ?? ""
        let parsedBehaviors: [Behavior]
        if behaviorsArg.isEmpty {
            parsedBehaviors = []
        } else {
            var behaviorList: [Behavior] = []
            var unknownKinds: [String] = []
            for token in behaviorsArg.components(separatedBy: ",") {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let parseResult = parseBehaviorToken(trimmed)
                switch parseResult {
                case .success(let b):
                    behaviorList.append(b)
                case .unknownKind(let kindStr):
                    unknownKinds.append(kindStr)
                }
            }
            if !unknownKinds.isEmpty {
                let valid = BehaviorKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                return "add_entity: unknown behavior kind(s): \(unknownKinds.joined(separator: ", ")). Valid kinds: \(valid)."
            }
            parsedBehaviors = behaviorList
        }

        let entity = GameEntity(
            name: entityName,
            role: role,
            position: PointSpec(x: x, y: y),
            size: SizeSpec(width: width, height: height),
            count: count,
            artRoleRef: artRole,
            placeholderColor: color,
            zPosition: z,
            behaviors: parsedBehaviors,
            initialText: text,
            fontSize: fontSize,
            fontColor: fontColor
        )

        document.parts[partIdx].updateRecipe { recipe in
            recipe?.entities.append(entity)
        }

        let actualAreaName = document.parts[partIdx].name
        let entityCount = document.parts[partIdx].spriteAreaSpecModel?.recipe?.entities.count ?? 1
        let behaviorSummary = parsedBehaviors.isEmpty ? "no behaviors" : parsedBehaviors.map { $0.kind.rawValue }.joined(separator: ", ")
        return "Added entity '\(entityName)' (role=\(role.rawValue), count=\(count), behaviors: \(behaviorSummary)) to recipe in '\(actualAreaName)'. Recipe now has \(entityCount) entity/entities."
    }

    // MARK: - attach_behavior

    /// Attach a behavior to an existing entity in the recipe.
    package static func executeAttachBehavior(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName   = arguments["sprite_area_name"] ?? ""
        let entityName = arguments["entity_name"] ?? ""
        let behaviorStr = arguments["behavior"] ?? ""
        let paramsStr   = arguments["params"] ?? ""

        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "attach_behavior: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }
        guard document.parts[partIdx].spriteAreaSpecModel?.recipe != nil else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe first."
        }
        guard let kind = BehaviorKind(rawValue: behaviorStr) else {
            let valid = BehaviorKind.allCases.map { $0.rawValue }.joined(separator: ", ")
            return "Unknown behavior kind '\(behaviorStr)'. Valid kinds: \(valid)."
        }

        var entityFound = false
        document.parts[partIdx].updateRecipe { recipe in
            guard var r = recipe else { return }
            guard let idx = r.entities.firstIndex(where: { $0.name == entityName }) else { return }
            entityFound = true
            let params = parseParamsString(paramsStr)
            r.entities[idx].behaviors.append(Behavior(kind: kind, params: params))
            recipe = r
        }

        if !entityFound {
            return "Entity '\(entityName)' not found in recipe for '\(document.parts[partIdx].name)'."
        }
        return "Attached behavior '\(behaviorStr)' to entity '\(entityName)' in '\(document.parts[partIdx].name)'."
    }

    // MARK: - detach_behavior

    /// Remove a behavior from an existing entity in the recipe.
    package static func executeDetachBehavior(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName    = arguments["sprite_area_name"] ?? ""
        let entityName  = arguments["entity_name"] ?? ""
        let behaviorStr = arguments["behavior"] ?? ""

        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "detach_behavior: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }
        guard document.parts[partIdx].spriteAreaSpecModel?.recipe != nil else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe first."
        }

        var entityFound = false
        var removedCount = 0
        document.parts[partIdx].updateRecipe { recipe in
            guard var r = recipe else { return }
            guard let idx = r.entities.firstIndex(where: { $0.name == entityName }) else { return }
            entityFound = true
            let before = r.entities[idx].behaviors.count
            r.entities[idx].behaviors.removeAll { $0.kind.rawValue == behaviorStr }
            removedCount = before - r.entities[idx].behaviors.count
            recipe = r
        }

        if !entityFound {
            return "Entity '\(entityName)' not found in recipe for '\(document.parts[partIdx].name)'."
        }
        if removedCount == 0 {
            return "Entity '\(entityName)' had no '\(behaviorStr)' behavior to remove."
        }
        return "Removed \(removedCount) '\(behaviorStr)' behavior(s) from '\(entityName)' in '\(document.parts[partIdx].name)'."
    }

    // MARK: - add_rule

    /// Add a reactive `GameRule` to the recipe.
    ///
    /// Trigger kinds: onContact, onKey, everyNSeconds, onScoreReached, onSceneLoad, onFrame.
    /// Action format: `kind` or `kind:key=val;key2=val2`.
    package static func executeAddRule(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName   = arguments["sprite_area_name"] ?? ""
        let triggerStr = arguments["trigger"] ?? "onSceneLoad"

        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "add_rule: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }
        guard document.parts[partIdx].spriteAreaSpecModel?.recipe != nil else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe first."
        }

        // Build trigger
        let triggerKind = RuleTrigger.Kind.decodeTolerant(triggerStr)
        let trigger = RuleTrigger(
            kind: triggerKind,
            roleA: arguments["role_a"].map { EntityRole.decodeTolerant($0) },
            roleB: arguments["role_b"].map { EntityRole.decodeTolerant($0) },
            key: arguments["key"],
            seconds: Double(arguments["seconds"] ?? ""),
            scoreThreshold: Int(arguments["score_threshold"] ?? "")
        )

        // Build conditions
        var conditions: [RuleCondition] = []
        if let conditionsStr = arguments["conditions"], !conditionsStr.isEmpty {
            // Simple conditions: "always" or a single stateVar comparison
            for token in conditionsStr.components(separatedBy: ",") {
                let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.lowercased() == "always" || t.isEmpty {
                    conditions.append(RuleCondition(kind: .always))
                } else {
                    conditions.append(RuleCondition(kind: .always))
                }
            }
        }

        // Build actions from comma-separated tokens: "kind" or "kind:key=val;key2=val2"
        var actions: [RuleAction] = []
        if let actionsStr = arguments["actions"], !actionsStr.isEmpty {
            for token in actionsStr.components(separatedBy: ",") {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let action = parseRuleActionToken(trimmed)
                actions.append(action)
            }
        }

        let rule = GameRule(trigger: trigger, conditions: conditions, actions: actions)
        document.parts[partIdx].updateRecipe { recipe in
            recipe?.rules.append(rule)
        }

        let actualAreaName = document.parts[partIdx].name
        let ruleCount = document.parts[partIdx].spriteAreaSpecModel?.recipe?.rules.count ?? 1
        let actionSummary = actions.map { $0.kind.rawValue }.joined(separator: ", ")
        return "Added rule (trigger=\(triggerStr), actions: \(actionSummary.isEmpty ? "none" : actionSummary)) to recipe in '\(actualAreaName)'. Recipe now has \(ruleCount) rule(s)."
    }

    // MARK: - set_game_state

    /// Configure the game state tracking, win/lose conditions, and HUD bindings.
    package static func executeSetGameState(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""

        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "set_game_state: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }
        guard document.parts[partIdx].spriteAreaSpecModel?.recipe != nil else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe first."
        }

        document.parts[partIdx].updateRecipe { recipe in
            guard var r = recipe else { return }

            if let v = context.boolArgument(arguments["track_score"]) { r.gameState.trackScore = v }
            if let v = Int(arguments["initial_score"] ?? "")          { r.gameState.initialScore = v }
            if let v = context.boolArgument(arguments["track_lives"])  { r.gameState.trackLives = v }
            if let v = Int(arguments["initial_lives"] ?? "")           { r.gameState.initialLives = v }
            if let v = context.boolArgument(arguments["track_level"])  { r.gameState.trackLevel = v }
            if let v = context.boolArgument(arguments["track_timer"])  { r.gameState.trackTimer = v }
            if let v = Double(arguments["initial_timer_seconds"] ?? "") { r.gameState.initialTimerSeconds = v }

            r.gameState.scoreHUDEntityName = arguments["score_hud"] ?? r.gameState.scoreHUDEntityName
            r.gameState.livesHUDEntityName = arguments["lives_hud"] ?? r.gameState.livesHUDEntityName
            r.gameState.statusHUDEntityName = arguments["status_hud"] ?? r.gameState.statusHUDEntityName

            // Win condition shorthand: "reachScore:100", "reachGoal:flag", "allCollected:collectible"
            if let winStr = arguments["win"], !winStr.isEmpty {
                if let cond = parseWinLoseCondition(winStr) {
                    r.gameState.winConditions = [cond]
                }
            }
            // Lose condition shorthand: "zeroLives", "contactRole:hazard"
            if let loseStr = arguments["lose"], !loseStr.isEmpty {
                if let cond = parseWinLoseCondition(loseStr) {
                    r.gameState.loseConditions = [cond]
                }
            }

            recipe = r
        }

        let gs = document.parts[partIdx].spriteAreaSpecModel?.recipe?.gameState ?? GameState()
        let actualAreaName = document.parts[partIdx].name
        var summary: [String] = []
        if gs.trackScore  { summary.append("score (start \(gs.initialScore))") }
        if gs.trackLives  { summary.append("lives (start \(gs.initialLives))") }
        if gs.trackLevel  { summary.append("level") }
        if gs.trackTimer  { summary.append("timer (\(gs.initialTimerSeconds)s)") }
        return "Updated game state for '\(actualAreaName)': tracking \(summary.isEmpty ? "nothing" : summary.joined(separator: ", ")). Win conditions: \(gs.winConditions.count), lose: \(gs.loseConditions.count)."
    }

    // MARK: - bind_art_role

    /// Upsert an `ArtRoleBinding` in the recipe. When `generate=true` this
    /// marks the intent only — it does NOT call any image/network API.
    package static func executeBindArtRole(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let role     = arguments["role"] ?? ""

        guard !role.isEmpty else {
            return "bind_art_role: 'role' is required."
        }
        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "bind_art_role: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }
        guard document.parts[partIdx].spriteAreaSpecModel?.recipe != nil else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe first."
        }

        let assetName = arguments["asset_name"]
        let generate  = context.boolArgument(arguments["generate"]) ?? false
        let prompt    = arguments["prompt"]

        let binding = ArtRoleBinding(
            role: role,
            assetName: assetName,
            generate: generate,
            generationPrompt: prompt
        )

        document.parts[partIdx].updateRecipe { recipe in
            guard var r = recipe else { return }
            if let idx = r.artRoles.firstIndex(where: { $0.role == role }) {
                r.artRoles[idx] = binding
            } else {
                r.artRoles.append(binding)
            }
            recipe = r
        }

        let actualAreaName = document.parts[partIdx].name
        var note = "Bound art role '\(role)'"
        if let asset = assetName {
            note += " → asset '\(asset)'"
        }
        if generate {
            note += " (generate=true; call generate_image or generate_sprite_asset separately, then re-bind with the resulting asset name)"
        }
        return "\(note) in recipe for '\(actualAreaName)'."
    }

    // MARK: - set_controls

    /// Replace the recipe's control bindings.
    ///
    /// Bindings format: comma-separated `key=action` pairs, optionally with
    /// `:targetEntityName` and `/magnitude`: e.g.
    /// `"left=moveLeft,right=moveRight,up=moveUp,down=moveDown,space=jump"`.
    package static func executeSetControls(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName   = arguments["sprite_area_name"] ?? ""
        let bindingsStr = arguments["bindings"] ?? ""

        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "set_controls: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }
        guard document.parts[partIdx].spriteAreaSpecModel?.recipe != nil else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe first."
        }

        var bindings: [ControlBinding] = []
        for token in bindingsStr.components(separatedBy: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Format: "key=action" or "key=action:target/magnitude"
            // Split on first '='
            guard let eqRange = trimmed.range(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eqRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            var rest = String(trimmed[eqRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            // Optional ":targetEntityName"
            var targetEntityName: String? = nil
            if let colonIdx = rest.firstIndex(of: ":") {
                targetEntityName = String(rest[rest.index(after: colonIdx)...])
                rest = String(rest[..<colonIdx])
            }
            // Optional "/magnitude"
            var magnitude: Double? = nil
            if let slashIdx = rest.firstIndex(of: "/") {
                magnitude = Double(String(rest[rest.index(after: slashIdx)...]))
                rest = String(rest[..<slashIdx])
            }

            let action = ControlBinding.Action.decodeTolerant(rest)
            bindings.append(ControlBinding(key: key, action: action, targetEntityName: targetEntityName, magnitude: magnitude))
        }

        document.parts[partIdx].updateRecipe { recipe in
            recipe?.controls = bindings
        }

        let actualAreaName = document.parts[partIdx].name
        let bindingSummary = bindings.map { "\($0.key)→\($0.action.rawValue)" }.joined(separator: ", ")
        return "Set \(bindings.count) control binding(s) in recipe for '\(actualAreaName)': \(bindingSummary.isEmpty ? "(none)" : bindingSummary)."
    }

    // MARK: - build_game

    /// Compile the recipe into a validated HypeTalk scene script and merge it
    /// into the active scene. Routes through the script gate before storing;
    /// a refusal returns the sentinel and leaves the document unchanged.
    package static func executeBuildGame(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""

        // Fail-closed: resolve target.
        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "build_game: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }

        let actualAreaName = document.parts[partIdx].name

        guard let recipe = document.parts[partIdx].spriteAreaSpecModel?.recipe else {
            return "Sprite area '\(actualAreaName)' has no recipe. Call start_game_recipe first."
        }

        // Compile.
        let compilationResult = RecipeCompiler.compile(recipe, repository: document.assetRepository)

        // Build the merged scene: start from the active scene (or a fresh one).
        var scene: SceneSpec
        if let requested = arguments["scene_name"].flatMap({ $0.isEmpty ? nil : $0 }),
           let areaSpec = document.parts[partIdx].spriteAreaSpecModel,
           let entry = areaSpec.scenes.first(where: { $0.scene.name.lowercased() == requested.lowercased() }) {
            scene = entry.scene
        } else {
            scene = document.parts[partIdx].activeSceneSpec
                ?? SceneSpec(name: recipe.sceneName, size: recipe.sceneSize)
        }

        // Apply recipe geometry.
        scene.size = recipe.sceneSize
        scene.backgroundColor = recipe.backgroundColor
        scene.gravity = recipe.gravity

        // Merge nodes and script.
        RecipeCompiler.merge(compilationResult, into: &scene)

        // Script gate — defense in depth.
        // rawScript: the compiler-validated script before scene merge (pre-existing content excluded).
        // wrappedScript: the post-merge scene script (full content after merge).
        // Passing both surfaces the non-HypeTalk heuristic over the right payloads.
        let rawScript = compilationResult.sceneScript
        let wrappedScript = scene.script
        if let refusal = context.refusalForInvalidDraft(
            toolName: "build_game",
            arguments: arguments,
            targetDescription: "game scene in sprite area '\(actualAreaName)'",
            rawScript: rawScript,
            wrappedScript: wrappedScript,
            document: document,
            currentCardId: currentCardId
        ) {
            return refusal.encodedSentinel()
        }

        // Write the merged scene.
        _ = context.modifyActiveScene(partIndex: partIdx, document: &document) { $0 = scene }

        // Surface diagnostics.
        let diagnosticNote = compilationResult.diagnostics.isEmpty
            ? ""
            : "\nDiagnostics: \(compilationResult.diagnostics.joined(separator: "; "))"

        return "Built game in '\(actualAreaName)': \(compilationResult.nodes.count) node(s) compiled, \(compilationResult.recipeOwnedNodeNames.count) recipe-owned name(s). Scene size \(Int(recipe.sceneSize.width))×\(Int(recipe.sceneSize.height)).\(diagnosticNote)"
    }

    // MARK: - describe_game

    /// Return a human-readable summary of the current recipe for planning
    /// follow-up calls. Read-only: never mutates the document.
    package static func executeDescribeGame(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""

        guard let partIdx = resolveExistingArea(named: areaName, currentCardId: currentCardId, in: &document, context: context) else {
            return areaName.isEmpty
                ? "describe_game: could not resolve a unique sprite area. Pass sprite_area_name."
                : "Sprite area '\(areaName)' not found."
        }

        guard let recipe = document.parts[partIdx].spriteAreaSpecModel?.recipe else {
            return "Sprite area '\(document.parts[partIdx].name)' has no recipe. Call start_game_recipe to begin."
        }

        let actualAreaName = document.parts[partIdx].name
        var lines: [String] = []
        lines.append("Recipe for '\(actualAreaName)'")
        // Sanitize recipe fields before echoing to AI context so a hostile name cannot
        // inject newlines into the AI context string.
        let safeSceneName = sanitizeDescribeLine(recipe.sceneName)
        lines.append("  Scene: '\(safeSceneName)' \(Int(recipe.sceneSize.width))×\(Int(recipe.sceneSize.height)), bg=\(recipe.backgroundColor), gravity=(\(recipe.gravity.dx),\(recipe.gravity.dy))")

        lines.append("  Entities (\(recipe.entities.count)):")
        for entity in recipe.entities {
            let safeName = sanitizeDescribeLine(entity.name)
            let bList = entity.behaviors.isEmpty ? "none" : entity.behaviors.map { b -> String in
                let safeParams = b.params.map { "\($0.key)=\(sanitizeDescribeLine($0.value))" }.joined(separator: ",")
                return b.params.isEmpty ? b.kind.rawValue : "\(b.kind.rawValue)[\(safeParams)]"
            }.joined(separator: ", ")
            lines.append("    '\(safeName)' role=\(entity.role.rawValue) count=\(entity.count) \(Int(entity.size.width))×\(Int(entity.size.height)) @ (\(Int(entity.position.x)),\(Int(entity.position.y))) behaviors: \(bList)")
        }

        lines.append("  Rules (\(recipe.rules.count)):")
        for rule in recipe.rules {
            let aList = rule.actions.map { $0.kind.rawValue }.joined(separator: ", ")
            lines.append("    trigger=\(rule.trigger.kind.rawValue) → actions: \(aList.isEmpty ? "none" : aList)")
        }

        let gs = recipe.gameState
        lines.append("  GameState: score=\(gs.trackScore) lives=\(gs.trackLives) level=\(gs.trackLevel) timer=\(gs.trackTimer)")
        lines.append("  Win conditions: \(gs.winConditions.map { $0.kind.rawValue }.joined(separator: ", "))")
        lines.append("  Lose conditions: \(gs.loseConditions.map { $0.kind.rawValue }.joined(separator: ", "))")

        lines.append("  Controls (\(recipe.controls.count)): \(recipe.controls.map { "\($0.key)→\($0.action.rawValue)" }.joined(separator: ", "))")

        let artSummary = recipe.artRoles.map { b -> String in
            let safeRole = sanitizeDescribeLine(b.role)
            let safeAsset = b.assetName.map { sanitizeDescribeLine($0) } ?? (b.generate ? "generate" : "none")
            return "\(safeRole)→\(safeAsset)"
        }.joined(separator: ", ")
        lines.append("  Art roles (\(recipe.artRoles.count)): \(artSummary)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    /// Strip newlines and carriage returns from a recipe-derived string before
    /// embedding it in the describe_game AI context output. A hostile entity name
    /// with embedded newlines could otherwise inject extra lines into the AI prompt.
    private static func sanitizeDescribeLine(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ")
           .replacingOccurrences(of: "\r", with: " ")
    }

    /// Resolve an existing sprite area, fail-closed.
    ///
    /// Returns an index only when exactly one candidate can be unambiguously
    /// identified. If `areaName` is empty and 0 or 2+ areas exist, returns nil.
    private static func resolveExistingArea(
        named areaName: String,
        currentCardId: UUID,
        in document: inout HypeDocument,
        context: HypeToolExecutor
    ) -> Int? {
        if !areaName.isEmpty {
            return context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document)
        }
        // Auto-resolve: exactly one on the current card.
        let candidates = document.effectivePartsForCard(currentCardId).filter { $0.partType == .spriteArea }
        guard candidates.count == 1,
              let idx = document.parts.firstIndex(where: { $0.id == candidates[0].id }) else {
            return nil
        }
        return idx
    }

    /// The result of parsing a behavior token.
    private enum BehaviorParseResult {
        case success(Behavior)
        case unknownKind(String)
    }

    /// Parse a behavior token of the form `kind` or `kind:key=val;key2=val2`.
    ///
    /// Returns `.success(Behavior)` or `.unknownKind(kindString)`.
    private static func parseBehaviorToken(_ token: String) -> BehaviorParseResult {
        // Split kind from params on first ':'.
        let kindStr: String
        let paramsStr: String
        if let colonIdx = token.firstIndex(of: ":") {
            kindStr = String(token[..<colonIdx])
            paramsStr = String(token[token.index(after: colonIdx)...])
        } else {
            kindStr = token
            paramsStr = ""
        }
        guard let kind = BehaviorKind(rawValue: kindStr) else {
            return .unknownKind(kindStr)
        }
        let params = paramsStr.isEmpty ? [:] : parseParamsString(paramsStr)
        return .success(Behavior(kind: kind, params: params))
    }

    /// Parse `key=val;key2=val2` into a dictionary.
    private static func parseParamsString(_ raw: String) -> [String: String] {
        guard !raw.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in raw.components(separatedBy: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let eqIdx = trimmed.firstIndex(of: "=") {
                let k = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let v = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                result[k] = v
            }
        }
        return result
    }

    /// Parse a rule action token: `kind` or `kind:key=val;key2=val2`.
    private static func parseRuleActionToken(_ token: String) -> RuleAction {
        let kindStr: String
        let paramsStr: String
        if let colonIdx = token.firstIndex(of: ":") {
            kindStr = String(token[..<colonIdx])
            paramsStr = String(token[token.index(after: colonIdx)...])
        } else {
            kindStr = token
            paramsStr = ""
        }
        let kind = RuleAction.Kind.decodeTolerant(kindStr)
        let params = parseParamsString(paramsStr)
        return RuleAction(
            kind: kind,
            amount: Double(params["amount"] ?? ""),
            entityName: params["entityName"],
            message: params["message"],
            velocityX: Double(params["velocityX"] ?? ""),
            velocityY: Double(params["velocityY"] ?? ""),
            soundAsset: params["soundAsset"]
        )
    }

    /// Parse `"dx,dy"` into a `VectorSpec`.
    private static func parseVector(_ raw: String) -> VectorSpec? {
        guard !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: ",")
        guard parts.count == 2,
              let dx = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let dy = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return VectorSpec(dx: dx, dy: dy)
    }

    /// Parse win/lose condition shorthand strings.
    ///
    /// Supported formats:
    /// - `"reachScore:100"`
    /// - `"reachGoal:entityName"`
    /// - `"allCollected:collectible"`
    /// - `"zeroLives"`
    /// - `"contactRole:hazard"`
    /// - `"zeroTimer"` / `"zeroHealth"`
    private static func parseWinLoseCondition(_ raw: String) -> WinLoseCondition? {
        let parts = raw.components(separatedBy: ":")
        let kindStr = parts[0].trimmingCharacters(in: .whitespaces)
        let param   = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil

        switch kindStr.lowercased() {
        case "reachscore":
            let threshold = param.flatMap { Int($0) }
            return WinLoseCondition(kind: .reachScore, scoreThreshold: threshold)
        case "reachgoal":
            return WinLoseCondition(kind: .reachGoal, goalEntityName: param)
        case "allcollected":
            let role = param.map { EntityRole.decodeTolerant($0) }
            return WinLoseCondition(kind: .allCollected, collectibleRole: role)
        case "zerolives":
            return WinLoseCondition(kind: .zeroLives)
        case "zerotimer":
            return WinLoseCondition(kind: .zeroTimer)
        case "zerohealth":
            return WinLoseCondition(kind: .zeroHealth)
        case "contactrole":
            let role = param.map { EntityRole.decodeTolerant($0) }
            return WinLoseCondition(kind: .contactRole, contactRole: role)
        default:
            return nil
        }
    }
}
