import Foundation
import Testing
import HypeCore
@testable import Hype

@Suite("Hype debug imported startup global seeding")
struct HypeDebugImportedStartupGlobalSeederTests {
    @Test("does nothing unless explicitly requested")
    func doesNothingUnlessRequested() {
        var document = HypeDocument.newDocument(name: "Myst Launcher")

        let result = HypeDebugImportedStartupGlobalSeeder.seed(from: [:], into: &document)

        #expect(result.seededGlobals.isEmpty)
        #expect(result.importedStartupGlobalKeys.isEmpty)
        #expect(result.errors.isEmpty)
        #expect(document.scriptGlobals.isEmpty)
    }

    @Test("seeds Myst launcher globals when requested")
    func seedsMystLauncherGlobalsWhenRequested() throws {
        var document = HypeDocument.newDocument(name: "Myst Launcher")
        let supportPackageURL = try makeSupportPackage()

        let result = HypeDebugImportedStartupGlobalSeeder.seed(from: [
            "seedImportedStartupGlobals": true,
            "importedStartupResourceDocumentPaths": [supportPackageURL.path],
        ], into: &document)

        #expect(result.errors.isEmpty)
        #expect(result.importedStartupGlobalKeys.contains("ALL_CurrStack"))
        #expect(result.importedStartupGlobalKeys.contains("Start_Game"))
        #expect(document.scriptGlobals["ALL_CurrStack"] == "Myst")
        #expect(document.scriptGlobals["Start_Game"] == "new")
        #expect(document.scriptGlobals["MY_RedBook"] == "000000")
    }

    @Test("reports missing startup support packages but still seeds known globals")
    func reportsMissingStartupSupportPackages() {
        var document = HypeDocument.newDocument(name: "Myst Launcher")
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).hype", isDirectory: true)

        let result = HypeDebugImportedStartupGlobalSeeder.seed(from: [
            "seedImportedStartupGlobals": true,
            "importedStartupResourceDocumentPaths": [missing.path],
        ], into: &document)

        #expect(result.errors.count == 1)
        #expect(result.errors[0].contains(missing.path))
        #expect(document.scriptGlobals["ALL_CurrStack"] == "Myst")
    }

    private func makeSupportPackage() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeDebugImportedStartupGlobalSeederTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let packageURL = root.appendingPathComponent("ALLRes-debug-imported.hype", isDirectory: true)
        try HypeSQLiteStackStore().save(HypeDocument.newDocument(name: "ALLRes"), toPackageAt: packageURL)
        return packageURL
    }
}
