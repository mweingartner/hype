import Foundation
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("Project navigation router")
struct ProjectNavigationRouterTests {
    @Test("opens target document and posts resolved card navigation")
    func opensTargetDocumentAndPostsResolvedCardNavigation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-project-navigation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var document = HypeDocument.newDocument(name: "Other")
        let first = document.cards[0]
        let targetCard = Card(
            stackId: document.stack.id,
            backgroundId: first.backgroundId,
            name: "Target Card",
            sortKey: "a1"
        )
        document.cards.append(targetCard)
        let packageURL = root.appendingPathComponent("Other.hype", isDirectory: true)
        try HypeSQLiteStackStore().save(document, toPackageAt: packageURL)

        var openedURL: URL?
        var postedCardId: UUID?
        let target = ProjectNavigationTarget(
            stackEntryId: UUID(),
            stackName: "Other",
            stackAlias: "Other",
            documentPath: packageURL.path,
            cardName: "Target Card"
        )

        ProjectNavigationRouter.route(
            target,
            openDocument: { url, completion in
                openedURL = url
                completion(nil)
            },
            postNavigation: { cardId in
                postedCardId = cardId
            }
        )

        #expect(openedURL?.standardizedFileURL == packageURL.standardizedFileURL)
        #expect(postedCardId == targetCard.id)
    }
}
