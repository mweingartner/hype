import Foundation

public struct StackImportPackageConverter: Sendable {
    public var options: HyperCardImportOptions

    public init(options: HyperCardImportOptions = HyperCardImportOptions()) {
        self.options = options
    }

    public func convert(packageFiles: [String: Data], sourcePackage: HyperCardImportPackage? = nil) throws -> HyperCardImportResult {
        try convert(reader: InMemoryXSTKPackageReader(files: packageFiles), sourcePackage: sourcePackage)
    }

    public func convert(packageURL: URL, sourcePackage: HyperCardImportPackage? = nil) throws -> HyperCardImportResult {
        try convert(reader: FileSystemXSTKPackageReader(packageURL: packageURL), sourcePackage: sourcePackage)
    }

    private func convert(reader: XSTKPackageReader, sourcePackage: HyperCardImportPackage? = nil) throws -> HyperCardImportResult {
        let decoder = JSONDecoder()
        let project = try decode(XSTKProject.self, from: "project.json", reader: reader, decoder: decoder)
        let stackFile = project.stackFile ?? "stack_-1.json"
        let stack = try decode(XSTKStack.self, from: stackFile, reader: reader, decoder: decoder)

        var document = HypeDocument.newDocument(name: nonEmpty(stack.name, fallback: project.sourceFileName ?? "Imported HyperCard Stack"))
        document.stack.width = stack.cardWidth
        document.stack.height = stack.cardHeight
        document.stack.script = disabledLegacyScript(stack.script)
        if let firstFont = project.fonts?.first?.name, !firstFont.isEmpty {
            document.stack.defaultFont = firstFont
        }
        document.backgrounds = []
        document.cards = []
        document.parts = []
        document.paintLayers = []
        document.constraints = []

        let backgroundLayers = stack.layers.filter { $0.kind == "background" }
        var backgroundIdMap: [Int: UUID] = [:]
        var backgroundFiles: [(legacyId: Int, path: String, model: XSTKLayer)] = []

        for (index, layer) in backgroundLayers.enumerated() {
            let bg = Background(
                stackId: document.stack.id,
                name: nonEmpty(layer.name, fallback: "Background \(index + 1)"),
                sortKey: sortKey(index),
                script: ""
            )
            document.backgrounds.append(bg)
            backgroundIdMap[layer.id] = bg.id
            if let file = layer.file {
                backgroundFiles.append((layer.id, file, layer))
            }
        }

        if document.backgrounds.isEmpty {
            let bg = Background(stackId: document.stack.id, name: "Background 1")
            document.backgrounds.append(bg)
        }
        document.defaultBackgroundId = document.backgrounds.first?.id

        var cardLayers = stack.layers.filter { $0.kind == "card" }
        if let orderedIds = stack.pages?.flatMap(\.cardIds), !orderedIds.isEmpty {
            let order = Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($0.element, $0.offset) })
            cardLayers.sort { (order[$0.id] ?? Int.max, $0.id) < (order[$1.id] ?? Int.max, $1.id) }
        }

        var cardIdMap: [Int: UUID] = [:]
        var cardFiles: [(legacyId: Int, path: String, model: XSTKLayer)] = []
        for (index, layer) in cardLayers.enumerated() {
            let backgroundId = layer.owner.flatMap { backgroundIdMap[$0] } ?? document.defaultBackgroundId ?? document.backgrounds[0].id
            let card = Card(
                stackId: document.stack.id,
                backgroundId: backgroundId,
                name: nonEmpty(layer.name, fallback: "Card \(index + 1)"),
                sortKey: sortKey(index),
                marked: layer.marked ?? false,
                script: ""
            )
            document.cards.append(card)
            cardIdMap[layer.id] = card.id
            if let file = layer.file {
                cardFiles.append((layer.id, file, layer))
            }
        }

        if document.cards.isEmpty {
            let card = Card(stackId: document.stack.id, backgroundId: document.backgrounds[0].id, name: "Card 1")
            document.cards.append(card)
        }

        var importedPartCount = 0
        for file in backgroundFiles {
            guard let backgroundId = backgroundIdMap[file.legacyId],
                  let bgIndex = document.backgrounds.firstIndex(where: { $0.id == backgroundId }) else { continue }
            let background = try decode(XSTKLayerDetail.self, from: file.path, reader: reader, decoder: decoder)
            document.backgrounds[bgIndex].script = disabledLegacyScript(background.script)
            appendBitmapPart(from: background, reader: reader, owner: .background(backgroundId), to: &document)
            for (partIndex, sourcePart) in background.parts.enumerated() {
                document.parts.append(makePart(sourcePart, owner: .background(backgroundId), index: partIndex + 1))
                importedPartCount += 1
            }
        }

        for file in cardFiles {
            guard let cardId = cardIdMap[file.legacyId],
                  let cardIndex = document.cards.firstIndex(where: { $0.id == cardId }) else { continue }
            let card = try decode(XSTKLayerDetail.self, from: file.path, reader: reader, decoder: decoder)
            document.cards[cardIndex].script = disabledLegacyScript(card.script)
            appendBitmapPart(from: card, reader: reader, owner: .card(cardId), to: &document)
            for (partIndex, sourcePart) in card.parts.enumerated() {
                document.parts.append(makePart(sourcePart, owner: .card(cardId), index: partIndex + 1))
                importedPartCount += 1
            }
        }

        applyCardFieldContents(from: cardFiles, reader: reader, decoder: decoder, cardIdMap: cardIdMap, to: &document)
        let sourceManifest = try? decode(XSTKSourceManifest.self, from: "source-manifest.json", reader: reader, decoder: decoder)
        appendResourceAssets(from: sourceManifest, reader: reader, to: &document)

        let blockSummary = project.blocks.map {
            HyperCardBlockSummary(type: $0.type, count: 1, totalBytes: $0.size ?? 0)
        }
        let resourceSummary = sourceManifest?.resourceFork.resources.reduce(into: [String: (count: Int, bytes: Int)]()) { partial, resource in
            let current = partial[resource.type, default: (0, 0)]
            partial[resource.type] = (current.count + 1, current.bytes + resource.bytes)
        }
        .map { MacResourceSummary(type: $0.key, count: $0.value.count, totalBytes: $0.value.bytes) }
        .sorted { $0.type < $1.type } ?? []
        let warnings = project.warnings ?? []
        let unsupported = project.blocks
            .filter { $0.understood == false }
            .map { "Block \($0.type) \($0.id) was emitted by stackimport as not fully understood." }
        let scriptWarning = "Imported HyperCard scripts that are not valid HypeTalk are preserved as comments and disabled until translated."

        let report = HyperCardImportReport(
            stackName: document.stack.name,
            cardSize: HyperCardSize(width: document.stack.width, height: document.stack.height),
            blockSummary: blockSummary,
            resourceSummary: resourceSummary,
            importedBackgrounds: document.backgrounds.count,
            importedCards: document.cards.count,
            importedParts: importedPartCount,
            importedScripts: importedScriptCount(document),
            warnings: stableUnique(warnings + (disabledScriptCount(document) > 0 ? [scriptWarning] : [])),
            unsupportedFeatures: stableUnique(unsupported)
        )

        if let sourcePackage {
            let totalOriginalBytes = sourcePackage.dataFork.count + (sourcePackage.resourceFork?.count ?? 0)
            let embedOriginal = options.preserveOriginalForks && totalOriginalBytes <= options.maxEmbeddedOriginalBytes
            document.legacyImport = LegacyStackImportMetadata(
                sourceFileName: sourcePackage.sourceURL?.lastPathComponent ?? project.sourceFileName,
                dataForkSHA256: sourcePackage.dataFork.hypeSHA256Hex,
                resourceForkSHA256: sourcePackage.resourceFork?.hypeSHA256Hex,
                embeddedDataFork: embedOriginal ? sourcePackage.dataFork : nil,
                embeddedResourceFork: embedOriginal ? sourcePackage.resourceFork : nil,
                report: report
            )
        } else {
            document.legacyImport = LegacyStackImportMetadata(
                sourceFileName: project.sourceFileName,
                dataForkSHA256: "",
                report: report
            )
        }

        return HyperCardImportResult(document: document, report: document.legacyImport?.report ?? report)
    }

    private enum Owner {
        case background(UUID)
        case card(UUID)
    }

    private func makePart(_ source: XSTKPart, owner: Owner, index: Int) -> Part {
        let rect = source.rect ?? XSTKRect(left: 100, top: 100, right: 220, bottom: 140)
        let partType: PartType = source.type == "field" ? .field : .button
        let originalName = source.name ?? ""
        var part = Part(
            partType: partType,
            cardId: {
                if case .card(let id) = owner { return id }
                return nil
            }(),
            backgroundId: {
                if case .background(let id) = owner { return id }
                return nil
            }(),
            name: nonEmpty(source.name, fallback: "\(partType.rawValue.capitalized) \(abs(source.id))"),
            sortKey: sortKey(index),
            left: Double(rect.left),
            top: Double(rect.top),
            width: Double(max(1, rect.right - rect.left)),
            height: Double(max(1, rect.bottom - rect.top))
        )
        part.visible = source.visible ?? true
        part.enabled = source.enabled ?? true
        part.hilite = source.highlight ?? false
        part.autoHilite = source.autoHighlight ?? true
        part.textFont = nonEmpty(source.font, fallback: part.textFont)
        part.textSize = Double(source.textSize ?? Int(part.textSize))
        part.textStyle = textStyle(source.textStyles)
        part.textAlign = TextAlignment(rawValue: source.textAlign ?? "") ?? (partType == .field ? .left : .center)
        part.script = disabledLegacyScript(source.script)

        if partType == .button {
            part.buttonStyle = buttonStyle(source.style)
            part.showName = (source.showName ?? true) && !originalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            part.family = source.family ?? 0
        } else {
            part.fieldStyle = fieldStyle(source.style)
            part.lockText = source.lockText ?? false
            part.dontWrap = source.dontWrap ?? false
            part.wideMargins = source.wideMargins ?? false
            part.textContent = normalizeText(source.text ?? "")
        }
        return part
    }

    private func appendBitmapPart(from layer: XSTKLayerDetail, reader: XSTKPackageReader, owner: Owner, to document: inout HypeDocument) {
        guard let bitmap = layer.bitmap, !bitmap.isEmpty else { return }
        guard let bitmapData = try? reader.data(for: bitmap),
              let pngData = try? PBMImageConverter.pngData(from: bitmap, data: bitmapData) else { return }

        let ownerName: String
        let ownerTags: [String]
        switch owner {
        case .background(let id):
            ownerName = document.backgrounds.first(where: { $0.id == id })?.name ?? "Background"
            ownerTags = ["background-paint-layer"]
        case .card(let id):
            ownerName = document.cards.first(where: { $0.id == id })?.name ?? "Card"
            ownerTags = ["card-paint-layer"]
        }
        let baseAssetName = "\(ownerName) Paint Layer"
        let assetName = uniqueName(baseAssetName, existingNames: Set(document.assetRepository.assets.map(\.name)))
        let asset = Asset(
            name: assetName,
            kind: .imageTexture,
            mimeType: "image/png",
            data: pngData,
            width: document.stack.width,
            height: document.stack.height,
            tags: stableUnique(["hypercard-import", "stackimport-layer-bitmap", "paint-layer"] + ownerTags),
            provenance: AssetProvenance(
                origin: .userImport,
                searchQuery: "HyperCard layer bitmap \(layer.id)",
                attribution: AssetAttribution(
                    title: ownerName,
                    providerName: "stackimport",
                    providerIdentifier: "stackimport"
                )
            )
        )
        document.assetRepository.addAsset(asset)

        var part = Part(
            partType: .image,
            cardId: {
                if case .card(let id) = owner { return id }
                return nil
            }(),
            backgroundId: {
                if case .background(let id) = owner { return id }
                return nil
            }(),
            name: assetName,
            sortKey: "a000000",
            left: 0,
            top: 0,
            width: Double(document.stack.width),
            height: Double(document.stack.height)
        )
        part.imageData = pngData
        document.parts.append(part)
    }

    private func appendResourceAssets(from manifest: XSTKSourceManifest?, reader: XSTKPackageReader, to document: inout HypeDocument) {
        guard let manifest else {
            appendLooseResourceAssets(from: reader, to: &document)
            return
        }
        var importedPaths: Set<String> = []
        for resource in manifest.resourceFork.resources {
            let safeArtifacts = resource.outputArtifacts.filter { artifact in
                let safe = isSafePackagePath(artifact.path)
                if !safe {
                    logImportWarning("Skipping unsafe stackimport artifact path '\(artifact.path)' for resource \(resource.type) \(resource.id)")
                }
                return safe
            }
            let artifacts = safeArtifacts
                .sorted { lhs, rhs in
                    if assetPriority(for: lhs) != assetPriority(for: rhs) {
                        return assetPriority(for: lhs) < assetPriority(for: rhs)
                    }
                    return lhs.path < rhs.path
                }
            guard let primary = artifacts.first(where: isImportableAssetArtifact) else {
                if !resource.outputArtifacts.isEmpty {
                    logImportWarning("No supported asset artifact for resource \(resource.type) \(resource.id); preserved only as legacy import evidence")
                }
                continue
            }
            if assetKind(for: primary.mediaType, path: primary.path) == .placeholderAsset {
                logImportWarning("Importing unhandled resource artifact as metadata placeholder: resource \(resource.type) \(resource.id), mediaType='\(primary.mediaType)', path='\(primary.path)'")
            }
            guard let primaryData = try? reader.data(for: primary.path), !primaryData.isEmpty else {
                logImportWarning("Could not read stackimport artifact '\(primary.path)' for resource \(resource.type) \(resource.id)")
                continue
            }
            importedPaths.insert(primary.path)

            var asset = makeResourceAsset(
                data: primaryData,
                path: primary.path,
                mediaType: primary.mediaType,
                resource: resource,
                artifact: primary,
                existingNames: Set(document.assetRepository.assets.map(\.name))
            )

            for artifact in artifacts where artifact.path != primary.path {
                guard let data = try? reader.data(for: artifact.path), !data.isEmpty else {
                    logImportWarning("Could not read related stackimport artifact '\(artifact.path)' for resource \(resource.type) \(resource.id)")
                    continue
                }
                importedPaths.insert(artifact.path)
                appendArtifact(artifact, data: data, to: &asset)
            }

            document.assetRepository.addAsset(asset)
        }

        appendLooseResourceAssets(from: reader, excluding: importedPaths, to: &document)
    }

    private func appendLooseResourceAssets(from reader: XSTKPackageReader, to document: inout HypeDocument) {
        appendLooseResourceAssets(from: reader, excluding: [], to: &document)
    }

    private func appendLooseResourceAssets(from reader: XSTKPackageReader, excluding importedPaths: Set<String>, to document: inout HypeDocument) {
        for path in reader.allPaths.sorted() where !importedPaths.contains(path) && isLooseResourceAssetPath(path) {
            guard let data = try? reader.data(for: path), !data.isEmpty else {
                logImportWarning("Could not read loose stackimport resource artifact '\(path)'")
                continue
            }
            let mediaType = mediaTypeForPath(path)
            let resource = resourceIdentity(from: path)
            let artifact = XSTKResourceArtifact(
                path: path,
                format: artifactFormatForPath(path),
                mediaType: mediaType,
                description: "converted HyperCard resource artifact",
                variantIndex: nil
            )
            let asset = makeResourceAsset(
                data: data,
                path: path,
                mediaType: mediaType,
                resource: resource,
                artifact: artifact,
                existingNames: Set(document.assetRepository.assets.map(\.name))
            )
            if asset.kind == .placeholderAsset {
                logImportWarning("Importing loose unhandled resource artifact as metadata placeholder: mediaType='\(mediaType)', path='\(path)'")
            }
            document.assetRepository.addAsset(asset)
        }
    }

    private func makeResourceAsset(
        data: Data,
        path: String,
        mediaType: String,
        resource: XSTKResourceSummary,
        artifact: XSTKResourceArtifact,
        existingNames: Set<String>
    ) -> Asset {
        let kind = assetKind(for: mediaType, path: path)
        let dimensions = kind == .imageTexture ? PNGEncoding.imageDimensions(data: data) : nil
        let baseName = resourceAssetName(resource: resource, artifact: artifact, path: path)
        let name = uniqueName(baseName, existingNames: existingNames)
        var asset = Asset(
            name: name,
            kind: kind,
            mimeType: mediaType.isEmpty ? mediaTypeForPath(path) : mediaType,
            data: data,
            width: dimensions?.width ?? 0,
            height: dimensions?.height ?? 0,
            tags: resourceTags(resource: resource, artifact: artifact),
            provenance: AssetProvenance(
                origin: .userImport,
                searchQuery: "HyperCard resource \(resource.type) \(resource.id)",
                attribution: AssetAttribution(
                    title: resource.name,
                    providerName: "stackimport",
                    providerIdentifier: "stackimport"
                )
            )
        )
        if kind == .placeholderAsset {
            appendArtifact(artifact, data: data, to: &asset)
        }
        appendResourceLookupMetadata(resource: resource, artifact: artifact, path: path, to: &asset)
        return asset
    }

    private func appendResourceLookupMetadata(
        resource: XSTKResourceSummary,
        artifact: XSTKResourceArtifact,
        path: String,
        to asset: inout Asset
    ) {
        let type = resource.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let decodedName = decodedResourceName(resource.name)
        let stem = decodedResourceName(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
        let classicNames = stableUnique([
            decodedName,
            stem,
            "\(type)_\(resource.id)",
            "\(type) \(resource.id)",
        ])
        asset.metadata.append(AssetMetadataEntry(key: "resource_type", value: type))
        asset.metadata.append(AssetMetadataEntry(key: "resource_id", value: String(resource.id)))
        asset.metadata.append(AssetMetadataEntry(key: "resource_path", value: path))
        asset.metadata.append(AssetMetadataEntry(key: "resource_artifact_format", value: artifact.format))
        for name in classicNames {
            asset.metadata.append(AssetMetadataEntry(key: "classic_name", value: name))
        }
    }

    private func appendArtifact(_ artifact: XSTKResourceArtifact, data: Data, to asset: inout Asset) {
        if artifact.mediaType == "application/json" || artifact.format == "json" || artifact.format == "text" || artifact.mediaType.hasPrefix("text/") {
            asset.metadata.append(AssetMetadataEntry(
                key: URL(fileURLWithPath: artifact.path).lastPathComponent,
                value: String(data: data, encoding: .utf8) ?? "",
                mimeType: artifact.mediaType.isEmpty ? mediaTypeForPath(artifact.path) : artifact.mediaType,
                tags: ["hypercard-import", "stackimport-artifact", "format-\(artifact.format)"]
            ))
        } else {
            asset.files.append(AssetFile(
                name: URL(fileURLWithPath: artifact.path).lastPathComponent,
                role: .metadata,
                mimeType: artifact.mediaType.isEmpty ? mediaTypeForPath(artifact.path) : artifact.mediaType,
                data: data,
                tags: ["hypercard-import", "stackimport-artifact", "format-\(artifact.format)"]
            ))
        }
    }

    private func isImportableAssetArtifact(_ artifact: XSTKResourceArtifact) -> Bool {
        let kind = assetKind(for: artifact.mediaType, path: artifact.path)
        return kind == .imageTexture || kind == .audioClip || kind == .videoClip || kind == .placeholderAsset
    }

    private func isLooseResourceAssetPath(_ path: String) -> Bool {
        guard isSafePackagePath(path) else { return false }
        let lower = path.lowercased()
        guard lower.hasPrefix("sounds/") ||
              lower.hasPrefix("resource-") ||
              lower.hasPrefix("resource/") ||
              lower.hasPrefix("resources/") ||
              resourceIdentity(from: path).type != "RSRC" else {
            return false
        }
        return ["png", "wav", "aiff", "aif", "mp3", "m4a", "mov", "mp4", "json", "txt"].contains(pathExtension(path))
    }

    private func isSafePackagePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/").contains("..")
    }

    private func assetKind(for mediaType: String, path: String) -> AssetKind {
        let lowerMedia = mediaType.lowercased()
        if lowerMedia.hasPrefix("image/") || pathExtension(path) == "png" {
            return .imageTexture
        }
        if lowerMedia.hasPrefix("audio/") || ["wav", "aiff", "aif", "mp3", "m4a"].contains(pathExtension(path)) {
            return .audioClip
        }
        if lowerMedia.hasPrefix("video/") || ["mov", "mp4"].contains(pathExtension(path)) {
            return .videoClip
        }
        return .placeholderAsset
    }

    private func assetPriority(for artifact: XSTKResourceArtifact) -> Int {
        switch assetKind(for: artifact.mediaType, path: artifact.path) {
        case .imageTexture, .audioClip, .videoClip: return 0
        case .placeholderAsset: return 1
        default: return 2
        }
    }

    private func resourceAssetName(resource: XSTKResourceSummary, artifact: XSTKResourceArtifact, path: String) -> String {
        if resource.type == "snd " {
            let decoded = decodedResourceName(resource.name)
            if !decoded.isEmpty { return decoded }
        }
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return decodedResourceName(stem).isEmpty ? "\(resource.type.trimmingCharacters(in: .whitespaces)) \(resource.id)" : decodedResourceName(stem)
    }

    private func resourceIdentity(from path: String) -> XSTKResourceSummary {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "_", omittingEmptySubsequences: false)
        if parts.count >= 2, let id = Int(parts[1]) {
            return XSTKResourceSummary(type: decodedResourceName(String(parts[0])), id: id, name: "", bytes: 0, outputArtifacts: [])
        }
        if let sndIndex = parts.firstIndex(where: { $0.lowercased() == "snd" }),
           parts.count > parts.index(after: sndIndex),
           let id = Int(parts[parts.index(after: sndIndex)]) {
            let nameStart = parts.index(sndIndex, offsetBy: 2)
            let name = parts.count > nameStart ? parts.suffix(from: nameStart).joined(separator: "_") : ""
            return XSTKResourceSummary(type: "snd ", id: id, name: decodedResourceName(name), bytes: 0, outputArtifacts: [])
        }
        return XSTKResourceSummary(type: "RSRC", id: 0, name: decodedResourceName(stem), bytes: 0, outputArtifacts: [])
    }

    private func resourceTags(resource: XSTKResourceSummary, artifact: XSTKResourceArtifact) -> [String] {
        var tags = [
            "hypercard-import",
            "stackimport-artifact",
            "resource-\(resource.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())",
            "format-\(artifact.format)"
        ]
        if resource.type == "snd " {
            tags.append("sound-resource")
            tags.append("resource-snd")
        }
        if !artifact.description.isEmpty {
            tags.append("converted-resource")
        }
        return stableUnique(tags)
    }

    private func uniqueName(_ base: String, existingNames: Set<String>) -> String {
        let fallback = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported Resource" : base
        var name = fallback
        var counter = 2
        let lowerExisting = Set(existingNames.map { $0.lowercased() })
        while lowerExisting.contains(name.lowercased()) {
            name = "\(fallback) \(counter)"
            counter += 1
        }
        return name
    }

    private func decodedResourceName(_ name: String) -> String {
        (name.removingPercentEncoding ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pathExtension(_ path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    private func artifactFormatForPath(_ path: String) -> String {
        switch pathExtension(path) {
        case "png": return "png"
        case "json": return "json"
        case "txt": return "text"
        case "wav", "aiff", "aif", "mp3", "m4a": return "audio"
        case "mov", "mp4": return "video"
        default: return "binary"
        }
    }

    private func mediaTypeForPath(_ path: String) -> String {
        switch pathExtension(path) {
        case "png": return "image/png"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "wav": return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }

    private func logImportWarning(_ message: String) {
        HypeLogger.shared.warn(message, source: "HyperCardImport")
    }

    private func applyCardFieldContents(
        from cardFiles: [(legacyId: Int, path: String, model: XSTKLayer)],
        reader: XSTKPackageReader,
        decoder: JSONDecoder,
        cardIdMap: [Int: UUID],
        to document: inout HypeDocument
    ) {
        for file in cardFiles {
            guard let cardId = cardIdMap[file.legacyId],
                  let detail = try? decode(XSTKLayerDetail.self, from: file.path, reader: reader, decoder: decoder) else { continue }
            for content in detail.contents where content.layer == "card" {
                guard let index = document.parts.firstIndex(where: { $0.cardId == cardId && legacyNameMatches($0, content.id) }) else { continue }
                document.parts[index].textContent = normalizeText(content.text)
            }
        }
    }

    private func legacyNameMatches(_ part: Part, _ legacyId: Int) -> Bool {
        part.name.hasSuffix(" \(abs(legacyId))")
    }

    private func decode<T: Decodable>(_ type: T.Type, from path: String, reader: XSTKPackageReader, decoder: JSONDecoder) throws -> T {
        do {
            return try decoder.decode(T.self, from: reader.data(for: path))
        } catch {
            throw HyperCardImportError.generatedPackageInvalid("\(path): \(error.localizedDescription)")
        }
    }

    private func buttonStyle(_ style: String?) -> ButtonStyle {
        switch style?.lowercased() {
        case "transparent": return .transparent
        case "opaque": return .opaque
        case "roundrect": return .roundRect
        case "shadow": return .shadow
        case "checkbox": return .checkBox
        case "radiobutton": return .radio
        case "standard": return .standard
        case "default": return .default
        case "oval": return .oval
        default: return .standard
        }
    }

    private func fieldStyle(_ style: String?) -> FieldStyle {
        switch style?.lowercased() {
        case "transparent": return .transparent
        case "shadow": return .shadow
        case "scrolling": return .scrolling
        case "opaque", "rectangle": return .rectangle
        default: return .rectangle
        }
    }

    private func textStyle(_ styles: [String]?) -> String {
        let filtered = (styles ?? []).filter { $0 != "plain" }
        return filtered.isEmpty ? "plain" : filtered.joined(separator: ",")
    }

    private func normalizeText(_ text: String?) -> String {
        (text ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private func disabledLegacyScript(_ text: String?) -> String {
        LegacyHyperTalkScript.preparedForHypeTalkRuntime(normalizeText(text))
    }

    private func nonEmpty(_ value: String?, fallback: String) -> String {
        guard let value, !value.isEmpty else { return fallback }
        return value
    }

    private func sortKey(_ index: Int) -> String {
        String(format: "a%06d", index)
    }

    private func importedScriptCount(_ document: HypeDocument) -> Int {
        [document.stack.script].filter { !$0.isEmpty }.count +
            document.backgrounds.filter { !$0.script.isEmpty }.count +
            document.cards.filter { !$0.script.isEmpty }.count +
            document.parts.filter { !$0.script.isEmpty }.count
    }

    private func disabledScriptCount(_ document: HypeDocument) -> Int {
        ([document.stack.script] + document.backgrounds.map(\.script) + document.cards.map(\.script) + document.parts.map(\.script))
            .filter(LegacyHyperTalkScript.isDisabledForHypeTalkRuntime)
            .count
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }
}

private protocol XSTKPackageReader {
    var allPaths: [String] { get }
    func data(for path: String) throws -> Data
}

private struct FileSystemXSTKPackageReader: XSTKPackageReader {
    var packageURL: URL

    var allPaths: [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let root = packageURL.path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.path
            paths.append(path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent)
        }
        return paths
    }

    func data(for path: String) throws -> Data {
        try Data(contentsOf: packageURL.appendingPathComponent(path))
    }
}

private struct InMemoryXSTKPackageReader: XSTKPackageReader {
    var files: [String: Data]

    var allPaths: [String] {
        Array(files.keys)
    }

    func data(for path: String) throws -> Data {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let data = files[normalized] else {
            throw HyperCardImportError.generatedPackageInvalid("Missing generated file \(path)")
        }
        return data
    }
}

private struct XSTKProject: Decodable {
    var sourceFileName: String?
    var stackFile: String?
    var blocks: [XSTKBlock]
    var fonts: [XSTKFont]?
    var warnings: [String]?
}

private struct XSTKSourceManifest: Decodable {
    var resourceFork: XSTKResourceForkManifest
}

private struct XSTKResourceForkManifest: Decodable {
    var resources: [XSTKResourceSummary]

    init(resources: [XSTKResourceSummary] = []) {
        self.resources = resources
    }

    private enum CodingKeys: String, CodingKey {
        case resources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resources = try container.decodeIfPresent([XSTKResourceSummary].self, forKey: .resources) ?? []
    }
}

private struct XSTKResourceSummary: Decodable {
    var type: String
    var id: Int
    var name: String
    var bytes: Int
    var outputArtifacts: [XSTKResourceArtifact]

    init(type: String, id: Int, name: String, bytes: Int, outputArtifacts: [XSTKResourceArtifact]) {
        self.type = type
        self.id = id
        self.name = name
        self.bytes = bytes
        self.outputArtifacts = outputArtifacts
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, bytes, outputArtifacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "RSRC"
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        bytes = try container.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
        outputArtifacts = try container.decodeIfPresent([XSTKResourceArtifact].self, forKey: .outputArtifacts) ?? []
    }
}

private struct XSTKResourceArtifact: Decodable {
    var path: String
    var format: String
    var mediaType: String
    var description: String
    var variantIndex: Int?

    init(path: String, format: String, mediaType: String, description: String, variantIndex: Int?) {
        self.path = path
        self.format = format
        self.mediaType = mediaType
        self.description = description
        self.variantIndex = variantIndex
    }

    private enum CodingKeys: String, CodingKey {
        case path, format, mediaType, description, variantIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        variantIndex = try container.decodeIfPresent(Int.self, forKey: .variantIndex)
    }
}

private struct XSTKBlock: Decodable {
    var type: String
    var id: Int
    var size: Int?
    var understood: Bool?
}

private struct XSTKFont: Decodable {
    var id: Int
    var name: String
}

private struct XSTKStack: Decodable {
    var name: String?
    var cardWidth: Int
    var cardHeight: Int
    var script: String?
    var pages: [XSTKPage]?
    var layers: [XSTKLayer]
}

private struct XSTKPage: Decodable {
    var cardIds: [Int]
}

private struct XSTKLayer: Decodable {
    var kind: String
    var id: Int
    var file: String?
    var name: String?
    var owner: Int?
    var marked: Bool?
}

private struct XSTKLayerDetail: Decodable {
    var id: Int
    var bitmap: String?
    var parts: [XSTKPart]
    var contents: [XSTKContent]
    var name: String?
    var script: String?
}

private struct XSTKPart: Decodable {
    var id: Int
    var type: String
    var visible: Bool?
    var enabled: Bool?
    var rect: XSTKRect?
    var style: String?
    var showName: Bool?
    var highlight: Bool?
    var autoHighlight: Bool?
    var family: Int?
    var textAlign: String?
    var font: String?
    var textSize: Int?
    var textStyles: [String]?
    var name: String?
    var script: String?
    var lockText: Bool?
    var dontWrap: Bool?
    var wideMargins: Bool?
    var text: String?
}

private struct XSTKRect: Decodable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
}

private struct XSTKContent: Decodable {
    var layer: String?
    var id: Int
    var text: String
}

private enum PBMImageConverter {
    static func pngData(from path: String, data: Data) throws -> Data {
        var scanner = PBMScanner(data: data)
        guard scanner.nextToken() == "P4",
              let widthToken = scanner.nextToken(),
              let heightToken = scanner.nextToken(),
              let width = Int(widthToken),
              let height = Int(heightToken),
              width > 0,
              height > 0 else {
            throw HyperCardImportError.generatedPackageInvalid("Unsupported PBM bitmap \(path)")
        }
        scanner.skipSingleWhitespaceAfterHeader()
        let bytesPerRow = (width + 7) / 8
        let expected = bytesPerRow * height
        guard scanner.offset + expected <= data.count else {
            throw HyperCardImportError.generatedPackageInvalid("Truncated PBM bitmap \(path)")
        }

        var rgba = Data(count: width * height * 4)

        data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: UInt8.self)
            rgba.withUnsafeMutableBytes { rawRGBA in
                guard let bitmapData = rawRGBA.bindMemory(to: UInt8.self).baseAddress else { return }
                for y in 0..<height {
                    for x in 0..<width {
                        let byte = source[scanner.offset + y * bytesPerRow + x / 8]
                        let isBlack = ((byte >> UInt8(7 - (x % 8))) & 1) == 1
                        let dest = y * width * 4 + x * 4
                        let value: UInt8 = isBlack ? 0 : 255
                        bitmapData[dest] = value
                        bitmapData[dest + 1] = value
                        bitmapData[dest + 2] = value
                        bitmapData[dest + 3] = 255
                    }
                }
            }
        }

        guard let png = PNGEncoding.rgbaDataToPNG(rgba, width: width, height: height) else {
            throw HyperCardImportError.generatedPackageInvalid("Could not encode bitmap \(path)")
        }
        return png
    }
}

private struct PBMScanner {
    let data: Data
    var offset = 0

    mutating func nextToken() -> String? {
        skipWhitespaceAndComments()
        let start = offset
        while offset < data.count {
            let byte = data[offset]
            if byte == 35 || byte == 9 || byte == 10 || byte == 13 || byte == 32 { break }
            offset += 1
        }
        guard offset > start else { return nil }
        return String(data: data[start..<offset], encoding: .ascii)
    }

    mutating func skipSingleWhitespaceAfterHeader() {
        if offset < data.count {
            let byte = data[offset]
            if byte == 9 || byte == 10 || byte == 13 || byte == 32 {
                offset += 1
            }
        }
    }

    private mutating func skipWhitespaceAndComments() {
        while offset < data.count {
            let byte = data[offset]
            if byte == 35 {
                while offset < data.count, data[offset] != 10 { offset += 1 }
            } else if byte == 9 || byte == 10 || byte == 13 || byte == 32 {
                offset += 1
            } else {
                return
            }
        }
    }
}
