import Testing
import Foundation
@testable import Hype
@testable import HypeCore

// MARK: - Stubs

/// Stub converter that returns canned USDZ bytes without touching the filesystem.
private struct StubConverter: Scene3DAssetConverting {
    /// Bytes to return from `convertToUSDZ`. If `nil`, the stub throws `StubError`.
    let result: Data?

    enum StubError: Error, LocalizedError {
        case conversionFailed
        var errorDescription: String? { "stub conversion failure" }
    }

    func convertToUSDZ(sourceData: Data, fileExtension: String) throws -> Data {
        guard let data = result else {
            throw StubError.conversionFailed
        }
        return data
    }
}

// MARK: - Helpers

/// Sentinel USDZ bytes: ZIP PK magic followed by a minimal USDZ-like payload.
private let usdzSentinel = Data([0x50, 0x4B, 0x03, 0x04, 0x55, 0x53, 0x44, 0x5A]) // "PK..USDZ"

/// Sentinel GLB bytes: glTF binary magic `glTF` (0x67 0x6C 0x54 0x46).
private let glbSentinel = Data([0x67, 0x6C, 0x54, 0x46, 0x02, 0x00, 0x00, 0x00])

/// Sentinel "converted" USDZ bytes returned by the stub converter.
private let convertedUSDZ = Data([0x50, 0x4B, 0x03, 0x04, 0x43, 0x4F, 0x4E, 0x56]) // "PK..CONV"

