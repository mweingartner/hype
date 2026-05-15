import Foundation
import AppKit
@preconcurrency import Quartz
import HypeCore

// MARK: - ARQuickLookError

/// Errors surfaced to the user from the AR Quick Look path.
public enum ARQuickLookError: Error, LocalizedError, Sendable, Equatable {
    /// The asset kind is not `model3D`.
    case unsupportedAssetKind(kind: String)
    /// Asset has no recognised MIME type / file extension.
    case unknownFormat
    /// macOS 12 or earlier — MDLAsset GLB support requires macOS 13+.
    case unsupportedOS
    /// Conversion from GLB to USDZ failed.
    case conversionFailed(reason: String)
    /// Couldn't write the staged file to disk.
    case stagingFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedAssetKind(let kind):
            return "AR Quick Look only supports model3D assets (got '\(kind)')."
        case .unknownFormat:
            return "Couldn't determine the 3D file format for this asset."
        case .unsupportedOS:
            return "AR Quick Look requires macOS 13 or later."
        case .conversionFailed(let reason):
            return "Couldn't convert model to USDZ: \(String(reason.prefix(200)))."
        case .stagingFailed(let reason):
            return "Couldn't write the model to a temporary file: \(String(reason.prefix(200)))."
        }
    }
}

// MARK: - ARQuickLookPresenter

/// Presents a 3D asset in the macOS Quick Look panel.
///
/// macOS Quick Look automatically provides the AR Quick Look surface on
/// supported devices for USDZ assets. iOS uses `QLPreviewController`; macOS
/// uses the shared `QLPreviewPanel`.
///
/// Lifecycle:
/// 1. Caller invokes `present(asset:)`.
/// 2. The presenter writes the asset bytes to a temp file at
///    `~/Library/Caches/com.hype.app/ar-quicklook/<assetId>.<ext>`.
///    - For USDZ assets, bytes are written as-is.
///    - For GLB assets, `Scene3DAssetConverter.convertToUSDZ` runs on a
///      detached task before the panel opens.
/// 3. `QLPreviewPanel.shared().reloadData()` is called; the panel opens.
/// 4. The presenter retains the staged URL strongly via its data-source
///    conformance so Quick Look has a stable reference for its lifetime.
///
/// **Security:**
/// - The temp directory is created with POSIX permissions `0o700` (user-only).
/// - Temp files are named by `assetId.uuidString` — no user-controlled paths.
/// - On `evictOldStagedFiles`, files older than 30 days and totalling more
///   than 200 MB are deleted.
///
/// Threading: `present(asset:)` is `@MainActor`. GLB→USDZ conversion runs
/// on a detached task; the panel opens only after the file is ready.
@MainActor
public final class ARQuickLookPresenter: NSObject {

    // MARK: - Singleton

    public static let shared = ARQuickLookPresenter()

    // MARK: - Private state

    /// Currently-staged file URL, retained so Quick Look can read it.
    private var stagedURL: URL?

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Cache directory

    /// Returns the cache directory for AR Quick Look temp files.
    ///
    /// Creates the directory with `0o700` permissions (C10) if it doesn't exist.
    /// Declared `nonisolated` so it can be called from the detached eviction task.
    nonisolated private static func resolveCacheDirectory() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches
            .appendingPathComponent("com.hype.app", isDirectory: true)
            .appendingPathComponent("ar-quicklook", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return dir
    }

    // MARK: - Public API

