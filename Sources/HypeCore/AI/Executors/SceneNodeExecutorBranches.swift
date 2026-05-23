import Foundation

/// Executor branches for SpriteKit scene-node mutating AI tools:
/// `apply_scene_diff`, `set_node_property`, `set_node_script`,
/// `set_physics_body`, `delete_scene_node`, `add_action`, `remove_all_actions`.
///
/// These are extracted from `HypeToolExecutor.execute` to reduce file size.
/// All tool names, arguments, and return strings are identical to the original;
/// this is a pure mechanical move with no behavioral change.
package enum SceneNodeExecutorBranches {

    // MARK: - Tool case branches

    /// Handles the `apply_scene_diff` tool case.
    package static func executeApplySceneDiff(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let diffJson = arguments["diff_json"] ?? ""
        guard let partIdx = context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
            return "Sprite area '\(areaName)' not found"
        }
        guard var spec = document.parts[partIdx].activeSceneSpec else {
            return "Invalid scene spec"
        }
        guard let diffData = diffJson.data(using: .utf8),
              let diff = try? JSONDecoder().decode(SceneDiff.self, from: diffData) else {
            return "Invalid diff JSON"
        }
        diff.apply(to: &spec)
        _ = context.modifyActiveScene(partIndex: partIdx, document: &document) { $0 = spec }
        return "Applied scene diff to '\(areaName)'. Scene now has \(spec.nodes.count) nodes."
    }

    /// Handles the `set_node_property` tool case.
    package static func executeSetNodeProperty(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let nodeName = arguments["node_name"] ?? ""
        let property = arguments["property"] ?? ""
        let value = arguments["value"] ?? ""
        let requestedSceneName = arguments["scene_name"] ?? ""
        guard let partIdx = context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
            return "Sprite area '\(areaName)' not found"
        }
        guard !property.isEmpty else {
            return "set_node_property: property is required"
        }
        var resolvedSceneName = ""
        var nodeFoundFlag = false
        var sceneFoundFlag = false
        context.modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
            let sceneIdx: Int?
            if !requestedSceneName.isEmpty {
                sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
            } else if let entry = areaSpec.activeSceneEntry {
                sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
            } else {
                sceneIdx = nil
            }
            guard let idx = sceneIdx else { return }
            sceneFoundFlag = true
            guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                return
            }
            nodeFoundFlag = true
            _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { node in
                context.applyNodeProperty(&node, property: property, value: value)
            }
            if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
            }
            resolvedSceneName = areaSpec.scenes[idx].scene.name
        }
        if !sceneFoundFlag {
            return !requestedSceneName.isEmpty
                ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                : "Sprite area '\(areaName)' has no active scene"
        }
        if !nodeFoundFlag {
            return "Node '\(nodeName)' not found in '\(areaName)'"
        }
        return "Set \(property) of '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)' to '\(value)'"
    }

    /// Handles the `set_node_script` tool case.
    package static func executeSetNodeScript(
        toolName: String,
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let nodeName = arguments["node_name"] ?? ""
        let rawScript = arguments["script"] ?? ""
        let requestedSceneName = arguments["scene_name"] ?? ""
        let wrapped = context.wrapScript(rawScript)
        if let refusal = context.refusalForInvalidDraft(
            toolName: toolName,
            arguments: arguments,
            targetDescription: "node '\(nodeName)' in sprite area '\(areaName)'",
            rawScript: rawScript,
            wrappedScript: wrapped,
            document: document,
            currentCardId: currentCardId
        ) {
            return refusal.encodedSentinel()
        }
        guard let partIdx = context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
            return "Sprite area '\(areaName)' not found"
        }
        var resolvedSceneName = ""
        var nodeFoundFlag = false
        var sceneFoundFlag = false
        context.modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
            let sceneIdx: Int?
            if !requestedSceneName.isEmpty {
                sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
            } else if let entry = areaSpec.activeSceneEntry {
                sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
            } else {
                sceneIdx = nil
            }
            guard let idx = sceneIdx else { return }
            sceneFoundFlag = true
            guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                return
            }
            nodeFoundFlag = true
            _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                n.script = wrapped
            }
            if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
            }
            resolvedSceneName = areaSpec.scenes[idx].scene.name
        }
        if !sceneFoundFlag {
            return !requestedSceneName.isEmpty
                ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                : "Sprite area '\(areaName)' has no active scene"
        }
        if !nodeFoundFlag {
            return "Node '\(nodeName)' not found in '\(areaName)'"
        }
        return "Set script of '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"
    }

    /// Handles the `set_physics_body` tool case.
    package static func executeSetPhysicsBody(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let nodeName = arguments["node_name"] ?? ""
        let requestedSceneName = arguments["scene_name"] ?? ""
        guard let partIdx = context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
            return "Sprite area '\(areaName)' not found"
        }
        var resolvedSceneName = ""
        var nodeFoundFlag = false
        var sceneFoundFlag = false
        context.modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
            let sceneIdx: Int?
            if !requestedSceneName.isEmpty {
                sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
            } else if let entry = areaSpec.activeSceneEntry {
                sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
            } else {
                sceneIdx = nil
            }
            guard let idx = sceneIdx else { return }
            sceneFoundFlag = true
            guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                return
            }
            nodeFoundFlag = true
            _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                var body = n.physicsBody ?? PhysicsBodySpec()
                if let bt = arguments["body_type"], let bodyType = PhysicsBodyType(rawValue: bt) {
                    body.bodyType = bodyType
                }
                if let dyn = arguments["is_dynamic"] {
                    body.isDynamic = (dyn.lowercased() == "true")
                }
                if let r = arguments["restitution"], let v = Double(r) {
                    body.restitution = v
                }
                if let f = arguments["friction"], let v = Double(f) {
                    body.friction = v
                }
                if let m = arguments["mass"], let v = Double(m) {
                    body.mass = v
                }
                if let g = arguments["affected_by_gravity"] {
                    body.affectedByGravity = (g.lowercased() == "true")
                }
                if let ar = arguments["allows_rotation"] {
                    body.allowsRotation = (ar.lowercased() == "true")
                }
                if let vx = arguments["velocity_x"], let v = Double(vx) {
                    body.velocityX = v
                }
                if let vy = arguments["velocity_y"], let v = Double(vy) {
                    body.velocityY = v
                }
                n.physicsBody = body
            }
            if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
            }
            resolvedSceneName = areaSpec.scenes[idx].scene.name
        }
        if !sceneFoundFlag {
            return !requestedSceneName.isEmpty
                ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                : "Sprite area '\(areaName)' has no active scene"
        }
        if !nodeFoundFlag {
            return "Node '\(nodeName)' not found in '\(areaName)'"
        }
        return "Configured physics body on '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"
    }

    /// Handles the `delete_scene_node` tool case.
    package static func executeDeleteSceneNode(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let nodeName = arguments["node_name"] ?? ""
        let requestedSceneName = arguments["scene_name"] ?? ""
        guard let partIdx = context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
            return "Sprite area '\(areaName)' not found"
        }
        var resolvedSceneName = ""
        var nodeFoundFlag = false
        var sceneFoundFlag = false
        context.modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
            let sceneIdx: Int?
            if !requestedSceneName.isEmpty {
                sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
            } else if let entry = areaSpec.activeSceneEntry {
                sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
            } else {
                sceneIdx = nil
            }
            guard let idx = sceneIdx else { return }
            sceneFoundFlag = true
            guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                return
            }
            nodeFoundFlag = true
            _ = areaSpec.scenes[idx].scene.removeNode(id: nodeFound.id)
            if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
            }
            resolvedSceneName = areaSpec.scenes[idx].scene.name
        }
        if !sceneFoundFlag {
            return !requestedSceneName.isEmpty
                ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                : "Sprite area '\(areaName)' has no active scene"
        }
        if !nodeFoundFlag {
            return "Node '\(nodeName)' not found in '\(areaName)'"
        }
        return "Deleted node '\(nodeName)' from scene '\(resolvedSceneName)' of '\(areaName)'"
    }

    /// Handles the `add_action` tool case.
    package static func executeAddAction(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let nodeName = arguments["node_name"] ?? ""
        let actionTypeStr = arguments["action_type"] ?? ""
        let requestedSceneName = arguments["scene_name"] ?? ""
        guard let actionType = ActionType(rawValue: actionTypeStr) else {
            let valid = "moveTo, moveBy, rotateTo, rotateBy, scaleTo, scaleBy, fadeTo, fadeIn, fadeOut, sequence, group, repeatForever, repeatCount, wait, removeFromParent, followPath, setTexture, animate, playAudio, stopAudio, changeVolume, resize, hide, unhide, colorize, speedTo, speedBy"
            return "Invalid action_type '\(actionTypeStr)'. Valid: \(valid)"
        }
        guard let partIdx = context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
            return "Sprite area '\(areaName)' not found"
        }
        let duration = Double(arguments["duration"] ?? "0.25") ?? 0.25
        let actionName = arguments["name"] ?? ""
        var parameters: [String: String] = [:]
        if let json = arguments["parameters_json"], !json.isEmpty,
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in dict {
                if let str = v as? String {
                    parameters[k] = str
                } else if let num = v as? NSNumber {
                    parameters[k] = num.stringValue
                } else if let bool = v as? Bool {
                    parameters[k] = bool ? "true" : "false"
                } else {
                    parameters[k] = String(describing: v)
                }
            }
        }
        let action = ActionSpec(
            actionType: actionType,
            name: actionName,
            duration: duration,
            parameters: parameters,
            children: nil
        )
        var resolvedSceneName = ""
        var nodeFoundFlag = false
        var sceneFoundFlag = false
        context.modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
            let sceneIdx: Int?
            if !requestedSceneName.isEmpty {
                sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
            } else if let entry = areaSpec.activeSceneEntry {
                sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
            } else {
                sceneIdx = nil
            }
            guard let idx = sceneIdx else { return }
            sceneFoundFlag = true
            guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                return
            }
            nodeFoundFlag = true
            _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                n.actions.append(action)
            }
            if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
            }
            resolvedSceneName = areaSpec.scenes[idx].scene.name
        }
        if !sceneFoundFlag {
            return !requestedSceneName.isEmpty
                ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                : "Sprite area '\(areaName)' has no active scene"
        }
        if !nodeFoundFlag {
            return "Node '\(nodeName)' not found in '\(areaName)'"
        }
        return "Added \(actionType.rawValue) action (duration=\(duration)) to '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"
    }

    /// Handles the `remove_all_actions` tool case.
    package static func executeRemoveAllActions(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let areaName = arguments["sprite_area_name"] ?? ""
        let nodeName = arguments["node_name"] ?? ""
        let requestedSceneName = arguments["scene_name"] ?? ""
        guard let partIdx = context.spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
            return "Sprite area '\(areaName)' not found"
        }
        var resolvedSceneName = ""
        var nodeFoundFlag = false
        var sceneFoundFlag = false
        var removedCount = 0
        context.modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
            let sceneIdx: Int?
            if !requestedSceneName.isEmpty {
                sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
            } else if let entry = areaSpec.activeSceneEntry {
                sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
            } else {
                sceneIdx = nil
            }
            guard let idx = sceneIdx else { return }
            sceneFoundFlag = true
            guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                return
            }
            nodeFoundFlag = true
            removedCount = nodeFound.actions.count
            _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                n.actions = []
            }
            if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
            }
            resolvedSceneName = areaSpec.scenes[idx].scene.name
        }
        if !sceneFoundFlag {
            return !requestedSceneName.isEmpty
                ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                : "Sprite area '\(areaName)' has no active scene"
        }
        if !nodeFoundFlag {
            return "Node '\(nodeName)' not found in '\(areaName)'"
        }
        return "Removed \(removedCount) action(s) from '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"
    }
}
