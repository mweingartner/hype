import Foundation
import AppKit
@preconcurrency import Quartz
import HypeCore

// MARK: - UncheckedSendableBox

/// Wraps a non-Sendable value and declares it `@unchecked Sendable`.
///
/// Use only for values that are safe for concurrent read access and whose
/// concurrent write risk is managed by the caller (e.g. a per-task local
/// copy that is never written to concurrently).  This is the same pattern
/// the project uses for `JSONCodec.decoder/encoder` (see JSONCodec.swift).
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

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
///    `~/Library/Caches/com.hype.app/<cacheDirectoryName>/<assetId>.<ext>`.
///    - For USDZ assets, bytes are written as-is.
///    - For GLB assets, `converter.convertToUSDZ` runs on a detached task
///      before the panel opens.
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
/// **Dependency injection:**
/// The designated initializer accepts `fileManager`, `converter`, and an
/// `osVersion` closure so the OS-version gate, file I/O, and conversion
/// are all substitutable in tests.
///
/// Threading: `present(asset:)` is `@MainActor`. GLB→USDZ conversion runs
/// on a detached task; the panel opens only after the file is ready.
@MainActor
public final class ARQuickLookPresenter: NSObject {

    // MARK: - Singleton

    /// Shared production instance using `FileManager.default`,
    /// `Scene3DAssetConverter()`, and the real macOS version check.
    public static let shared = ARQuickLookPresenter()

    // MARK: - Dependencies
    //
    // These are `let` constants set at init time and never mutated.
    // Read-only access is safe under the class-level `@MainActor`
    // isolation and the surrounding lock-free immutable usage pattern.

    /// FileManager for all cache-directory I/O.
    private let fileManager: FileManager
    /// GLB→USDZ converter (protocol-typed for test substitution).
    private let converter: any Scene3DAssetConverting
    /// Last path component of the per-app cache subdirectory.
    private let cacheDirectoryName: String
    /// Returns `true` when the OS supports ModelIO GLB/FBX conversion (macOS 13+).
    private let osVersionSupported: @Sendable () -> Bool

    // MARK: - Private state

    /// Currently-staged file URL, retained so Quick Look can read it.
    private var stagedURL: URL?

    // MARK: - Init

    /// Create a presenter with injected dependencies.
    ///
    /// - Parameters:
    ///   - fileManager: FileManager used for all cache-directory I/O. Defaults
    ///     to `FileManager.default`.
    ///   - converter: The GLB→USDZ converter. Defaults to
    ///     `Scene3DAssetConverter()`.
    ///   - cacheDirectoryName: Last path component of the per-app cache
    ///     subdirectory. Defaults to `"ar-quicklook"`.
    ///   - osVersion: Closure returning `true` when the OS supports ModelIO
    ///     GLB/FBX conversion (i.e. macOS 13+). Defaults to a runtime
    ///     `#available(macOS 13, *)` check. Tests pass `{ false }` to simulate
    ///     macOS 12.
    public init(
        fileManager: FileManager = .default,
        converter: any Scene3DAssetConverting = Scene3DAssetConverter(),
        cacheDirectoryName: String = "ar-quicklook",
        osVersion: @escaping @Sendable () -> Bool = {
            if #available(macOS 13, *) { return true } else { return false }
        }
    ) {
        self.fileManager = fileManager
        self.converter = converter
        self.cacheDirectoryName = cacheDirectoryName
        self.osVersionSupported = osVersion
        super.init()
    }

    // MARK: - Cache directory

    /// Returns the cache directory for AR Quick Look temp files.
    ///
    /// Creates the directory with `0o700` permissions (C10) if it doesn't exist.
    /// Declared `nonisolated` so it can be called from the eviction helper
    /// without crossing the main-actor boundary.
    nonisolated private func resolveCacheDirectory() throws -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches
            .appendingPathComponent("com.hype.app", isDirectory: true)
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(
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
        let stagedPath = try await stageAsset(asset)

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

    /// Stage an asset to the cache directory without opening Quick Look.
    ///
    /// This method contains all the testable I/O logic from `present(asset:)`.
    /// It is `internal` (accessible via `@testable import`) so tests can exercise
    /// the byte-staging and OS-gate paths without activating `QLPreviewPanel`.
    ///
    /// - Parameter asset: A `model3D` asset.
    /// - Returns: The URL of the staged USDZ file in the cache directory.
    /// - Throws: `ARQuickLookError`.
    func stageAsset(_ asset: SpriteAsset) async throws -> URL {
        guard asset.kind == .model3D else {
            throw ARQuickLookError.unsupportedAssetKind(kind: asset.kind.rawValue)
        }

        let ext = fileExtension(for: asset.mimeType)
        guard !ext.isEmpty else {
            throw ARQuickLookError.unknownFormat
        }

        let cacheDir = try resolveCacheDirectory()

        if ext == "usdz" {
            // USDZ: write directly, no conversion needed.
            let stagedPath = cacheDir.appendingPathComponent("\(asset.id.uuidString).usdz")
            do {
                try asset.data.write(to: stagedPath, options: .atomic)
            } catch {
                throw ARQuickLookError.stagingFailed(reason: error.localizedDescription)
            }
            return stagedPath
        } else {
            // GLB (or other MDLAsset-readable format): convert to USDZ.
            // Conversion requires macOS 13+.
            guard osVersionSupported() else {
                throw ARQuickLookError.unsupportedOS
            }

            let usdzPath = cacheDir.appendingPathComponent("\(asset.id.uuidString).usdz")
            let sourceExt = ext
            let sourceData = asset.data
            let converterRef = converter

            let conversionResult: Result<Data, Error> =
                await Task.detached(priority: .userInitiated) {
                    do {
                        let usdzData = try converterRef.convertToUSDZ(
                            sourceData: sourceData,
                            fileExtension: sourceExt
                        )
                        return .success(usdzData)
                    } catch {
                        return .failure(error)
                    }
                }.value

            switch conversionResult {
            case .success(let usdzData):
                do {
                    try usdzData.write(to: usdzPath, options: .atomic)
                } catch {
                    throw ARQuickLookError.stagingFailed(reason: error.localizedDescription)
                }
                return usdzPath
            case .failure(let err):
                throw ARQuickLookError.conversionFailed(
                    reason: err.localizedDescription.prefix(200).description
                )
            }
        }
    }

    /// Evict staged files in the cache directory older than 30 days (200 MB cap).
    ///
    /// Safe to call from any actor — I/O runs on a detached task.
    public func evictOldStagedFiles() async {
        // Box the non-Sendable FileManager for safe capture into the detached task.
        // The detached task accesses `fm` serially; no concurrent mutation occurs.
        let fmBox = UncheckedSendableBox(fileManager)
        guard let cacheDir = try? resolveCacheDirectory() else { return }
        await Task.detached(priority: .background) {
            let fm = fmBox.value
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
