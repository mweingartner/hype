import Foundation

private final class SpriteAreaSpecJSONCache: @unchecked Sendable {
    static let shared = SpriteAreaSpecJSONCache()

    private let lock = NSLock()
    private var values: [String: SpriteAreaSpec] = [:]
    private var order: [String] = []
    private let limit = 8

    private init() {}

    func cachedPlain(json: String) -> SpriteAreaSpec? {
        cached(key: plainKey(json))
    }

    func cachedStored(json: String, fallbackSize: SizeSpec) -> SpriteAreaSpec? {
        cached(key: storedKey(json, fallbackSize: fallbackSize))
    }

    func storePlain(_ spec: SpriteAreaSpec, json: String) {
        store(spec, key: plainKey(json))
    }

    func storeStored(_ spec: SpriteAreaSpec, json: String, fallbackSize: SizeSpec) {
        store(spec, key: storedKey(json, fallbackSize: fallbackSize))
    }

    private func cached(key: String) -> SpriteAreaSpec? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    private func store(_ spec: SpriteAreaSpec, key: String) {
        lock.lock()
        defer { lock.unlock() }

        if values[key] == nil {
            order.append(key)
        }
        values[key] = spec

        while order.count > limit {
            let evicted = order.removeFirst()
            values.removeValue(forKey: evicted)
        }
    }

    private func plainKey(_ json: String) -> String {
        "plain|\(json)"
    }

    private func storedKey(_ json: String, fallbackSize: SizeSpec) -> String {
        "stored|\(fallbackSize.width)x\(fallbackSize.height)|\(json)"
    }
}

/// A named scene entry owned by a Sprite Area.
public struct SpriteAreaScene: Identifiable, Codable, Sendable {
    public var id: UUID
    public var scene: SceneSpec

    public init(id: UUID = UUID(), scene: SceneSpec) {
        self.id = id
        self.scene = scene
    }
}

/// Canonical Sprite Area storage.
///
/// Legacy `.hype` documents stored a single `SceneSpec` JSON string in
/// `Part.sceneSpec`. This type adds a named-scene registry plus area-level
/// defaults while keeping a migration path from the old single-scene format.
public struct SpriteAreaSpec: Codable, Sendable {
    public var activeSceneID: UUID
    public var scenes: [SpriteAreaScene]
    public var designSize: SizeSpec
    public var scaleMode: SceneScaleMode
    public var showsPhysics: Bool
    public var showsFPS: Bool
    public var showsNodeCount: Bool
    /// Optional declarative game recipe. When present, a later-phase
    /// compiler lowers this into the active `SceneSpec` plus generated
    /// HypeTalk scripts. Nil for non-game sprite areas and legacy docs.
    public var recipe: GameRecipe?

    public init(
        activeSceneID: UUID,
        scenes: [SpriteAreaScene],
        designSize: SizeSpec,
        scaleMode: SceneScaleMode = .aspectFit,
        showsPhysics: Bool = false,
        showsFPS: Bool = false,
        showsNodeCount: Bool = false,
        recipe: GameRecipe? = nil
    ) {
        self.activeSceneID = activeSceneID
        self.scenes = scenes
        self.designSize = designSize
        self.scaleMode = scaleMode
        self.showsPhysics = showsPhysics
        self.showsFPS = showsFPS
        self.showsNodeCount = showsNodeCount
        self.recipe = recipe
        normalize()
    }

    public init(scene: SceneSpec, fallbackSize: SizeSpec) {
        let normalizedName = scene.name.isEmpty ? "main" : scene.name
        let migratedScene = SceneSpec(
            name: normalizedName,
            size: scene.size.width > 0 && scene.size.height > 0 ? scene.size : fallbackSize,
            backgroundColor: scene.backgroundColor,
            gravity: scene.gravity,
            nodes: scene.nodes,
            joints: scene.joints,
            sceneConstraints: scene.sceneConstraints,
            fields: scene.fields,
            script: scene.script,
            isPaused: scene.isPaused,
            showsPhysics: scene.showsPhysics,
            showsFPS: scene.showsFPS,
            showsNodeCount: scene.showsNodeCount,
            scaleMode: scene.scaleMode
        )
        let entry = SpriteAreaScene(scene: migratedScene)
        self.init(
            activeSceneID: entry.id,
            scenes: [entry],
            designSize: migratedScene.size,
            scaleMode: migratedScene.scaleMode,
            showsPhysics: migratedScene.showsPhysics,
            showsFPS: migratedScene.showsFPS,
            showsNodeCount: migratedScene.showsNodeCount
        )
    }

