import Foundation

public struct StackImportPackageDocumentImportOptions: Sendable {
    public var packageURL: URL
    public var outputDirectoryURL: URL
    public var outputFileName: String?
    public var looseMediaManifestURL: URL?
    public var looseMediaSourceRootURL: URL?
    public var looseMediaReplacementRootURL: URL?
    public var looseMediaNames: Set<String>?
    public var stackLibraryEntries: [HypeStackLibraryEntry]
    public var usedStackAliases: [String]
    public var deploymentTargets: StackDeploymentTargets

    public init(
        packageURL: URL,
        outputDirectoryURL: URL = FileManager.default.temporaryDirectory,
        outputFileName: String? = nil,
        looseMediaManifestURL: URL? = nil,
        looseMediaSourceRootURL: URL? = nil,
        looseMediaReplacementRootURL: URL? = nil,
        looseMediaNames: Set<String>? = nil,
        stackLibraryEntries: [HypeStackLibraryEntry] = [],
        usedStackAliases: [String] = [],
        deploymentTargets: StackDeploymentTargets = .automationDefault()
    ) {
        self.packageURL = packageURL
        self.outputDirectoryURL = outputDirectoryURL
        self.outputFileName = outputFileName
        self.looseMediaManifestURL = looseMediaManifestURL
        self.looseMediaSourceRootURL = looseMediaSourceRootURL
        self.looseMediaReplacementRootURL = looseMediaReplacementRootURL
        self.looseMediaNames = looseMediaNames
        self.stackLibraryEntries = stackLibraryEntries
        self.usedStackAliases = usedStackAliases
        self.deploymentTargets = deploymentTargets
    }
}

public struct StackImportPackageDocumentImportResult: Sendable {
    public var document: HypeDocument
    public var report: HyperCardImportReport
    public var outputPackageURL: URL
    public var looseMediaResult: LooseMediaImportResult?

    public init(
        document: HypeDocument,
        report: HyperCardImportReport,
        outputPackageURL: URL,
        looseMediaResult: LooseMediaImportResult? = nil
    ) {
        self.document = document
        self.report = report
        self.outputPackageURL = outputPackageURL
        self.looseMediaResult = looseMediaResult
    }

    public var summary: StackImportPackageDocumentImportSummary {
        StackImportPackageDocumentImportSummary(
            stackName: document.stack.name,
            cardCount: document.cards.count,
            backgroundCount: document.backgrounds.count,
            partCount: document.parts.count,
            assetCount: document.assetRepository.assets.count,
            sharedContentAssetCount: document.assetRepository.assets.filter(\.isSharedContentStackAsset).count,
            outputPackagePath: outputPackageURL.path,
            warnings: report.warnings,
            stackImportDiagnostics: report.stackImportDiagnostics,
            looseMedia: looseMediaResult.map { result in
                StackImportLooseMediaImportSummary(
                    importedAssetCount: result.importedAssets.count,
                    imported: result.importedAssets.map(StackImportLooseMediaImportedAssetSummary.init(asset:)),
                    missing: result.missing,
                    skipped: result.skipped
                )
            },
            stackLibrary: document.stackLibrary.isEmpty ? nil : StackImportPackageStackLibrarySummary(
                entryCount: document.stackLibrary.entries.count,
                usedStackAliases: document.stackLibrary.usedStackAliases,
                ambiguousAliases: ambiguousAliases(in: document.stackLibrary)
            )
        )
    }

    private func ambiguousAliases(in library: HypeStackLibrary) -> [String] {
        let aliases = library.entries.flatMap(\.aliases)
        return aliases.filter { alias in
            if case .ambiguous = library.resolution(for: alias) {
                return true
            }
            return false
        }
        .reduce(into: [String]()) { result, alias in
            guard !result.contains(where: { HypeStackLibrary.lookupKey($0) == HypeStackLibrary.lookupKey(alias) }) else { return }
            result.append(alias)
        }
    }
}

public struct StackImportPackageDocumentImportSummary: Codable, Equatable, Sendable {
    public var stackName: String
    public var cardCount: Int
    public var backgroundCount: Int
    public var partCount: Int
    public var assetCount: Int
    public var sharedContentAssetCount: Int
    public var outputPackagePath: String
    public var warnings: [String]
    public var stackImportDiagnostics: StackImportPackageDiagnostics?
    public var looseMedia: StackImportLooseMediaImportSummary?
    public var stackLibrary: StackImportPackageStackLibrarySummary?

