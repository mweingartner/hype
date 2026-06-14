import AppKit
import HypeCore

@MainActor
enum ProjectNavigationRouter {
    typealias DocumentOpener = (URL, @escaping (Error?) -> Void) -> Void

    static func route(
        _ target: ProjectNavigationTarget,
        openDocument: DocumentOpener? = nil,
        postNavigation: ((UUID) -> Void)? = nil
    ) {
        guard let documentURL = documentURL(for: target) else {
            HypeLogger.shared.error(
                "Project navigation target has no openable .hype document path for stack '\(target.stackName)'.",
                source: "ProjectNavigationRouter"
            )
            return
        }

        let targetCardId = resolvedCardId(for: target, at: documentURL)
        let opener = openDocument ?? { url, completion in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                completion(error)
            }
        }
        let poster = postNavigation ?? { cardId in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .navigateToCard, object: cardId)
            }
        }
        opener(documentURL) { error in
            if let error {
                HypeLogger.shared.error(
                    "Project navigation failed to open \(documentURL.path): \(error.localizedDescription)",
                    source: "ProjectNavigationRouter"
                )
                return
            }
            guard let targetCardId else { return }
            poster(targetCardId)
        }
    }

    private static func documentURL(for target: ProjectNavigationTarget) -> URL? {
        if let documentPath = target.documentPath, !documentPath.isEmpty {
            return URL(fileURLWithPath: documentPath, isDirectory: true)
        }
        if let packagePath = target.packagePath,
           URL(fileURLWithPath: packagePath).pathExtension.lowercased() == "hype" {
            return URL(fileURLWithPath: packagePath, isDirectory: true)
        }
        return nil
    }

    private static func resolvedCardId(for target: ProjectNavigationTarget, at documentURL: URL) -> UUID? {
        do {
            let document = try HypeSQLiteStackStore().load(fromPackageAt: documentURL)
            return ProjectNavigationTargetResolver.resolveCardId(for: target, in: document)
        } catch {
            HypeLogger.shared.error(
                "Project navigation could not inspect \(documentURL.path): \(error.localizedDescription)",
                source: "ProjectNavigationRouter"
            )
            return target.hypeCardId
        }
    }
}
