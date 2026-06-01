import Foundation

public struct LooseMediaImportOptions: Sendable {
    public var manifestURL: URL
    public var sourceRootURL: URL?
    public var replacementRootURL: URL?
    public var requestedNames: Set<String>?

    public init(
        manifestURL: URL,
        sourceRootURL: URL? = nil,
        replacementRootURL: URL? = nil,
        requestedNames: Set<String>? = nil
    ) {
        self.manifestURL = manifestURL
        self.sourceRootURL = sourceRootURL
        self.replacementRootURL = replacementRootURL
        self.requestedNames = requestedNames
    }
}

public struct LooseMediaImportResult: Sendable {
    public var importedAssets: [Asset]
    public var missing: [LooseMediaImportDiagnostic]
    public var skipped: [LooseMediaImportDiagnostic]

    public init(
        importedAssets: [Asset] = [],
        missing: [LooseMediaImportDiagnostic] = [],
        skipped: [LooseMediaImportDiagnostic] = []
    ) {
        self.importedAssets = importedAssets
        self.missing = missing
        self.skipped = skipped
    }
}

public struct LooseMediaImportDiagnostic: Codable, Equatable, Sendable {
    public var relPath: String
    public var name: String
    public var reason: String

    public init(relPath: String, name: String, reason: String) {
        self.relPath = relPath
        self.name = name
        self.reason = reason
    }
}

public struct LooseMediaManifestEntry: Codable, Equatable, Sendable {
    public var relPath: String
    public var sourcePath: String
    public var outputPath: String
    public var size: Int?
    public var sha256: String
    public var finderType: String
    public var creator: String
    public var suffix: String
    public var kind: String

    public init(
        relPath: String,
        sourcePath: String,
        outputPath: String,
        size: Int?,
        sha256: String,
        finderType: String,
        creator: String,
        suffix: String,
        kind: String
    ) {
        self.relPath = relPath
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.size = size
        self.sha256 = sha256
        self.finderType = finderType
        self.creator = creator
        self.suffix = suffix
        self.kind = kind
    }
}

public enum LooseMediaManifestImportError: Error, LocalizedError {
    case unreadableManifest(URL)
    case malformedHeader

    public var errorDescription: String? {
        switch self {
        case .unreadableManifest(let url):
            return "Could not read loose media manifest at \(url.path)."
        case .malformedHeader:
            return "Loose media manifest is missing required TSV columns."
        }
    }
}

public struct LooseMediaManifestImporter: Sendable {
    public init() {}

