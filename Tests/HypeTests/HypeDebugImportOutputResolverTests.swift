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

    @Test("refuses to overwrite existing output package by default")
    func refusesToOverwriteExistingOutputPackageByDefault() throws {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeDebugImportOutputSafetyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Existing-debug-imported.hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        do {
            try HypeDebugImportOutputSafety.prepareOutputPackage(at: packageURL, params: [:])
            Issue.record("Expected debug import output safety to reject existing package")
        } catch let error as HypeDebugImportOutputSafetyError {
            #expect(error == .outputPackageAlreadyExists(packageURL))
        }
    }

    @Test("allows intentional output package replacement")
    func allowsIntentionalOutputPackageReplacement() throws {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeDebugImportOutputSafetyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Existing-debug-imported.hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        try HypeDebugImportOutputSafety.prepareOutputPackage(
            at: packageURL,
            params: ["replaceExistingOutputPackage": true]
        )

        #expect(!FileManager.default.fileExists(atPath: packageURL.path))
    }

    @Test("parses string overwrite opt in")
    func parsesStringOverwriteOptIn() {
        #expect(HypeDebugImportOutputSafety.replaceExistingOutput(from: ["replaceExisting": "true"]))
        #expect(HypeDebugImportOutputSafety.replaceExistingOutput(from: ["overwriteExisting": "1"]))
        #expect(!HypeDebugImportOutputSafety.replaceExistingOutput(from: ["replaceExisting": "false"]))
        #expect(!HypeDebugImportOutputSafety.replaceExistingOutput(from: [:]))
    }
}