    public init(
        stackName: String,
        cardCount: Int,
        backgroundCount: Int,
        partCount: Int,
        assetCount: Int,
        sharedContentAssetCount: Int = 0,
        outputPackagePath: String,
        warnings: [String],
        stackImportDiagnostics: StackImportPackageDiagnostics?,
        looseMedia: StackImportLooseMediaImportSummary? = nil,
        stackLibrary: StackImportPackageStackLibrarySummary? = nil
    ) {
        self.stackName = stackName
        self.cardCount = cardCount
        self.backgroundCount = backgroundCount
        self.partCount = partCount
        self.assetCount = assetCount
        self.sharedContentAssetCount = sharedContentAssetCount
        self.outputPackagePath = outputPackagePath
        self.warnings = warnings
        self.stackImportDiagnostics = stackImportDiagnostics
        self.looseMedia = looseMedia
        self.stackLibrary = stackLibrary
    }
}

public struct StackImportLooseMediaImportSummary: Codable, Equatable, Sendable {
    public var importedAssetCount: Int
    public var imported: [StackImportLooseMediaImportedAssetSummary]
    public var missing: [LooseMediaImportDiagnostic]
    public var skipped: [LooseMediaImportDiagnostic]

    public init(
        importedAssetCount: Int,
        imported: [StackImportLooseMediaImportedAssetSummary] = [],
        missing: [LooseMediaImportDiagnostic],
        skipped: [LooseMediaImportDiagnostic]
    ) {
        self.importedAssetCount = importedAssetCount
        self.imported = imported
        self.missing = missing
        self.skipped = skipped
    }
}

public struct StackImportLooseMediaImportedAssetSummary: Codable, Equatable, Sendable {
    public var relPath: String
    public var name: String
    public var assetName: String
    public var kind: String
    public var resolvedPath: String

    public init(
        relPath: String,
        name: String,
        assetName: String,
        kind: String,
        resolvedPath: String
    ) {
        self.relPath = relPath
        self.name = name
        self.assetName = assetName
        self.kind = kind
        self.resolvedPath = resolvedPath
    }

    public init(asset: Asset) {
        self.init(
            relPath: asset.metadataValue(for: "rel_path"),
            name: asset.metadataValue(for: "classic_name").isEmpty ? asset.name : asset.metadataValue(for: "classic_name"),
            assetName: asset.name,
            kind: asset.kind.rawValue,
            resolvedPath: asset.metadataValue(for: "resolved_path")
        )
    }
}

private extension Asset {
    func metadataValue(for key: String) -> String {
        metadata.first { $0.key == key }?.value ?? ""
    }
}

public struct StackImportPackageStackLibrarySummary: Codable, Equatable, Sendable {
    public var entryCount: Int
    public var usedStackAliases: [String]
    public var ambiguousAliases: [String]

    public init(entryCount: Int, usedStackAliases: [String], ambiguousAliases: [String]) {
        self.entryCount = entryCount
        self.usedStackAliases = usedStackAliases
        self.ambiguousAliases = ambiguousAliases
    }
}

public struct StackImportPackageDocumentImporter: Sendable {
    public init() {}

    public func importPackage(
        options: StackImportPackageDocumentImportOptions
    ) throws -> StackImportPackageDocumentImportResult {
        var result = try StackImportPackageConverter(
            options: HyperCardImportOptions(deploymentTargets: options.deploymentTargets)
        ).convert(packageURL: options.packageURL)
        let looseMediaResult = try importLooseMediaIfRequested(options: options, into: &result.document)
        let outputURL = outputPackageURL(for: options, stackName: result.document.stack.name)
        applyStackLibraryIfRequested(options: options, outputPackageURL: outputURL, to: &result.document)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: outputURL)
        try HypeSQLiteStackStore().save(result.document, toPackageAt: outputURL)

