import Foundation
import Testing
@testable import Hype

@Suite("Hype debug import output resolver")
struct HypeDebugImportOutputResolverTests {
    @Test("defaults to isolated temp directories")
    func defaultsToIsolatedTempDirectories() throws {
        let first = try HypeDebugImportOutputResolver.outputDirectory(from: [:])
        let second = try HypeDebugImportOutputResolver.outputDirectory(from: [:])

        #expect(first != second)
        #expect(first.deletingLastPathComponent().lastPathComponent == HypeDebugImportOutputResolver.isolatedRootName)
        #expect(second.deletingLastPathComponent().lastPathComponent == HypeDebugImportOutputResolver.isolatedRootName)
        #expect(first.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    @Test("honors explicit output directory")
    func honorsExplicitOutputDirectory() throws {
        let explicit = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeDebugImportOutputResolverTests", isDirectory: true)

        let resolved = try HypeDebugImportOutputResolver.outputDirectory(from: [
            "outputDirectory": explicit.path
        ])

        #expect(resolved.standardizedFileURL == explicit.standardizedFileURL)
    }
}
