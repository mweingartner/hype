import Foundation
import Testing
@testable import Hype

@Suite("Hype debug script global seeding")
struct HypeDebugScriptGlobalSeedParserTests {
    @Test("parses dictionary scriptGlobals into HyperTalk strings")
    func parsesDictionaryScriptGlobals() {
        let globals = HypeDebugScriptGlobalSeedParser.globals(from: [
            "scriptGlobals": [
                "Start_Game": "new",
                "playsounds": true,
                "Trans": 2,
                " ": "ignored",
                "Empty": NSNull(),
            ] as [String: Any]
        ])

        #expect(globals?["Start_Game"] == "new")
        #expect(globals?["playsounds"] == "true")
        #expect(globals?["Trans"] == "2")
        #expect(globals?["Empty"] == nil)
        #expect(globals?[""] == nil)
    }

    @Test("accepts globals aliases and JSON object strings")
    func acceptsAliasesAndJSONStrings() {
        let globalsAlias = HypeDebugScriptGlobalSeedParser.globals(from: [
            "globals": ["Quick": false]
        ])
        let hypercardAlias = HypeDebugScriptGlobalSeedParser.globals(from: [
            "hypercardGlobals": "{\"MY_RedBook\":\"000000\",\"DU_End\":\"\"}"
        ])

        #expect(globalsAlias?["Quick"] == "false")
        #expect(hypercardAlias?["MY_RedBook"] == "000000")
        #expect(hypercardAlias?["DU_End"] == "")
    }

    @Test("parses imported startup global seeding options")
    func parsesImportedStartupGlobalSeedingOptions() {
        let params: [String: Any] = [
            "seedImportedStartupGlobals": "true",
            "resourceDocuments": [
                ["path": " /tmp/ALLRes-debug-imported.hype "],
                "/tmp/INRes1-debug-imported.hype",
                ["ignored": "missing path"],
            ] as [Any],
        ]

        #expect(HypeDebugImportedStartupGlobalSeedOptions.isEnabled(in: params))
        #expect(HypeDebugImportedStartupGlobalSeedOptions.resourceDocumentPaths(from: params) == [
            "/tmp/ALLRes-debug-imported.hype",
            "/tmp/INRes1-debug-imported.hype",
        ])
    }
}