        return StackImportPackageDocumentImportResult(
            document: result.document,
            report: result.report,
            outputPackageURL: outputURL,
            looseMediaResult: looseMediaResult
        )
    }

    private func importLooseMediaIfRequested(
        options: StackImportPackageDocumentImportOptions,
        into document: inout HypeDocument
    ) throws -> LooseMediaImportResult? {
        guard let manifestURL = options.looseMediaManifestURL else { return nil }
        return try LooseMediaManifestImporter().importManifest(
            options: LooseMediaImportOptions(
                manifestURL: manifestURL,
                sourceRootURL: options.looseMediaSourceRootURL,
                replacementRootURL: options.looseMediaReplacementRootURL,
                requestedNames: options.looseMediaNames
            ),
            into: &document
        )
    }

    private func outputPackageURL(
        for options: StackImportPackageDocumentImportOptions,
        stackName: String
    ) -> URL {
        let fileName = options.outputFileName?.nonEmpty
            ?? "\(Self.sanitizedFileName(stackName.nonEmpty ?? options.packageURL.deletingPathExtension().lastPathComponent))-debug-imported.hype"
        return options.outputDirectoryURL.appendingPathComponent(fileName, isDirectory: true)
    }

    private func applyStackLibraryIfRequested(
        options: StackImportPackageDocumentImportOptions,
        outputPackageURL: URL,
        to document: inout HypeDocument
    ) {
        guard !options.stackLibraryEntries.isEmpty || !options.usedStackAliases.isEmpty else { return }
        let entries = options.stackLibraryEntries.map { entry in
            enrichedCurrentStackEntry(
                entry,
                options: options,
                outputPackageURL: outputPackageURL,
                document: document
            )
        }
        document.stackLibrary = HypeStackLibrary(
            entries: entries,
            usedStackAliases: options.usedStackAliases
        )
    }

    private func enrichedCurrentStackEntry(
        _ entry: HypeStackLibraryEntry,
        options: StackImportPackageDocumentImportOptions,
        outputPackageURL: URL,
        document: HypeDocument
    ) -> HypeStackLibraryEntry {
        guard entryMatchesCurrentImport(entry, options: options, document: document) else { return entry }
        var enriched = entry
        enriched.documentPath = outputPackageURL.path
        enriched.cardReferences = entry.cardReferences.map { reference in
            var updated = reference
            if updated.hypeCardId == nil {
                updated.hypeCardId = cardId(for: reference, in: document)
            }
            return updated
        }
        return enriched
    }

    private func entryMatchesCurrentImport(
        _ entry: HypeStackLibraryEntry,
        options: StackImportPackageDocumentImportOptions,
        document: HypeDocument
    ) -> Bool {
        if let packagePath = entry.packagePath, !packagePath.isEmpty {
            return URL(fileURLWithPath: packagePath).standardizedFileURL.path
                == options.packageURL.standardizedFileURL.path
        }
        return HypeStackLibrary.lookupKey(entry.stackName) == HypeStackLibrary.lookupKey(document.stack.name)
    }

    private func cardId(for reference: HypeStackLibraryCardReference, in document: HypeDocument) -> UUID? {
        let cards = document.sortedCards
        if let sortIndex = reference.sortIndex, cards.indices.contains(sortIndex) {
            return cards[sortIndex].id
        }
        guard !reference.name.isEmpty else { return nil }
        let key = HypeStackLibrary.lookupKey(reference.name)
        let matches = cards.filter { HypeStackLibrary.lookupKey($0.name) == key }
        return matches.count == 1 ? matches[0].id : nil
    }

    fileprivate static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported Stack" : cleaned
    }
}

public struct StackImportPackageProjectImportOptions: Sendable {
    public var packageURLs: [URL]
    public var outputDirectoryURL: URL
    public var looseMediaManifestURL: URL?
    public var looseMediaSourceRootURL: URL?
    public var looseMediaReplacementRootURL: URL?
    public var looseMediaNames: Set<String>?
    public var stackLibraryEntries: [HypeStackLibraryEntry]
    public var usedStackAliases: [String]
    public var deploymentTargets: StackDeploymentTargets

    public init(
        packageURLs: [URL],
        outputDirectoryURL: URL = FileManager.default.temporaryDirectory,
        looseMediaManifestURL: URL? = nil,
        looseMediaSourceRootURL: URL? = nil,
        looseMediaReplacementRootURL: URL? = nil,
        looseMediaNames: Set<String>? = nil,
        stackLibraryEntries: [HypeStackLibraryEntry] = [],
        usedStackAliases: [String] = [],
        deploymentTargets: StackDeploymentTargets = .automationDefault()
    ) {
        self.packageURLs = packageURLs
        self.outputDirectoryURL = outputDirectoryURL
        self.looseMediaManifestURL = looseMediaManifestURL
        self.looseMediaSourceRootURL = looseMediaSourceRootURL
        self.looseMediaReplacementRootURL = looseMediaReplacementRootURL
        self.looseMediaNames = looseMediaNames
        self.stackLibraryEntries = stackLibraryEntries
        self.usedStackAliases = usedStackAliases
        self.deploymentTargets = deploymentTargets
    }
}

