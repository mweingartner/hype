import Foundation
import Testing
@testable import HypeCore

struct HyperCardImportedGlobalSeederTests {
    @Test("derives new-game globals from imported Defaults field and LoadGlobals order")
    func derivesNewGameGlobalsFromImportedDefaultsAndLoadGlobalsOrder() throws {
        let launcher = launcherDocument(defaults: [
            "Myst",
            "",
            "1",
            "true",
            "2",
            "false",
            "alpha",
            "beta",
        ].joined(separator: "\n"))
        let resources = resourceDocument(script: """
        on LoadGlobals
          put 1 into lineNum
          putit "ALL_CurrStack"
          putit "ALL_Page"
          putit "ALL_Version"
          putit "Playsounds"
          putit "Trans"
          putit "Quick"
          putit "line 1 of MY_SpaceNotes"
          putit "line 2 of MY_SpaceNotes"
        end LoadGlobals
        """)

        let globals = try #require(HyperCardImportedGlobalSeeder.newGameGlobals(
            from: launcher,
            resourceDocuments: [resources]
        ))

        #expect(globals["ALL_CurrStack"] == "Myst")
        #expect(globals["ALL_Page"] == "")
        #expect(globals["ALL_Version"] == "1")
        #expect(globals["Playsounds"] == "true")
        #expect(globals["Trans"] == "2")
        #expect(globals["Quick"] == "false")
        #expect(globals["MY_SpaceNotes"] == "alpha\nbeta")
        #expect(globals["Start_Game"] == "new")
        #expect(globals["RestoreData"] == "Myst\n\n1\ntrue\n2\nfalse\nalpha\nbeta")
    }

    @Test("reads LoadGlobals targets from disabled imported legacy stack scripts")
    func readsLoadGlobalsTargetsFromDisabledImportedLegacyStackScripts() throws {
        let resources = resourceDocument(script: LegacyHyperTalkScript.disabledForHypeTalkRuntime("""
        on openStack
        end openStack

        on LoadGlobals
          -- putit "Ignored_Comment"
          putit "ALL_CurrStack"
          putit "MY_RedBook"
        end LoadGlobals
        """))

        #expect(HyperCardImportedGlobalSeeder.loadGlobalsTargets(in: resources) == [
            "ALL_CurrStack",
            "MY_RedBook",
        ])
    }

    private func launcherDocument(defaults: String) -> HypeDocument {
        var document = HypeDocument.newDocument(name: "Myst-Application")
        document.cards[0].name = "Defaults"
        var field = Part(partType: .field, cardId: document.cards[0].id, name: "Defaults")
        field.textContent = defaults
        document.parts.append(field)
        return document
    }

    private func resourceDocument(script: String) -> HypeDocument {
        var document = HypeDocument.newDocument(name: "ALLRes")
        document.stack.script = script
        return document
    }
}