    public func parseManifest(at url: URL) throws -> [LooseMediaManifestEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw LooseMediaManifestImportError.unreadableManifest(url)
        }
        return try parseManifest(text)
    }

    public func parseManifest(_ text: String) throws -> [LooseMediaManifestEntry] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let header = lines.first else { return [] }
        let columns = tsvColumns(header)
        let index = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, $0.offset) })
        let required = ["rel_path", "source_path", "output_path", "size", "sha256", "finder_type", "creator", "suffix", "kind"]
        guard required.allSatisfy({ index[$0] != nil }) else {
            throw LooseMediaManifestImportError.malformedHeader
        }

        return lines.dropFirst().compactMap { line in
            let row = tsvColumns(line)
            func value(_ key: String) -> String {
                guard let column = index[key], row.indices.contains(column) else { return "" }
                return row[column]
            }
            return LooseMediaManifestEntry(
                relPath: value("rel_path"),
                sourcePath: value("source_path"),
                outputPath: value("output_path"),
                size: Int(value("size")),
                sha256: value("sha256"),
                finderType: value("finder_type"),
                creator: value("creator"),
                suffix: value("suffix"),
                kind: value("kind")
            )
        }
    }

    public func importManifest(options: LooseMediaImportOptions, into document: inout HypeDocument) throws -> LooseMediaImportResult {
        let entries = try parseManifest(at: options.manifestURL)
        return try importEntries(entries, options: options, into: &document)
    }

    public func importEntries(
        _ entries: [LooseMediaManifestEntry],
        options: LooseMediaImportOptions,
        into document: inout HypeDocument
    ) throws -> LooseMediaImportResult {
        let requestedKeys = options.requestedNames.map { Set($0.map(Self.lookupKey)) }
        var result = LooseMediaImportResult()
        var importedRequestedKeys: Set<String> = []

        for entry in entries {
            let name = Self.classicMediaName(for: entry)
            let lookupKey = Self.lookupKey(name)
            if let requestedKeys, !requestedKeys.contains(lookupKey) {
                result.skipped.append(LooseMediaImportDiagnostic(relPath: entry.relPath, name: name, reason: "not requested"))
                continue
            }
            if requestedKeys != nil, importedRequestedKeys.contains(lookupKey) {
                result.skipped.append(LooseMediaImportDiagnostic(relPath: entry.relPath, name: name, reason: "duplicate requested media"))
                continue
            }

            guard let resolvedURL = resolvedURL(for: entry, options: options) else {
                result.missing.append(LooseMediaImportDiagnostic(relPath: entry.relPath, name: name, reason: "file not found"))
                continue
            }
            let data = try Data(contentsOf: resolvedURL)
            guard !data.isEmpty else {
                result.missing.append(LooseMediaImportDiagnostic(relPath: entry.relPath, name: name, reason: "file is empty"))
                continue
            }

            let existingNames = Set(document.assetRepository.assets.map(\.name))
            let asset = makeAsset(entry: entry, name: name, resolvedURL: resolvedURL, data: data, existingNames: existingNames)
            document.assetRepository.addAsset(asset)
            result.importedAssets.append(asset)
            importedRequestedKeys.insert(lookupKey)
        }

        return result
    }

    public static func lookupKey(_ name: String) -> String {
        classicMediaStem(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[:/\\\s_\-\.]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func classicMediaName(for entry: LooseMediaManifestEntry) -> String {
        classicMediaStem(URL(fileURLWithPath: entry.relPath).lastPathComponent)
    }

    private func makeAsset(
        entry: LooseMediaManifestEntry,
        name: String,
        resolvedURL: URL,
        data: Data,
        existingNames: Set<String>
    ) -> Asset {
        let kind = assetKind(for: entry, resolvedURL: resolvedURL)
        let dimensions = kind == .imageTexture ? PNGEncoding.imageDimensions(data: data) : nil
        let mimeType = mediaType(for: entry, resolvedURL: resolvedURL)
        var asset = Asset(
            name: uniqueName(name, existingNames: existingNames),
            kind: kind,
            mimeType: mimeType,
            data: data,
            width: dimensions?.width ?? 0,
            height: dimensions?.height ?? 0,
            tags: tags(for: entry),
            provenance: AssetProvenance(
                origin: .userImport,
                searchQuery: "HyperCard loose media \(entry.relPath)",
                attribution: AssetAttribution(
                    title: name,
                    sourceURL: resolvedURL.path,
                    providerName: "stackimport",
                    providerIdentifier: "loose-media"
                )
            )
        )
        asset.metadata = metadata(for: entry, resolvedURL: resolvedURL, name: name)
        return asset
    }

    private func resolvedURL(for entry: LooseMediaManifestEntry, options: LooseMediaImportOptions) -> URL? {
        for candidate in candidateURLs(for: entry, options: options) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func candidateURLs(for entry: LooseMediaManifestEntry, options: LooseMediaImportOptions) -> [URL] {
        var candidates: [URL] = []
        let name = Self.classicMediaName(for: entry)

        if let replacementRootURL = options.replacementRootURL, isQuickTime(entry) {
            let modernNames = [
                "\(name)-modern-av.mov",
                "\(name)-modern.mov",
                "\(name)-modern-audio.m4a",
                URL(fileURLWithPath: entry.relPath).lastPathComponent
            ]
            candidates.append(contentsOf: modernNames.map { replacementRootURL.appendingPathComponent($0, isDirectory: false) })
        }

        if let sourceRootURL = options.sourceRootURL {
            candidates.append(sourceRootURL.appendingPathComponent(entry.relPath, isDirectory: false))
            if entry.sourcePath.contains("<myst-source-root>") {
                let suffix = entry.sourcePath.replacingOccurrences(of: "<myst-source-root>/", with: "")
                candidates.append(sourceRootURL.appendingPathComponent(suffix, isDirectory: false))
            }
        }

        for path in [entry.outputPath, entry.sourcePath] where !path.isEmpty && !path.contains("<myst-source-root>") {
            let url = URL(fileURLWithPath: path)
            if url.path == path, url.path.hasPrefix("/") {
                candidates.append(url)
            }
        }

        return stableUniqueURLs(candidates)
    }

    private func assetKind(for entry: LooseMediaManifestEntry, resolvedURL: URL) -> AssetKind {
        let lowerKind = entry.kind.lowercased()
        let ext = resolvedURL.pathExtension.lowercased()
        if isQuickTime(entry) || ["mov", "moov", "mp4"].contains(ext) {
            return .videoClip
        }
        if lowerKind.contains("sound") || lowerKind.contains("audio") || ["wav", "aiff", "aif", "mp3", "m4a"].contains(ext) {
            return .audioClip
        }
        if lowerKind.contains("image") || ["png", "jpg", "jpeg", "gif"].contains(ext) {
            return .imageTexture
        }
        return .placeholderAsset
    }

    private func mediaType(for entry: LooseMediaManifestEntry, resolvedURL: URL) -> String {
        let ext = resolvedURL.pathExtension.lowercased()
        if isQuickTime(entry) || ["mov", "moov"].contains(ext) { return "video/quicktime" }
        switch ext {
        case "mp4": return "video/mp4"
        case "wav": return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }

    private func tags(for entry: LooseMediaManifestEntry) -> [String] {
        var tags = ["hypercard-import", "loose-media", "classic-media"]
        if !entry.kind.isEmpty {
            tags.append("kind-\(safeTagComponent(entry.kind))")
        }
        if !entry.finderType.isEmpty {
            tags.append("finder-\(entry.finderType.lowercased())")
        }
        if isQuickTime(entry) {
            tags.append("quicktime")
        }
        return stableUnique(tags)
    }

    private func metadata(for entry: LooseMediaManifestEntry, resolvedURL: URL, name: String) -> [AssetMetadataEntry] {
        [
            ("classic_name", name),
            ("lookup_key", Self.lookupKey(name)),
            ("rel_path", entry.relPath),
            ("source_path", entry.sourcePath),
            ("output_path", entry.outputPath),
            ("resolved_path", resolvedURL.path),
            ("size", entry.size.map(String.init) ?? ""),
            ("sha256", entry.sha256),
            ("finder_type", entry.finderType),
            ("creator", entry.creator),
            ("suffix", entry.suffix),
            ("kind", entry.kind),
            ("quicktime_audio_only", isAudioOnlyQuickTimeReplacement(entry: entry, resolvedURL: resolvedURL) ? "true" : "")
        ].map { key, value in
            AssetMetadataEntry(key: key, value: value, tags: ["hypercard-import", "loose-media"])
        }
    }

    private func isAudioOnlyQuickTimeReplacement(entry: LooseMediaManifestEntry, resolvedURL: URL) -> Bool {
        guard isQuickTime(entry) else { return false }
        let lowerName = resolvedURL.deletingPathExtension().lastPathComponent.lowercased()
        let ext = resolvedURL.pathExtension.lowercased()
        return lowerName.hasSuffix("-modern-audio") || ["m4a", "wav", "aif", "aiff", "mp3"].contains(ext)
    }

    private func isQuickTime(_ entry: LooseMediaManifestEntry) -> Bool {
        entry.kind.lowercased().contains("quicktime") ||
            entry.finderType.lowercased() == "myqt" ||
            entry.suffix.lowercased() == ".moov" ||
            entry.suffix.lowercased() == ".mov"
    }

    private static func classicMediaStem(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let separatorCount = trimmed.filter { $0 == ":" || $0 == "/" }.count
        let candidate: String
        if separatorCount >= 2 {
            candidate = trimmed
                .split(whereSeparator: { $0 == ":" || $0 == "/" })
                .last
                .map(String.init) ?? trimmed
        } else {
            candidate = trimmed
        }
        var stem = (candidate as NSString).deletingPathExtension
        if stem.isEmpty {
            stem = candidate
        }
        for suffix in ["-modern-audio", "-modern-av", "-modern"] where stem.lowercased().hasSuffix(suffix) {
            stem.removeLast(suffix.count)
        }
        return stem.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueName(_ base: String, existingNames: Set<String>) -> String {
        let fallback = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported Media" : base
        var name = fallback
        var counter = 2
        let lowerExisting = Set(existingNames.map { $0.lowercased() })
        while lowerExisting.contains(name.lowercased()) {
            name = "\(fallback) \(counter)"
            counter += 1
        }
        return name
    }

    private func safeTagComponent(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func stableUniqueURLs(_ values: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for value in values {
            let key = value.standardizedFileURL.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
    }

    private func tsvColumns(_ line: String) -> [String] {
        line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
}
