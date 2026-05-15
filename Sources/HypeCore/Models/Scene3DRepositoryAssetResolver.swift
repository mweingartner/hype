import Foundation

public struct Scene3DResolvedRepositoryAsset: Sendable {
    public let selectedAsset: SpriteAsset
    public let renderAsset: SpriteAsset
    public let usesCompanionAsset: Bool
}

public enum Scene3DRepositoryAssetResolver {
    public static func selectedAsset(for ref: AssetRef, in repository: SpriteRepository) -> SpriteAsset? {
        repository.asset(byId: ref.id) ?? repository.asset(byName: ref.name)
    }

    public static func resolvedAsset(
        for ref: AssetRef,
        in repository: SpriteRepository
    ) -> Scene3DResolvedRepositoryAsset? {
        guard let selected = selectedAsset(for: ref, in: repository) else {
            return nil
        }
        if isGLB(selected),
           let companion = usdzCompanion(for: selected, in: repository) {
            return Scene3DResolvedRepositoryAsset(
                selectedAsset: selected,
                renderAsset: companion,
                usesCompanionAsset: true
            )
        }
        return Scene3DResolvedRepositoryAsset(
            selectedAsset: selected,
            renderAsset: selected,
            usesCompanionAsset: false
        )
    }

    public static func loadIdentity(
        for ref: AssetRef,
        in repository: SpriteRepository?,
        fallbackURL: String
    ) -> String {
        guard let repository,
              let resolved = resolvedAsset(for: ref, in: repository) else {
            return "missing:\(ref.id.uuidString):\(ref.name):\(fallbackURL)"
        }

        let selected = resolved.selectedAsset
        let render = resolved.renderAsset
        return [
            "asset",
            selected.id.uuidString,
            selected.name,
            String(selected.data.count),
            render.id.uuidString,
            render.name,
            String(render.data.count),
            resolved.usesCompanionAsset ? "companion" : "direct"
        ].joined(separator: ":")
    }

    public static func isGLB(_ asset: SpriteAsset) -> Bool {
        let ext = asset.name.lowercasedPathExtension
        let mime = asset.mimeType.lowercased()
        return ext == "glb" || mime == "model/gltf-binary" || mime == "model/gltf+json"
    }

    public static func isUSDZ(_ asset: SpriteAsset) -> Bool {
        let ext = asset.name.lowercasedPathExtension
        let mime = asset.mimeType.lowercased()
        return ext == "usdz" || mime == "model/vnd.usdz+zip" || mime.contains("usdz")
    }

    public static func requiresCompanionForSceneKit(_ asset: SpriteAsset) -> Bool {
        // SceneKit/ModelIO on current macOS does not load GLB reliably. Keep
        // GLB as the portable Meshy/archive asset, but render the USDZ sibling.
        isGLB(asset)
    }

    private static func usdzCompanion(for selected: SpriteAsset, in repository: SpriteRepository) -> SpriteAsset? {
        let candidates = repository.assets.filter { $0.kind == .model3D && isUSDZ($0) }

        if let taskId = selected.provenance?.attribution.taskId, !taskId.isEmpty,
           let byTask = candidates.first(where: { $0.provenance?.attribution.taskId == taskId }) {
            return byTask
        }

        let selectedStem = selected.name.deletingKnown3DExtension.lowercased()
        return candidates.first {
            $0.name.deletingKnown3DExtension.lowercased() == selectedStem
        }
    }
}

private extension String {
    var lowercasedPathExtension: String {
        (self as NSString).pathExtension.lowercased()
    }

    var deletingKnown3DExtension: String {
        let ext = lowercasedPathExtension
        if ["glb", "gltf", "usdz", "usd", "fbx", "obj", "scn", "dae", "ply", "abc", "stl"].contains(ext) {
            return (self as NSString).deletingPathExtension
        }
        return self
    }
}