public struct StackImportPackageProjectImportResult: Sendable {
    public var packageResults: [StackImportPackageDocumentImportResult]
    public var stackLibraryEntries: [HypeStackLibraryEntry]

    public init(
        packageResults: [StackImportPackageDocumentImportResult],
        stackLibraryEntries: [HypeStackLibraryEntry]
    ) {
        self.packageResults = packageResults
        self.stackLibraryEntries = stackLibraryEntries
    }

    public var summary: StackImportPackageProjectImportSummary {
        StackImportPackageProjectImportSummary(
            stackCount: packageResults.count,
            outputPackagePaths: packageResults.map(\.outputPackageURL.path),
            stackLibraryEntryCount: stackLibraryEntries.count,
            sharedContentAssetCopyCount: packageResults
                .map { $0.document.assetRepository.assets.filter(\.isSharedContentStackAsset).count }
                .reduce(0, +),
            stacks: packageResults.map(projectStackSummary),
            packages: packageResults.map(\.summary)
        )
    }

    private func projectStackSummary(
        for result: StackImportPackageDocumentImportResult
    ) -> StackImportPackageProjectStackSummary {
        let firstCard = result.document.sortedCards.first
        let currentEntry = currentStackEntry(in: result.document, outputPackageURL: result.outputPackageURL)
        let firstCardReference = firstCard.flatMap { card in
            currentEntry?.cardReferences.first { reference in
                if reference.hypeCardId == card.id { return true }
                return reference.sortIndex == 0
            }
        }
        return StackImportPackageProjectStackSummary(
            stackName: result.document.stack.name,
            documentPath: result.outputPackageURL.path,
            cardCount: result.document.cards.count,
            firstCardId: firstCard?.id.uuidString,
            firstCardName: firstCardReference?.name.nonEmpty ?? firstCard?.name,
            legacyFirstCardId: firstCardReference?.legacyCardId ?? currentEntry?.legacyFirstCardId,
            stackLibraryEntryId: currentEntry?.id.uuidString,
            stackLibraryAliasCount: currentEntry?.aliases.count ?? 0
        )
    }

    private func currentStackEntry(
        in document: HypeDocument,
        outputPackageURL: URL
    ) -> HypeStackLibraryEntry? {
        document.stackLibrary.entries.first { entry in
            if let documentPath = entry.documentPath, !documentPath.isEmpty {
                return URL(fileURLWithPath: documentPath).standardizedFileURL.path
                    == outputPackageURL.standardizedFileURL.path
            }
            return HypeStackLibrary.lookupKey(entry.stackName) == HypeStackLibrary.lookupKey(document.stack.name)
        }
    }
}

public struct StackImportPackageProjectImportSummary: Codable, Equatable, Sendable {
    public var stackCount: Int
    public var outputPackagePaths: [String]
    public var stackLibraryEntryCount: Int
    public var sharedContentAssetCopyCount: Int
    public var stacks: [StackImportPackageProjectStackSummary]
    public var packages: [StackImportPackageDocumentImportSummary]

    public init(
        stackCount: Int,
        outputPackagePaths: [String],
        stackLibraryEntryCount: Int,
        sharedContentAssetCopyCount: Int = 0,
        stacks: [StackImportPackageProjectStackSummary] = [],
        packages: [StackImportPackageDocumentImportSummary]
    ) {
        self.stackCount = stackCount
        self.outputPackagePaths = outputPackagePaths
        self.stackLibraryEntryCount = stackLibraryEntryCount
        self.sharedContentAssetCopyCount = sharedContentAssetCopyCount
        self.stacks = stacks
        self.packages = packages
    }
}

public struct StackImportPackageProjectStackSummary: Codable, Equatable, Sendable {
    public var stackName: String
    public var documentPath: String
    public var cardCount: Int
    public var firstCardId: String?
    public var firstCardName: String?
    public var legacyFirstCardId: Int?
    public var stackLibraryEntryId: String?
    public var stackLibraryAliasCount: Int

