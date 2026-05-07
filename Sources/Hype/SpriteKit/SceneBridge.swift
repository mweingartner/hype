import SpriteKit
import HypeCore
import simd

struct SceneTextureCacheStats: Equatable {
    var referencedTextureCount: Int
    var cachedTextureCount: Int
    var missingTextureCount: Int
    var referencedAssetIDs: [UUID]
    var cachedAssetIDs: [UUID]
    var missingAssetIDs: [UUID]
}

/// Translates between SceneSpec (data model) and live SKScene nodes.
@MainActor
final class SceneBridge {
    let registry = NodeRegistry()
    private var converter: CoordinateConverter
    private var textureCache: [UUID: SKTexture] = [:]
    weak var eventDelegate: SpriteEventDelegate?

    init(sceneHeight: Double) {
        self.converter = CoordinateConverter(sceneHeight: sceneHeight)
    }

    /// Apply property changes from a SceneSpec to live SKNodes without rebuilding.
    /// Returns `true` if a full rebuild is needed (node count changed).
    func applyLiveUpdates(spec: SceneSpec, to scene: SKScene, repository: SpriteRepository) -> Bool {
        // Update scene-level properties
        scene.backgroundColor = nsColor(from: spec.backgroundColor)
        scene.physicsWorld.gravity = CGVector(dx: spec.gravity.dx, dy: spec.gravity.dy)
        scene.isPaused = spec.isPaused

        // Check if structural change occurred (node added/removed)
        let specNodeIds = Set(spec.allNodeIDs)
        let registryIds = Set(registry.allIDs())
        if specNodeIds != registryIds {
            return true  // need full rebuild
        }

        // Update each node's properties
        for nodeSpec in spec.allNodes {
            guard let node = registry.node(for: nodeSpec.id) else {
                return true
            }

            // Position (convert from Hype to SpriteKit coords)
            let skPos = converter.toSK(nodeSpec.position)
            node.position = CGPoint(x: skPos.x, y: skPos.y)

            // Common properties
            node.zPosition = CGFloat(nodeSpec.zPosition)
            node.zRotation = CGFloat(converter.toSKRotation(nodeSpec.rotation))
            node.xScale = CGFloat(nodeSpec.xScale)
            node.yScale = CGFloat(nodeSpec.yScale)
            node.alpha = CGFloat(nodeSpec.alpha)
            node.isHidden = nodeSpec.isHidden
            node.name = nodeSpec.name

            // Size (for sprites)
            if let sprite = node as? SKSpriteNode, let size = nodeSpec.size {
                sprite.size = CGSize(width: size.width, height: size.height)
                if let ref = nodeSpec.assetRef, let texture = loadTexture(for: ref, from: repository) {
                    sprite.texture = texture
                }
            }

            // Label text. Apply textStyle traits (bold / italic) to
            // the resolved font; underline / strikethrough land via
            // SKLabelNode.attributedText so they survive into the
            // glyph pass. `attributedText` overrides `text` when
            // set, so we only touch it when there's something to
            // decorate — otherwise the simpler `text` path stays.
            if let label = node as? SKLabelNode {
                label.text = nodeSpec.text ?? ""
                if let fn = nodeSpec.fontName { label.fontName = fn }
                if let fs = nodeSpec.fontSize { label.fontSize = CGFloat(fs) }
                if let fc = nodeSpec.fontColor { label.fontColor = nsColor(from: fc) }
                Self.applyLabelTextStyle(label, spec: nodeSpec)
            }

            // Shape properties
            if let shape = node as? SKShapeNode, let ss = nodeSpec.shapeSpec {
                shape.fillColor = nsColor(from: ss.fillColor)
                shape.strokeColor = nsColor(from: ss.strokeColor)
                shape.lineWidth = CGFloat(ss.lineWidth)
            }

            // Physics body runtime updates
            if let physics = nodeSpec.physicsBody, let body = node.physicsBody {
                body.isDynamic = physics.isDynamic
                body.affectedByGravity = physics.affectedByGravity
                body.allowsRotation = physics.allowsRotation
                body.restitution = CGFloat(physics.restitution)
                body.friction = CGFloat(physics.friction)
                if let mass = physics.mass { body.mass = CGFloat(mass) }
                if let d = physics.density { body.density = CGFloat(d) }
                if let ld = physics.linearDamping { body.linearDamping = CGFloat(ld) }
                if let ad = physics.angularDamping { body.angularDamping = CGFloat(ad) }
                if let vx = physics.velocityX, let vy = physics.velocityY {
                    body.velocity = CGVector(dx: vx, dy: vy)
                }
                if let av = physics.angularVelocity {
                    body.angularVelocity = CGFloat(av)
                }
            }

            // Emitter updates
            if let emitter = node as? SKEmitterNode, let es = nodeSpec.emitterSpec {
                emitter.particleBirthRate = CGFloat(es.particleBirthRate)
                emitter.particleLifetime = CGFloat(es.particleLifetime)
                emitter.particleSpeed = CGFloat(es.particleSpeed)
                emitter.particleAlpha = CGFloat(es.particleAlpha)
                emitter.particleScale = CGFloat(es.particleScale)
                emitter.particleColor = nsColor(from: es.particleColor)
            }

            // Camera target constraint update
            if nodeSpec.nodeType == .camera, let cam = node as? SKCameraNode {
                if let targetName = nodeSpec.cameraTarget, !targetName.isEmpty,
                   let targetSpec = spec.node(named: targetName),
                   let targetNode = registry.node(for: targetSpec.id) {
                    let constraint = SKConstraint.distance(SKRange(constantValue: 0), to: targetNode)
                    cam.constraints = [constraint]
                } else {
                    cam.constraints = nil
                }
            }
        }

        return false  // live updates sufficient
    }