    public init(defaultSceneNamed name: String = "main", fallbackSize: SizeSpec) {
        self.init(
            scene: SceneSpec(
                name: name,
                size: fallbackSize,
                scaleMode: .aspectFit
            ),
            fallbackSize: fallbackSize
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeSceneID = try container.decode(UUID.self, forKey: .activeSceneID)
        scenes = try container.decode([SpriteAreaScene].self, forKey: .scenes)
        designSize = try container.decodeIfPresent(SizeSpec.self, forKey: .designSize) ?? SizeSpec(width: 800, height: 600)
        scaleMode = try container.decodeIfPresent(SceneScaleMode.self, forKey: .scaleMode) ?? .aspectFit
        showsPhysics = try container.decodeIfPresent(Bool.self, forKey: .showsPhysics) ?? false
        showsFPS = try container.decodeIfPresent(Bool.self, forKey: .showsFPS) ?? false
        showsNodeCount = try container.decodeIfPresent(Bool.self, forKey: .showsNodeCount) ?? false
        recipe = try container.decodeIfPresent(GameRecipe.self, forKey: .recipe)
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case activeSceneID, scenes, designSize, scaleMode, showsPhysics, showsFPS, showsNodeCount
        case recipe
    }

    public static func fromJSON(_ json: String) -> SpriteAreaSpec? {
        if let cached = SpriteAreaSpecJSONCache.shared.cachedPlain(json: json) {
            return cached
        }
        guard let spec = JSONCodec.decode(SpriteAreaSpec.self, from: json) else {
            return nil
        }
        SpriteAreaSpecJSONCache.shared.storePlain(spec, json: json)
        return spec
    }

    public static func fromStoredJSON(_ json: String, fallbackSize: SizeSpec) -> SpriteAreaSpec? {
        if let cached = SpriteAreaSpecJSONCache.shared.cachedStored(json: json, fallbackSize: fallbackSize) {
            return cached
        }
        if let spec = fromJSON(json) {
            SpriteAreaSpecJSONCache.shared.storeStored(spec, json: json, fallbackSize: fallbackSize)
            return spec
        }
        guard let legacy = SceneSpec.fromLegacyJSON(json) else { return nil }
        let spec = SpriteAreaSpec(scene: legacy, fallbackSize: fallbackSize)
        SpriteAreaSpecJSONCache.shared.storeStored(spec, json: json, fallbackSize: fallbackSize)
        return spec
    }

    public var activeSceneEntry: SpriteAreaScene? {
        guard let index = activeSceneIndex else { return nil }
        return scenes[index]
    }

    public var activeScene: SceneSpec? {
        guard let index = activeSceneIndex else { return nil }
        return effectiveScene(for: scenes[index].scene)
    }

    public var sceneNames: [String] {
        scenes.map { $0.scene.name }
    }

    public mutating func setActiveScene(_ scene: SceneSpec) {
        guard let index = activeSceneIndex else {
            let entry = SpriteAreaScene(scene: scene)
            scenes = [entry]
            activeSceneID = entry.id
            syncAreaDefaults(from: scene)
            return
        }
        scenes[index].scene = scene
        syncAreaDefaults(from: scene)
    }

    @discardableResult
    public mutating func addScene(named name: String, basedOn template: SceneSpec? = nil) -> SpriteAreaScene {
        let base = template ?? activeScene ?? SceneSpec(size: designSize, scaleMode: scaleMode)
        var scene = base
        scene.name = uniqueSceneName(startingWith: name)
        scene.size = designSize
        scene.scaleMode = scaleMode
        scene.showsPhysics = showsPhysics
        scene.showsFPS = showsFPS
        scene.showsNodeCount = showsNodeCount
        let entry = SpriteAreaScene(scene: scene)
        scenes.append(entry)
        activeSceneID = entry.id
        return entry
    }

    @discardableResult
    public mutating func duplicateActiveScene() -> SpriteAreaScene? {
        guard let scene = activeScene else { return nil }
        return addScene(named: "\(scene.name) Copy", basedOn: scene)
    }

    @discardableResult
    public mutating func removeScene(id sceneId: UUID) -> SpriteAreaScene? {
        guard scenes.count > 1,
              let index = scenes.firstIndex(where: { $0.id == sceneId }) else {
            return nil
        }

        let removed = scenes.remove(at: index)
        if activeSceneID == sceneId, let replacement = scenes.first {
            activeSceneID = replacement.id
            syncAreaDefaults(from: effectiveScene(for: replacement.scene))
        }
        normalize()
        return removed
    }

    @discardableResult
    public mutating func removeScene(named name: String) -> SpriteAreaScene? {
        guard let scene = scenes.first(where: { $0.scene.name.lowercased() == name.lowercased() }) else {
            return nil
        }
        return removeScene(id: scene.id)
    }

    @discardableResult
    public mutating func activateScene(named name: String) -> Bool {
        guard let index = scenes.firstIndex(where: { $0.scene.name.lowercased() == name.lowercased() }) else {
            return false
        }
        activeSceneID = scenes[index].id
        let scene = effectiveScene(for: scenes[index].scene)
        syncAreaDefaults(from: scene)
        return true
    }

    @discardableResult
    public mutating func activateScene(id: UUID) -> Bool {
        guard scenes.contains(where: { $0.id == id }) else { return false }
        activeSceneID = id
        if let scene = activeScene {
            syncAreaDefaults(from: scene)
        }
        return true
    }

    public func scene(id: UUID) -> SceneSpec? {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return nil }
        return effectiveScene(for: scenes[index].scene)
    }