    public init(
        stackName: String,
        documentPath: String,
        cardCount: Int,
        firstCardId: String? = nil,
        firstCardName: String? = nil,
        legacyFirstCardId: Int? = nil,
        stackLibraryEntryId: String? = nil,
        stackLibraryAliasCount: Int = 0
    ) {
        self.stackName = stackName
        self.documentPath = documentPath
        self.cardCount = cardCount
        self.firstCardId = firstCardId
        self.firstCardName = firstCardName
        self.legacyFirstCardId = legacyFirstCardId
        self.stackLibraryEntryId = stackLibraryEntryId
        self.stackLibraryAliasCount = stackLibraryAliasCount
    }
}

public struct StackImportPackageProjectImporter: Sendable {
    public init() {}

    public func importProject(
        options: StackImportPackageProjectImportOptions
    ) throws -> StackImportPackageProjectImportResult {
        let documentImporter = StackImportPackageDocumentImporter()
        var packageResults: [StackImportPackageDocumentImportResult] = []

        for packageURL in options.packageURLs {
            let outputFileName = "\(StackImportPackageDocumentImporter.sanitizedFileName(packageURL.deletingPathExtension().lastPathComponent))-debug-imported.hype"
            let result = try documentImporter.importPackage(
                options: StackImportPackageDocumentImportOptions(
                    packageURL: packageURL,
                    outputDirectoryURL: options.outputDirectoryURL,
                    outputFileName: outputFileName,
                    looseMediaManifestURL: options.looseMediaManifestURL,
                    looseMediaSourceRootURL: options.looseMediaSourceRootURL,
                    looseMediaReplacementRootURL: options.looseMediaReplacementRootURL,
                    looseMediaNames: options.looseMediaNames,
                    stackLibraryEntries: options.stackLibraryEntries,
                    usedStackAliases: options.usedStackAliases,
                    deploymentTargets: options.deploymentTargets
                )
            )
            packageResults.append(result)
        }

        let enrichedEntries = fullyEnrichedEntries(
            baseEntries: options.stackLibraryEntries,
            packageResults: packageResults
        )
        let library = HypeStackLibrary(
            entries: enrichedEntries,
            usedStackAliases: options.usedStackAliases
        )
        let contentAssetSources = contentStackAssetSources(
            entries: enrichedEntries,
            packageResults: packageResults
        )
        let rewrittenResults = try packageResults.map { result in
            var rewritten = result
            rewritten.document.stackLibrary = library
            shareContentStackAssets(from: contentAssetSources, into: &rewritten)
            try HypeSQLiteStackStore().save(rewritten.document, toPackageAt: rewritten.outputPackageURL)
            return rewritten
        }

        return StackImportPackageProjectImportResult(
            packageResults: rewrittenResults,
            stackLibraryEntries: enrichedEntries
        )
    }

    private func fullyEnrichedEntries(
        baseEntries: [HypeStackLibraryEntry],
        packageResults: [StackImportPackageDocumentImportResult]
    ) -> [HypeStackLibraryEntry] {
        baseEntries.map { entry in
            let candidates = packageResults
                .compactMap { enrichedEntry(matching: entry, in: $0.document) }
            return candidates.first(where: isEnrichedProjectEntry)
                ?? candidates.first
                ?? entry
        }
    }

    private func isEnrichedProjectEntry(_ entry: HypeStackLibraryEntry) -> Bool {
        if entry.documentPath?.isEmpty == false { return true }
        return entry.cardReferences.contains { $0.hypeCardId != nil }
    }

    private func enrichedEntry(
        matching entry: HypeStackLibraryEntry,
        in document: HypeDocument
    ) -> HypeStackLibraryEntry? {
        document.stackLibrary.entries.first { candidate in
            if let packagePath = entry.packagePath, !packagePath.isEmpty {
                guard let candidatePackagePath = candidate.packagePath, !candidatePackagePath.isEmpty else {
                    return false
                }
                return URL(fileURLWithPath: packagePath).standardizedFileURL.path
                    == URL(fileURLWithPath: candidatePackagePath).standardizedFileURL.path
            }
            return HypeStackLibrary.lookupKey(entry.stackName) == HypeStackLibrary.lookupKey(candidate.stackName)
        }
    }