    /// Full rebuild: remove all children from scene, create nodes from spec.
    func apply(spec: SceneSpec, to scene: SKScene, repository: SpriteRepository) {
        registry.clear()
        scene.removeAllChildren()
        scene.removeAllActions()

        // Apply scene-level properties
        scene.backgroundColor = nsColor(from: spec.backgroundColor)
        scene.physicsWorld.gravity = CGVector(dx: spec.gravity.dx, dy: spec.gravity.dy)
        scene.isPaused = spec.isPaused

        // Apply scale mode
        switch spec.scaleMode {
        case .fill:       scene.scaleMode = .fill
        case .aspectFill: scene.scaleMode = .aspectFill
        case .aspectFit:  scene.scaleMode = .aspectFit
        case .resizeFill: scene.scaleMode = .resizeFill
        }

        // Create nodes
        for nodeSpec in spec.nodes {
            let node = makeNode(from: nodeSpec, repository: repository)
            scene.addChild(node)
        }

        // Apply physics joints after all nodes have been created
        applyJoints(spec: spec, scene: scene)

        // Apply constraints after all nodes have been created
        applyConstraints(spec: spec)

        // Apply physics fields
        applyFields(spec: spec, scene: scene)

        // Assign camera nodes to the scene and set up follow targets
        for nodeSpec in spec.nodes where nodeSpec.nodeType == .camera {
            if let camNode = registry.node(for: nodeSpec.id) as? SKCameraNode {
                scene.camera = camNode
                // Camera follow target
                if let targetName = nodeSpec.cameraTarget, !targetName.isEmpty,
                   let targetSpec = spec.node(named: targetName),
                   let targetNode = registry.node(for: targetSpec.id) {
                    let constraint = SKConstraint.distance(SKRange(constantValue: 0), to: targetNode)
                    camNode.constraints = [constraint]
                }
            }
        }
    }

    /// Build an SKNode tree from a HypeNodeSpec (recursive for children).
    func makeNode(from spec: HypeNodeSpec, repository: SpriteRepository) -> SKNode {
        let node: SKNode

        switch spec.nodeType {
        case .sprite:
            let sprite = SKSpriteNode()
            // Load texture from asset ref
            if let ref = spec.assetRef, let texture = loadTexture(for: ref, from: repository) {
                sprite.texture = texture
                sprite.size = texture.size()
            }
            if let s = spec.size {
                sprite.size = CGSize(width: s.width, height: s.height)
            }
            node = sprite

        case .label:
            let label = SKLabelNode(text: spec.text ?? "")
            label.fontName = spec.fontName ?? "Helvetica"
            label.fontSize = CGFloat(spec.fontSize ?? 14)
            label.fontColor = nsColor(from: spec.fontColor ?? "#000000")
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            Self.applyLabelTextStyle(label, spec: spec)
            node = label

        case .shape:
            if let shapeSpec = spec.shapeSpec {
                let shape: SKShapeNode
                let size = spec.size ?? SizeSpec(width: 50, height: 50)
                switch shapeSpec.shapeType {
                case .rect:
                    shape = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height), cornerRadius: CGFloat(shapeSpec.cornerRadius))
                case .circle:
                    shape = SKShapeNode(circleOfRadius: CGFloat(min(size.width, size.height) / 2))
                case .ellipse:
                    shape = SKShapeNode(ellipseOf: CGSize(width: size.width, height: size.height))
                case .path:
                    if let points = shapeSpec.path, points.count >= 2 {
                        let path = CGMutablePath()
                        let first = converter.toSK(points[0])
                        path.move(to: CGPoint(x: first.x, y: first.y))
                        for i in 1..<points.count {
                            let p = converter.toSK(points[i])
                            path.addLine(to: CGPoint(x: p.x, y: p.y))
                        }
                        shape = SKShapeNode(path: path)
                    } else {
                        // No explicit path — render as an upward-pointing
                        // triangle fitting the node's declared size. This
                        // makes "triangle" (and other polygon names the
                        // tolerant decoder maps to .path) render as a
                        // recognizable shape instead of a silent empty
                        // node or a fallback rect.
                        let halfW = CGFloat(size.width / 2)
                        let halfH = CGFloat(size.height / 2)
                        let path = CGMutablePath()
                        path.move(to: CGPoint(x: 0, y: halfH))
                        path.addLine(to: CGPoint(x: -halfW, y: -halfH))
                        path.addLine(to: CGPoint(x: halfW, y: -halfH))
                        path.closeSubpath()
                        shape = SKShapeNode(path: path)
                    }
                }
                shape.fillColor = nsColor(from: shapeSpec.fillColor)
                shape.strokeColor = nsColor(from: shapeSpec.strokeColor)
                shape.lineWidth = CGFloat(shapeSpec.lineWidth)
                node = shape
            } else {
                node = SKNode()
            }

