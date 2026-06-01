import Foundation
import Testing
@testable import HypeCore

@Suite("Hype stack library")
struct HypeStackLibraryTests {
    @Test("resolves aliases using classic stack-name normalization")
    func resolvesAliasesUsingClassicStackNameNormalization() {
        let myst = HypeStackLibraryEntry(
            stackName: "Myst",
            aliases: ["Myst Island", "Myst.xstk"],
            source: .importedStackPackage,
            packagePath: "exports/stacks/Myst.xstk",
            legacyFirstCardId: 21776,
            cardCount: 330
        )
        let allRes = HypeStackLibraryEntry(
            stackName: "ALLRes",
            aliases: ["ALL Res", "ALLRes.xstk"],
            source: .importedStackPackage,
            packagePath: "exports/stacks/ALLRes.xstk"
        )
        let library = HypeStackLibrary(entries: [myst, allRes])

        #expect(library.resolution(for: "myst-island") == .resolved(myst))
        #expect(library.resolution(for: "mYsT.XSTK") == .resolved(myst))
        #expect(library.resolution(for: "ALL_res") == .resolved(allRes))
        #expect(library.resolution(for: "missing") == .missing(alias: "missing"))
    }

    @Test("start and stop using stack update the used stack set")
    func startAndStopUsingStackUpdateUsedStackSet() {
        let allRes = HypeStackLibraryEntry(
            stackName: "ALLRes",
            aliases: ["ALLRes", "ALL Res"],
            source: .importedStackPackage
        )
        var library = HypeStackLibrary(entries: [allRes])

        #expect(library.startUsing("all-res") == .started(allRes))
        #expect(library.startUsing("ALLRes") == .started(allRes))
        #expect(library.usedStackAliases == ["ALLRes"])

        #expect(library.stopUsing("ALL Res") == .stopped(allRes))
        #expect(library.usedStackAliases.isEmpty)
    }

    @Test("ambiguous aliases remain explicit")
    func ambiguousAliasesRemainExplicit() {
        let launcher = HypeStackLibraryEntry(
            stackName: " Myst",
            aliases: ["Myst", "Myst-Application"],
            source: .importedStackPackage,
            packagePath: "Myst-Application.xstk"
        )
        let island = HypeStackLibraryEntry(
            stackName: "Myst",
            aliases: ["Myst"],
            source: .importedStackPackage,
            packagePath: "Myst.xstk"
        )
        let library = HypeStackLibrary(entries: [launcher, island])

        #expect(library.resolution(for: "Myst") == .ambiguous(alias: "Myst", candidates: [launcher, island]))
    }

    @Test("imported stack entries can carry legacy card references")
    func importedStackEntriesCanCarryLegacyCardReferences() {
        let entry = HypeStackLibraryEntry(
            stackName: "Myst",
            source: .importedStackPackage,
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 44018, name: "Dock", sortIndex: 0),
                HypeStackLibraryCardReference(legacyCardId: 46439, name: "Black", sortIndex: 1)
            ]
        )

        #expect(entry.cardReferences.map(\.legacyCardId) == [44018, 46439])
        #expect(entry.cardReferences.map(\.name) == ["Dock", "Black"])
        #expect(entry.cardReferences.map(\.sortIndex) == [0, 1])
    }

    @Test("project navigation targets resolve through hype card ids")
    func projectNavigationTargetsResolveThroughHypeCardIds() {
        var document = HypeDocument.newDocument(name: "Myst")
        let dock = document.cards[0]
        let black = Card(stackId: document.stack.id, backgroundId: dock.backgroundId, name: "Black", sortKey: "a1")
        document.cards.append(black)

        let entry = HypeStackLibraryEntry(
            stackName: "Myst",
            source: .importedStackPackage,
            cardReferences: [
                HypeStackLibraryCardReference(legacyCardId: 44018, name: "Dock", sortIndex: 0, hypeCardId: dock.id),
                HypeStackLibraryCardReference(legacyCardId: 46439, name: "Black", sortIndex: 1, hypeCardId: black.id)
            ]
        )
        document.stackLibrary = HypeStackLibrary(entries: [entry])

        let target = ProjectNavigationTarget(
            stackEntryId: entry.id,
            stackName: "Myst",
            stackAlias: "Myst",
            legacyCardId: 46439,
            cardName: "Black"
        )

        #expect(ProjectNavigationTargetResolver.resolveCardId(for: target, in: document) == black.id)
    }

    @Test("project navigation targets can fall back to sorted card index")
    func projectNavigationTargetsCanFallBackToSortedCardIndex() {
        var document = HypeDocument.newDocument(name: "Myst")
        let dock = document.cards[0]
        let black = Card(stackId: document.stack.id, backgroundId: dock.backgroundId, name: "Black", sortKey: "a1")
        document.cards.append(black)

        let target = ProjectNavigationTarget(
            stackEntryId: UUID(),
            stackName: "Myst",
            stackAlias: "Myst",
            cardName: "",
            sortIndex: 1
        )

        #expect(ProjectNavigationTargetResolver.resolveCardId(for: target, in: document) == black.id)
    }
}