    private func contentStackAssetSources(
        entries: [HypeStackLibraryEntry],
        packageResults: [StackImportPackageDocumentImportResult]
    ) -> [ContentStackAssetSource] {
        entries
            .filter(\.isContentStack)
            .compactMap { entry in
                guard let result = packageResult(for: entry, in: packageResults),
                      !result.document.assetRepository.assets.isEmpty else {
                    return nil
                }
                return ContentStackAssetSource(
                    entry: entry,
                    outputPackageURL: result.outputPackageURL,
                    assets: result.document.assetRepository.assets
                )
            }
    }

    private func packageResult(
        for entry: HypeStackLibraryEntry,
        in packageResults: [StackImportPackageDocumentImportResult]
    ) -> StackImportPackageDocumentImportResult? {
        packageResults.first { result in
            if let documentPath = entry.documentPath, !documentPath.isEmpty {
                return URL(fileURLWithPath: documentPath).standardizedFileURL.path
                    == result.outputPackageURL.standardizedFileURL.path
            }
            return HypeStackLibrary.lookupKey(entry.stackName) == HypeStackLibrary.lookupKey(result.document.stack.name)
        }
    }

    private func shareContentStackAssets(
        from sources: [ContentStackAssetSource],
        into result: inout StackImportPackageDocumentImportResult
    ) {
        guard !sources.isEmpty else { return }
        let currentEntry = result.document.stackLibrary.entries.first { entry in
            if let documentPath = entry.documentPath, !documentPath.isEmpty {
                return URL(fileURLWithPath: documentPath).standardizedFileURL.path
                    == result.outputPackageURL.standardizedFileURL.path
            }
            return HypeStackLibrary.lookupKey(entry.stackName) == HypeStackLibrary.lookupKey(result.document.stack.name)
        }

        for source in sources where source.entry.id != currentEntry?.id {
            for asset in source.assets where shouldCopyContentAsset(asset, into: result.document.assetRepository) {
                result.document.assetRepository.addAsset(
                    contentStackCopy(
                        of: asset,
                        from: source
                    )
                )
            }
        }
    }

    private func shouldCopyContentAsset(
        _ asset: Asset,
        into repository: AssetRepository
    ) -> Bool {
        if let classicName = asset.classicMediaName,
           repository.asset(byClassicMediaName: classicName, kind: asset.kind) != nil {
            return false
        }
        if repository.assets.contains(where: { candidate in
            candidate.kind == asset.kind && candidate.resourceIdentity == asset.resourceIdentity
        }) {
            return false
        }
        return repository.asset(byName: asset.name, kind: asset.kind) == nil
    }

    private func contentStackCopy(
        of asset: Asset,
        from source: ContentStackAssetSource
    ) -> Asset {
        var copy = asset
        copy.id = UUID()
        copy.compilation = nil
        copy.metadata.append(contentsOf: [
            AssetMetadataEntry(key: "shared_from_content_stack", value: source.entry.stackName),
            AssetMetadataEntry(key: "shared_from_stack_entry_id", value: source.entry.id.uuidString),
            AssetMetadataEntry(key: "shared_from_document_path", value: source.outputPackageURL.path),
            AssetMetadataEntry(key: "shared_from_asset_id", value: asset.id.uuidString)
        ])
        if !copy.tags.contains("content-stack-shared") {
            copy.tags.append("content-stack-shared")
        }
        return copy
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ContentStackAssetSource {
    var entry: HypeStackLibraryEntry
    var outputPackageURL: URL
    var assets: [Asset]
}

private extension HypeStackLibraryEntry {
    var isContentStack: Bool {
        metadata.contains { entry in
            entry.key == "contentStack" && entry.value.caseInsensitiveCompare("true") == .orderedSame
        }
    }
}

private extension Asset {
    var isSharedContentStackAsset: Bool {
        metadata.contains { $0.key == "shared_from_content_stack" }
    }

    var classicMediaName: String? {
        if let name = metadata.reversed().first(where: { $0.key.lowercased() == "classic_name" })?.value,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var resourceIdentity: String? {
        guard let type = metadata.first(where: { $0.key == "resource_type" })?.value,
              let id = metadata.first(where: { $0.key == "resource_id" })?.value,
              !type.isEmpty,
              !id.isEmpty else {
            return nil
        }
        return "\(type):\(id)"
    }
}