        case .group:
            node = SKNode()

        case .emitter:
            let emitter = SKEmitterNode()
            if let es = spec.emitterSpec {
                emitter.particleBirthRate = CGFloat(es.particleBirthRate)
                emitter.particleLifetime = CGFloat(es.particleLifetime)
                emitter.particleSpeed = CGFloat(es.particleSpeed)
                emitter.particleSpeedRange = CGFloat(es.particleSpeedRange)
                emitter.emissionAngle = CGFloat(es.emissionAngle * .pi / 180)
                emitter.emissionAngleRange = CGFloat(es.emissionAngleRange * .pi / 180)
                emitter.particleAlpha = CGFloat(es.particleAlpha)
                emitter.particleAlphaSpeed = CGFloat(es.particleAlphaSpeed)
                emitter.particleScale = CGFloat(es.particleScale)
                emitter.particleScaleSpeed = CGFloat(es.particleScaleSpeed)
                emitter.particleColorBlendFactor = CGFloat(es.particleColorBlendFactor)
                emitter.particleColor = nsColor(from: es.particleColor)
                emitter.particlePositionRange = CGVector(dx: es.particlePositionRangeX, dy: es.particlePositionRangeY)
                // Use a small white circle as default particle texture
                let size = CGSize(width: 8, height: 8)
                let renderer = NSImage(size: size)
                renderer.lockFocus()
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
                renderer.unlockFocus()
                emitter.particleTexture = SKTexture(image: renderer)
            } else {
                emitter.particleBirthRate = 50
                emitter.particleLifetime = 2
                emitter.particleSpeed = 100
            }
            // If emitter has asset ref, use that as particle texture
            if let ref = spec.assetRef, let texture = loadTexture(for: ref, from: repository) {
                emitter.particleTexture = texture
            }
            node = emitter

        case .audio:
            // Load audio from repository asset and create SKAudioNode
            if let ref = spec.assetRef, let asset = repository.asset(byId: ref.id) {
                // Write audio data to a temp file so SKAudioNode can load it
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("\(ref.id.uuidString).\(audioExtension(for: asset.mimeType))")
                if !FileManager.default.fileExists(atPath: tempFile.path) {
                    try? asset.data.write(to: tempFile)
                }
                let audioNode = SKAudioNode(url: tempFile)
                audioNode.autoplayLooped = spec.audioLoop ?? false
                audioNode.isPositional = spec.audioPositional ?? false
                if !(spec.audioAutoplay ?? true) {
                    audioNode.autoplayLooped = false
                }
                node = audioNode
            } else {
                node = SKNode() // Placeholder if asset missing
            }