/// Creates a per-test isolated cache directory name and returns it alongside
/// the full `URL` that `ARQuickLookPresenter` will create under
/// `~/Library/Caches/com.hype.app/<name>`. Callers must clean up with `defer`.
private func makeIsolatedCacheName() -> (name: String, fullURL: URL) {
    let name = "ar-ql-test-\(UUID().uuidString)"
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let url = caches
        .appendingPathComponent("com.hype.app", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    return (name, url)
}

// MARK: - ARQuickLookPresenterTests

/// Unit tests for `ARQuickLookPresenter`.
///
/// All I/O is isolated to a per-test subdirectory under
/// `~/Library/Caches/com.hype.app/ar-ql-test-<UUID>` and cleaned up in `defer`.
/// No real GLB/USDZ conversion is performed; converters are stubbed.
/// `QLPreviewPanel` is never activated — tests call `stageAsset(_:)` directly.
@MainActor
@Suite("ARQuickLookPresenter")
struct ARQuickLookPresenterTests {

    // MARK: - Scenario 1: non-model3D asset throws .unsupportedAssetKind

    @Test("non-model3D asset throws unsupportedAssetKind")
    func nonModel3DAssetThrowsUnsupportedKind() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: convertedUSDZ),
            cacheDirectoryName: cacheName,
            osVersion: { true }
        )

        let imageAsset = SpriteAsset(
            name: "photo.png",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data([0xFF, 0xD8, 0xFF]),
            width: 64,
            height: 64
        )

        await #expect(throws: ARQuickLookError.self) {
            _ = try await presenter.stageAsset(imageAsset)
        }

        // Verify it's specifically .unsupportedAssetKind.
        do {
            _ = try await presenter.stageAsset(imageAsset)
            Issue.record("Expected ARQuickLookError.unsupportedAssetKind but no error was thrown")
        } catch let err as ARQuickLookError {
            #expect(err == .unsupportedAssetKind(kind: "imageTexture"))
        }
    }

    // MARK: - Scenario 2: USDZ asset is staged directly without conversion

    @Test("USDZ asset is staged directly, bytes preserved, no conversion")
    func usdzAssetStagedDirectly() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let converter = StubConverter(result: nil) // throws if called — should NOT be called
        let presenter = ARQuickLookPresenter(
            converter: converter,
            cacheDirectoryName: cacheName,
            osVersion: { true }
        )

        let assetID = UUID()
        let usdzAsset = SpriteAsset(
            id: assetID,
            name: "model.usdz",
            kind: .model3D,
            mimeType: "model/vnd.usdz+zip",
            data: usdzSentinel,
            width: 0,
            height: 0
        )

        let stagedURL = try await presenter.stageAsset(usdzAsset)

        // The staged path must exist.
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))

        // The path must be named after the asset UUID.
        #expect(stagedURL.lastPathComponent == "\(assetID.uuidString).usdz")

        // The bytes on disk must be the original USDZ bytes (no conversion).
        let onDisk = try Data(contentsOf: stagedURL)
        #expect(onDisk == usdzSentinel)

        // The cache directory must have been created with 0o700 permissions (C10).
        let attrs = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
        if let perms = attrs[.posixPermissions] as? Int {
            #expect(perms == 0o700,
                "Expected 0o700 permissions on cache dir, got 0o\(String(perms, radix: 8))")
        }
    }

    // MARK: - Scenario 3: GLB asset routes through converter

    @Test("GLB asset routes through converter, staged file contains converter output")
    func glbAssetRoutedThroughConverter() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: convertedUSDZ),
            cacheDirectoryName: cacheName,
            osVersion: { true }
        )

        let assetID = UUID()
        let glbAsset = SpriteAsset(
            id: assetID,
            name: "robot.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: glbSentinel,
            width: 0,
            height: 0
        )

        let stagedURL = try await presenter.stageAsset(glbAsset)

        // Staged file exists.
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))

        // Named after the asset UUID with .usdz extension.
        #expect(stagedURL.lastPathComponent == "\(assetID.uuidString).usdz")

        // Bytes come from the converter, NOT the original GLB input.
        let onDisk = try Data(contentsOf: stagedURL)
        #expect(onDisk == convertedUSDZ,
            "Expected converter output bytes on disk, got \(onDisk.prefix(8).map { String($0, radix: 16) })")
        #expect(onDisk != glbSentinel,
            "Staged file should NOT contain the raw GLB bytes")
    }

    // MARK: - Scenario 4: FBX asset routes through converter

    @Test("FBX asset routes through converter")
    func fbxAssetRoutedThroughConverter() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let fbxSentinel = Data([0x4B, 0x61, 0x79, 0x64, 0x61, 0x72, 0x61]) // "Kaydara" FBX magic
        let fbxUSDZ = Data([0x50, 0x4B, 0x03, 0x04, 0x46, 0x42, 0x58, 0x21]) // "PK..FBX!"

        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: fbxUSDZ),
            cacheDirectoryName: cacheName,
            osVersion: { true }
        )

        let fbxAsset = SpriteAsset(
            name: "character.fbx",
            kind: .model3D,
            mimeType: "model/fbx",
            data: fbxSentinel,
            width: 0,
            height: 0
        )

        let stagedURL = try await presenter.stageAsset(fbxAsset)
        let onDisk = try Data(contentsOf: stagedURL)

        // Staged bytes come from the converter (not the raw FBX).
        #expect(onDisk == fbxUSDZ)
        #expect(onDisk != fbxSentinel)
    }

    // MARK: - Scenario 5: OS version gate

    @Test("osVersion: false causes unsupportedOS for any non-USDZ model3D")
    func unsupportedOSGateTriggersOnNonUSDZ() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: convertedUSDZ),
            cacheDirectoryName: cacheName,
            osVersion: { false }   // Simulates macOS 12
        )

        let glbAsset = SpriteAsset(
            name: "model.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: glbSentinel,
            width: 0,
            height: 0
        )

        do {
            _ = try await presenter.stageAsset(glbAsset)
            Issue.record("Expected ARQuickLookError.unsupportedOS but no error was thrown")
        } catch let err as ARQuickLookError {
            #expect(err == .unsupportedOS)
        }
    }

    @Test("osVersion: false does NOT block USDZ assets (no conversion needed)")
    func unsupportedOSDoesNotBlockUSDZ() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: nil), // would throw if called
            cacheDirectoryName: cacheName,
            osVersion: { false }   // Simulates macOS 12
        )

        let usdzAsset = SpriteAsset(
            name: "model.usdz",
            kind: .model3D,
            mimeType: "model/vnd.usdz+zip",
            data: usdzSentinel,
            width: 0,
            height: 0
        )

        // Should NOT throw — USDZ bypasses the OS-version gate entirely.
        let stagedURL = try await presenter.stageAsset(usdzAsset)
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    // MARK: - Scenario 6: Cache eviction

    @Test("eviction removes files older than 30 days")
    func evictionRemovesOldFiles() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        // Create the cache directory.
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Pre-populate with 5 fake USDZ files backdated 31 days.
        let thirtyOneDaysAgo = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        for i in 0..<5 {
            let fileURL = cacheURL.appendingPathComponent("fake-\(i).usdz")
            try Data([0x50, 0x4B]).write(to: fileURL)
            try FileManager.default.setAttributes(
                [.creationDate: thirtyOneDaysAgo],
                ofItemAtPath: fileURL.path
            )
        }

        // Verify 5 files exist before eviction.
        let before = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
        #expect(before.count == 5)

        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: nil),
            cacheDirectoryName: cacheName,
            osVersion: { true }
        )

        await presenter.evictOldStagedFiles()

        // All 5 files should have been evicted (older than 30-day cutoff).
        let after = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
        #expect(after.isEmpty,
            "Expected empty cache directory after eviction but found \(after)")
    }

    @Test("eviction respects 200 MB cap by removing oldest files first")
    func evictionRespects200MBCap() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Create 3 files with distinct ages, totalling > 200 MB when combined.
        // Each "file" will be faked at 80 MB using setAttributes (size attribute
        // is not writable via setAttributes on real files, so we use real large data).
        // Instead we work around this: create real 80 MB files.
        let eightMBChunk = Data(repeating: 0x41, count: 80 * 1024 * 1024)
        let now = Date()
        let dates: [Date] = [
            now.addingTimeInterval(-10 * 24 * 60 * 60), // 10 days old — newest
            now.addingTimeInterval(-20 * 24 * 60 * 60), // 20 days old
            now.addingTimeInterval(-25 * 24 * 60 * 60), // 25 days old — oldest
        ]

        // Write oldest-first so the sorted order in eviction matches expectations.
        for (i, date) in dates.enumerated() {
            let fileURL = cacheURL.appendingPathComponent("big-\(i).usdz")
            try eightMBChunk.write(to: fileURL)
            try FileManager.default.setAttributes(
                [.creationDate: date],
                ofItemAtPath: fileURL.path
            )
        }

        let before = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
        #expect(before.count == 3)

        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: nil),
            cacheDirectoryName: cacheName,
            osVersion: { true }
        )

        await presenter.evictOldStagedFiles()

        // After eviction the oldest file(s) that pushed cumulative total over
        // 200 MB should be gone. With 3 × 80 MB = 240 MB total and oldest-first
        // sorting: after 1 file (80 MB < 200 MB), cumulative = 80 MB; after 2nd
        // file (25-day-old), cumulative = 160 MB; after 3rd file, cumulative =
        // 240 MB > 200 MB → 3rd oldest file is evicted.
        // None are older than 30 days, so only the size cap triggers.
        let after = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
        // At least one file should have been evicted (the one that pushed over 200 MB).
        #expect(after.count < 3,
            "Expected some files removed by 200 MB cap, but found \(after.count) remaining")
    }

    // MARK: - Scenario 7: Conversion failure produces .conversionFailed

    @Test("converter failure is wrapped in conversionFailed with sanitized message")
    func converterFailureWrappedAsSanitizedError() async throws {
        let (cacheName, cacheURL) = makeIsolatedCacheName()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        // Stub that always throws.
        let presenter = ARQuickLookPresenter(
            converter: StubConverter(result: nil),
            cacheDirectoryName: cacheName,
            osVersion: { true }
        )

        let glbAsset = SpriteAsset(
            name: "broken.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: glbSentinel,
            width: 0,
            height: 0
        )

        do {
            _ = try await presenter.stageAsset(glbAsset)
            Issue.record("Expected ARQuickLookError.conversionFailed but no error was thrown")
        } catch let err as ARQuickLookError {
            // Must be .conversionFailed, not the raw StubError.
            guard case .conversionFailed(let reason) = err else {
                Issue.record("Expected .conversionFailed, got \(err)")
                return
            }

            // The reason string must not be empty.
            #expect(!reason.isEmpty, "conversionFailed reason should not be empty")

            // The reason must be capped at 200 characters (no raw exception leak).
            #expect(reason.count <= 200,
                "conversionFailed reason exceeds 200 chars: \(reason)")

            // The raw internal error type name should NOT appear in the reason.
            #expect(!reason.contains("StubError"),
                "Raw error type leaked into conversionFailed reason: \(reason)")
        }
    }
}
