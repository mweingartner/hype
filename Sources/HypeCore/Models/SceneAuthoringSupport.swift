import Foundation

public enum SceneChecklistStatus: String, Codable, Sendable, Equatable {
    case complete
    case recommended
    case missing
}

public struct SceneChecklistItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { key }
    public var key: String
    public var title: String
    public var status: SceneChecklistStatus
    public var detail: String

    public init(
        key: String,
        title: String,
        status: SceneChecklistStatus,
        detail: String
    ) {
        self.key = key
        self.title = title
        self.status = status
        self.detail = detail
    }

    // Lenient decoder for AI-produced checklist entries: unknown
    // status words ("done", "todo", "optional") map to the nearest
    // canonical value instead of failing decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key)) ?? ""
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        if let raw = try? c.decode(String.self, forKey: .status) {
            switch raw.lowercased() {
            case "complete", "completed", "done", "ok", "passed": self.status = .complete
            case "recommended", "suggested", "optional", "todo": self.status = .recommended
            case "missing", "incomplete", "required": self.status = .missing
            default: self.status = .recommended
            }
        } else {
            self.status = .recommended
        }
        self.detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
    }
}

public enum SceneDiagnosticSeverity: String, Codable, Sendable, Equatable {
    case info
    case warning
    case error
}

public struct SceneDiagnosticIssue: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(severity.rawValue):\(message)" }
    public var severity: SceneDiagnosticSeverity
    public var message: String

    public init(severity: SceneDiagnosticSeverity, message: String) {
        self.severity = severity
        self.message = message
    }

    // Lenient decoder: unknown severity words map to `.info` so the
    // rest of the repair plan still applies.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? c.decode(String.self, forKey: .severity) {
            switch raw.lowercased() {
            case "error", "critical", "fatal": self.severity = .error
            case "warning", "warn", "caution": self.severity = .warning
            case "info", "informational", "note", "notice": self.severity = .info
            default: self.severity = .info
            }
        } else {
            self.severity = .info
        }
        self.message = (try? c.decode(String.self, forKey: .message)) ?? ""
    }
}

public struct SceneDiagnosticsReport: Codable, Sendable, Equatable {
    public var sceneName: String
    public var nodeCount: Int
    public var texturedNodeCount: Int
    public var physicsBodyCount: Int
    public var emitterCount: Int
    public var missingAssetCount: Int
    public var referencedAssetIDs: [UUID]
    public var missingAssetIDs: [UUID]
    public var issues: [SceneDiagnosticIssue]

    public init(
        sceneName: String,
        nodeCount: Int,
        texturedNodeCount: Int,
        physicsBodyCount: Int,
        emitterCount: Int,
        missingAssetCount: Int,
        referencedAssetIDs: [UUID],
        missingAssetIDs: [UUID],
        issues: [SceneDiagnosticIssue]
    ) {
        self.sceneName = sceneName
        self.nodeCount = nodeCount
        self.texturedNodeCount = texturedNodeCount
        self.physicsBodyCount = physicsBodyCount
        self.emitterCount = emitterCount
        self.missingAssetCount = missingAssetCount
        self.referencedAssetIDs = referencedAssetIDs
        self.missingAssetIDs = missingAssetIDs
        self.issues = issues
    }
}

public enum AssetUsageRole: String, Codable, Sendable, Equatable {
    case nodeTexture
    case tileSet
}

public struct AssetUsage: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(sceneId.uuidString):\(nodeId.uuidString):\(role.rawValue)" }
    public var assetId: UUID
    public var partId: UUID
    public var partName: String
    public var sceneId: UUID
    public var sceneName: String
    public var nodeId: UUID
    public var nodeName: String
    public var nodeType: NodeType
    public var role: AssetUsageRole

    public init(
        assetId: UUID,
        partId: UUID,
        partName: String,
        sceneId: UUID,
        sceneName: String,
        nodeId: UUID,
        nodeName: String,
        nodeType: NodeType,
        role: AssetUsageRole
    ) {
        self.assetId = assetId
        self.partId = partId
        self.partName = partName
        self.sceneId = sceneId
        self.sceneName = sceneName
        self.nodeId = nodeId
        self.nodeName = nodeName
        self.nodeType = nodeType
        self.role = role
    }
}

public extension SceneSpec {
    var referencedAssetIDs: Set<UUID> {
        var ids = Set(allNodes.compactMap { $0.assetRef?.id })
        for node in allNodes {
            if let tileSetID = node.tileMapSpec?.tileSetAssetRef?.id {
                ids.insert(tileSetID)
            }
        }
        return ids
    }