        case .tileMap:
            if let tmSpec = spec.tileMapSpec, let tsRef = tmSpec.tileSetAssetRef,
               let tsAsset = repository.asset(byId: tsRef.id),
               let tsImage = NSImage(data: tsAsset.data) {
                let texture = SKTexture(image: tsImage)
                // Prefer the asset's classified tile metadata when
                // the spec is missing or nonsensical (tile size 0,
                // columns 0). This handles legacy specs that were
                // built before Interpreter.createTileMap knew how
                // to pull metadata from the asset — the renderer
                // recovers instead of division-by-zero-ing.
                let effectiveTileW: Double = {
                    if tmSpec.tileWidth > 0 { return tmSpec.tileWidth }
                    if tsAsset.tileWidth > 0 { return Double(tsAsset.tileWidth) }
                    return 32
                }()
                let effectiveTileH: Double = {
                    if tmSpec.tileHeight > 0 { return tmSpec.tileHeight }
                    if tsAsset.tileHeight > 0 { return Double(tsAsset.tileHeight) }
                    return 32
                }()
                let sheetCols: Int = {
                    if tmSpec.tileSetColumns > 0 { return tmSpec.tileSetColumns }
                    if tsAsset.tileColumns > 0 { return tsAsset.tileColumns }
                    // Fall back to deriving from image width when
                    // nothing is specified.
                    return max(1, Int(tsImage.size.width / CGFloat(effectiveTileW)))
                }()
                let tileSize = CGSize(width: effectiveTileW, height: effectiveTileH)

                // Build tile groups from the sprite sheet. Divide
                // image height by tile height to infer the number
                // of rows in the sheet — guarded against zero.
                var tileGroups: [SKTileGroup] = []
                let rowsInSheet = max(1, Int(tsImage.size.height / CGFloat(effectiveTileH)))
                let tileCount = sheetCols * rowsInSheet

                for i in 0..<tileCount {
                    let col = i % sheetCols
                    let row = i / sheetCols
                    let texRect = CGRect(
                        x: CGFloat(col) * CGFloat(effectiveTileW) / tsImage.size.width,
                        y: 1.0 - CGFloat(row + 1) * CGFloat(effectiveTileH) / tsImage.size.height,
                        width: CGFloat(effectiveTileW) / tsImage.size.width,
                        height: CGFloat(effectiveTileH) / tsImage.size.height
                    )
                    let tileTexture = SKTexture(rect: texRect, in: texture)
                    let tileDef = SKTileDefinition(texture: tileTexture, size: tileSize)
                    tileGroups.append(SKTileGroup(tileDefinition: tileDef))
                }

                let emptyGroup = SKTileGroup.empty()
                let finalTileSet = SKTileSet(tileGroups: [emptyGroup] + tileGroups)
                let tileMap = SKTileMapNode(
                    tileSet: finalTileSet,
                    columns: tmSpec.columns,
                    rows: tmSpec.rows,
                    tileSize: tileSize
                )

                // Fill with tile data
                for (rowIdx, row) in tmSpec.tileData.enumerated() {
                    for (colIdx, tileIdx) in row.enumerated() {
                        if rowIdx < tmSpec.rows && colIdx < tmSpec.columns && tileIdx >= 0 {
                            let groupIdx = tileIdx + 1  // +1 because 0 is empty
                            if groupIdx < finalTileSet.tileGroups.count {
                                tileMap.setTileGroup(finalTileSet.tileGroups[groupIdx], forColumn: colIdx, row: tmSpec.rows - 1 - rowIdx)
                            }
                        }
                    }
                }

                node = tileMap
            } else {
                // Placeholder: empty tile map
                let tileSize = CGSize(width: spec.tileMapSpec?.tileWidth ?? 32, height: spec.tileMapSpec?.tileHeight ?? 32)
                let ts = SKTileSet(tileGroups: [SKTileGroup.empty()])
                node = SKTileMapNode(tileSet: ts, columns: spec.tileMapSpec?.columns ?? 10, rows: spec.tileMapSpec?.rows ?? 10, tileSize: tileSize)
            }

        case .video:
            if let ref = spec.assetRef, let asset = repository.asset(byId: ref.id) {
                // Write video data to temp file so SKVideoNode can load it
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("\(ref.id.uuidString).mp4")
                if !FileManager.default.fileExists(atPath: tempFile.path) {
                    try? asset.data.write(to: tempFile)
                }
                let videoNode = SKVideoNode(url: tempFile)
                if let s = spec.size {
                    videoNode.size = CGSize(width: s.width, height: s.height)
                }
                if spec.videoAutoplay ?? true {
                    videoNode.play()
                }
                node = videoNode
            } else {
                node = SKSpriteNode(color: .darkGray, size: CGSize(width: spec.size?.width ?? 100, height: spec.size?.height ?? 75))
            }

        case .camera:
            let cam = SKCameraNode()
            node = cam

        case .crop:
            let cropNode = SKCropNode()
            if let ref = spec.assetRef, let texture = loadTexture(for: ref, from: repository) {
                cropNode.maskNode = SKSpriteNode(texture: texture)
            }
            node = cropNode

        case .effect:
            let effectNode = SKEffectNode()
            effectNode.shouldEnableEffects = true
            if let filterName = spec.shapeSpec?.fillColor, !filterName.isEmpty {
                effectNode.filter = CIFilter(name: filterName)
            }
            node = effectNode

