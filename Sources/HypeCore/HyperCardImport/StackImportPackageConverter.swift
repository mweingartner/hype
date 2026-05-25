import AppKit
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
        appendAudioAssets(from: reader, to: &document)

        let blockSummary = project.blocks.map {
            HyperCardBlockSummary(type: $0.type, count: 1, totalBytes: $0.size ?? 0)
        }
        let warnings = project.warnings ?? []
        let unsupported = project.blocks
            .filter { $0.understood == false }
            .map { "Block \($0.type) \($0.id) was emitted by stackimport as not fully understood." }
        let scriptWarning = "Imported HyperCard scripts are preserved as comments and disabled until translated to native HypeTalk."

        let report = HyperCardImportReport(
            stackName: document.stack.name,
            cardSize: HyperCardSize(width: document.stack.width, height: document.stack.height),
            blockSummary: blockSummary,
            importedBackgrounds: document.backgrounds.count,
            importedCards: document.cards.count,
            importedParts: importedPartCount,
            importedScripts: importedScriptCount(document),
            warnings: stableUnique(warnings + (importedScriptCount(document) > 0 ? [scriptWarning] : [])),
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
            name: "Paint Layer",
            sortKey: "a000000",
            left: 0,
            top: 0,
            width: Double(document.stack.width),
            height: Double(document.stack.height)
        )
        part.imageData = pngData
        document.parts.append(part)
    }

    private func appendAudioAssets(from reader: XSTKPackageReader, to document: inout HypeDocument) {
        var importedNames = Set(document.assetRepository.assets
            .filter { $0.kind == .audioClip }
            .map { $0.name.lowercased() })
        for path in reader.allPaths.sorted() where path.lowercased().hasSuffix(".wav") {
            guard let data = try? reader.data(for: path), !data.isEmpty else { continue }
            let name = audioAssetName(from: path)
            guard !name.isEmpty, importedNames.insert(name.lowercased()).inserted else { continue }
            document.assetRepository.addAsset(Asset(
                name: name,
                kind: .audioClip,
                mimeType: "audio/wav",
                data: data,
                tags: ["hypercard-import", "sound-resource"]
            ))
        }
    }

    private func audioAssetName(from path: String) -> String {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let components = stem.split(separator: "_", omittingEmptySubsequences: false)
        if components.count >= 3, components[0].lowercased() == "snd", Int(components[1]) != nil {
            return decodedAudioAssetName(components.dropFirst(2).joined(separator: "_"))
        }
        if let sndIndex = components.firstIndex(where: { $0.lowercased() == "snd" }),
           components.count > components.index(sndIndex, offsetBy: 2),
           Int(components[components.index(after: sndIndex)]) != nil {
            return decodedAudioAssetName(components.suffix(from: components.index(sndIndex, offsetBy: 2)).joined(separator: "_"))
        }
        return decodedAudioAssetName(stem)
    }

    private func decodedAudioAssetName(_ name: String) -> String {
        (name.removingPercentEncoding ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
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
        LegacyHyperTalkScript.disabledForHypeTalkRuntime(normalizeText(text))
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

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let bitmapData = rep.bitmapData else {
            throw HyperCardImportError.generatedPackageInvalid("Could not allocate bitmap \(path)")
        }

        data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: UInt8.self)
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

        guard let png = rep.representation(using: .png, properties: [:]) else {
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
