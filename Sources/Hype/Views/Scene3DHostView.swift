import AppKit
import SceneKit
import HypeCore

/// AppKit-hosted 3D scene viewer for `scene3D` parts.
///
/// Wraps `SCNView`. Loads `.usdz` / `.scn` / `.dae` / `.obj` / `.glb` /
/// `.fbx` / `.stl` via `Scene3DAssetLoader`. The `apply(_:)` method only
/// re-loads the scene when the URL or asset ref actually changed — toggling
/// camera control or anti-aliasing doesn't force a heavyweight scene rebuild.
///
/// Two load paths:
/// 1. **Asset-ref path** (preferred): `part.scene3DAssetRef` points to a
///    `SpriteAsset(kind: .model3D)` in the repository. Bytes are written to a
///    temp file under `URL.temporaryDirectory/hype-scene3d/<uuid>.<ext>`.
/// 2. **Legacy URL path**: `part.scene3DURL` — original file-URL behaviour.
///    When BOTH are set, `scene3DAssetRef` wins.
///
/// `onLoadFailed` is called (on the main thread) when loading fails.
/// The reason string is a safe structural description — no raw file paths
/// for the asset-ref path (security invariant M2).
final class Scene3DHostNSView: NSView {

    let scnView = SCNView()
    /// Tracks which URL was last loaded (legacy path).
    private var loadedURL: String = ""
    /// Tracks which asset-ref id was last loaded (asset-ref path).
    private var loadedAssetRefId: UUID?
    /// Current temp file for the asset-ref path — deleted before next swap.
    private var tempScenePath: String?
    /// Repository reference, refreshed on each `apply(_:)` call.
    private var repository: SpriteRepository?

    private let loader = Scene3DAssetLoader()

    /// Called on the main thread when a scene fails to load. The `reason`
    /// string is a safe structural description (no raw file bytes).
    var onLoadFailed: ((_ reason: String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .clear
        addSubview(scnView)
        NSLayoutConstraint.activate([
            scnView.topAnchor.constraint(equalTo: topAnchor),
            scnView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scnView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        // Remove any leftover temp file for the asset-ref path.
        if let tempPath = tempScenePath {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
    }

    /// Apply a part's 3D-scene settings. Repository must be provided
    /// so the asset-ref path can look up bytes.
    func apply(_ part: Part, repository: SpriteRepository?) {
        self.repository = repository

        scnView.allowsCameraControl = part.scene3DAllowsCameraControl
        scnView.autoenablesDefaultLighting = part.scene3DAutoLighting
        scnView.antialiasingMode = Self.aaMode(for: part.scene3DAntialiasing)

        if part.scene3DBackground.isEmpty {
            scnView.backgroundColor = .clear
        } else if let bg = NSColor(hexString: part.scene3DBackground) {
            scnView.backgroundColor = bg
        }

        // Asset-ref path takes priority over the legacy URL path.
        if let ref = part.scene3DAssetRef {
            if ref.id != loadedAssetRefId {
                loadedAssetRefId = ref.id
                loadedURL = ""  // Invalidate URL cache.
                loadScene(fromAssetRef: ref, fallbackURL: part.scene3DURL)
            }
        } else if part.scene3DURL != loadedURL {
            loadedAssetRefId = nil
            loadedURL = part.scene3DURL
            loadScene(from: part.scene3DURL)
        }
    }

    // MARK: - Legacy URL load

    private func loadScene(from raw: String) {
        guard !raw.isEmpty else {
            scnView.scene = nil
            return
        }
        let url: URL?
        if let parsed = URL(string: raw), parsed.scheme != nil {
            url = parsed
        } else {
            url = URL(fileURLWithPath: raw)
        }
        guard let url else {
            scnView.scene = nil
            return
        }
        // Load on a background queue so a large model doesn't
        // freeze the main thread; swap the scene in once ready.
        let localLoader = loader
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scene: SCNScene? = try? localLoader.load(from: url)
            DispatchQueue.main.async {
                self?.scnView.scene = scene
                if scene == nil {
                    self?.onLoadFailed?("SCNScene returned nil for \(url.lastPathComponent)")
                }
            }
        }
    }

    // MARK: - Asset-ref load

    /// Load a scene from a `SpriteAsset` by writing its bytes to a temp file.
    ///
    /// Security (M2): the `onLoadFailed` reason string uses `asset.name`
    /// NOT the raw temp file path (which contains the asset UUID).
    private func loadScene(fromAssetRef ref: AssetRef, fallbackURL: String) {
        guard let repo = repository,
              let asset = repo.asset(byId: ref.id) else {
            // Asset not found — fall back to the legacy URL.
            loadScene(from: fallbackURL)
            return
        }

        let ext = Self.ext(forMime: asset.mimeType)
        let assetName = asset.name  // Captured for the error string (M2).
        let data = asset.data

        let localLoader = loader
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Create temp directory.
            let tempDir = URL.temporaryDirectory
                .appendingPathComponent("hype-scene3d", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: tempDir, withIntermediateDirectories: true
            )

            // Delete previous temp file before writing new one.
            if let prev = self?.tempScenePath {
                try? FileManager.default.removeItem(atPath: prev)
                DispatchQueue.main.async { self?.tempScenePath = nil }
            }

            // Write bytes to a UUID-named temp file (no path traversal).
            let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
            do {
                try data.write(to: tempURL, options: .atomic)
            } catch {
                DispatchQueue.main.async {
                    self?.onLoadFailed?("Model asset '\(assetName)' could not be loaded")
                }
                return
            }

            // Track temp path so it can be cleaned up on next swap / deinit.
            DispatchQueue.main.async { self?.tempScenePath = tempURL.path }

            // Load via the asset loader.
            let scene: SCNScene? = try? localLoader.load(from: tempURL)
            DispatchQueue.main.async {
                self?.scnView.scene = scene
                if scene == nil {
                    // M2: use asset.name, not the temp path.
                    self?.onLoadFailed?("Model asset '\(assetName)' could not be loaded")
                }
            }
        }
    }

    // MARK: - Helpers

    private static func aaMode(for raw: String) -> SCNAntialiasingMode {
        switch raw.lowercased() {
        case "none": return .none
        case "multisampling2x": return .multisampling2X
        case "multisampling4x": return .multisampling4X
        case "multisampling8x":
            // SCNAntialiasingMode .multisampling8X is iOS-only; fall
            // back to 4X on macOS so the model field round-trips
            // without crashing.
            return .multisampling4X
        default: return .multisampling4X
        }
    }

    /// MIME type → file extension for temp-file naming.
    private static func ext(forMime mime: String) -> String {
        switch mime.lowercased() {
        case "model/gltf-binary": return "glb"
        case "model/vnd.usdz+zip", "application/zip": return "usdz"
        case "model/fbx": return "fbx"
        case "application/octet-stream", "": return "glb"
        default: return "glb"
        }
    }
}
