import Foundation
import SceneKit
import Testing
@testable import HypeCore

@Suite("Scene3DAssetLoader")
struct Scene3DAssetLoaderTests {

    private let loader = Scene3DAssetLoader()

    // MARK: (a) supportedExtensions includes all expected formats

    @Test("supportedExtensions includes all required formats")
    func supportedExtensionsComplete() {
        let expected = ["usdz", "usd", "scn", "dae", "obj", "stl", "ply", "abc", "fbx"]
        for ext in expected {
            #expect(Scene3DAssetLoader.supportedExtensions.contains(ext),
                    "\(ext) must be in supportedExtensions")
        }
        #expect(!Scene3DAssetLoader.supportedExtensions.contains("glb"),
                "GLB is stored in the repository but rendered through a USDZ companion")
    }

    // MARK: (b) strategy table correctness

    @Test("strategy(forExtension: fbx) returns .modelIO")
    func fbxStrategyIsModelIO() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "fbx") == .modelIO)
    }

    @Test("strategy(forExtension: glb) returns nil")
    func glbStrategyIsNil() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "glb") == nil)
    }

    @Test("strategy(forExtension: usdz) returns .sceneKit")
    func usdzStrategyIsSceneKit() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "usdz") == .sceneKit)
    }

    @Test("strategy(forExtension: stl) returns .stlConvert")
    func stlStrategyIsConvert() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "stl") == .stlConvert)
    }

    @Test("strategy(forExtension: scn) returns .sceneKit")
    func scnStrategyIsSceneKit() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "scn") == .sceneKit)
    }

    @Test("strategy(forExtension: dae) returns .sceneKit")
    func daeStrategyIsSceneKit() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "dae") == .sceneKit)
    }

    @Test("strategy(forExtension: ply) returns .modelIO")
    func plyStrategyIsModelIO() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "ply") == .modelIO)
    }

    @Test("strategy(forExtension: abc) returns .modelIO")
    func abcStrategyIsModelIO() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "abc") == .modelIO)
    }

    @Test("strategy for unknown extension returns nil")
    func unknownExtReturnsNil() {
        #expect(Scene3DAssetLoader.strategy(forExtension: "xyz") == nil)
        #expect(Scene3DAssetLoader.strategy(forExtension: "") == nil)
    }

    // MARK: (c) load(from:) with a non-existent path throws .fileMissing

    @Test("load with non-existent supported file throws fileMissing")
    func nonExistentFileThrowsFileMissing() {
        // A path with a supported extension that doesn't exist on disk.
        let url = URL(fileURLWithPath: "/tmp/hype-test-nonexistent-\(UUID().uuidString).obj")
        do {
            _ = try loader.load(from: url)
            Issue.record("Expected fileMissing error")
        } catch Scene3DAssetLoader.LoadError.fileMissing {
            // Expected.
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("load with missing file throws fileMissing")
    func missingFileThrowsFileMissing() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/model.obj")
        do {
            _ = try loader.load(from: url)
            Issue.record("Expected fileMissing error")
        } catch Scene3DAssetLoader.LoadError.fileMissing {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: (d) load(from:) with unsupported extension throws .unsupportedExtension

    @Test("load with unsupported extension throws unsupportedExtension")
    func unsupportedExtThrows() throws {
        // Write a temp file with an unknown extension.
        let tempURL = URL.temporaryDirectory.appendingPathComponent("test.xyz")
        try Data("hello".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try loader.load(from: tempURL)
            Issue.record("Expected unsupportedExtension error")
        } catch Scene3DAssetLoader.LoadError.unsupportedExtension(let ext) {
            #expect(ext == "xyz")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: (e) load(from:) for a tiny OBJ succeeds

    @Test("load a minimal OBJ file succeeds")
    func loadMinimalOBJ() throws {
        let objContent = """
        # Minimal OBJ
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """
        let tempURL = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).obj")
        try Data(objContent.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Load should succeed without throwing.
        let scene = try loader.load(from: tempURL)
        // Just verify it's a non-nil scene.
        #expect(type(of: scene) == SCNScene.self)
    }
}