        case .light:
            let lightNode = SKLightNode()
            lightNode.categoryBitMask = 1
            if let fc = spec.fontColor {
                lightNode.lightColor = nsColor(from: fc)
            }
            lightNode.falloff = CGFloat(spec.fontSize ?? 1.0)
            lightNode.ambientColor = nsColor(from: spec.shapeSpec?.fillColor ?? "#333333")
            node = lightNode
        }

        // Common properties (use converter for position)
        let skPos = converter.toSK(spec.position)
        node.position = CGPoint(x: skPos.x, y: skPos.y)
        node.zPosition = CGFloat(spec.zPosition)
        node.zRotation = CGFloat(converter.toSKRotation(spec.rotation))
        node.xScale = CGFloat(spec.xScale)
        node.yScale = CGFloat(spec.yScale)
        node.alpha = CGFloat(spec.alpha)
        node.isHidden = spec.isHidden
        node.name = spec.name

        // Register
        registry.register(id: spec.id, node: node)

        // Physics body
        if let physics = spec.physicsBody {
            node.physicsBody = buildPhysicsBody(physics, node: node, nodeSpec: spec)
        }

        // Actions — wrap named actions with completion callback for actionFinished event
        for actionSpec in spec.actions {
            var action = buildAction(actionSpec, repository: repository)
            if !actionSpec.name.isEmpty {
                let name = actionSpec.name
                let nodeId = spec.id
                let delegate = self.eventDelegate
                action = SKAction.sequence([action, SKAction.run { [weak delegate] in
                    guard let delegate = delegate,
                          let scene = node.scene as? HypeSKScene else { return }
                    delegate.spriteScene(scene, didReceiveEvent: .actionFinished(name: name, nodeId: nodeId))
                }])
                node.run(action, withKey: name)
            } else {
                node.run(action)
            }
        }

        // Recursively add children
        for childSpec in spec.children {
            let childNode = makeNode(from: childSpec, repository: repository)
            node.addChild(childNode)
        }

        return node
    }

    // MARK: - Physics Body

    func buildPhysicsBody(_ spec: PhysicsBodySpec, node: SKNode, nodeSpec: HypeNodeSpec) -> SKPhysicsBody {
        let size = nodeSpec.size ?? SizeSpec(width: 50, height: 50)
        let body: SKPhysicsBody
        switch spec.bodyType {
        case .circle:
            body = SKPhysicsBody(circleOfRadius: CGFloat(min(size.width, size.height) / 2))
        case .rect:
            body = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: size.height))
        case .texture:
            if let sprite = node as? SKSpriteNode, let texture = sprite.texture {
                body = SKPhysicsBody(texture: texture, size: sprite.size)
            } else {
                body = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: size.height))
            }
        case .edge:
            body = SKPhysicsBody(edgeLoopFrom: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
        case .none:
            return SKPhysicsBody()
        }
        body.isDynamic = spec.isDynamic
        body.categoryBitMask = spec.categoryBitmask
        body.contactTestBitMask = spec.contactTestBitmask
        body.collisionBitMask = spec.collisionBitmask
        body.restitution = CGFloat(spec.restitution)
        body.friction = CGFloat(spec.friction)
        if let mass = spec.mass { body.mass = CGFloat(mass) }
        body.affectedByGravity = spec.affectedByGravity
        body.allowsRotation = spec.allowsRotation
        if let d = spec.density { body.density = CGFloat(d) }
        if let ld = spec.linearDamping { body.linearDamping = CGFloat(ld) }
        if let ad = spec.angularDamping { body.angularDamping = CGFloat(ad) }
        if let vx = spec.velocityX, let vy = spec.velocityY {
            body.velocity = CGVector(dx: vx, dy: vy)
        }
        if let av = spec.angularVelocity { body.angularVelocity = CGFloat(av) }
        return body
    }

    // MARK: - Actions

    func buildAction(_ spec: ActionSpec, repository: SpriteRepository? = nil) -> SKAction {
        let dur = spec.duration
        switch spec.actionType {
        case .moveTo:
            let x = Double(spec.parameters["x"] ?? "0") ?? 0
            let y = Double(spec.parameters["y"] ?? "0") ?? 0
            let skPt = converter.toSK(PointSpec(x: x, y: y))
            return SKAction.move(to: CGPoint(x: skPt.x, y: skPt.y), duration: dur)
        case .moveBy:
            let dx = Double(spec.parameters["dx"] ?? "0") ?? 0
            let dy = Double(spec.parameters["dy"] ?? "0") ?? 0
            return SKAction.moveBy(x: CGFloat(dx), y: CGFloat(-dy), duration: dur)
        case .rotateTo:
            let deg = Double(spec.parameters["degrees"] ?? "0") ?? 0
            return SKAction.rotate(toAngle: CGFloat(converter.toSKRotation(deg)), duration: dur)
        case .rotateBy:
            let deg = Double(spec.parameters["degrees"] ?? "0") ?? 0
            return SKAction.rotate(byAngle: CGFloat(converter.toSKRotation(deg)), duration: dur)
        case .scaleTo:
            let s = Double(spec.parameters["scale"] ?? "1") ?? 1
            return SKAction.scale(to: CGFloat(s), duration: dur)
        case .scaleBy:
            let s = Double(spec.parameters["scale"] ?? "1") ?? 1
            return SKAction.scale(by: CGFloat(s), duration: dur)
        case .fadeTo:
            let a = Double(spec.parameters["alpha"] ?? "1") ?? 1
            return SKAction.fadeAlpha(to: CGFloat(a), duration: dur)
        case .fadeIn:
            return SKAction.fadeIn(withDuration: dur)
        case .fadeOut:
            return SKAction.fadeOut(withDuration: dur)
        case .wait:
            return SKAction.wait(forDuration: dur)
        case .removeFromParent:
            return SKAction.removeFromParent()
        case .sequence:
            let children = (spec.children ?? []).map { buildAction($0, repository: repository) }
            return SKAction.sequence(children)
        case .group:
            let children = (spec.children ?? []).map { buildAction($0, repository: repository) }
            return SKAction.group(children)
        case .repeatForever:
            if let child = spec.children?.first {
                return SKAction.repeatForever(buildAction(child, repository: repository))
            }
            return SKAction.wait(forDuration: 0)
        case .repeatCount:
            let count = Int(spec.parameters["count"] ?? "1") ?? 1
            if let child = spec.children?.first {
                return SKAction.repeat(buildAction(child, repository: repository), count: count)
            }
            return SKAction.wait(forDuration: 0)
        case .followPath:
            let w = Double(spec.parameters["width"] ?? "100") ?? 100
            let h = Double(spec.parameters["height"] ?? "100") ?? 100
            let rect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
            let path = CGPath(rect: rect, transform: nil)
            return SKAction.follow(path, asOffset: true, orientToPath: false, duration: dur)
        case .setTexture:
            // Change sprite's texture to a named asset
            if let repo = repository, let assetName = spec.parameters["assetName"] {
                let trimmed = assetName.trimmingCharacters(in: .whitespaces)
                if let asset = repo.asset(byName: trimmed), let img = NSImage(data: asset.data) {
                    let texture = SKTexture(image: img)
                    return SKAction.setTexture(texture)
                }
            }
            return SKAction.wait(forDuration: 0)
        case .animate:
            // Animate through texture frames — params: "frames" (comma-separated asset names), "fps"
            let fps = Double(spec.parameters["fps"] ?? "12") ?? 12
            let timePerFrame = 1.0 / fps
            let frameNames = (spec.parameters["frames"] ?? "").split(separator: ",").map(String.init)
            if let repo = repository {
                var textures: [SKTexture] = []
                for name in frameNames {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if let asset = repo.asset(byName: trimmed), let img = NSImage(data: asset.data) {
                        textures.append(SKTexture(image: img))
                    }
                }
                if !textures.isEmpty {
                    return SKAction.animate(with: textures, timePerFrame: timePerFrame)
                }
            }
            return SKAction.wait(forDuration: dur)
        case .playAudio:
            return SKAction.play()
        case .stopAudio:
            return SKAction.stop()
        case .changeVolume:
            let vol = Float(spec.parameters["volume"] ?? "1.0") ?? 1.0
            return SKAction.changeVolume(to: vol, duration: dur)
        case .resize:
            let w = Double(spec.parameters["width"] ?? "100") ?? 100
            let h = Double(spec.parameters["height"] ?? "100") ?? 100
            return SKAction.resize(toWidth: CGFloat(w), height: CGFloat(h), duration: dur)
        case .hide:
            return SKAction.hide()
        case .unhide:
            return SKAction.unhide()
        case .colorize:
            let color = nsColor(from: spec.parameters["color"] ?? "#FF0000")
            let factor = CGFloat(Double(spec.parameters["factor"] ?? "1") ?? 1)
            return SKAction.colorize(with: color, colorBlendFactor: factor, duration: dur)
        case .speedTo:
            let speed = CGFloat(Double(spec.parameters["speed"] ?? "1") ?? 1)
            return SKAction.speed(to: speed, duration: dur)
        case .speedBy:
            let speed = CGFloat(Double(spec.parameters["speed"] ?? "1") ?? 1)
            return SKAction.speed(by: speed, duration: dur)
        }
    }

    // MARK: - Transitions

    /// Build an SKTransition from a TransitionSpec.
    func buildTransition(_ spec: TransitionSpec) -> SKTransition {
        let dur = spec.duration
        switch spec.type {
        case .fade:            return SKTransition.fade(withDuration: dur)
        case .push:            return SKTransition.push(with: .left, duration: dur)
        case .moveIn:          return SKTransition.moveIn(with: .right, duration: dur)
        case .reveal:          return SKTransition.reveal(with: .down, duration: dur)
        case .crossfade:       return SKTransition.crossFade(withDuration: dur)
        case .doorway:         return SKTransition.doorway(withDuration: dur)
        case .flipHorizontal:  return SKTransition.flipHorizontal(withDuration: dur)
        case .flipVertical:    return SKTransition.flipVertical(withDuration: dur)
        }
    }

    // MARK: - Audio Helpers

    private func audioExtension(for mimeType: String) -> String {
        switch mimeType {
        case "audio/mpeg": return "mp3"
        case "audio/wav": return "wav"
        case "audio/aiff": return "aiff"
        case "audio/mp4": return "m4a"
        case "audio/x-caf": return "caf"
        default: return "mp3"
        }
    }

    // MARK: - Texture Loading

    func loadTexture(for ref: AssetRef, from repository: SpriteRepository) -> SKTexture? {
        if let cached = textureCache[ref.id] { return cached }
        guard let asset = repository.asset(byId: ref.id) else { return nil }
        guard let image = NSImage(data: asset.data) else { return nil }
        let texture = SKTexture(image: image)
        textureCache[ref.id] = texture
        return texture
    }

    func preloadTextures(for spec: SceneSpec, repository: SpriteRepository) {
        for assetID in spec.referencedAssetIDs {
            guard let asset = repository.asset(byId: assetID) else { continue }
            let ref = repository.assetRef(for: asset)
            _ = loadTexture(for: ref, from: repository)
        }
    }

    func textureCacheStats(for spec: SceneSpec, repository: SpriteRepository) -> SceneTextureCacheStats {
        let referencedAssetIDs = spec.referencedAssetIDs.sorted { $0.uuidString < $1.uuidString }
        let cachedAssetIDs = referencedAssetIDs.filter { textureCache[$0] != nil }
        let missingAssetIDs = referencedAssetIDs.filter { repository.asset(byId: $0) == nil }
        return SceneTextureCacheStats(
            referencedTextureCount: referencedAssetIDs.count,
            cachedTextureCount: cachedAssetIDs.count,
            missingTextureCount: missingAssetIDs.count,
            referencedAssetIDs: referencedAssetIDs,
            cachedAssetIDs: cachedAssetIDs,
            missingAssetIDs: missingAssetIDs
        )
    }

    func invalidateTexture(for assetId: UUID) {
        textureCache.removeValue(forKey: assetId)
    }

    func clearTextureCache() { textureCache.removeAll() }

    // MARK: - Color Conversion

    // MARK: - Physics Joints

    /// Create SKPhysicsJoint objects from the spec and add them to the scene's physics world.
    private func applyJoints(spec: SceneSpec, scene: SKScene) {
        for jointSpec in spec.joints {
            guard let nodeASpec = spec.node(named: jointSpec.nodeA),
                  let nodeBSpec = spec.node(named: jointSpec.nodeB),
                  let skNodeA = registry.node(for: nodeASpec.id),
                  let skNodeB = registry.node(for: nodeBSpec.id),
                  let bodyA = skNodeA.physicsBody,
                  let bodyB = skNodeB.physicsBody else { continue }

            let anchorPoint = skNodeA.position
            let joint: SKPhysicsJoint
            switch jointSpec.jointType {
            case .pin:
                joint = SKPhysicsJointPin.joint(withBodyA: bodyA, bodyB: bodyB, anchor: anchorPoint)
            case .spring:
                let sj = SKPhysicsJointSpring.joint(withBodyA: bodyA, bodyB: bodyB, anchorA: skNodeA.position, anchorB: skNodeB.position)
                sj.frequency = CGFloat(jointSpec.springFrequency ?? 1.0)
                sj.damping = CGFloat(jointSpec.springDamping ?? 0.5)
                joint = sj
            case .sliding:
                joint = SKPhysicsJointSliding.joint(withBodyA: bodyA, bodyB: bodyB, anchor: anchorPoint, axis: CGVector(dx: 1, dy: 0))
            case .fixed:
                joint = SKPhysicsJointFixed.joint(withBodyA: bodyA, bodyB: bodyB, anchor: anchorPoint)
            case .limit:
                let lj = SKPhysicsJointLimit.joint(withBodyA: bodyA, bodyB: bodyB, anchorA: skNodeA.position, anchorB: skNodeB.position)
                if let maxDist = jointSpec.springFrequency {
                    lj.maxLength = CGFloat(maxDist)
                }
                joint = lj
            }
            scene.physicsWorld.add(joint)
        }
    }

    // MARK: - Scene Constraints

    /// Apply SKConstraint objects to nodes based on the spec.
    private func applyConstraints(spec: SceneSpec) {
        for constraintSpec in spec.sceneConstraints {
            guard let sourceNodeSpec = spec.node(named: constraintSpec.sourceNode),
                  let targetNodeSpec = spec.node(named: constraintSpec.targetNode),
                  let skSource = registry.node(for: sourceNodeSpec.id),
                  let skTarget = registry.node(for: targetNodeSpec.id) else { continue }

            let constraint: SKConstraint
            switch constraintSpec.constraintType {
            case .distance:
                constraint = SKConstraint.distance(
                    SKRange(lowerLimit: CGFloat(constraintSpec.minDistance ?? 0),
                            upperLimit: CGFloat(constraintSpec.maxDistance ?? 1000)),
                    to: skTarget)
            case .orient:
                constraint = SKConstraint.orient(to: skTarget, offset: SKRange(constantValue: 0))
            case .position:
                // Lock source to target's position using distance constraint
                constraint = SKConstraint.distance(SKRange(constantValue: 0), to: skTarget)
            }
            skSource.constraints = (skSource.constraints ?? []) + [constraint]
        }
    }

    // MARK: - Physics Fields

    /// Create SKFieldNode objects from the spec and add them to the scene.
    private func applyFields(spec: SceneSpec, scene: SKScene) {
        for fieldSpec in spec.fields {
            let field: SKFieldNode
            switch fieldSpec.fieldType {
            case .linearGravity:
                let dir = fieldSpec.direction ?? PointSpec(x: 0, y: -1)
                field = SKFieldNode.linearGravityField(withVector: vector_float3(Float(dir.x), Float(dir.y), 0))
            case .radialGravity:
                field = SKFieldNode.radialGravityField()
            case .vortex:
                field = SKFieldNode.vortexField()
            case .noise:
                field = SKFieldNode.noiseField(withSmoothness: 0.5, animationSpeed: 1)
            case .turbulence:
                field = SKFieldNode.turbulenceField(withSmoothness: 0.5, animationSpeed: 1)
            case .spring:
                field = SKFieldNode.springField()
            case .drag:
                field = SKFieldNode.dragField()
            case .electric:
                field = SKFieldNode.electricField()
            case .magnetic:
                field = SKFieldNode.magneticField()
            }
            field.strength = Float(fieldSpec.strength)
            if let region = fieldSpec.region {
                field.region = SKRegion(size: CGSize(width: region.width, height: region.height))
            }
            scene.addChild(field)
        }
    }

    private func nsColor(from hex: String) -> NSColor {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return .white }
        return NSColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    /// Apply a node's `textStyle` (parsed via `TextStyleFlags`) to a
    /// live `SKLabelNode`. Bold / italic flags become NSFont traits
    /// applied to the label's resolved font; underline / strike-
    /// through become attributedText keys.
    ///
    /// `attributedText` overrides `text` once set, so we only switch
    /// to it when there's actual decoration to apply — otherwise the
    /// simpler text + fontName + fontColor + fontSize path stays in
    /// effect (those properties get clobbered if attributedText is
    /// non-nil with conflicting attributes).
    static func applyLabelTextStyle(_ label: SKLabelNode, spec: HypeNodeSpec) {
        guard let raw = spec.textStyle else { return }
        let flags = TextStyleFlags(string: raw)
        if flags.isPlain {
            // Defensive: if the user cleared the textStyle back to
            // plain after a prior decorated render, drop the
            // attributed text so the simple path takes over again.
            label.attributedText = nil
            return
        }
        // Resolve the font with traits. Apple's NSFontManager
        // respects family + size when toggling traits, so we don't
        // lose the user's font face by switching to system.
        let baseFont = NSFont(name: label.fontName ?? "Helvetica", size: label.fontSize)
            ?? NSFont.systemFont(ofSize: label.fontSize)
        var styledFont = baseFont
        if flags.bold {
            styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .boldFontMask)
        }
        if flags.italic {
            styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .italicFontMask)
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: styledFont,
            .foregroundColor: label.fontColor ?? NSColor.white,
        ]
        if flags.underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if flags.strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        label.attributedText = NSAttributedString(string: spec.text ?? "", attributes: attrs)
    }
}