    public func scene(named name: String) -> SceneSpec? {
        guard let index = scenes.firstIndex(where: { $0.scene.name.lowercased() == name.lowercased() }) else { return nil }
        return effectiveScene(for: scenes[index].scene)
    }

    public func toStoredJSON() -> String {
        return JSONCodec.encode(self)
    }

    private var activeSceneIndex: Int? {
        if let index = scenes.firstIndex(where: { $0.id == activeSceneID }) {
            return index
        }
        return scenes.isEmpty ? nil : 0
    }

    private func effectiveScene(for scene: SceneSpec) -> SceneSpec {
        var scene = scene
        scene.size = designSize
        scene.scaleMode = scaleMode
        scene.showsPhysics = showsPhysics
        scene.showsFPS = showsFPS
        scene.showsNodeCount = showsNodeCount
        return scene
    }

    private mutating func normalize() {
        if scenes.isEmpty {
            let entry = SpriteAreaScene(scene: SceneSpec(name: "main", size: designSize, scaleMode: scaleMode))
            scenes = [entry]
            activeSceneID = entry.id
        }
        if !scenes.contains(where: { $0.id == activeSceneID }) {
            activeSceneID = scenes[0].id
        }
        if let scene = activeScene {
            if designSize.width <= 0 || designSize.height <= 0 {
                designSize = scene.size
            }
            syncAreaDefaults(from: scene)
        }
    }

    private mutating func syncAreaDefaults(from scene: SceneSpec) {
        designSize = scene.size
        scaleMode = scene.scaleMode
        showsPhysics = scene.showsPhysics
        showsFPS = scene.showsFPS
        showsNodeCount = scene.showsNodeCount
    }

    private func uniqueSceneName(startingWith base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? "Scene" : trimmed
        if !sceneNames.contains(where: { $0.lowercased() == seed.lowercased() }) {
            return seed
        }
        var index = 2
        while sceneNames.contains(where: { $0.lowercased() == "\(seed) \(index)".lowercased() }) {
            index += 1
        }
        return "\(seed) \(index)"
    }
}

public extension Part {
    var spriteAreaSpecModel: SpriteAreaSpec? {
        guard partType == .spriteArea else { return nil }
        return SpriteAreaSpec.fromStoredJSON(
            sceneSpec,
            fallbackSize: SizeSpec(width: width, height: height)
        )
    }

    var activeSceneSpec: SceneSpec? {
        spriteAreaSpecModel?.activeScene
    }

    var activeSceneID: UUID? {
        spriteAreaSpecModel?.activeSceneEntry?.id
    }

    mutating func setSpriteAreaSpec(_ spec: SpriteAreaSpec) {
        sceneSpec = spec.toStoredJSON()
        let fallbackSize = SizeSpec(width: width, height: height)
        SpriteAreaSpecJSONCache.shared.storePlain(spec, json: sceneSpec)
        SpriteAreaSpecJSONCache.shared.storeStored(spec, json: sceneSpec, fallbackSize: fallbackSize)
    }

    mutating func updateSpriteAreaSpec(_ transform: (inout SpriteAreaSpec) -> Void) {
        var spec = spriteAreaSpecModel ?? SpriteAreaSpec(
            defaultSceneNamed: name.isEmpty ? "main" : name,
            fallbackSize: SizeSpec(width: width, height: height)
        )
        transform(&spec)
        setSpriteAreaSpec(spec)
    }

    mutating func updateActiveSceneSpec(_ transform: (inout SceneSpec) -> Void) {
        var spec = spriteAreaSpecModel ?? SpriteAreaSpec(
            defaultSceneNamed: name.isEmpty ? "main" : name,
            fallbackSize: SizeSpec(width: width, height: height)
        )
        var scene = spec.activeScene ?? SceneSpec(
            name: name.isEmpty ? "main" : name,
            size: SizeSpec(width: width, height: height)
        )
        transform(&scene)
        spec.setActiveScene(scene)
        setSpriteAreaSpec(spec)
    }

    /// Apply `transform` to the `GameRecipe` stored inside this part's
    /// `SpriteAreaSpec`, then write the updated spec back via
    /// `setSpriteAreaSpec`. Mirrors the `updateSpriteAreaSpec` round-trip.
    mutating func updateRecipe(_ transform: (inout GameRecipe?) -> Void) {
        var spec = spriteAreaSpecModel ?? SpriteAreaSpec(
            defaultSceneNamed: name.isEmpty ? "main" : name,
            fallbackSize: SizeSpec(width: width, height: height)
        )
        transform(&spec.recipe)
        setSpriteAreaSpec(spec)
    }
}