    /// Present `asset` in Quick Look.
    ///
    /// The asset must be `model3D`; other kinds throw `.unsupportedAssetKind`.
    /// USDZ assets open directly; GLB assets are converted on a background
    /// task before presentation.
    ///
    /// - Parameter asset: A `model3D` asset from the Sprite Repository.
    /// - Throws: `ARQuickLookError`.
    public func present(asset: SpriteAsset) async throws {
        guard asset.kind == .model3D else {
            throw ARQuickLookError.unsupportedAssetKind(kind: asset.kind.rawValue)
        }

        // Determine the file extension from the asset's MIME type.
        let ext = fileExtension(for: asset.mimeType)
        guard !ext.isEmpty else {
            throw ARQuickLookError.unknownFormat
        }

        // Build the stable staged path using the asset id — never user-controlled.
        let cacheDir = try ARQuickLookPresenter.resolveCacheDirectory()
        let stagedPath: URL

        if ext == "usdz" {
            // USDZ: write directly.
            stagedPath = cacheDir.appendingPathComponent("\(asset.id.uuidString).usdz")
            do {
                try asset.data.write(to: stagedPath, options: .atomic)
            } catch {
                throw ARQuickLookError.stagingFailed(reason: error.localizedDescription)
            }
        } else {
            // GLB (or other MDLAsset-readable format): write the source file,
            // then convert to USDZ on a detached background task (C10).
            let sourcePath = cacheDir.appendingPathComponent("\(asset.id.uuidString).\(ext)")
            do {
                try asset.data.write(to: sourcePath, options: .atomic)
            } catch {
                throw ARQuickLookError.stagingFailed(reason: error.localizedDescription)
            }

            let usdzPath = cacheDir.appendingPathComponent("\(asset.id.uuidString).usdz")

            // Conversion requires macOS 13+.
            if #available(macOS 13, *) {
                let converter = Scene3DAssetConverter()
                let conversionResult: Result<Void, Scene3DAssetConverter.ConvertError> =
                    await Task.detached(priority: .userInitiated) {
                        do {
                            try converter.convertToUSDZ(inputURL: sourcePath, outputURL: usdzPath)
                            return .success(())
                        } catch let err as Scene3DAssetConverter.ConvertError {
                            return .failure(err)
                        } catch {
                            return .failure(.exportFailed(reason: error.localizedDescription))
                        }
                    }.value

                switch conversionResult {
                case .success:
                    stagedPath = usdzPath
                case .failure(let err):
                    throw ARQuickLookError.conversionFailed(reason: err.errorDescription ?? err.localizedDescription)
                }
            } else {
                throw ARQuickLookError.unsupportedOS
            }
        }

        // Retain the staged URL for the QLPreviewPanelDataSource callbacks.
        self.stagedURL = stagedPath

        // Open the shared Quick Look panel.
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.reloadData()
        if !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Evict staged files in the cache directory older than 30 days (200 MB cap).
    ///
    /// Safe to call from any actor — I/O runs on a detached task.
    public func evictOldStagedFiles() async {
        await Task.detached(priority: .background) {
            guard let cacheDir = try? ARQuickLookPresenter.resolveCacheDirectory() else { return }
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            ) else { return }

            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days
            let maxBytes: Int = 200 * 1024 * 1024 // 200 MB

            // Sort oldest-first so we evict the oldest when over the size cap.
            let sorted = items.sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return dateA < dateB
            }

            var totalBytes = 0
            for url in sorted {
                let rv = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let created = rv?.creationDate ?? .distantPast
                let size = rv?.fileSize ?? 0
                totalBytes += size

                if created < cutoff || totalBytes > maxBytes {
                    try? fm.removeItem(at: url)
                }
            }
        }.value
    }

    // MARK: - Private helpers

    /// Map a MIME type to a file extension for the staged temp file.
    private func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "model/vnd.usdz+zip", "model/usd", "model/usda", "model/usdc":
            return "usdz"
        case "model/gltf-binary", "application/octet-stream":
            // GLB is commonly delivered as application/octet-stream when the
            // server doesn't set the correct type. Accept it as GLB for model3D.
            return "glb"
        case "model/gltf+json":
            return "gltf"
        case "model/obj":
            return "obj"
        case "model/fbx":
            return "fbx"
        case "model/stl":
            return "stl"
        case "model/dae", "model/collada+xml":
            return "dae"
        default:
            // Heuristic: if the MIME contains "usdz" → usdz; "glb" / "gltf" → glb.
            if mimeType.contains("usdz") { return "usdz" }
            if mimeType.contains("glb") || mimeType.contains("gltf") { return "glb" }
            return ""
        }
    }
}

// MARK: - QLPreviewPanelDataSource

extension ARQuickLookPresenter: QLPreviewPanelDataSource {

    nonisolated public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        // Access `stagedURL` safely from the nonisolated context.
        // `QLPreviewPanel` calls this synchronously from the main thread, so
        // the main-actor isolation of `stagedURL` is satisfied in practice.
        // We use a MainActor.assumeIsolated guard to satisfy the compiler.
        return MainActor.assumeIsolated {
            stagedURL != nil ? 1 : 0
        }
    }

    nonisolated public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        return MainActor.assumeIsolated {
            stagedURL.map { $0 as NSURL }
        }
    }
}
