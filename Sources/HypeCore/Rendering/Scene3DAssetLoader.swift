import Foundation
import SceneKit
import ModelIO

// MARK: - Scene3DAssetLoader

/// Centralised "file extension → SCNScene" loader.
///
/// Replaces the per-call `try? SCNScene(url:)` scattered across
/// `Scene3DHostNSView` with a single strategy table:
///
/// | Extension            | Strategy       |
/// |----------------------|----------------|
/// | `.usdz`, `.usd`, `.scn`, `.dae`, `.obj` | `SCNScene(url:)` — SceneKit native |
/// | `.fbx` (macOS 13+)   | `MDLAsset(url:)` → `SCNScene(mdlAsset:)` (experimental; higher attack surface than GLB/USDZ — see OQ2 in the security addendum) |
/// | `.stl`               | `STLConverter.convert(stlPath:)` → OBJ → `SCNScene(url:)` |
/// | `.ply`, `.abc`       | `MDLAsset(url:)` → `SCNScene(mdlAsset:)` (macOS 13+) |
///
/// All methods are synchronous and must be called on a background queue.
/// They NEVER crash on malformed files — structured `LoadError` is
/// thrown instead.
///
/// Security invariants:
/// - Parsing happens off-main-thread (caller's responsibility).
/// - Nil results from `SCNScene(url:)` surface as `LoadError`, not fatal.
/// - GLB is intentionally not listed here. SceneKit/ModelIO do not load GLB
///   reliably on current macOS; repository-bound GLB assets render through a
///   same-task/same-name USDZ companion resolved before this loader is called.
/// - FBX support gated on `#available(macOS 13, *)` — higher attack
///   surface (Autodesk SDK underlies ModelIO FBX); document this path.
public struct Scene3DAssetLoader: Sendable {

    // MARK: - Error

    public enum LoadError: Error, Sendable, Equatable {
        /// The file URL was empty or the file doesn't exist.
        case fileMissing(path: String)
        /// The extension is not in `supportedExtensions`.
        case unsupportedExtension(ext: String)
        /// `SCNScene(url:)` returned nil (corrupt / unsupported content).
        case sceneKitReturnedNil(path: String)
        /// `MDLAsset(url:)` returned nil or contained zero objects.
        case mdlAssetFailed(path: String)
        /// STL-to-OBJ conversion failed.
        case stlConversionFailed
    }

    // MARK: - Strategy

    public enum Strategy: Sendable, Equatable {
        case sceneKit
        case modelIO
        case stlConvert
    }

    // MARK: - Constants

    /// Recognised file extensions, in lowercase.
    public static let supportedExtensions: [String] = [
        "usdz", "usd", "scn", "dae", "obj", "stl", "ply", "abc", "fbx"
    ]

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Load a 3D scene from `fileURL`. Synchronous — call on a background queue.
    ///
    /// - Parameter fileURL: An absolute `file://` URL (or a URL whose path
    ///   points to a writable temp file from `URL.temporaryDirectory`).
    /// - Returns: A `SCNScene` ready to assign to `SCNView.scene`.
    /// - Throws: `LoadError` for any failure. Never calls `fatalError()`.
    public func load(from fileURL: URL) throws -> SCNScene {
        let path = fileURL.path
        guard !path.isEmpty else {
            throw LoadError.fileMissing(path: "")
        }

        let ext = fileURL.pathExtension.lowercased()
        guard let strategy = Self.strategy(forExtension: ext) else {
            throw LoadError.unsupportedExtension(ext: ext)
        }

        guard FileManager.default.fileExists(atPath: path) else {
            throw LoadError.fileMissing(path: path)
        }

        switch strategy {
        case .sceneKit:
            return try loadViaSceneKit(url: fileURL)
        case .modelIO:
            return try loadViaMDLAsset(url: fileURL)
        case .stlConvert:
            return try loadViaSTLConverter(stlPath: path)
        }
    }

    /// Returns the loading strategy for a given file extension.
    public static func strategy(forExtension ext: String) -> Strategy? {
        let lower = ext.lowercased()
        switch lower {
        case "usdz", "usd", "scn", "dae", "obj":
            return .sceneKit
        case "ply", "abc", "fbx":
            return .modelIO
        case "stl":
            return .stlConvert
        default:
            return nil
        }
    }

    // MARK: - Private loaders

    private func loadViaSceneKit(url: URL) throws -> SCNScene {
        // `SCNScene(url:)` is documented to return nil — not throw — on failure.
        guard let scene = try? SCNScene(url: url, options: nil) else {
            throw LoadError.sceneKitReturnedNil(path: url.path)
        }
        return scene
    }

    private func loadViaMDLAsset(url: URL) throws -> SCNScene {
        // NOTE (OQ2 / FBX): FBX parsing has higher attack surface than
        // GLB/USDZ due to Autodesk SDK internals. This is accepted for
        // Phase 1 per the security addendum decision. Phase 4 may add
        // tighter sandboxing or format-specific validation.
        if #available(macOS 13, *) {
            let asset = MDLAsset(url: url)
            guard asset.count > 0 else {
                throw LoadError.mdlAssetFailed(path: url.path)
            }
            // Round-trip through a temp USDZ so SceneKit can load the
            // converted geometry. MDLAsset can export to USDZ format which
            // SceneKit handles natively.
            let tempDir = URL.temporaryDirectory
                .appendingPathComponent("hype-scene3d", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).usdz")
            defer { try? FileManager.default.removeItem(at: tempURL) }

            do {
                try asset.export(to: tempURL)
            } catch {
                throw LoadError.mdlAssetFailed(path: url.path)
            }
            return try loadViaSceneKit(url: tempURL)
        } else {
            // Pre-macOS 13: GLB/FBX via MDLAsset is not supported. Fall
            // back gracefully — the caller shows an "unsupported" message.
            throw LoadError.mdlAssetFailed(path: url.path)
        }
    }

    private func loadViaSTLConverter(stlPath: String) throws -> SCNScene {
        let objPath: String
        do {
            objPath = try STLConverter.convert(stlPath: stlPath)
        } catch {
            throw LoadError.stlConversionFailed
        }
        let objURL = URL(fileURLWithPath: objPath)
        return try loadViaSceneKit(url: objURL)
    }
}