    func authoringChecklist(using repository: AssetRepository) -> [SceneChecklistItem] {
        let nodes = allNodes
        let missingAssetRefs = nodes.filter {
            guard let ref = $0.assetRef else { return false }
            return repository.asset(byId: ref.id) == nil
        }
        let tileMaps = nodes.filter { $0.nodeType == .tileMap }
        let playerLikeNodes = nodes.filter {
            let lowered = $0.name.lowercased()
            return lowered == "player" || lowered == "hero" || lowered == "avatar"
        }
        let hasPhysics = nodes.contains { $0.physicsBody != nil } || gravity.dx != 0 || gravity.dy != 0
        let hasCamera = nodes.contains { $0.nodeType == .camera }
        let hasScripts = !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            nodes.contains { !$0.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return [
            SceneChecklistItem(
                key: "basics",
                title: "Scene Basics",
                status: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || size.width <= 0 || size.height <= 0 ? .missing : .complete,
                detail: "Name the scene and set a positive design size."
            ),
            SceneChecklistItem(
                key: "world",
                title: "World Content",
                status: nodes.isEmpty ? .missing : .complete,
                detail: "Add at least one gameplay node, label, tile map, or effect."
            ),
            SceneChecklistItem(
                key: "player",
                title: "Main Actor",
                status: playerLikeNodes.isEmpty ? .recommended : .complete,
                detail: "Add a player or other clearly named primary actor node."
            ),
            SceneChecklistItem(
                key: "camera",
                title: "Framing",
                status: hasCamera ? .complete : .recommended,
                detail: "Use a camera node when the scene should follow action or pan."
            ),
            SceneChecklistItem(
                key: "physics",
                title: "Physics / World Rules",
                status: hasPhysics || !tileMaps.isEmpty ? .complete : .recommended,
                detail: "Decide whether the scene uses gravity, tile collisions, or physics bodies."
            ),
            SceneChecklistItem(
                key: "assets",
                title: "Asset Bindings",
                status: missingAssetRefs.isEmpty ? .complete : .missing,
                detail: missingAssetRefs.isEmpty
                    ? "No broken texture or media references were found."
                    : "Some nodes reference repository assets that are missing."
            ),
            SceneChecklistItem(
                key: "scripts",
                title: "Scene Logic",
                status: hasScripts ? .complete : .recommended,
                detail: "Seed scene or node scripts for input, lifecycle, or collisions."
            )
        ]
    }

    func diagnostics(using repository: AssetRepository) -> SceneDiagnosticsReport {
        let nodes = allNodes
        let referencedIDs = Array(referencedAssetIDs).sorted { $0.uuidString < $1.uuidString }
        var issues: [SceneDiagnosticIssue] = []
        var missingAssetIDs = Set<UUID>()

        for node in nodes {
            if let ref = node.assetRef, repository.asset(byId: ref.id) == nil {
                missingAssetIDs.insert(ref.id)
                issues.append(.init(
                    severity: .warning,
                    message: "Node '\(node.name)' references missing asset '\(ref.name)'."
                ))
            }
            if let tileSetRef = node.tileMapSpec?.tileSetAssetRef,
               repository.asset(byId: tileSetRef.id) == nil {
                missingAssetIDs.insert(tileSetRef.id)
                issues.append(.init(
                    severity: .warning,
                    message: "Tile map '\(node.name)' references a missing tileset asset."
                ))
            }
            if node.physicsBody != nil && node.nodeType == .sprite && node.size == nil && node.assetRef == nil {
                issues.append(.init(
                    severity: .info,
                    message: "Sprite '\(node.name)' has physics enabled without an explicit size or texture."
                ))
            }
        }

        let names = nodes.map(\.name).filter { !$0.isEmpty }
        let duplicateNames = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        for duplicate in duplicateNames {
            issues.append(.init(
                severity: .warning,
                message: "Duplicate node name '\(duplicate)'."
            ))
        }

        for joint in joints {
            if node(named: joint.nodeA) == nil {
                issues.append(.init(
                    severity: .error,
                    message: "Joint references unknown node '\(joint.nodeA)'."
                ))
            }
            if node(named: joint.nodeB) == nil {
                issues.append(.init(
                    severity: .error,
                    message: "Joint references unknown node '\(joint.nodeB)'."
                ))
            }
        }

        return SceneDiagnosticsReport(
            sceneName: name,
            nodeCount: nodes.count,
            texturedNodeCount: nodes.filter { $0.assetRef != nil }.count,
            physicsBodyCount: nodes.filter { $0.physicsBody != nil }.count,
            emitterCount: nodes.filter { $0.nodeType == .emitter }.count,
            missingAssetCount: missingAssetIDs.count,
            referencedAssetIDs: referencedIDs,
            missingAssetIDs: Array(missingAssetIDs).sorted { $0.uuidString < $1.uuidString },
            issues: issues
        )
    }
}

public extension HypeDocument {
    func assetUsages(for assetId: UUID) -> [AssetUsage] {
        var usages: [AssetUsage] = []
        for part in parts where part.partType == .spriteArea {
            guard let areaSpec = part.spriteAreaSpecModel else { continue }
            let partName = part.name.isEmpty ? "Sprite Area" : part.name
            for entry in areaSpec.scenes {
                for node in entry.scene.allNodes {
                    if node.assetRef?.id == assetId {
                        usages.append(AssetUsage(
                            assetId: assetId,
                            partId: part.id,
                            partName: partName,
                            sceneId: entry.id,
                            sceneName: entry.scene.name,
                            nodeId: node.id,
                            nodeName: node.name,
                            nodeType: node.nodeType,
                            role: .nodeTexture
                        ))
                    }
                    if node.tileMapSpec?.tileSetAssetRef?.id == assetId {
                        usages.append(AssetUsage(
                            assetId: assetId,
                            partId: part.id,
                            partName: partName,
                            sceneId: entry.id,
                            sceneName: entry.scene.name,
                            nodeId: node.id,
                            nodeName: node.name,
                            nodeType: node.nodeType,
                            role: .tileSet
                        ))
                    }
                }
            }
        }
        return usages
    }
}
