import Foundation

/// Shared resolver for the author-facing `object` / `model` properties on
/// `scene3D` parts.
///
/// The preferred path is a document-embedded Sprite Repository asset of
/// `kind == .model3D`. If no asset with the supplied name exists, callers may
/// fall back to their legacy file-path resolver.
public enum Scene3DModelBindingResolver {
    public enum BindingResult: Sendable, Equatable {
        case asset(name: String)
        case path(source: String, resolved: String)
    }

    /// Returns the author-visible model value for introspection surfaces.
    public static func displayModel(for part: Part) -> String {
        if let assetRef = part.scene3DAssetRef, !assetRef.name.isEmpty {
            return assetRef.name
        }
        return part.scene3DSourceURL.isEmpty ? part.scene3DURL : part.scene3DSourceURL
    }

    /// Bind `value` to a `scene3D` part, preferring model3D repository assets
    /// over legacy URL/path loading.
    @discardableResult
    public static func bindModelOrObject(
        value: String,
        to part: inout Part,
        repository: SpriteRepository,
        resolvePath: (String) -> String
    ) -> BindingResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let asset = modelAsset(named: trimmed, in: repository) {
            part.scene3DAssetRef = repository.assetRef(for: asset)
            part.scene3DSourceURL = ""
            part.scene3DURL = ""
            return .asset(name: asset.name)
        }

        part.scene3DAssetRef = nil
        part.scene3DSourceURL = trimmed
        part.scene3DURL = resolvePath(trimmed)
        return .path(source: trimmed, resolved: part.scene3DURL)
    }

    /// Force legacy URL/path binding and clear any previous repository asset
    /// reference. Use this for explicit `modelURL` / `sceneURL` aliases.
    @discardableResult
    public static func bindPath(
        value: String,
        to part: inout Part,
        resolvePath: (String) -> String
    ) -> BindingResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        part.scene3DAssetRef = nil
        part.scene3DSourceURL = trimmed
        part.scene3DURL = resolvePath(trimmed)
        return .path(source: trimmed, resolved: part.scene3DURL)
    }

    public static func modelAsset(named rawName: String, in repository: SpriteRepository) -> SpriteAsset? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = repository.asset(byName: trimmed), exact.kind == .model3D {
            return exact
        }

        let requestedStem = trimmed.deletingKnown3DExtension.lowercased()
        let modelAssets = repository.assets.reversed().filter { $0.kind == .model3D }
        if let preferredGLB = modelAssets.first(where: {
            Scene3DRepositoryAssetResolver.isGLB($0)
                && $0.name.deletingKnown3DExtension.lowercased() == requestedStem
        }) {
            return preferredGLB
        }
        return modelAssets.first {
            $0.name.deletingKnown3DExtension.lowercased() == requestedStem
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
